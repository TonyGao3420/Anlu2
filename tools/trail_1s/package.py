"""Validate and publish the one-second smoothed-trail main-project build."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/trail_1s_20261025'
for script in ['audit.py', 'make_preview.py']:
    subprocess.run([sys.executable, str(root / 'tools/trail_1s' / script)], cwd=root, check=True)

checks = {
    'smooth_trail.log': ['PASS smooth_trail: 8847360 pixels', 'independent median/IIR/deadband/cadence/bitmap reference'],
    'mode_integration_final.log': ['PASS mode_integration: 7372800 actual 720p output pixels',
                                   'PASS mode_switches_1s:', 'SW1 servo outputs cycle-exact'],
    'style_switch.log': ['PASS style_switch: default 750000-cycle/10ms filter'],
    'style_small.log': ['PASS style_reference FULL0: 36864 pixels per run'],
    'style_720p.log': ['PASS style_reference FULL1: 2764800 pixels per run'],
    'trail_small.log': ['PASS trail_reference: 159744 pixels per reset run', 'TTL999/1000'],
    'trail_clock.log': ['PASS trail_clock: exact 75000-cycle milliseconds'],
    'trail_watchdog.log': ['PASS trail_watchdog: retain before 250ms'],
    'trail_budget.log': ['PASS trail_budget: 257 live records/overwrite'],
    'trail_movie.log': ['PASS trail_movie: 3379200 RGB pixels'],
    'logo_rom_equivalence.log': ['PASS logo_rom_equivalence: all 32768 addresses'],
    'production_regression.log': ['ModelSim regression passed.', 'PASS ROI height', 'PASS green highlights'],
    'synthesis.log': ['export_db camera_to_dsi_display_gate.db'],
    'route_bitgen.log': ['export_db camera_to_dsi_display_pr.db', 'bitgen -bit camera_to_dsi_display.bit'],
}
for name, markers in checks.items():
    log = (build / name).read_text(encoding='utf-8', errors='replace')
    assert all(m in log for m in markers), (name, 'Missing completion/PASS')
    assert not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b|Run .* failed|invalid command', log), (name, 'Error')

run = root / 'td_project/camera_to_dsi_display_Runs'
phy = run / 'phy_1'
qor = (phy / 'route.qor').read_text(encoding='utf-8', errors='replace')


def metric(label):
    match = re.search(r'\|\s*' + re.escape(label) + r'\s*\|\s*(-?\d+)', qor)
    assert match, label
    return int(match[1])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


resources = {k: metric(n) for k, n in [('slices', '#slices'), ('eram20k', '#RAMs'), ('dsp', '#DSPs')]}
timing = {n: metric(n) for n in ['Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS']}
assert resources['slices'] <= 21216 and resources['eram20k'] == 94 and resources['dsp'] == 40, resources
assert timing['Setup WNS'] >= 0 and timing['Hold WNS'] >= 0 and timing['Setup TNS'] == timing['Hold TNS'] == 0, timing
coverage = float(re.search(r'STA coverage\s*:\s*([0-9.]+)%', (phy / 'final_timing.rpt').read_text())[1])
backup = root.parent / 'recovery_backups/Anlu2_before_trail_1s_20261025'
previous = json.loads((backup / 'sim/build/eram_opt_20261025/Anlu2_eram_optimized_20261025_manifest.json').read_text(encoding='utf-8'))
route_log = (build / 'route_bitgen.log').read_text(encoding='utf-8', errors='replace')
critical = [l[l.index('CRITICAL-WARNING:'):] for l in route_log.splitlines() if 'CRITICAL-WARNING:' in l]
assert all(w in previous['inherited_critical_warnings'] for w in critical), ('New critical warning', critical)
production = [p for p in (root / 'user_source').rglob('*') if p.is_file()]
bit = phy / 'camera_to_dsi_display.bit'
route = phy / 'camera_to_dsi_display_pr.db'
gate = run / 'syn_1/camera_to_dsi_display_gate.db'
assert bit.stat().st_mtime > route.stat().st_mtime > gate.stat().st_mtime > max(p.stat().st_mtime for p in production), 'Stale FPGA output'
trail_mtime = (root / 'user_source/hdl_source/video/roi_motion_trail.v').stat().st_mtime
assert all((build / n).stat().st_mtime > trail_mtime for n in ['smooth_trail.log', 'mode_integration_final.log', 'trail_small.log', 'trail_budget.log', 'trail_movie.log'])
counts = re.search(r'ROI (\d+) OSD (\d+) background (\d+) trail (\d+)', (build / 'mode_integration_final.log').read_text())
assert counts and int(counts[4]) == 32, 'Main-pipeline short-dwell trajectory coverage mismatch'
artifact = build / 'Anlu2_trail_1s_smooth_20261025.bit'
shutil.copy2(bit, artifact)
shutil.copy2(phy / 'route.qor', build / 'final_route.qor')
shutil.copy2(phy / 'final_timing.rpt', build / 'final_timing.rpt')

report = f'''# Anlu2 一秒平滑运动轨迹（2026-10-25）

## 修改与显示效果

风格化模式的轨迹由3秒缩短为1秒，按真实毫秒时间戳消退；位图仍逐帧重建、在帧边界发布，到期可见误差约一帧。历史记录按50ms固定时间间隔抽样（约20Hz），相邻有效点继续画连续折线，减少逐帧ROI中心变化造成的细碎折返。

轨迹坐标先经过三点中值、Q2定点1/2平滑及4像素死区：中值抑制孤立跳点，平滑减轻高频摆动，死区阻止小幅静止抖动反复画线。目标丢失、重获、超过150ms的采样间隙或过大跳变仍断开连线；退出/清空模式及视频中断清理不变。失效目标会立即在历史中留下断点，不等50ms采样。

轨迹阶段只修改`roi_motion_trail.v`和顶层轨迹参数。后续GUI兼容修复将未改动的图标ERAM定义搬入`hdmi_mixer.v`，旧文件为空兼容条目；详见GUI_COMPILE_FIX_20261025.md。ROI检测、以屏幕中心为原点的坐标文字、舵机、拨码、颜色、背景风格化算法与修改前一致。RGB/VS/HS/DE流水线未增加延迟。平滑和抽样会带来少量轨迹位置滞后，原始坐标及舵机不使用平滑结果。ROI框本身的刷新率保持原样。

为改善滤波到ERAM的组合路径，在帧首采集轨迹点后下一时钟写入历史；时间戳仍是采样时刻，历史读取晚于位图清空，因此显示结果与独立参考逐像素一致。

## 主工程编译结果

| 项目 | 修改前 | 当前 |
|---|---:|---:|
| Slice / 21216 | 17710 | {resources['slices']} |
| ERAM / 108 | 94 | {resources['eram20k']} |
| DSP / 40 | 40 | {resources['dsp']} |
| Setup WNS | +101ps | +{timing['Setup WNS']}ps |
| Hold WNS | +20ps | +{timing['Hold WNS']}ps |

资源未超限，ERAM/DSP占用不增加；Setup/Hold TNS均为0。约束、引脚和工具策略未修改。STA覆盖率{coverage}%，继承的时钟critical warning未增加；这些结果不等于板上实测。

## 仿真与审计

- 240帧、8847360个RGB像素与独立Python数值/位图参考一致，覆盖静止抖动、移动、孤立跳点、丢失/重获、模式清理、16位时间回绕、计时间隙及OSD/ROI优先级；同时比较原3秒未平滑方案。
- 1秒到期的999/1000ms边界、交叉轨迹、环形缓存覆盖、视频250ms中断清理、75MHz毫秒计时及完整720p绘制预算通过。
- 完整主显示链路8帧、7372800像素通过，含拨码抖动、进入/退出/重入、ROI/文字/图标和两路舵机PWM逐拍对照。短暂风格化阶段因50ms抽样产生32个可见轨迹像素；长时间连续轨迹由240帧独立参考验证。
- 风格化720p参考、图标32768地址等价和原7项回归通过，包含亮白排除和完整ROI高度。
- 源码审计确认其他硬件功能、显示流水、计时、工程配置与引脚未改。合成、布局布线、静态时序和bitgen完成。

仿真对比图位于`sim/build/trail_1s_20261025/preview/trail_comparison.gif`，为RTL真实输出配合合成ROI输入，不是上板实拍。新版本尚未上板，实际摄像头观感需下载后确认。

## 使用与产物

主工程入口：`td_project/camera_to_dsi_display.al`，源码来自`user_source/`。完整重新综合及布局布线后，常规输出为`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。

命名比特流：`sim/build/trail_1s_20261025/{artifact.name}`，与主输出逐字节一致。SHA256：`{sha(artifact)}`。同目录manifest保存源码、日志、配置及产物哈希。

SW2上进入风格化及1秒轨迹模式；SW1继续独立控制舵机。SW2下保留原显示模式。轨迹仍为屏幕坐标路径，没有云台运动补偿。

重跑完整验证与编译：`powershell -ExecutionPolicy Bypass -File tools/trail_1s/rebuild.ps1`。Python仅用于离线参考、仿真和打包，板上执行Verilog，无需先运行Python即可使用TD主工程编译。

修改前备份：`../recovery_backups/Anlu2_before_trail_1s_20261025/`，原比特流SHA256：`{previous['sha256']}`。
'''
(root / 'doc/TRAIL_1S_SMOOTH_20261025.md').write_text(report, encoding='utf-8')
paths = production + [root / 'README.md', root / 'doc/TRAIL_1S_SMOOTH_20261025.md',
                      root / 'doc/THREE_MODE_BOARD_CHECK_20261025.md', root / 'td_project/camera_to_dsi_display.al',
                      root / 'td_project/camera_to_dsi_display.sdc']
for directory in ['tools/trail_1s', 'tools/eram_opt', 'tools/style_mode', 'sim/tb/trail_1s', 'sim/tb/style_mode',
                  'sim/models/eram_opt', 'sim/models/style_mode', 'sim/modelsim_trail_1s',
                  'sim/modelsim_trail_units', 'sim/modelsim_style_mode']:
    paths += [p for p in (root / directory).rglob('*') if p.is_file() and 'work' not in p.parts
              and '__pycache__' not in p.parts and p.suffix in ['.py', '.ps1', '.v', '.sv', '.do']]
paths += list(run.glob('*/settings.cfg')) + list(run.glob('*/*.prj'))
manifest = {
    'artifact': artifact.name, 'sha256': sha(artifact), 'main_bit_sha256': sha(bit), 'bytes': bit.stat().st_size,
    'main_project': 'td_project/camera_to_dsi_display.al',
    'build_time_local': datetime.datetime.fromtimestamp(bit.stat().st_mtime).isoformat(),
    'resources_before': previous['resources_after'], 'resources_after': resources,
    'timing_ps_before': previous['timing_ps_after'], 'timing_ps_after': timing,
    'wire_length_after': metric('Wire length'), 'sta_coverage_percent': coverage,
    'inherited_critical_warnings': critical, 'additional_video_pipeline_clocks': 0,
    'trajectory_settings': {'ttl_ms': 1000, 'median_points': 3, 'iir_alpha': '1/2', 'deadband_pixels': 4,
                            'sample_interval_ms': 50, 'rebuild_every_frame': True},
    'source_audit': json.loads((build / 'source_audit.json').read_text()), 'validation': checks,
    'synthetic_reference_metrics': json.loads((build / 'smooth_reference_metrics.json').read_text()),
    'board_test_performed': False,
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in paths},
    'validation_log_sha256': {n: sha(build / n) for n in checks},
}
assert manifest['sha256'] == manifest['main_bit_sha256']
(build / 'Anlu2_trail_1s_smooth_20261025_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Packaged', artifact)
print('Resources', resources)
print('Timing ps', timing)
print('SHA256', manifest['sha256'])

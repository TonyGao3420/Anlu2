"""Publish the clean GUI build and a source-complete project archive."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import sys
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit import audit, root, build, backup


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source_audit = audit()
run = root / 'td_project/camera_to_dsi_display_Runs'
for stage, label in [('syn_1', 'synthesis'), ('phy_1', 'route_bitgen')]:
    log = run / stage / 'run.log'
    text = log.read_text(encoding='utf-8', errors='replace')
    assert not re.search(r'\bERROR\b|HDL-8007|HDL-7144|Run .* failed|invalid command', text), stage
    if stage == 'syn_1':
        assert re.search(r'elaborate module anlogic_logo_eram in .*hdmi_mixer\.v', text)
        assert 'export_db camera_to_dsi_display_gate.db' in text
        assert (run / stage / '.opt_gate.end.f').exists()
    else:
        assert 'bitgen -bit camera_to_dsi_display.bit' in text
        assert (run / stage / '.bitgen.end.f').exists()
    shutil.copy2(log, build / (label + '.log'))

checks = {
    'logo_equivalence.log': ['PASS eram_logo: 32768 addresses sequential and permuted'],
    'mixer_equivalence.log': ['PASS mixer_eram_equivalence: 2764800 full 720p pixels', 'sync cycle-exact'],
    'mixer_without_logo_entry.log': ['PASS mixer_eram_equivalence: 2764800 full 720p pixels', 'sync cycle-exact'],
    'production_regression.log': ['ModelSim regression passed.', 'PASS ROI height', 'PASS green highlights'],
}
for name, markers in checks.items():
    log = (build / name).read_text(encoding='utf-8', errors='replace')
    assert all(m in log for m in markers), name
    assert not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b', log), name
    assert (build / name).stat().st_mtime > (root / 'user_source/hdl_source/hdmi_mixer.v').stat().st_mtime

phy = run / 'phy_1'
qor = (phy / 'route.qor').read_text()


def metric(name):
    return int(re.search(r'\|\s*' + re.escape(name) + r'\s*\|\s*(-?\d+)', qor)[1])


resources = {k: metric(n) for k, n in [('slices', '#slices'), ('eram20k', '#RAMs'), ('dsp', '#DSPs')]}
timing = {n: metric(n) for n in ['Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS']}
assert resources['slices'] <= 21216 and resources['eram20k'] == 94 and resources['dsp'] == 40
assert timing['Setup WNS'] >= 0 and timing['Hold WNS'] >= 0 and timing['Setup TNS'] == timing['Hold TNS'] == 0, timing
coverage = float(re.search(r'STA coverage\s*:\s*([0-9.]+)%', (phy / 'final_timing.rpt').read_text())[1])
old = json.loads((backup / 'before_release_manifest.json').read_text())
route_text = (build / 'route_bitgen.log').read_text(encoding='utf-8', errors='replace')
critical = [l[l.index('CRITICAL-WARNING:'):] for l in route_text.splitlines() if 'CRITICAL-WARNING:' in l]
assert all(w in old['inherited_critical_warnings'] for w in critical), critical
bit = phy / 'camera_to_dsi_display.bit'
production = [p for p in (root / 'user_source').rglob('*') if p.is_file()]
assert bit.stat().st_mtime > (phy / 'camera_to_dsi_display_pr.db').stat().st_mtime > (run / 'syn_1/camera_to_dsi_display_gate.db').stat().st_mtime > max(p.stat().st_mtime for p in production)
artifact = build / 'Anlu2_GUI_compile_fixed_20261025.bit'
shutil.copy2(bit, artifact)
for name in ['route.qor', 'final_timing.rpt']:
    shutil.copy2(phy / name, build / name)

report = f'''# TD GUI 黑盒错误修复与干净编译验证

用户截图的报错为`HDL-8007: anlogic_logo_eram is a black box`，以及对应的`HDL-7144`未知模块警告，表示该次综合没有读到图标模块定义。之前命令行综合读到了该定义，但没有覆盖GUI重新打开后的完整流程。本机GUI能列出原文件，未复现另一台电脑为何漏读；不能据此将用户的报错归为操作错误。

## 修改

将完整、未改动的`anlogic_logo_eram`模块及其ERAM初始化数据放进`user_source/hdl_source/hdmi_mixer.v`，与调用者一起编译，消除对新增独立源文件条目的依赖。旧`anlogic_logo_eram.v`保留为空兼容条目，避免已有工程列表报文件丢失或出现重复定义。今后不能再拿旧的完整模块覆盖这个兼容文件。

逐字节审计确认mixer原有模块体和图标模块体/数据都不变；除这两份文件的定义搬移外，所有`user_source/`文件与一秒平滑轨迹版一致。ROI、舵机、拨码、颜色、坐标、风格化和一秒平滑轨迹不变，无新增显示流水级。

TD GUI已重新载入并保存主工程，整理了编译顺序并自动排除了不用的旧ROM/空兼容条目；源文件集合、器件、顶层、策略、引脚和时序约束保持对应配置。GUI生成的syn/phy工作工程源文件集合与主工程一致，settings.cfg与修改前一致。

## 验证结果

- 关闭旧工程后，将原Runs目录完整移到恢复备份，重新打开主工程，从Flow Runs的Launch Runs启动全新综合和物理设计。并非使用旧缓存或仅运行命令行。
- GUI综合日志明确记录`anlogic_logo_eram`在`hdmi_mixer.v`展开，`HDL-8007/HDL-7144`未再出现；综合、布局布线和bitgen完成。
- 32768图标地址及所有580种颜色、透明值、复位恢复保持一致。
- 三个完整720p画面、2764800像素的mixer等价检查通过；RGB/OSD/ROI/坐标、DDR读请求、同步逐拍一致。
- 刻意从仿真文件列表去掉`anlogic_logo_eram.v`，再做2764800像素对照仍通过，覆盖截图中“缺独立条目”的情形。
- 原7项功能回归通过，包括亮白排除、完整ROI高度、RAW和显示路径。轨迹与背景算法源码逐字节保持上一版，不在本轮改动范围。

| 最终布线结果 | 数值 |
|---|---:|
| Slice / 21216 | {resources['slices']} |
| ERAM / 108 | {resources['eram20k']} |
| DSP / 40 | {resources['dsp']} |
| Setup WNS | +{timing['Setup WNS']} ps |
| Hold WNS | +{timing['Hold WNS']} ps |

Setup/Hold TNS均为0，资源未超限。STA覆盖率{coverage}%，既有时钟critical warning没有增加；不等于零警告或上板实测。

## 使用

请复制完整的修正版工程，关闭之前已打开的工程，再打开`Anlu2/td_project/camera_to_dsi_display.al`。`prj/Anlu2.al`为旧入口，不含当前完整功能。正常完整运行综合、物理设计和bitgen即可，不需要先运行Python。

干净工程ZIP含全部user_source、主工程配置、约束和已编译比特流；不含旧Runs缓存。比特流在ZIP的`Anlu2/output/`内。自己重新编译后的常规输出仍是`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。

GUI中也可以依次选择Flow Runs里的`syn_1`、`phy_1`，右键`Launch Runs`。本轮正是按这一入口从空运行目录编译。

命名比特流：`sim/build/gui_compile_fix_20261025/{artifact.name}`，与本次主工程常规输出字节一致。SHA256：`{sha(artifact)}`。

原工程运行目录、原两份HDL和上一版清单完整保存在`../recovery_backups/Anlu2_before_GUI_project_fix_20261025/`。上一版比特流SHA256：`{old['sha256']}`。本版尚未上板验证。
'''
doc = root / 'doc/GUI_COMPILE_FIX_20261025.md'
doc.write_text(report, encoding='utf-8')
archive = build / 'Anlu2_GUI_compile_fixed_20261025.zip'
portable_readme = '''# Anlu2 GUI编译修正版

请将本压缩包完整解压到一个新目录，再用TD打开`td_project/camera_to_dsi_display.al`。
包内含全部user_source、主工程配置及约束，不含旧编译缓存。可直接在TD完整运行综合、物理设计和bitgen，不需要运行Python或额外添加图标源文件。
也可依次在Flow Runs中选择syn_1、phy_1，右键Launch Runs运行。

预编译比特流位于output/；自行编译后输出位于td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit。
本版已由TD 6.2.1 GUI从全新运行目录编译通过；尚未上板。

SW2下为原彩色ROI模式，SW1控制是否开启舵机跟踪；SW2上为背景风格化及一秒平滑轨迹，SW1继续独立控制舵机。

图标ERAM定义与调用者一起位于user_source/hdl_source/hdmi_mixer.v。anlogic_logo_eram.v为空兼容条目，请勿覆盖回旧的完整模块，否则会产生重复定义。
本次仅整理图标模块的编译归属，一秒轨迹、ROI、坐标、舵机、颜色及拨码算法保持上一版。

详细说明见doc/GUI_COMPILE_FIX_20261025.md。
'''
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for p in production:
        z.write(p, 'Anlu2/' + p.relative_to(root).as_posix())
    for rel in ['td_project/camera_to_dsi_display.al', 'td_project/camera_to_dsi_display.sdc',
                'doc/GUI_COMPILE_FIX_20261025.md', 'doc/TRAIL_1S_SMOOTH_20261025.md',
                'doc/THREE_MODE_BOARD_CHECK_20261025.md']:
        z.write(root / rel, 'Anlu2/' + rel)
    z.writestr('Anlu2/README.md', portable_readme)
    z.write(artifact, 'Anlu2/output/' + artifact.name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for p in production:
        assert hashlib.sha256(z.read('Anlu2/' + p.relative_to(root).as_posix())).hexdigest() == sha(p)
    assert 'Anlu2/td_project/camera_to_dsi_display.al' in z.namelist()
paths = production + [root / 'td_project/camera_to_dsi_display.al', root / 'td_project/camera_to_dsi_display.sdc', doc, root / 'README.md']
paths += list((root / 'tools/gui_compile_fix').glob('*.py'))
paths += [root / 'sim/modelsim_gui_compile_fix/run_missing_logo_entry.do', root / 'sim/modelsim_eram_opt/run_logo.do', root / 'sim/modelsim_eram_opt/run_mixer.do']
manifest = {
    'artifact': artifact.name, 'sha256': sha(artifact), 'main_bit_sha256': sha(bit),
    'archive': archive.name, 'archive_sha256': sha(archive), 'archive_all_sources_verified': True,
    'build_time_local': datetime.datetime.fromtimestamp(bit.stat().st_mtime).isoformat(),
    'main_project': 'td_project/camera_to_dsi_display.al', 'build_started_from_GUI_after_removing_old_run_directory': True,
    'source_audit': source_audit, 'resources': resources, 'timing_ps': timing, 'sta_coverage_percent': coverage,
    'inherited_critical_warnings': critical, 'functional_validation': checks, 'board_test_performed': False,
    'previous_1s_release_bit_identical': sha(artifact) == old['sha256'],
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in paths},
    'log_sha256': {n: sha(build / n) for n in list(checks) + ['synthesis.log', 'route_bitgen.log']},
}
assert manifest['sha256'] == manifest['main_bit_sha256']
(build / 'Anlu2_GUI_compile_fixed_20261025_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Packaged', artifact, archive, resources, timing, 'SHA256', manifest['sha256'], sep='\n')

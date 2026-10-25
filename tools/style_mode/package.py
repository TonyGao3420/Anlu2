from pathlib import Path
import subprocess,sys,re,json,hashlib,shutil,datetime,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2];build=root/'sim/build/style_mode_20261025'
for script in ['audit.py','make_preview.py','make_trail_preview.py']:
 subprocess.run([sys.executable,str(root/'tools/style_mode'/script)],check=True,cwd=root)
checks={
 'style_switch.log':['PASS style_switch: default 750000-cycle/10ms filter'],
 'style_small.log':['PASS style_reference FULL0: 36864 pixels per run'],
 'style_720p.log':['PASS style_reference FULL1: 2764800 pixels per run'],
 'trail_small.log':['PASS trail_reference: 159744 pixels per reset run'],
 'trail_clock.log':['PASS trail_clock: exact 75000-cycle milliseconds'],
 'trail_watchdog.log':['PASS trail_watchdog: retain before 250ms'],
 'trail_budget.log':['PASS trail_budget: 257 live records/overwrite','bottom-right cell57599'],
 'trail_movie.log':['PASS trail_movie: 3379200 RGB pixels'],
 'logo_rom_equivalence.log':['PASS logo_rom_equivalence: all 32768 addresses'],
 'mode_integration.log':['PASS mode_integration: 7372800 actual 720p output pixels','PASS mode_switches:','SW1 servo outputs cycle-exact'],
 'production_regression.log':['ModelSim regression passed.','PASS ROI height','PASS green highlights'],
 'synthesis.log':['export_db camera_to_dsi_display_gate.db'],
 'route_bitgen.log':['export_db camera_to_dsi_display_pr.db','bitgen -bit camera_to_dsi_display.bit']}
for name,markers in checks.items():
 text=(build/name).read_text(encoding='utf-8',errors='replace')
 assert all(m in text for m in markers),(name,'Completion marker missing')
 assert not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b|Run .* failed|invalid command',text),(name,'Error in log')
run=root/'td_project/camera_to_dsi_display_Runs';phy=run/'phy_1'
qor=(phy/'route.qor').read_text(encoding='utf-8',errors='replace')
def metric(name):
 m=re.search(r'\|\s*'+re.escape(name)+r'\s*\|\s*(-?\d+)',qor);assert m,name;return int(m[1])
resources={k:metric(n) for k,n in [('slices','#slices'),('eram20k','#RAMs'),('dsp','#DSPs')]}
assert resources['slices']<=21216 and resources['eram20k']<=108 and resources['dsp']<=40,resources
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
sta=(phy/'final_timing.rpt').read_text(encoding='utf-8',errors='replace')
coverage=float(re.search(r'STA coverage\s*:\s*([0-9.]+)%',sta)[1])
area=(run/'syn_1/camera_to_dsi_display_gate.area').read_text(encoding='utf-8',errors='replace')
for inst in ['u_background_stylize','u_motion_trail','u_style_switch','u_trail_time']:
 line=next(l for l in area.splitlines() if '|  '+inst+' ' in l)
 assert [x.strip() for x in line.split('|')][7]=='0',(inst,'Added DSP use')
source=phy/'camera_to_dsi_display.bit';gate=run/'syn_1/camera_to_dsi_display_gate.db';route=phy/'camera_to_dsi_display_pr.db'
production=[p for p in (root/'user_source').rglob('*') if p.is_file()]
latest=max(p.stat().st_mtime for p in production)
assert source.stat().st_mtime>route.stat().st_mtime>gate.stat().st_mtime>latest,'Stale bitstream'
integration=(build/'mode_integration.log').read_text(encoding='utf-8',errors='replace')
counts=re.search(r'ROI (\d+) OSD (\d+) background (\d+) trail (\d+)',integration);assert counts and int(counts[4])>=100
normal=re.search(r'normal RGB pixels(\d+), style pixels(\d+), enter(\d+) leave(\d+)',integration)
assert normal and list(map(int,[normal[1],normal[3],normal[4]]))==[3686400,2,1],normal
budget=(build/'trail_budget.log').read_text(encoding='utf-8',errors='replace')
clocks=int(re.search(r'max rebuild (\d+) clocks',budget)[1]);assert clocks<1237500
# Review inherited clock warnings; do not describe STA as 100% coverage.
route_log=(build/'route_bitgen.log').read_text(encoding='utf-8',errors='replace')
critical=[l[l.index('CRITICAL-WARNING:'):] for l in route_log.splitlines() if 'CRITICAL-WARNING:' in l]
prior=(root.parent/'SC520_Stylize_Trail_Standalone_20261021/build/route_bitgen_final.log').read_text(encoding='utf-8',errors='replace')
assert all(w in prior for w in critical),('New critical warning needs review',critical)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
artifact=build/'Anlu2_three_modes_20261025.bit';shutil.copy2(source,artifact)
report=f"""# Anlu2 三模式集成验证（2026-10-25）

当前入口为 `td_project/camera_to_dsi_display.al`，编译源是 `user_source/`，不是旧 `prj/Anlu2.al`。

## 拨码与保留行为

SW2下、SW1下：模式一，原彩色ROI识别与坐标；舵机保持。SW2下、SW1上：模式二，原舵机实时追踪。SW2上：模式三，彩色ROI、8×8背景灰度风格化和三秒橙色轨迹；SW1继续独立决定是否追踪。开发板手册第21页与官方按键开关例程共同确认SW1=A4、SW2=B4，拨上为1。

SW1同步、使能、事件toggle和visual_servo_pwm参数/代码原样保留。SW2增加两级同步和10ms稳定滤波；风格化在帧首锁存，模式位与视频元数据一起延迟后驱动轨迹，退出时清除旧轨迹。不会用两个不同延迟的视频源直接切换HDMI。

模式一、二的有效像素与原显示输出逐像素相同，所有模式共同增加13204拍显示延迟（约176µs），不会加入检测/舵机反馈通路。原图标、OSD、颜色、ROI和DDR源代码未改动。ROI仍是矩形保留，不是轮廓级抠图。

## 数字验证

| 检查 | 结果 |
|---|---|
| SW2默认750000拍稳定滤波、双向抖动、复位恢复 | PASS |
| 风格化小图与3个完整720p帧的独立参考、RGB/ROI/模式元数据对齐 | PASS |
| 轨迹2999/3000ms、交叉线、丢失/重获、大跳变、回绕、复位 | PASS |
| 视频中断250ms后的缓存清理与恢复 | PASS |
| 默认720p、257条循环覆盖、四边寻址与最右下单元 | PASS |
| 60幅实际轨迹RTL输出、目标移走后逐段到期 | PASS |
| 原图标ROM32768地址与未知/默认行为等价 | PASS |
| 实际新旧显示链路、8个720p帧、7372800输出像素 | PASS |
| 原七项功能回归（含亮白排除与完整ROI高度） | PASS |
| 全量综合、布局布线、静态时序、bitgen | PASS |

完整链路包括真实ROI、图标、坐标、颜色和舵机模块；逐拍比较DDR读请求、检测输入、ROI结果、SW1使能及两路PWM。四帧普通模式共{normal[1]}个像素保持原RGB；两次进入、一次退出，包含SW1画面中途改变与SW2短抖动，未发生半帧模式混合。风格化帧检查ROI像素{counts[1]}、OSD像素{counts[2]}、背景像素{counts[3]}与轨迹像素{counts[4]}。最大实测轨迹重画{clocks}拍，小于每帧1237500拍。

图标快速ROM仅用于仿真，已做逐地址等价证明；生产工程仍编译原图标ROM。

## 资源与时序

| 资源 | 最终使用 | 容量 | 剩余 |
|---|---:|---:|---:|
| Slice | {resources['slices']} | 21216 | {21216-resources['slices']} |
| ERAM | {resources['eram20k']} | 108 | {108-resources['eram20k']} |
| DSP | {resources['dsp']} | 40 | {40-resources['dsp']} |

Setup WNS={timing['Setup WNS']}ps、Hold WNS={timing['Hold WNS']}ps，TNS均为0。原时序约束和工具策略未放宽，原引脚仅增加SW2。新增显示模块不占DSP，整体DSP已满。

STA覆盖率{coverage}%；原时钟混合扇出/局部路由相关critical warning与先前验证版本一致，并非零警告或100%物理覆盖。

## 文件与可复现性

主输出：`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。

本次命名产物：`sim/build/style_mode_20261025/Anlu2_three_modes_20261025.bit`，SHA256：`{sha(artifact)}`。两者字节相同，来自本次主工程编译；源码、配置和仿真日志索引见同目录manifest。

合并前最新源码备份：`../recovery_backups/Anlu2_before_style_mode_20261025/`。之前独立工程保持原样。完整重跑：`powershell -ExecutionPolicy Bypass -File tools/style_mode/rebuild.ps1`。

## 实测范围与限制

本版本尚未下载板卡验证；操作步骤见 `doc/THREE_MODE_BOARD_CHECK_20261025.md`。数字验证不能代替真实摄像头、云台、HDMI链路或显示器测试。轨迹为屏幕坐标路径、约4像素量化，约一帧缓存更新延迟，三秒边界约一帧误差。云台锁定中心时轨迹将集中在中心；没有世界坐标或相机运动补偿。原检测器短暂目标保持策略继续生效。
"""
(root/'doc/STYLE_MODE_INTEGRATION_20261025.md').write_text(report,encoding='utf-8')
paths=production+[root/'README.md',root/'td_project/camera_to_dsi_display.al',root/'td_project/camera_to_dsi_display.sdc',root/'doc/STYLE_MODE_INTEGRATION_20261025.md',root/'doc/THREE_MODE_BOARD_CHECK_20261025.md']
for d in ['tools/style_mode','sim/tb/style_mode','sim/models/style_mode','sim/modelsim_style_mode']:
 paths += [p for p in (root/d).rglob('*') if p.is_file() and '__pycache__' not in p.parts and 'work' not in p.parts and p.suffix in ['.py','.ps1','.v','.sv','.do']]
paths+=list(run.glob('*/settings.cfg'))+list(run.glob('*/*.prj'))
manifest={'artifact':artifact.name,'sha256':sha(artifact),'main_bit_sha256':sha(source),'bit_bytes':artifact.stat().st_size,
 'source_entry':'td_project/camera_to_dsi_display.al','normal_main_output':source.relative_to(root).as_posix(),
 'build_time_local':datetime.datetime.fromtimestamp(source.stat().st_mtime).isoformat(),'resources':resources,'timing_ps':timing,
 'sta_coverage_percent':coverage,'inherited_critical_warnings':critical,'board_test_performed':False,
 'modes':{'SW2=0 SW1=0':'original ROI, servo hold','SW2=0 SW1=1':'original ROI and servo tracking','SW2=1':'style plus three-second trail; SW1 servo control preserved'},
 'switch2_pin':'B4','switch2_debounce_ms':10,'display_latency_added_clocks':13204,'pixel_clock_hz':75000000,
 'trajectory_ttl_ms':3000,'trajectory_history_entries':256,'max_rebuild_clocks':clocks,
 'mode_integration':{'total_pixels':7372800,'original_RGB_pixels':int(normal[1]),'entries':int(normal[3]),'exits':int(normal[4]),'servo_comparison':'cycle exact'},
 'source_audit':json.loads((build/'source_audit.json').read_text(encoding='utf-8')),'checks':checks,
 'source_sha256':{p.relative_to(root).as_posix():sha(p) for p in paths}}
assert manifest['sha256']==manifest['main_bit_sha256']
(build/'Anlu2_three_modes_20261025_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Packaged',artifact);print('Resources',resources);print('Timing ps',timing);print('SHA256',manifest['sha256'])

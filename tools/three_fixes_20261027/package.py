"""Release only fresh, passing current-source hardware and independent tests."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,runpy,sys,zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
from audit import audit
root=Path(__file__).resolve().parents[2]
build=root/'sim/build/three_fixes_20261027';run=root/'td_project/camera_to_dsi_display_Runs';phy=run/'phy_1'
backup=root.parent/'recovery_backups/Anlu2_before_three_fixes_20261027'
result=audit()
checks={
 'logo.log':['PASS official_logo: all 25600 official pixels/580 colors'],
 'logo_mixer.log':['PASS official_logo_mixer: 25600 raster pixels'],
 'rotate.log':['PASS rotate180: 3686400 720p RGB pixels'],
 'orientation.log':['PASS orientation_preserve: 100 spatial/color/protect cases'],
 'small.log':[f'PASS model_style FULL0 run{i}: 1228800 RGB/timing pixels' for i in range(3)]+['PASS motion watchdog:'],
 'full.log':['PASS model_style FULL1 run0: 7372800 RGB/timing pixels'],
 'replay.log':['PASS video_replay: 921600 supplied-video RGB pixels'],
 'main.log':['PASS final_main: 7372800 full 720p pixels','+6 aligned video clocks'],
 'production_regression.log':['ModelSim regression passed.','PASS ROI height','PASS green highlights'],
 'synthesis.log':['export_db camera_to_dsi_display_gate.db'],
 'route_bitgen.log':['finish command "bitgen -bit camera_to_dsi_display.bit"'],
}
for name in ['roi','display','color','raw10','bilinear_color','official_awb','roi_extent_720p']:checks[f'legacy_{name}.log']=['Errors: 0']
for name,markers in checks.items():
 text=(build/name).read_text(encoding='utf-8',errors='replace')
 assert all(m in text for m in markers),(name,'Missing PASS/completion')
 assert not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b|invalid command|No such file',text),name
qor=(phy/'route.qor').read_text()
def metric(name):
 m=re.search(r'\|\s*'+re.escape(name)+r'\s*\|\s*(-?\d+)',qor);assert m,name
 return int(m[1])
resources={k:metric(n) for k,n in [('slices','#slices'),('eram20k','#RAMs'),('dsp','#DSPs')]}
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert resources['slices']<=21216 and resources['eram20k']<=108 and resources['dsp']<=40,resources
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
coverage=float(re.search(r'STA coverage\s*:\s*([0-9.]+)%',(phy/'final_timing.rpt').read_text())[1])
def criticals(p):return [l[l.index('CRITICAL-WARNING:'):] for l in p.read_text(errors='replace').splitlines() if 'CRITICAL-WARNING:' in l]
warnings={}
for log,old in [('synthesis.log','synthesis.log'),('route_bitgen.log','route_bitgen.log')]:
 warnings[log]=criticals(build/log);prior=criticals(backup/'reports'/old)
 assert all(w in prior for w in warnings[log]),('New critical warning',log,warnings[log])
production=sorted(p for p in (root/'user_source').rglob('*') if p.is_file())
config=[root/'td_project/camera_to_dsi_display.al',root/'td_project/camera_to_dsi_display.sdc']
config+=list(run.glob('*/*.prj'))+list(run.glob('*/settings.cfg'))
bit=phy/'camera_to_dsi_display.bit';gate=run/'syn_1/camera_to_dsi_display_gate.db';route=phy/'camera_to_dsi_display_pr.db'
assert bit.stat().st_mtime>route.stat().st_mtime>gate.stat().st_mtime>max(p.stat().st_mtime for p in production+config),'Stale hardware'
style=root/'user_source/hdl_source/video/roi_background_stylize.v'
for log in ['small.log','full.log','replay.log','main.log']:assert (build/log).stat().st_mtime>style.stat().st_mtime,('Stale style simulation',log)
assert (build/'logo.log').stat().st_mtime>(root/'user_source/hdl_source/hdmi_mixer.v').stat().st_mtime
assert (build/'rotate.log').stat().st_mtime>(root/'user_source/hdl_source/video_out.v').stat().st_mtime
assert (build/'main.log').stat().st_mtime>(root/'user_source/hdl_source/design_top_wrapper.v').stat().st_mtime
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in re.findall(r'<File\s+Path="([^"]+)"',config[0].read_text(encoding='utf-8-sig')):
 assert not re.match(r'[A-Za-z]:',name) and (config[0].parent/name).is_file(),name
runpy.run_path(str(root/'tools/three_fixes_20261027/make_preview.py'),run_name='__main__')
artifact=build/'Anlu2_three_fixes_20261027.bit';archive=build/'Anlu2_three_fixes_20261027.zip'
shutil.copy2(bit,artifact)
for name in ['route.qor','final_timing.rpt']:shutil.copy2(phy/name,build/('final_route.qor' if name=='route.qor' else name))
main_line=next(l.lstrip('# ') for l in (build/'main.log').read_text().splitlines() if 'PASS final_main:' in l)
block=f'''完整综合、布局布线及bitgen通过：Slice {resources['slices']}/21216，ERAM {resources['eram20k']}/108，DSP {resources['dsp']}/40。

Setup WNS +{timing['Setup WNS']}ps、Hold WNS +{timing['Hold WNS']}ps，Setup/Hold TNS均为0，STA覆盖{coverage}%。没有降低时钟或放松约束。

所有发布检查通过；主通路记录：`{main_line}`。

本次命名bit与主输出SHA256相同：`{sha(bit)}`。尚未上板验证。
'''
doc=root/'doc/THREE_FIXES_20261027.md'
for p in [doc,root/'README.md']:
 text=p.read_text(encoding='utf-8');text=re.sub(r'<!-- FINAL_RESULT -->.*?<!-- /FINAL_RESULT -->','<!-- FINAL_RESULT -->\n'+block+'<!-- /FINAL_RESULT -->',text,flags=re.S);p.write_text(text,encoding='utf-8')
manifest={'artifact':artifact.name,'sha256':sha(artifact),'main_bit_sha256':sha(bit),'main_project':'td_project/camera_to_dsi_display.al',
 'build_time_local':datetime.datetime.fromtimestamp(bit.stat().st_mtime).isoformat(),'resources':resources,'timing_ps':timing,
 'sta_coverage_percent':coverage,'inherited_critical_warnings':warnings,'audit':result,'validation':checks,
 'small_reference':json.loads((build/'small_metrics.json').read_text()),'full_reference':json.loads((build/'full_metrics.json').read_text()),
 'video_replay':json.loads((build/'replay_reference.json').read_text()),'board_test_performed':False,
 'source_sha256':{p.relative_to(root).as_posix():sha(p) for p in production+config[:2]+[doc]},
 'build_worker_config_sha256':{p.relative_to(root).as_posix():sha(p) for p in config[2:]},
 'workspace_readme_sha256':sha(root/'README.md'),
 'log_sha256':{n:sha(build/n) for n in checks},'archive':archive.name,'archive_all_sources_verified':True}
verification_sources=[]
for directory in ['tools/three_fixes_20261027','sim/models/three_fixes_20261027']:
 verification_sources += [p for p in (root/directory).rglob('*') if p.is_file() and p.suffix in ['.py','.ps1','.v']]
verification_sources += [root/'sim/tb'/name for name in ['tb_official_logo_20261027.sv','tb_official_logo_mixer_20261027.sv','tb_rotate180_20261027.sv','tb_orientation_preserve_20261027.sv','tb_three_fixes_style_20261027.sv','tb_main_three_fixes_20261027.sv','tb_video_replay_20261027.sv']]
for folder in ['modelsim_three_fixes_20261027','modelsim_three_fixes_small_20261027','modelsim_three_fixes_full_20261027','modelsim_three_fixes_integration_final_20261027','modelsim_three_fixes_replay_20261027','modelsim_three_fixes_legacy_20261027']:
 verification_sources+=list((root/'sim'/folder).glob('*.do'))
manifest['verification_source_sha256']={p.relative_to(root).as_posix():sha(p) for p in verification_sources}
clean_readme=f'''# Anlu2 三项修改主工程（2026-10-27）

打开 td_project/camera_to_dsi_display.al，完整运行综合和物理设计。
无需Python，不依赖原目录Runs缓存。user_source/须整目录保留，含全部Logo MIF。
预编译当前bit：output/{artifact.name}。

官方例程3安路Logo；倒装摄像头默认180°转正（CAMERA_ROTATE_180=1）；
第三模式灰色背景随场景变化，绿色目标保色/去噪，一秒平滑橙色轨迹。
SW2下原彩色、上第三模式；SW1独立控制原舵机。原识别、坐标、引脚和校色保留。
滤波统一增加6个像素时钟，不进入检测/舵机反馈。没有新帧缓存。

{resources['slices']}/21216 Slice，{resources['eram20k']}/108 ERAM，{resources['dsp']}/40 DSP。
Setup +{timing['Setup WNS']}ps，Hold +{timing['Hold WNS']}ps；继承时钟/舵机警告，非全路径无警告。
本版未上板；请按doc内顺序核验实际旋转、机械闭环和噪点改善。
preview中含真实视频原帧的RTL回放，不是新bit的SC520实拍。
干净工程不含大体积离线参考数组；完整工作区保留重验脚本。
'''
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in production+config[:2]+[doc]:z.write(p,'Anlu2/'+p.relative_to(root).as_posix())
 z.writestr('Anlu2/README.md',clean_readme);z.write(artifact,'Anlu2/output/'+artifact.name)
 for name in list(checks)+['source_audit.json','final_route.qor','final_timing.rpt','replay_reference.json']:
  z.write(build/name,'Anlu2/verification/'+name)
 if (build/'main_tool_crash.log').is_file():
  z.write(build/'main_tool_crash.log','Anlu2/verification/main_tool_crash.log')
 for p in (build/'preview').glob('*.png'):z.write(p,'Anlu2/preview/'+p.name)
 z.writestr('Anlu2/verification/manifest.json',json.dumps(manifest,indent=2))
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for p in production+config[:2]+[doc]:assert hashlib.sha256(z.read('Anlu2/'+p.relative_to(root).as_posix())).hexdigest()==sha(p)
 assert hashlib.sha256(z.read('Anlu2/output/'+artifact.name)).hexdigest()==sha(bit)
 for n in ['official_logo_index0','official_logo_index1','official_logo_index2','official_logo_palette']:
  assert 'Anlu2/user_source/hdl_source/'+n+'.mif' in z.namelist()
manifest['archive_sha256']=sha(archive)
(build/'Anlu2_three_fixes_20261027_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('PASS final release',resources,timing,'coverage',coverage,flush=True)
print('BIT',artifact,sha(bit));print('ZIP',archive,sha(archive))

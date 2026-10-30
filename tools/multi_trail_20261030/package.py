from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,re,shutil,zipfile,runpy
r=Path(__file__).resolve().parents[2];tag='multi_trail_20261030';b=r/'sim/build'/tag;out=r/'output'
runpy.run_path(str(Path(__file__).with_name('audit.py')),run_name='__main__')
audit=json.loads((b/'source_audit.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tests={};newest=max((r/n).stat().st_mtime for n in audit['production_sha256'])
for n,marker in [('units','PASS multi_trail:'),('budget','PASS multi_trail_budget:'),('display','PASS eight_trail_display:')]:
 p=b/(n+'.log');s=p.read_text(encoding='utf-8-sig',errors='replace')
 assert marker in s and 'Errors: 0' in s and not re.search(r'\*\*\s*(?:Fatal|Error)|Errors:\s*[1-9]',s),n
 assert p.stat().st_mtime>newest,'Stale simulation '+n
 tests[n]=next(line.strip('# \r') for line in s.splitlines() if marker in line)
for n in ['synthesis','route']:
 s=(b/(n+'.log')).read_text(encoding='utf-8-sig',errors='replace')
 assert 'export_db' in s and not re.search(r'\bERROR\b',s),n
phy=r/'td_project/camera_to_dsi_display_Runs/phy_1';syn=phy.parent/'syn_1'
q=(phy/'route.qor').read_text(encoding='utf-8-sig')
metric=lambda k:int(re.search(r'\|\s*'+re.escape(k)+r'\s*\|\s*(-?\d+)',q)[1])
metrics={k:metric(k) for k in ['Setup WNS','Hold WNS','Setup TNS','Hold TNS','#slices','#RAMs','#DSPs']}
assert metrics['Setup WNS']>=0 and metrics['Hold WNS']>=0 and metrics['Setup TNS']==metrics['Hold TNS']==0,metrics
assert metrics['#slices']<=21216 and metrics['#RAMs']<=108 and metrics['#DSPs']<=40,metrics
assert metrics['#RAMs']==106 and metrics['#DSPs']==39,'New trajectory unexpectedly allocated ERAM/DSP'
bit=phy/'camera_to_dsi_display.bit';gate=syn/'camera_to_dsi_display_gate.db';place=phy/'camera_to_dsi_display_place.db';pr=phy/'camera_to_dsi_display_pr.db'
assert bit.stat().st_mtime>pr.stat().st_mtime>place.stat().st_mtime>gate.stat().st_mtime>newest,'Stale implementation'
assert (phy/'camera_to_dsi_display.tcl').read_text(encoding='utf-8-sig')==(r/'sim/reference'/tag/'physical_flow_verified.tcl').read_text(encoding='utf-8-sig')
project=(r/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8-sig')
assert '<effort>normal</effort>' in project and '<post_route_opt>auto</post_route_opt>' in project
route_log=(b/'route.log').read_text(encoding='utf-8-sig',errors='replace')
assert re.search(r'\beffort\s*\|\s*normal\s*\|',route_log) and re.search(r'\bpost_route_opt\s*\|\s*auto\s*\|',route_log)
stem='Anlu2_EightTrails_20261030';named=out/(stem+'.bit');shutil.copy2(bit,named)
configs=[r/'td_project/camera_to_dsi_display.al',r/'td_project/camera_to_dsi_display.sdc']
for folder in [syn,phy]:configs.extend(folder/n for n in ['camera_to_dsi_display.prj','settings.cfg','camera_to_dsi_display.tcl'])
manifest={'release':stem,'generated_utc':datetime.now(timezone.utc).isoformat(),'board_test_performed':False,
 'main_project':'td_project/camera_to_dsi_display.al','generated_from_current_Anlu2':True,
 'actual_implementation_run':str(phy),'named_bit':named.relative_to(r).as_posix(),'standard_bit':bit.relative_to(r).as_posix(),
 'bit_sha256':sha(bit),'metrics_ps_and_resource_counts':metrics,'tests':tests,
 'placement_seed':'tool_default','route_effort':'normal','post_route_opt':'auto','GUI_strategy_aligned_to_verified_CLI_parameters':True,
 'production_sha256':audit['production_sha256'],'config_sha256':{p.relative_to(r).as_posix():sha(p) for p in configs},
 'source_audit':audit,'implementation_database_sha256':{'gate':sha(gate),'place':sha(place),'route':sha(pr)},
 'preserved':'All latest production sources/assets except trajectory module and top trajectory connections; color/AWB/calibration, user-updated detector and servo, style/ROI/rotation/Logo/coordinates/pins/clocks unchanged',
 'new_behavior':'SW2+SW3: up to eight independent smoothed one-second trails; existing single-style trail and multi-only normal RGB unchanged; shared original history and bitmap RAMs'}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
status=f'''# 八目标轨迹主工程已完成软件验证

当前入口：td_project/camera_to_dsi_display.al。当前比特流：output/{stem}.bit。

仅轨迹模块及顶层接线改变；本轮开始时的全部颜色处理、检测、舵机、背景和显示功能保留。SW2+SW3 同时开启可显示最多八个目标各自的一秒连续轨迹，SW2 单开仍为原单目标轨迹，SW3 单开仍为普通多目标显示。

主工程完整综合、布局布线、比特流生成已通过。实际 Slice {metrics['#slices']}/21216（{metrics['#slices']/21216:.2%}），ERAM {metrics['#RAMs']}/108，DSP {metrics['#DSPs']}/40。Setup WNS +{metrics['Setup WNS']}ps，Hold WNS +{metrics['Hold WNS']}ps，TNS 均为零。

八轨迹整数参考逐像素及单目标新旧对照：10485760 像素通过；720p 满 256 条历史绘线预算通过；实际主工程 720p 八目标和各模式显示回归：6451200 像素通过。资源、时序和逐像素结果记录于 output/manifest.json 与 sim/build/multi_trail_20261030。

SHA256：{sha(bit)}。

未上板验收。旧命名 bit/zip 保留为历史版本，测试本次八轨迹请选上述新命名文件或同内容的主工程标准输出。
'''
(r/'BUILD_STATUS.md').write_text(status,encoding='utf-8')
readme=r/'README.md';s=readme.read_text(encoding='utf-8').split('## 本轮验证结果')[0]
s=s.replace('# Anlu2 最新校色、资源优化与组合模式总工程（2026-10-30）','# Anlu2 八目标独立轨迹总工程（2026-10-30）')
if '本次新增：SW2+SW3' not in s:
 s=s.replace('\n\n唯一工程入口：','\n\n本次新增：SW2+SW3 组合模式下，最多八个目标各自显示连续的一秒轨迹。仅改轨迹模块及顶层轨迹接线，其余本轮开始时的生产代码与资源文件保持一致。\n\n唯一工程入口：',1)
s=s.replace('及原主目标轨迹','及八目标各自的一秒轨迹').replace('一秒轨迹仍沿用原主目标策略。','组合模式八目标各自保留一秒轨迹；单目标模式仍沿用原轨迹策略。')
s=s.replace('Anlu2_Combo_Optimized_20261030.bit',stem+'.bit').replace('Anlu2_Combo_Optimized_20261030.zip',stem+'.zip')
s=s.replace('最终布局起点会同时固定在工程自定义物理脚本和CLI配置中。应保留td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.tcl，避免GUI和命令行使用不同布局设置。原引脚、器件、速度等级及时钟约束不变。','本轮使用工具默认布局设置、normal 布线、auto 后布线优化。GUI 工程策略已与实际通过的命令行编译设置一致；原引脚、器件、速度等级及时钟约束不变。')
s=s.replace('发布后，原Anlu2_Final_4Mode_20261028和Anlu2_SpatialColor_20261028兼容文件名同步为同一最新版；修改前输出已随工程备份。为避免下载器缓存旧选择，首次测试应重新选中30日新命名bit。','旧命名 bit/zip 保留为历史版本；本次请选 Anlu2_EightTrails_20261030.bit 或相同内容的主工程标准输出。')
s=s.replace('本轮说明见doc/RESOURCE_COMBO_20261030.md。','最新八轨迹修复见doc/EIGHT_TRAILS_20261030.md；之前资源优化见doc/RESOURCE_COMBO_20261030.md。')
s=s.replace('可用prepare_tests.py更新工程根路径','可用tools/multi_trail_20261030/prepare_tests.py更新工程根路径')
detail=status.split('\n',1)[1].strip()+'\n'
readme.write_text(s.rstrip()+'\n\n## 本轮验证结果\n\n'+detail,encoding='utf-8')
doc=r/'doc/EIGHT_TRAILS_20261030.md';s=doc.read_text(encoding='utf-8').split('## 最终主工程结果')[0];doc.write_text(s.rstrip()+'\n\n## 最终主工程结果\n\n'+detail,encoding='utf-8')
files=set(p for p in (r/'user_source').rglob('*') if p.is_file());files.update(configs)
files.update([readme,doc,r/'BUILD_STATUS.md',r/'tools/rebuild.ps1',named,bit,out/'manifest.json',b/'source_audit.json',b/'production_changes.patch'])
for folder in [Path(__file__).parent,r/'sim/reference'/tag,r/'sim/tb'/tag,r/'sim/models/resource_combo_20261030',r/'sim/reference/resource_combo_20261030']:
 files.update(p for p in folder.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name not in ['apply.py','sampler.v.txt'])
files.add(r/'tools/resource_combo_20261030/generate_shading_rom.py')
for folder in [b,r/'sim/build/resource_combo_20261030']:
 files.update(folder.glob('*.hex'))
files.add(b/'display_paths.v')
for n in ['units','budget','display']:
 files.add(b/(n+'.log'));files.add(r/'sim'/('run_multi_trail_'+n)/'run.do')
for n in ['synthesis','route']:files.add(b/(n+'.log'))
for n in ['route.qor','camera_to_dsi_display_phy.area','camera_to_dsi_display_pr.timing','route_clock_utilization.txt']:files.add(phy/n)
archive=out/(stem+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(files):z.write(p,'Anlu2/'+p.relative_to(r).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert [n for n in z.namelist() if n.endswith('.al')]==['Anlu2/td_project/camera_to_dsi_display.al']
 for n,h in {**manifest['production_sha256'],**manifest['config_sha256'],manifest['named_bit']:sha(bit),manifest['standard_bit']:sha(bit)}.items():assert hashlib.sha256(z.read('Anlu2/'+n)).hexdigest()==h,n
(out/(stem+'.zip.sha256')).write_text(sha(archive)+'  '+archive.name+'\n',encoding='utf-8')
print(json.dumps({'bit':str(named),'zip':str(archive),'sha256':sha(bit),'metrics':metrics},indent=2))
print('PASS publication: latest-main source audit, fresh successful native synthesis/place/route/bit generation, capacity/timing, three new regression suites, portable ZIP CRC/source/config/bit verification')

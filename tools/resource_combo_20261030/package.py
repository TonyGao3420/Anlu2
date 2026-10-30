from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,re,shutil,zipfile,runpy
r=Path(__file__).resolve().parents[2];tag='resource_combo_20261030';b=r/'sim/build'/tag;out=r/'output'
runpy.run_path(str(Path(__file__).with_name('audit.py')),run_name='__main__')
m=json.loads((b/'record.json').read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for p,h in m['optimization_color_sha256'].items():assert sha(r/p)==h,'Color changed after optimization verification'
markers={'color_equivalence':'PASS color_equivalence:','opt_equivalence':'PASS resource_equivalence:',
 'union_mask':'PASS union_mask:','combo_coldboot_final':'PASS combo_coldboot:','combo_integration':'PASS combo_integration:'}
if m.get('overlay_box_reuse'):markers['overlay_reuse']='PASS overlay_reuse:'
if m.get('awb_serial_exact'):
 markers['awb_divider']='PASS awb_divider:';markers['awb_frame']='PASS awb_frame:'
tests={}
if m.get('overlay_box_reuse'):
 newest=max((r/n).stat().st_mtime for n in ['user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/hdmi_mixer.v'])
 for n in ['combo_coldboot_final','combo_integration','overlay_reuse']:assert (b/(n+'.log')).stat().st_mtime>newest,'Stale '+n
for n,mark in markers.items():
 s=(b/(n+'.log')).read_text(errors='replace', encoding='utf-8-sig');assert mark in s and 'Errors: 0' in s,n
 assert not re.search(r'\*\*\s*(?:Fatal|Error)|Errors:\s*[1-9]',s),n
 tests[n]=next(x.strip('# \r') for x in s.splitlines() if mark in x)
for n in ['combo_synthesis','final_route']:
 s=(b/(n+'.log')).read_text(errors='replace', encoding='utf-8-sig');assert not re.search(r'\bERROR\b',s),n
 assert 'export_db' in s,n
phy=r/'td_project/camera_to_dsi_display_Runs/phy_1';syn=phy.parent/'syn_1';q=(phy/'route.qor').read_text(encoding='utf-8-sig')
metric=lambda k:int(re.search(r'\|\s*'+re.escape(k)+r'\s*\|\s*(-?\d+)',q)[1])
metrics={k:metric(k) for k in ['Setup WNS','Hold WNS','Setup TNS','Hold TNS','#slices','#RAMs','#DSPs']}
assert metrics['Setup WNS']>=0 and metrics['Hold WNS']>=0 and metrics['Setup TNS']==metrics['Hold TNS']==0
assert metrics['#slices']<=21216 and metrics['#RAMs']<=108 and metrics['#DSPs']<=40
bit=phy/'camera_to_dsi_display.bit';gate=syn/'camera_to_dsi_display_gate.db';pr=phy/'camera_to_dsi_display_pr.db';place=phy/'camera_to_dsi_display_place.db'
assert bit.stat().st_mtime>pr.stat().st_mtime>place.stat().st_mtime>gate.stat().st_mtime>max((r/p).stat().st_mtime for p in m['production_sha256'])
assert re.search(r'I_sw3\s+INPUT\s+E11', (phy/'camera_to_dsi_display_phy.area').read_text(encoding='utf-8-sig'))
seed=m['selected_seed'];assert f'place seed {seed}' in (phy/'settings.cfg').read_text(encoding='utf-8-sig') and f'set_param place seed {seed}' in (phy/'camera_to_dsi_display.tcl').read_text(encoding='utf-8-sig')
effort=m.get('selected_route_effort','normal')
if effort=='routability':assert 'route effort routability' in (phy/'settings.cfg').read_text(encoding='utf-8-sig') and 'set_param route effort routability' in (phy/'camera_to_dsi_display.tcl').read_text(encoding='utf-8-sig')
stem='Anlu2_Combo_Optimized_20261030';out.mkdir(exist_ok=True);named=out/(stem+'.bit');shutil.copy2(bit,named)
aliases=['Anlu2_Final_4Mode_20261028','Anlu2_SpatialColor_20261028']
for a in aliases:shutil.copy2(bit,out/(a+'.bit'))
configs=[r/'td_project/camera_to_dsi_display.al',r/'td_project/camera_to_dsi_display.sdc']
for d in [syn,phy]:configs.extend(d/n for n in ['camera_to_dsi_display.prj','settings.cfg','camera_to_dsi_display.tcl'])
manifest={'release':stem,'generated_utc':datetime.now(timezone.utc).isoformat(),'board_test_performed':False,
 'main_project':'td_project/camera_to_dsi_display.al','generated_from_current_Anlu2':True,'selected_layout_seed':seed,'route_effort':effort,'actual_implementation_run':m['selected_run'],
 'standard_bit':bit.relative_to(r).as_posix(),'named_bit':named.relative_to(r).as_posix(),'bit_sha256':sha(bit),'metrics_ps_and_resource_counts':metrics,
 'tests':tests,'awb_exact_48_bit_quotient_same_50_clock_done':bool(m.get('awb_serial_exact')),'latest_color_nodes':m['latest_color_nodes'],'production_sha256':m['production_sha256'],
 'config_sha256':{p.relative_to(r).as_posix():sha(p) for p in configs},'before_source_sha256':m['before_source_sha256'],
 'optimization_only_bit_sha256':m['optimization_bit_sha256'],'optimization_only_qor':m['optimization_metrics'],
 'implementation_database_sha256':{'gate':sha(gate),'place':sha(place),'route':sha(pr)},
 'preserved':'Latest user nine-point calibration, updated servo parameters, original modes, camera/RAW/ISP/rotation/ROI/trajectory/Logo/pins/clocks',
 'new_combination':'SW2 style and SW3 multi independently enabled; all valid ROI rectangles retain original corrected RGB; existing primary trail and servo remain'}
status=(f'## 本轮验证结果\n\n最终组合版：Slice {metrics["#slices"]}/21216，ERAM {metrics["#RAMs"]}/108，DSP {metrics["#DSPs"]}/40；'
 f'Setup +{metrics["Setup WNS"]}ps、Hold +{metrics["Hold WNS"]}ps，TNS均0。\n\n'
 '先完成不改变功能的资源优化及5529600像素旧四模式对照，再接入组合模式。2764800像素最新校色对照逐位一致；'
 '6451200像素组合整合、八ROI并集/坐标复用等价、1843200像素八目标组合冷启动均通过。原独立模式RGB、ROI、PWM和读请求保持一致。\n\n'
 f'布局Seed {seed}已同时写入GUI自定义物理脚本及CLI配置，未改变引脚或时钟约束。综合报告中带星号的Slice是估算值，最终容量以此处物理结果为准。\n\n'
 f'新比特流：output/{stem}.bit；主输出与两份旧命名兼容文件内容一致。SHA256：`{sha(bit)}`。未上板验收。\n')
for p in [r/'README.md',r/'doc/RESOURCE_COMBO_20261030.md']:
 s=p.read_text(encoding='utf-8').split('## 本轮验证结果')[0].rstrip();p.write_text(s+'\n\n'+status,encoding='utf-8')
(r/'BUILD_STATUS.md').write_text('# 当前资源优化及组合模式主工程已完成软件验证\n\n'+status,encoding='utf-8')
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
files={p for p in (r/'user_source').rglob('*') if p.is_file()};files.update(configs)
files.update([r/'README.md',r/'BUILD_STATUS.md',r/'doc/RESOURCE_COMBO_20261030.md',r/'tools/rebuild.ps1',named,bit,out/'manifest.json',b/'record.json',b/'source_audit.json'])
files.update(out/(a+'.bit') for a in aliases)
for n in ['prepare_tests.py','prepare_combo_tests.py','audit.py','rebuild.ps1','package.py','generate_shading_rom.py']:files.add(Path(__file__).parent/n)
for folder in [r/'sim/reference'/tag,r/'sim/models'/tag,r/'sim/tb'/tag]:files.update(p for p in folder.rglob('*') if p.is_file())
for n in markers:files.add(b/(n+'.log'))
for n in ['combo_synthesis','final_route','opt_synthesis','opt_route']:files.add(b/(n+'.log'))
for n in ['color','mask','coldboot','combo','equivalence','overlay','awb','awb_frame']:files.add(r/'sim'/('run_resource_'+n)/'run.do')
files.update(b.glob('*.hex'))
for n in ['route.qor','camera_to_dsi_display_phy.area','camera_to_dsi_display_pr.timing','route_clock_utilization.txt']:files.add(phy/n)
archive=out/(stem+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(files):z.write(p,'Anlu2/'+p.relative_to(r).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert [n for n in z.namelist() if n.endswith('.al')]==['Anlu2/td_project/camera_to_dsi_display.al']
 for p,h in {**manifest['production_sha256'],**manifest['config_sha256'],manifest['named_bit']:sha(bit),manifest['standard_bit']:sha(bit)}.items():assert hashlib.sha256(z.read('Anlu2/'+p)).hexdigest()==h,p
for a in [stem]+aliases:
 if a!=stem:shutil.copy2(archive,out/(a+'.zip'))
 (out/(a+'.zip.sha256')).write_text(sha(archive)+'  '+a+'.zip\n', encoding='utf-8')
print('PASS current main publication: exact latest colors, preserved latest functionality, independent/combined modes, fresh physical implementation, capacity/timing, ZIP CRC and all source/config/bit hashes')
print(json.dumps({'bit':str(named),'zip':str(archive),'sha256':sha(bit),'metrics':metrics,'seed':seed},indent=2))

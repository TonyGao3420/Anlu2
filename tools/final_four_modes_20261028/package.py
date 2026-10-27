"""Publish only after the current Anlu2 sources pass the complete local flow."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re, runpy, shutil, zipfile

r=Path(__file__).resolve().parents[2]
tag='final_four_modes_20261028'; stem='Anlu2_Final_4Mode_20261028'
b=r/'sim/build'/tag; out=r/'output'; phy=r/'td_project/camera_to_dsi_display_Runs/phy_1'
syn=r/'td_project/camera_to_dsi_display_Runs/syn_1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:p.read_text(encoding='utf-8-sig',errors='replace')
runpy.run_path(str(Path(__file__).with_name('audit.py')),run_name='__main__')
m=json.loads(read(b/'merge_record.json'))
markers={'slots':'PASS multi_slots:','latency':'PASS frame_latency:','tracker':'PASS multi_tracker:',
         'coldboot':'PASS final_coldboot:','main':'PASS final_main_vtc:'}
passed={}
for name,marker in markers.items():
    s=read(b/(name+'.log'))
    assert marker in s and 'Errors: 0' in s, name+' simulation not passed'
    assert not re.search(r'\*\*\s*(?:Fatal|Error)|Errors:\s*[1-9]|readmem.*(?:fail|unable)',s,re.I),name
    passed[name]=next(line.strip('# \r') for line in s.splitlines() if marker in line)
for name in ['synthesis','route_bitgen']:
    s=read(b/(name+'.log'))
    assert not re.search(r'\bERROR\b|CRITICAL[- ]ERROR',s,re.I),name+' contains errors'
    assert 'export_db' in s,name+' incomplete'
assert 'bitgen' in read(b/'route_bitgen.log'), 'Bitgen missing'
q=read(phy/'route.qor')
def metric(label):
    hit=re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)\s*\|',q)
    assert hit,'Missing QoR '+label
    return int(hit[1])
metrics={k:metric(k) for k in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS','#slices','#RAMs','#DSPs']}
assert metrics['Setup WNS']>=0 and metrics['Hold WNS']>=0
assert metrics['Setup TNS']==metrics['Hold TNS']==0
assert metrics['#slices']<=21216 and metrics['#RAMs']<=108 and metrics['#DSPs']<=40
area=read(phy/'camera_to_dsi_display_phy.area')
assert re.search(r'I_sw3\s+INPUT\s+E11\s+LVCMOS33',area),'SW3 physical binding mismatch'
bit=phy/'camera_to_dsi_display.bit'; gate=syn/'camera_to_dsi_display_gate.db'
placed=phy/'camera_to_dsi_display_place.db'; routed=phy/'camera_to_dsi_display_pr.db'
latest_source=max((r/n).stat().st_mtime for n in m['production_sha256'])
assert bit.stat().st_mtime>routed.stat().st_mtime>placed.stat().st_mtime>gate.stat().st_mtime>latest_source,'Stale implementation output'
assert (phy/'route.qor').stat().st_mtime>gate.stat().st_mtime,'Stale QoR'
out.mkdir(exist_ok=True); named=out/(stem+'.bit');shutil.copy2(bit,named)
assert sha(bit)==sha(named)
m['new_main_bit_generated']=True
m['new_main_bit_sha256']=sha(bit)
(b/'merge_record.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
configs=[r/'td_project/camera_to_dsi_display.al',r/'td_project/camera_to_dsi_display.sdc']
for d in [syn,phy]:configs += [d/'settings.cfg',d/'camera_to_dsi_display.prj',d/'camera_to_dsi_display.tcl']
manifest={'release':stem,'generated_utc':datetime.now(timezone.utc).isoformat(),
 'authoritative_project':'Anlu2/td_project/camera_to_dsi_display.al',
 'generated_from_merged_main':True,'board_test_performed':False,
 'standard_bit':bit.relative_to(r).as_posix(),'named_bit':named.relative_to(r).as_posix(),
 'bit_sha256':sha(bit),'metrics_ps_and_resource_counts':metrics,
 'capacity':{'slices':21216,'ERAM':108,'DSP':40},
 'tests':passed,'production_sha256':m['production_sha256'],
 'config_sha256':{p.relative_to(r).as_posix():sha(p) for p in configs},
 'backup_before_merge':m['backup'],'changed_hardware':m['changed_hardware'],
 'previous_main_bit_sha256':m['previous_main_bit_sha256'],
 'reference_four_mode_bit_sha256':m['reference_four_mode_bit_sha256'],
 'build_evidence':{p.relative_to(r).as_posix():{'sha256':sha(p),'mtime_utc':datetime.fromtimestamp(p.stat().st_mtime,timezone.utc).isoformat()}
                   for p in [gate,placed,routed,bit,b/'synthesis.log',b/'route_bitgen.log',phy/'route.qor']}}
status=(f'## 本次主工程构建结果\n\n合并后Anlu2重新完成全部5项仿真、综合、布局布线及bitgen。'
 f"Slice {metrics['#slices']}/21216，ERAM {metrics['#RAMs']}/108，DSP {metrics['#DSPs']}/40；"
 f"Setup WNS +{metrics['Setup WNS']}ps，Hold WNS +{metrics['Hold WNS']}ps，TNS均0。\n\n"
 '原三模式5529600像素逐位对比通过（统一增加3个对齐像素时钟），原主目标反馈/PWM逐周期一致；'
 '直接拨SW3启动8目标、独立区域/关联/容量、真实DDR槽位延迟测试均通过。\n\n'
 f'标准主输出与output/{stem}.bit完全相同。SHA256：`{sha(bit)}`。本次没有实板验证。\n')
for doc in [r/'README.md',r/'doc/FINAL_FOUR_MODES_20261028.md']:
    original=read(doc).split('## 本次主工程构建结果')[0].rstrip()
    doc.write_text(original+'\n\n'+status,encoding='utf-8')
(r/'BUILD_STATUS.md').write_text('# 四模式主工程已完成编译与软件验证\n\n'+status+
 '\n工程入口为td_project/camera_to_dsi_display.al。仅从本次Anlu2新编译结果发布比特流。\n',encoding='utf-8')
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

# Allowlist a self-contained submission: one public project, no historical caches or old bits.
files=set(p for p in (r/'user_source').rglob('*') if p.is_file())
files.update(configs)
files.update([r/'README.md',r/'BUILD_STATUS.md',r/'doc/FINAL_FOUR_MODES_20261028.md',r/'tools/rebuild.ps1',
              bit,named,out/'manifest.json',b/'merge_record.json',b/'source_audit.json',phy/'route.qor',phy/'camera_to_dsi_display_phy.area'])
for name in ['prepare_tests.py','audit.py','rebuild.ps1','package.py']:files.add(Path(__file__).parent/name)
for folder in [r/'sim/reference'/tag,r/'sim/models'/tag,r/'sim/tb'/tag]:
    files.update(p for p in folder.rglob('*') if p.is_file())
for name in markers:
    files.add(r/'sim'/('run_final_'+name)/'run.do');files.add(b/(name+'.log'))
for name in ['synthesis','route_bitgen']:files.add(b/(name+'.log'))
for p in b.glob('official_logo_*.hex'):files.add(p)
for name in ['camera_to_dsi_display_pr.timing','route_clock_utilization.txt']:
    if (phy/name).is_file():files.add(phy/name)
archive=out/(stem+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(files):z.write(p,'Anlu2/'+p.relative_to(r).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None,'ZIP CRC failure'
    assert [n for n in z.namelist() if n.endswith('.al')]==['Anlu2/td_project/camera_to_dsi_display.al']
    for n,h in {**manifest['production_sha256'],**manifest['config_sha256'],manifest['standard_bit']:sha(bit),manifest['named_bit']:sha(bit)}.items():
        assert hashlib.sha256(z.read('Anlu2/'+n)).hexdigest()==h,n
(out/(stem+'.zip.sha256')).write_text(sha(archive)+'  '+archive.name+'\n',encoding='utf-8')
print('PASS publication: freshly built Anlu2; all tests/timing/resources/physical E11/freshness/ZIP CRC/content hashes checked')
print(json.dumps({'bit':str(named),'zip':str(archive),'sha256':sha(bit),'metrics':metrics},ensure_ascii=False,indent=2))

from pathlib import Path
import hashlib,json,re,shutil,zipfile
root=Path(__file__).resolve().parents[2];build=root/'sim/build/roi_original_20261027'
backup=root.parent/'recovery_backups/Anlu2_before_roi_original_20261027'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
production=sorted(p for p in (root/'user_source').rglob('*') if p.is_file())
changed=[p.relative_to(root).as_posix() for p in production if sha(p)!=sha(backup/p.relative_to(root))]
assert changed==['user_source/hdl_source/video/roi_background_stylize.v'],changed
old=(backup/changed[0]).read_text(encoding='utf-8-sig');new=(root/changed[0]).read_text(encoding='utf-8-sig')
expected=old.replace('else if(v1[26] || (v1[25] && (!MODEL_STYLE_ENABLE || v1[30])))stage_rgb<=v1[23:0];','else if(v1[26] || v1[25])stage_rgb<=v1[23:0];')
expected=expected.replace('   else if(center[57] && green)out_rgb<=filtered;','   // The complete selected rectangle is the normal camera image. Never\n   // threshold or median-filter its pixels; only its exterior is stylized.\n   else if(center[57])out_rgb<=center[31:8];')
assert new==expected,'Unexpected source change'
checks={'small.log':'PASS ROI_original FULL0: 184320 pixels','full.log':'PASS ROI_original FULL1: 2764800 pixels','synthesis.log':'export_db camera_to_dsi_display_gate.db','route_bitgen.log':'finish command "bitgen -bit camera_to_dsi_display.bit"'}
for name,marker in checks.items():
 text=(build/name).read_text(errors='replace');assert marker in text and not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b',text),name
run=root/'td_project/camera_to_dsi_display_Runs';phy=run/'phy_1';qor=(phy/'route.qor').read_text()
metric=lambda s:int(re.search(r'\|\s*'+re.escape(s)+r'\s*\|\s*(-?\d+)',qor)[1])
resources={k:metric(v) for k,v in [('slices','#slices'),('ERAM','#RAMs'),('DSP','#DSPs')]}
assert resources['slices']<=21216 and resources['ERAM']<=108 and resources['DSP']<=40
assert metric('Setup WNS')>=0 and metric('Hold WNS')>=0 and metric('Setup TNS')==metric('Hold TNS')==0
bit=phy/'camera_to_dsi_display.bit';assert bit.stat().st_mtime>(phy/'camera_to_dsi_display_pr.db').stat().st_mtime>(run/'syn_1/camera_to_dsi_display_gate.db').stat().st_mtime>max(p.stat().st_mtime for p in production)
artifact=build/'Anlu2_ROI_Original_20261028.bit';archive=build/'Anlu2_ROI_Original_20261028.zip';shutil.copy2(bit,artifact)
report=f'''# ROI整框原图修复（2026-10-28）

第三模式ROI整个矩形内恢复正常彩色原图，不再逐像素判绿或中值修改目标。原有Logo、框、坐标文字仍叠加；仅框外保持现有灰色风格化。普通模式、舵机、拨码、颜色校正、180度转正和一秒轨迹不变。

生产源码只改roi_background_stylize.v的两处ROI选择。显示延迟、VS/HS/DE/保护/模式/ROI标记不变。小画面184320像素和完整720p三帧2764800像素通过：所有ROI原RGB（含红蓝白暗面及噪点）精确一致，其他像素与修改前逐位相同。

完整主工程综合/布局布线/bitgen通过：{resources}；Setup +{metric('Setup WNS')}ps、Hold +{metric('Hold WNS')}ps，TNS均0。继承原时钟/舵机警告，不声称全部路径已约束。

主入口td_project/camera_to_dsi_display.al，命名bit与主输出SHA256一致：{sha(bit)}。本版未上板。第四模式另在../Anlu2_MultiTarget_20261028开发，不覆盖本修复版。
'''
doc=root/'doc/ROI_ORIGINAL_20261028.md';doc.write_text(report,encoding='utf-8')
config=[root/'td_project/camera_to_dsi_display.al',root/'td_project/camera_to_dsi_display.sdc']
for p in config:assert sha(p)==sha(backup/p.relative_to(root))
manifest={'resources':resources,'setup_ps':metric('Setup WNS'),'hold_ps':metric('Hold WNS'),'bit_sha256':sha(bit),'source_sha256':{p.relative_to(root).as_posix():sha(p) for p in production+config},'changed_hardware':changed,'checks':checks,'board_test_performed':False}
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in production+config+[doc]:z.write(p,'Anlu2/'+p.relative_to(root).as_posix())
 z.write(artifact,'Anlu2/output/'+artifact.name)
 z.writestr('Anlu2/README.md',report+'\n保留整个user_source目录，正常TD GUI编译无需Python。\n')
 z.writestr('Anlu2/verification/manifest.json',json.dumps(manifest,indent=2))
 for name in checks:z.write(build/name,'Anlu2/verification/'+name)
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for p in production+config:assert hashlib.sha256(z.read('Anlu2/'+p.relative_to(root).as_posix())).hexdigest()==sha(p)
manifest['archive_sha256']=sha(archive);(build/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('PASS ROI original release',resources,metric('Setup WNS'),sha(bit),flush=True)

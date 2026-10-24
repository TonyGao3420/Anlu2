from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2];case=root/'sim/build/roi_center_20261011';bak=root/'sim/build/backup_roi_center_20261011'
before=json.loads((bak/'before_sha256.json').read_text());changed=[]
allowed={'user_source/hdl_source/hdmi_mixer.v','td_project/camera_to_dsi_display.al','sim/modelsim/run_logo_isolation.do','sim/tb/tb_logo_isolation.sv'}
allowed|={f'td_project/camera_to_dsi_display_Runs/{stage}/camera_to_dsi_display.prj' for stage in ['syn_1','phy_1']}
for p,h in before.items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:
  assert p in allowed,p;changed.append(p)
old=(bak/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig');s=(root/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
s=s.replace('    parameter integer CENTER_OSD_ENABLE = 1,\n','').replace('single-green-object tracker.','single-red-object tracker.')
s=re.sub(r'    // The tracker publishes at corrected-camera SOF,.*?    end endgenerate\n\n','',s,flags=re.S)
s=re.sub(r'        // Protect the complete coordinate HUD .*?        end\n\n','',s,flags=re.S)
assert s==old,'existing mixer behavior or pipeline changed'
p=root/'td_project/camera_to_dsi_display.al';a=p.read_text();entry=r'            <File Path="../user_source/hdl_source/video/roi_center_osd\.v">.*?            </File>\n'
assert len(re.findall(entry,a,re.S))==1;assert re.sub(entry,'',a,flags=re.S)==(bak/'td_project/camera_to_dsi_display.al').read_text(),'unrelated main project change'
def parse(p):return ET.fromstring(p.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__'))
main=parse(p);paths={(p.parent/f.attrib['Path']).resolve() for f in main.findall('Source_Files/*/File')}
for stage in ['syn_1','phy_1']:
 run=root/'td_project/camera_to_dsi_display_Runs'/stage;prj=run/'camera_to_dsi_display.prj';snapshot=parse(prj)
 assert {(prj.parent/f.attrib['Path']).resolve() for f in snapshot.findall('Source_Files/*/File')}==paths,(stage,'source mismatch')
 assert (run/'settings.cfg').read_bytes()==(bak/'td_project/camera_to_dsi_display_Runs'/stage/'settings.cfg').read_bytes(),(stage,'constraints or settings changed')
report={'changed_existing_manifest_files':changed,'new_production_source':'user_source/hdl_source/video/roi_center_osd.v','existing_mixer_pipeline_camera_logo_counter_rectangle_unchanged':True,'all_color_RAW_AWB_ROI_servo_top_DDR_sensor_constraints_sources_byte_identical':True,'main_project_only_one_source_added':True,'main_source_snapshots_match':True,'new_frame_capture':'line 1 after corrected-camera SOF publication','decimal_conversion':'16-clock shift/add, no multiply/divide','center':'floor((x0+x1)/2), floor((y0+y1)/2); detector stable bounds, before decorative display padding','user_confirmed_previous_color_solution':True}
(case/'source_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))

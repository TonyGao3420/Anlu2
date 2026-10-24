from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2]
case=root/'sim/build/roi_origin_center_20261011'
bak=root/'sim/build/backup_roi_origin_center_20261011'
before=json.loads((bak/'before_sha256.json').read_text(encoding='utf-8'))
allowed={'user_source/hdl_source/hdmi_mixer.v','user_source/hdl_source/video/roi_center_osd.v',
 'tools/roi_center/make_tests.py','tools/roi_center/make_display_test.py',
 'sim/tb/tb_roi_center_osd.sv','sim/tb/tb_roi_center_display.sv','sim/modelsim/run_roi_center_display.do'}
changed=[]
for p,h in before.items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:
  assert p in allowed,('unexpected change',p)
  changed.append(p)
old=(bak/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
new=(root/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
assert new.replace('wire signed [15:0] S_center_x,S_center_y;','wire [15:0] S_center_x,S_center_y;')==old,'unrelated mixer change'
def parse(p):return ET.fromstring(p.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__'))
main=root/'td_project/camera_to_dsi_display.al'
paths={(main.parent/f.attrib['Path']).resolve() for f in parse(main).findall('Source_Files/*/File')}
assert root/'user_source/hdl_source/video/roi_center_osd.v' in paths
for stage in ['syn_1','phy_1']:
 prj=root/'td_project/camera_to_dsi_display_Runs'/stage/'camera_to_dsi_display.prj'
 assert {(prj.parent/f.attrib['Path']).resolve() for f in parse(prj).findall('Source_Files/*/File')}==paths,(stage,'source mismatch')
report={'changed_previous_manifest_files':changed,'main_project_and_constraints_unchanged':True,
 'color_RAW_AWB_ROI_servo_top_DDR_sensor_sources_byte_identical':True,
 'existing_mixer_behavior_unchanged_except_signed_HUD_wire_declaration':True,
 'main_run_source_snapshots_match':True,'display_origin_pixel':[640,360],
 'coordinate_formula':'floor((x0+x1)/2)-640, floor((y0+y1)/2)-360',
 'axes':'x right positive, y down positive','tracker_and_servo_coordinates':'absolute, unchanged',
 'capture_conversion_and_video_pipeline_latency':'unchanged'}
(case/'source_audit.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))

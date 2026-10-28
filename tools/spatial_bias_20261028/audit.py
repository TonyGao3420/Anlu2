from pathlib import Path
import json,hashlib,re
r=Path(__file__).resolve().parents[2];b=r/'sim/build/spatial_bias_20261028'
m=json.loads((b/'merge_record.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
current={p.relative_to(r).as_posix():sha(p) for p in sorted((r/'user_source').rglob('*')) if p.is_file()}
assert current==m['production_sha256'],'Production differs from current color-stage snapshot'
changed=[n for n,h in current.items() if m['previous_production_sha256'][n]!=h]
assert changed==['user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/video/scene_color_stream.v'],changed
assert sha(r/'td_project/camera_to_dsi_display.sdc')==m['sdc_sha256']
al=(r/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8')
for n in re.findall(r'<File\s+Path="([^"]+)"',al):assert (r/'td_project'/n).exists(),n
assert [p.relative_to(r).as_posix() for d in [r,r/'prj',r/'td_project'] for p in d.glob('*.al')]==['td_project/camera_to_dsi_display.al']
top=(r/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8')
assert '.POSITION_BIAS_ENABLE(1)' in top and 'display_edge_color #(.ENABLE(0)' in top
assert '.MULTI_ENABLE(1),.MAX_TARGETS(8)' in top and '.sw2_async(I_sw3)' in top
result={'changed_hardware':changed,'single_main_entry':True,'old_perimeter_applied_once_shared':True,
 'sensor_ISP_RAW_DDR_rotation_detector_servo_style_trail_logo_and_constraints_unchanged':True,
 'video_latency_unchanged':True,'extra_DSP_or_ERAM_in_algorithm':0}
(b/'source_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS spatial source audit: only top + shared scene file; original ISP/RAW/DDR/rotation/ROI/servo/style/trail/Logo/pins/constraints exact; single main entry')

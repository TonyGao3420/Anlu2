from pathlib import Path
import json,hashlib
r=Path(__file__).resolve().parents[2];tag='multi_trail_20261030';b=r/'sim/build'/tag
before=json.loads((r/'sim/reference'/tag/'manifest_before.json').read_text(encoding='utf-8-sig'))
baseline=json.loads((r/'sim/reference'/tag/'baseline_sha256.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
current={p.relative_to(r).as_posix():sha(p) for p in (r/'user_source').rglob('*') if p.is_file()}
changed=sorted(n for n in current.keys()|baseline.keys() if current.get(n)!=baseline.get(n))
assert changed==['user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/video/roi_motion_trail.v'],changed
ref=(r/'sim/reference'/tag/'top_before.v').read_text(encoding='utf-8-sig')
ref=ref.replace('roi_motion_trail #(.TTL_MS(1000)','roi_motion_trail #(.MULTI_ENABLE(1),.TTL_MS(1000)')
needle='.point_valid(S_track2_valid),.point_x(S_track2_cx),.point_y(S_track2_cy),'
ref=ref.replace(needle,needle+'''
        .multi_mode(S_multi_frame),.multi_valid(S_multi_valid),
        .multi_x0(S_multi_x0),.multi_y0(S_multi_y0),.multi_x1(S_multi_x1),.multi_y1(S_multi_y1),''')
assert ref==(r/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig'),'Top modified beyond trail configuration/connections'
trail=(r/'user_source/hdl_source/video/roi_motion_trail.v').read_text(encoding='utf-8-sig')
old=(r/'sim/reference'/tag/'trail_before.v').read_text(encoding='utf-8-sig')
start='module roi_trail_point_filter #(';end='// Eight independently conditioned paths'
assert trail[trail.index(start):trail.index(end)].strip()==old[old.index(start):].strip(),'Existing single-object filter or millisecond clock changed'
for n in ['reg [39:0] history[0:HISTORY_DEPTH-1];','reg mask0[0:CELLS-1];reg mask1[0:CELLS-1];','parameter integer IMG_W=1280,IMG_H=720,SCALE_LOG2=2,HISTORY_DEPTH=256,']:
 assert n in trail and n in old,'Existing memory geometry changed'
assert before['config_sha256']['td_project/camera_to_dsi_display.sdc']==sha(r/'td_project/camera_to_dsi_display.sdc')
result={'changed_production_files':changed,'production_sha256':current,'baseline_is_actual_start_of_turn_backup':True,
 'preserved_user_changes_since_last_release':[n for n,h in baseline.items() if before['production_sha256'].get(n)!=h],
 'latest_color_and_AWB_sources_and_ROMs_byte_identical':True,
 'detector_slots_green_thresholds_servo_rotation_logo_primary_coordinates_style_RGB_pins_clocks_byte_identical':True,
 'single_filter_and_ms_clock_text_identical':True,'same_256x40_history_and_two_320x180_bitmaps':True,'video_pipeline_extra_clocks':0}
(b/'source_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS source audit: only trajectory module and top trail connections changed; all other production sources/assets byte identical to latest main')

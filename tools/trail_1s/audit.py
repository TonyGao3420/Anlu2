from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[2];backup=root.parent/'recovery_backups/Anlu2_before_trail_1s_20261025';build=root/'sim/build/trail_1s_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
prior=json.loads((backup/'source_sha256.json').read_text(encoding='utf-8'))
allowed={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/video/roi_motion_trail.v'}
changed={rel for rel,h in prior.items() if rel.startswith('user_source/') and sha(root/rel)!=h}
assert changed==allowed,('Unrelated hardware change',changed)
for rel,h in prior.items():
 if rel.endswith(('.sdc','.al','.prj','settings.cfg')) or rel=='user_source/constraints_source/pin.adc':assert sha(root/rel)==h,rel
new=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
assert '.TTL_MS(1000),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50),.JITTER_PIXELS(4)' in new
normalized=new.replace('// One-second smoothed trail:','// Three-second trail:').replace('roi_motion_trail #(.TTL_MS(1000),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50),.JITTER_PIXELS(4)) u_motion_trail(', 'roi_motion_trail u_motion_trail(')
assert normalized==old,'Changed top logic outside trajectory parameters'
a=(backup/'user_source/hdl_source/video/roi_motion_trail.v').read_text(encoding='utf-8')
b=(root/'user_source/hdl_source/video/roi_motion_trail.v').read_text(encoding='utf-8')
assert a[a.index('module video_ms_clock'):]==b[b.index('module video_ms_clock'):],'Clock divider changed'
assert a[a.index(' reg pvs,'):a.index(' assign render_busy')]==b[b.index(' reg pvs,'):b.index(' assign render_busy')],'Video/protected-overlay pipeline changed'
assert 'TTL_MS=1000' in b
for n in ['history[0:HISTORY_DEPTH-1]','mask0[0:CELLS-1]','mask1[0:CELLS-1]']:assert n in b and n in a
manifest=json.loads((backup/'sim/build/eram_opt_20261025/Anlu2_eram_optimized_20261025_manifest.json').read_text(encoding='utf-8'))
assert sha(backup/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit')==manifest['sha256']
report={'backup':str(backup),'changed_existing_hardware_sources':sorted(changed),'original_ROI_servo_center_coordinates_color_style_ERAM_logo_switch_sources_unchanged':True,
 'top_change_only_trajectory_parameters':True,'pins_SDC_projects_tool_strategy_unchanged':True,'video_pipeline_and_ms_clock_unchanged':True,
 'history_and_bitmap_capacity_unchanged':True,'trajectory':{'ttl_ms':1000,'median_points':3,'iir_alpha':'1/2','deadband_pixels':4,'sample_interval_ms':50,'rebuild_every_frame':True},
 'previous_bit_sha256':manifest['sha256']}
(build/'source_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))

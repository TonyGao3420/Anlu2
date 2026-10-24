from pathlib import Path
import hashlib,json,re,shutil
root=Path(__file__).resolve().parents[2];build=root/'sim/build'
route=build/'td_validation_shared_color_roi_20261009/video_check_Runs/phy_1'
qor=(route/'route.qor').read_text()
def metric(label):
 m=re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)',qor)
 assert m,label
 return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
backup=build/'backup_shared_color_roi_20261009'
before=json.loads((backup/'production_before_sha256.json').read_text())
allowed={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/track2/roi_target_tracker.v','td_project/camera_to_dsi_display.al'}
for p,h in before.items():
 if p not in allowed:assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
old=(backup/'user_source/hdl_source/track2/roi_target_tracker.v').read_text()
new=(root/'user_source/hdl_source/track2/roi_target_tracker.v').read_text()
assert old[old.index('module green_region_tracker'):]==new[new.index('module green_region_tracker'):]
old=(root/'sim/color_trial/display_color_shading.v').read_text()
new=(root/'user_source/hdl_source/video/display_color_shading.v').read_text()
assert old[old.index('module display_color_shading'):]==new[new.index('module display_color_shading'):]
al=(root/'td_project/camera_to_dsi_display.al').read_text()
for name in ['display_color_shading','scene_color_stream']:
 pattern=r'            <File Path="../user_source/hdl_source/video/'+name+r'\.v">.*?            </File>\n'
 matches=re.findall(pattern,al,re.S);assert len(matches)==1,name
 assert 'UsedInSyn' in matches[0] and 'UsedInP&R' in matches[0]
 al=re.sub(pattern,'',al,flags=re.S)
assert al==(backup/'td_project/camera_to_dsi_display.al').read_text()
checks={
 'production_regression.log':['ModelSim regression passed.','PASS green highlights'],
 'run_display_color_shading.log':['PASS display_color_shading: 18543 vectors'],
 'run_shared_color_roi.log':['PASS shared_color_roi: 3 complete 720p frames']}
for name,markers in checks.items():
 log=(build/'shared_color_roi_20261009'/name).read_text(errors='replace')
 assert all(s in log for s in markers),name
 assert '** Fatal:' not in log and re.search(r'Errors: [1-9]',log) is None,name
source=route/'video_check.bit';assert source.stat().st_size>1_000_000
target=build/'SC520_shared_color_green_roi_20261009.bit';shutil.copyfile(source,target)
files=list(before)+['user_source/hdl_source/video/display_color_shading.v','user_source/hdl_source/video/scene_color_stream.v',
 'td_project/rebuild_validation_shared_color_roi_20261009.tcl','doc/SHARED_COLOR_GREEN_ROI_20261009.md']
manifest=dict(purpose='shared_calibrated_camera_stream_for_display_and_green_ROI',
 physical_new_bit_color_result_confirmed=False,previous_pure_gray_confirmed_uniform=True,
 previous_display_trial_white_field_reported_improved=True,
 current_calibration_coefficients_identical_to_previous_trial=True,
 normal_project_updated=True,official_isp_awb_mixer_servo_pins_brightness_unchanged=True,
 region_stability_height_algorithm_unchanged=True,near_clip_green_threshold=248,
 camera_color_before_overlay_and_uniform_brightness=True,display_additional_pipeline_cycles=8,
 brightness_all_rgb_gain_q8=272,timing_ps=timing,slices=metric('#slices'),eram=metric('#RAMs'),dsp=metric('#DSPs'),
 bit_bytes=target.stat().st_size,bit_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
 source_sha256={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files},
 source_before_sha256=before,validation_checks=checks,
 limitations='Single-light 9-node calibration; synthetic highlight cases are not measured lamp RGB. Residual scene cast and real lamp false positives require hardware confirmation.',
 rollback_bits=['SC520_display_color_trial_20261009.bit','SC520_official_display_bright_20261009.bit'])
target.with_name(target.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(target);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

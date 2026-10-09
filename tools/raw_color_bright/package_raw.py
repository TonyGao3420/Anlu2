from pathlib import Path
import hashlib,json,re,shutil
root=Path(__file__).resolve().parents[2];build=root/'sim/build';case=build/'raw_color_bright_20261009';route=build/'td_validation_raw_color_bright_20261009/video_check_Runs/phy_1'
qor=(route/'route.qor').read_text()
def metric(n):
 m=re.search(r'\|\s*'+re.escape(n)+r'\s*\|\s*(-?\d+)',qor);assert m,n;return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
checks={
 'production_regression.log':['ModelSim regression passed.','PASS green highlights','PASS ROI height'],
 'run_raw_measured_shading.log':['PASS raw_measured_shading: 230400'],
 'run_awb_frame_stable.log':['PASS awb_frame_stable: six frames'],
 'run_display_common_tone.log':['PASS display_common_tone: 12262'],
 'run_isp_raw_color.log':['PASS isp_raw_color: two complete 720p frames','854628 neutral pixels'],
 'run_raw_corrected_roi_display.log':['PASS raw_corrected_roi_display: 3 complete 720p frames']}
for name,markers in checks.items():
 log=(case/name).read_text(errors='replace');assert all(s in log for s in markers),name
 assert '** Fatal:' not in log and not re.search(r'Errors: [1-9]',log),name
before=json.loads((build/'backup_raw_color_bright_20261009/before_sha256.json').read_text())
allowed={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/isp/isp_top.v','user_source/hdl_source/video/scene_color_stream.v','td_project/camera_to_dsi_display.al'}
for p,h in before.items():
 if p not in allowed:assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
old_manifest=json.loads((build/'SC520_shared_color_green_roi_20261009_manifest.json').read_text())
assert hashlib.sha256((build/'SC520_shared_color_green_roi_20261009.bit').read_bytes()).hexdigest()==old_manifest['bit_sha256']
assert metric('#slices')<=21216 and metric('#RAMs')<=108 and metric('#DSPs')<=40
source=route/'video_check.bit';assert source.stat().st_size>1000000
artifact=build/'SC520_raw_color_bright_20261009.bit';shutil.copyfile(source,artifact)
files=list(before)+['user_source/hdl_source/awb_frame_stable.v','user_source/hdl_source/isp/raw_measured_shading.v','user_source/hdl_source/video/display_common_tone.v','td_project/rebuild_validation_raw_color_bright_20261009.tcl','doc/RAW_COLOR_BRIGHT_20261009.md']
files+= [p.relative_to(root).as_posix() for p in (root/'tools/raw_color_bright').glob('*.py')]
files+=['sim/tb/tb_raw_measured_shading.sv','sim/tb/tb_awb_frame_stable.sv','sim/tb/tb_display_common_tone.sv','sim/tb/tb_isp_raw_color.sv','sim/tb/isp_ram_models.sv','sim/tb/tb_raw_corrected_roi_display.sv']
manifest={
 'purpose':'measured four-plane RAW shading before demosaic; complete-frame AWB; common display-only RGB tone',
 'physical_result_for_this_bit_confirmed':False,'prior_user_white_ROI_fix_confirmed':True,
 'ROI_classifier_regions_servo_pins_SDC_sensor_config_DDR_request_timing_unchanged':True,
 'original_official_awb_source_unchanged':True,'production_main_project_updated':True,
 'build':'full synthesis, place-and-route, bitgen in isolated validation project using current production sources',
 'raw_pipeline_cycles':8,'extra_display_tone_cycles':3,'legacy_post_AWB_RGB_shading_disabled_in_production':True,
 'raw_black_level':64,'awb_and_tone_RGB_black_level':14,
 'awb':'full-frame eligible statistics, once-per-frame gain update, first valid gain direct; later 1/4 slew; original IP/buffering/early SOF',
 'tone':'common RGB gain based on max channel; black-preserving gamma ~0.65, gain capped at 2; white endpoint 255; OSD bypass; ROI upstream',
 'tone_gray_samples':{'32':50,'64':101,'128':162,'192':212,'255':255},
 'timing_ps':timing,'slices':metric('#slices'),'eram':metric('#RAMs'),'dsp':metric('#DSPs'),
 'bit_bytes':artifact.stat().st_size,'bit_sha256':hashlib.sha256(artifact.read_bytes()).hexdigest(),
 'source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in dict.fromkeys(files)},
 'source_before_sha256':before,'validation_checks':checks,
 'calibration':json.loads((case/'calibration.json').read_text()),'source_audit':json.loads((case/'source_audit.json').read_text()),
 'limitations':'Single-light nine-window calibration, black readings are intervals; node2 B transcription has <1% sensitivity. Synthetic spatial white and ROI tests do not constitute hardware optical confirmation. IR-cut presence is unknown.',
 'rollback_bit':'SC520_shared_color_green_roi_20261009.bit'}
artifact.with_name(artifact.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(artifact);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

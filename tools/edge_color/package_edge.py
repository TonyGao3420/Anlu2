from pathlib import Path
import hashlib,json,re,shutil
root=Path(__file__).resolve().parents[2];build=root/'sim/build';case=build/'edge_color_20261009';route=build/'td_validation_edge_color_20261009/video_check_Runs/phy_1'
qor=(route/'route.qor').read_text()
def metric(n):
 m=re.search(r'\|\s*'+re.escape(n)+r'\s*\|\s*(-?\d+)',qor);assert m,n;return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
checks={'run_display_edge_color.log':['PASS display_edge_color: 921600 pixels','complete 15-cycle display/tone controls'],
 'production_regression.log':['ModelSim regression passed.','PASS green highlights','PASS ROI height']}
for name,markers in checks.items():
 log=(case/name).read_text(errors='replace');assert all(s in log for s in markers),name
 assert '** Fatal:' not in log and not re.search(r'Errors: [1-9]',log),name
before=json.loads((build/'backup_edge_color_20261009/before_sha256.json').read_text())
allowed={'user_source/hdl_source/design_top_wrapper.v','td_project/camera_to_dsi_display.al'}
for p,h in before.items():
 if p not in allowed:assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
previous=json.loads((build/'SC520_raw_color_bright_20261009_manifest.json').read_text())
assert hashlib.sha256((build/'SC520_raw_color_bright_20261009.bit').read_bytes()).hexdigest()==previous['bit_sha256']
assert metric('#slices')<=21216 and metric('#RAMs')<=108 and metric('#DSPs')<=40
source=route/'video_check.bit';assert source.stat().st_size>1000000
artifact=build/'SC520_edge_color_20261009.bit';shutil.copyfile(source,artifact)
files=list(before)+['user_source/hdl_source/video/display_edge_color.v','td_project/rebuild_validation_edge_color_20261009.tcl','doc/EDGE_COLOR_20261009.md',
 'sim/tb/tb_display_edge_color.sv','sim/modelsim/run_display_edge_color.do','tools/edge_color/integrate_display.py','tools/edge_color/make_display_tests.py','tools/edge_color/audit_edge.py','tools/edge_color/package_edge.py']
manifest={
 'purpose':'display-only smooth bounded perimeter R/B compensation; upper-left strongest, blue slightly raised on right',
 'physical_result_for_this_bit_confirmed':False,'previous_user_center_green_improved':True,'previous_user_white_ROI_problem_resolved':True,
 'build':'full synthesis, place-and-route, bitgen in isolated validation project using current production sources',
 'RAW_ISP_AWB_ROI_and_ROI_input_servo_tone_mixer_DDR_sensor_constraints_unchanged':True,
 'center_rectangle_new_gain_exact_unity':[384,216,896,504],'main_project_updated':True,'extra_display_pipeline_cycles':6,
 'timing_ps':timing,'slices':metric('#slices'),'eram':metric('#RAMs'),'dsp':metric('#DSPs'),
 'bit_bytes':artifact.stat().st_size,'bit_sha256':hashlib.sha256(artifact.read_bytes()).hexdigest(),
 'source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in dict.fromkeys(files)},'source_before_sha256':before,
 'validation_checks':checks,'source_audit':json.loads((case/'source_audit.json').read_text()),'model_checks':json.loads((case/'model_checks.json').read_text()),
 'edge_calibration':json.loads((case/'edge_calibration.json').read_text()),
 'limitations':'Bounded residual tuning from user photograph/feedback, not a new quantitative sensor flat-field calibration. Physical white-field result requires board confirmation. Original inner RAW table and ROI input are unchanged.',
 'rollback_bit':'SC520_raw_color_bright_20261009.bit'}
artifact.with_name(artifact.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(artifact);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

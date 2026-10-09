from pathlib import Path
import json,hashlib,re,shutil
root=Path(__file__).resolve().parents[2]
build=root/'sim/build'
route=build/'td_validation_color_trial_20261009/video_check_Runs/phy_1'
qor=(route/'route.qor').read_text()
def metric(label):
 m=re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)',qor)
 assert m,label
 return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
hashes=json.loads((build/'backup_color_diagnostic_20261009/production_hashes.json').read_text())
for p,h in hashes.items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
assert 'display_color_shading' not in (root/'td_project/camera_to_dsi_display.al').read_text()
regression=(build/'color_trial_20261009/production_regression.log').read_text(encoding='utf-8-sig',errors='replace')
assert 'ModelSim regression passed.' in regression
log=(build/'color_trial_20261009/run_display_color_shading.log').read_text(errors='replace')
assert 'PASS display_color_shading: 18543 vectors' in log and '** Fatal:' not in log
source=route/'video_check.bit';assert source.stat().st_size>1_000_000
target=build/'SC520_display_color_trial_20261009.bit';shutil.copyfile(source,target)
files=['sim/color_trial/display_color_shading.v','sim/color_trial/design_top_wrapper_color_trial.v',
 'td_project/rebuild_validation_color_trial_20261009.tcl','sim/build/color_trial_20261009/calibration.json',
 'doc/DISPLAY_COLOR_TRIAL_20261009.md']
manifest=dict(purpose='isolated_display_color_trial_measured_white_dark',
 physical_color_result_confirmed=False,production_project_unchanged=True,first_gray_frames=1800,
 roi_servo_input_unchanged=True,official_isp_awb_unchanged=True,brightness_rgb_gain_q8=272,
 timing_ps=timing,slices=metric('#slices'),eram=metric('#RAMs'),dsp=metric('#DSPs'),
 bit_bytes=target.stat().st_size,bit_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
 production_sha256=hashes,trial_source_sha256={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files},
 validations=['18543 reference vectors, eight-stage color and six-stage brightness, controls/protection/blanking/bypass/darks/clipping',
 'seven existing ModelSim regressions passed','full TD synthesis/route/bitgen and nonnegative timing',
 'actual VTC+mixer reproduces old diagnostic count mismatch while DE count and all region means are correct'],
 calibration_note='Provisional: 9-point white RGB, user dark RGB 14/15; old RGB Q incomplete-count caveat recorded in calibration.json.',
 rollback_bit='SC520_official_display_bright_20261009.bit')
target.with_name(target.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(target);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

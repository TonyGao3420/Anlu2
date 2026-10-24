"""Publish the diagnostic bit only after route timing and source audit pass."""
from pathlib import Path
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[2]
build = root/'sim/build'
route = build/'td_validation_color_diagnostic_v2_20261009/video_check_Runs/phy_1'
qor = (route/'route.qor').read_text()


def metric(label):
    found = re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)', qor)
    if not found:
        raise ValueError('Missing QoR metric: '+label)
    return int(found[1])


timing = {label: metric(label) for label in ['Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS']}
assert timing['Setup WNS'] >= 0 and timing['Hold WNS'] >= 0, timing
assert timing['Setup TNS'] == timing['Hold TNS'] == 0, timing
hashes = json.loads((build/'backup_color_diagnostic_20261009/production_hashes.json').read_text())
for path, expected in hashes.items():
    actual = hashlib.sha256((root/path).read_bytes()).hexdigest()
    assert actual == expected, 'Production file changed: '+path
assert 'color_diagnostic' not in (root/'td_project/camera_to_dsi_display.al').read_text()
assert 'u_diag' not in (root/'user_source/hdl_source/design_top_wrapper.v').read_text()
source = route/'video_check.bit'
assert source.stat().st_size > 1_000_000
target = build/'SC520_color_diagnostic_20261009.bit'
shutil.copyfile(source, target)
extra = ['sim/diagnostic/color_diagnostic.v', 'sim/diagnostic/design_top_wrapper_diagnostic.v',
         'td_project/rebuild_validation_color_diagnostic_20261009.tcl',
         'tools/color_diagnostic/analyze_probe.py']
manifest = {
    'purpose': 'isolated_diagnostic_only_no_color_correction_applied',
    'normal_project_unchanged': True,
    'uniform_camera_rgb_gain': '17/16, all three channels; display branch only',
    'gray_test': 'first 300 HDMI frames: RGB=128, protected from enhancement',
    'measurements': '9 RAW BGGR + RGB regions; full-frame counts and clipping flags',
    'physical_color_result_confirmed': False,
    'flashed_to_hardware': False,
    'bit_bytes': target.stat().st_size,
    'bit_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    'timing_ps': timing,
    'slices': metric('#slices'), 'eram': metric('#RAMs'), 'dsp': metric('#DSPs'),
    'protected_production_sha256': hashes,
    'diagnostic_source_sha256': {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in extra},
    'validation': ['nine-window RAW/RGB, clipping, incomplete frames, coupled CDC mailbox simulation',
                   '720p diagnostic render, true gray after production enhancement, 921600 pixels',
                   'production equal-channel brightness regression',
                   'synthetic analysis: uniform, sensor-side shading, ISP-side variation, dark subtraction, invalid input'],
    'qor_report': str(route/'route.qor'),
}
target.with_name(target.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(target)
print('Timing ps:',timing)
print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp'])
print('SHA256:',manifest['bit_sha256'])

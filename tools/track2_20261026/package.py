"""Publish only a fresh, passing current-source motion-style build."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit import audit

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/track2_requirements_20261026'
backup = root.parent / 'recovery_backups/Anlu2_before_motion_style_20261026'
run = root / 'td_project/camera_to_dsi_display_Runs'
phy = run / 'phy_1'
audit_result = audit()
checks = {
    'motion_small.log': [f'PASS motion_style FULL0 run{i}: 1228800 RGB/timing pixels' for i in range(3)]
                        + ['PASS motion watchdog: interrupted stream clears and may resume without reset'],
    'motion_full.log': ['PASS motion_style FULL1 run0: 7372800 RGB/timing pixels'],
    'main_integration.log': ['PASS main_track2: 7372800 full 720p pixels'],
    'production_regression.log': ['ModelSim regression passed.', 'PASS ROI height', 'PASS green highlights'],
    'synthesis.log': ['export_db camera_to_dsi_display_gate.db'],
    'route_bitgen.log': ['export_db camera_to_dsi_display_pr.db', 'bitgen -bit camera_to_dsi_display.bit'],
}
for n in ['roi', 'display', 'color', 'raw10', 'bilinear_color', 'official_awb', 'roi_extent_720p']:
    checks[f'legacy_{n}.log'] = ['Errors: 0']
for name, markers in checks.items():
    log = (build / name).read_text(encoding='utf-8', errors='replace')
    assert all(s in log for s in markers), (name, 'Missing completion/PASS')
    assert not re.search(r'\*\* Fatal:|Errors: [1-9]|\bERROR\b|Run .* failed|invalid command', log), name


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


qor = (phy / 'route.qor').read_text()


def metric(label):
    m = re.search(r'\|\s*' + re.escape(label) + r'\s*\|\s*(-?\d+)', qor)
    assert m, label
    return int(m[1])


resources = {k: metric(n) for k, n in [('slices', '#slices'), ('eram20k', '#RAMs'), ('dsp', '#DSPs')]}
timing = {n: metric(n) for n in ['Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS']}
assert resources['slices'] <= 21216 and resources['eram20k'] <= 108 and resources['dsp'] <= 40, resources
assert timing['Setup WNS'] >= 0 and timing['Hold WNS'] >= 0 and timing['Setup TNS'] == timing['Hold TNS'] == 0
coverage = float(re.search(r'STA coverage\s*:\s*([0-9.]+)%', (phy / 'final_timing.rpt').read_text())[1])


def criticals(path):
    return [s[s.index('CRITICAL-WARNING:'):] for s in path.read_text(errors='replace').splitlines()
            if 'CRITICAL-WARNING:' in s]


old_manifest = json.loads((backup / 'sim/build/gui_compile_fix_20261025/Anlu2_GUI_compile_fixed_20261025_manifest.json').read_text())
route_warnings = criticals(build / 'route_bitgen.log')
assert all(w in old_manifest['inherited_critical_warnings'] for w in route_warnings), route_warnings
syn_warnings = criticals(build / 'synthesis.log')
old_syn_warnings = criticals(backup / 'td_project/camera_to_dsi_display_Runs/syn_1/run.log')
assert syn_warnings == old_syn_warnings, ('New synthesis critical warning', syn_warnings)
production = sorted(p for p in (root / 'user_source').rglob('*') if p.is_file())
config = [root / 'td_project/camera_to_dsi_display.al', root / 'td_project/camera_to_dsi_display.sdc']
config += list(run.glob('*/*.prj')) + list(run.glob('*/settings.cfg'))
bit = phy / 'camera_to_dsi_display.bit'
route = phy / 'camera_to_dsi_display_pr.db'
gate = run / 'syn_1/camera_to_dsi_display_gate.db'
newest_source = max(p.stat().st_mtime for p in production + config)
assert bit.stat().st_mtime > route.stat().st_mtime > gate.stat().st_mtime > newest_source, 'Stale main bit/config/source'
for log in ['motion_small.log', 'motion_full.log', 'main_integration.log', 'production_regression.log']:
    assert (build / log).stat().st_mtime > newest_source, ('Stale simulation', log)

# TD source list is relative; ensure every declared source/IP/constraint exists.
# TD .al permits literal '&' in attributes such as UsedInP&R, so it is
# XML-like, not strict XML. Read only observed File Path attributes.
project_text = config[0].read_text(encoding='utf-8-sig')
entries = re.findall(r'<File\s+Path="([^"]+)"', project_text)
assert len(entries) > 30
for name in entries:
    assert not re.match(r'[A-Za-z]:', name), ('Absolute project source', name)
    assert (config[0].parent / name).is_file(), ('Missing project source', name)

subprocess.run([sys.executable, str(root / 'tools/track2_20261026/make_preview.py')], check=True, cwd=root)
artifact = build / 'Anlu2_motion_style_20261026.bit'
archive = build / 'Anlu2_motion_style_20261026.zip'
shutil.copy2(bit, artifact)
shutil.copy2(phy / 'route.qor', build / 'final_route.qor')
shutil.copy2(phy / 'final_timing.rpt', build / 'final_timing.rpt')
docs = [root / 'doc/TRACK2_REQUIREMENTS_AND_MOTION_STYLE_20261026.md', root / 'doc/TRACK2_BOARD_CHECK_20261026.md']
package_readme = '''# Anlu2 当前主工程（2026-10-26）

打开 td_project/camera_to_dsi_display.al，运行完整综合和物理设计。
生产源码为 user_source/；所有Logo初始化MIF均已包含，必须整目录复制。
无需Python，不依赖原工程Runs缓存。常规输出为
td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit。
output/Anlu2_motion_style_20261026.bit 是同源码已编译产物。

SW2下：原彩色/ROI/坐标；SW2上：彩色ROI+灰度轮廓背景+一秒平滑橙色轨迹
+青色运动区域提示。SW1独立开关原舵机追踪。
右上角MODE表示图像算法；MOT为16×16活动网格数，不是物体个数。
GLOBAL表示大范围变化抑制，未做相机运动补偿。

18234/21216 Slice，104/108 ERAM，40/40 DSP，Setup +166ps，Hold +20ps。
继承原时钟及舵机异步复位/置位警告；STA覆盖96.42%。
本版尚未上板。基础功能已有，长期稳定性/FIFO/剧烈光照与端到端延迟待实测。
详见doc内要求核对及上板方法。验证日志/manifest见verification/。
该干净工程不含离线Python参考数组及ModelSim工作库；工作区中保留完整复验脚本。
'''
files = production + config[:2] + docs
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, 'Anlu2/' + p.relative_to(root).as_posix())
    z.writestr('Anlu2/README.md', package_readme)
    z.write(artifact, 'Anlu2/output/' + artifact.name)
    for name in list(checks) + ['source_audit.json', 'final_route.qor', 'final_timing.rpt']:
        z.write(build / name, 'Anlu2/verification/' + name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for p in files:
        assert hashlib.sha256(z.read('Anlu2/' + p.relative_to(root).as_posix())).hexdigest() == sha(p)
    assert hashlib.sha256(z.read('Anlu2/output/' + artifact.name)).hexdigest() == sha(bit)
    for name in ['logo_index0', 'logo_index1', 'logo_index2', 'logo_index3', 'logo_palette']:
        assert f'Anlu2/user_source/hdl_source/{name}.mif' in z.namelist()
extra = [root / 'README.md'] + docs
for directory in ['tools/track2_20261026', 'sim/models/track2_20261026']:
    extra += [p for p in (root / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
extra += [root / 'sim/tb/tb_motion_style_20261026.sv', root / 'sim/tb/tb_main_track2_20261026.sv']
extra += [root / f'sim/{d}/{n}' for d, n in [('modelsim_track2_20261026', 'run_motion_small.do'),
        ('modelsim_track2_full_20261026', 'run_motion_full.do'), ('modelsim_track2_integration_20261026', 'run_main.do')]]
manifest = {
    'artifact': artifact.name, 'sha256': sha(artifact), 'main_bit_sha256': sha(bit), 'bytes': bit.stat().st_size,
    'archive': archive.name, 'archive_sha256': sha(archive), 'archive_all_sources_verified': True,
    'build_time_local': datetime.datetime.fromtimestamp(bit.stat().st_mtime).isoformat(),
    'main_project': 'td_project/camera_to_dsi_display.al', 'resources_after': resources, 'timing_ps_after': timing,
    'sta_coverage_percent': coverage, 'inherited_critical_warnings': route_warnings,
    'inherited_synthesis_critical_warnings': syn_warnings, 'additional_video_pipeline_clocks': 0,
    'board_test_performed': False, 'source_audit': audit_result, 'validation': checks,
    'small_reference_metrics': json.loads((build / 'small_metrics.json').read_text()),
    'full_reference_metrics': json.loads((build / 'full_metrics.json').read_text()),
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in production + config + extra},
    'validation_log_sha256': {n: sha(build / n) for n in checks},
}
assert manifest['sha256'] == manifest['main_bit_sha256']
manifest_path = build / 'Anlu2_motion_style_20261026_manifest.json'
manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
# Embed a non-circular manifest: archive hash remains in the external manifest.
embedded = dict(manifest)
embedded.pop('archive_sha256')
with zipfile.ZipFile(archive, 'a', zipfile.ZIP_DEFLATED) as z:
    z.writestr('Anlu2/verification/manifest.json', json.dumps(embedded, indent=2))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
manifest['archive_sha256'] = sha(archive)
manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('PASS current-source publication', resources, timing, 'STA coverage', coverage)
print('BIT', artifact, sha(bit))
print('ZIP', archive, sha(archive))

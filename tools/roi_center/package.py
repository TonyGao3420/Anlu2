from pathlib import Path
import json,hashlib,re,subprocess,sys,shutil,datetime
root=Path(__file__).resolve().parents[2];case=root/'sim/build/roi_center_20261011';runs=root/'td_project/camera_to_dsi_display_Runs';phy=runs/'phy_1'
subprocess.run([sys.executable,str(root/'tools/roi_center/audit.py')],check=True,cwd=root.parent)
checks={'run_logo_isolation.log':['PASS logo_isolation: actual mixer on/off','full 720p ROI and displayed camera identical outside OSD'],
 'run_roi_center_unit.log':['PASS roi_center_osd: 2289 boxes','34816 glyph pixels'],
 'run_roi_center_display.log':['PASS roi_center_display: four complete 720p frames','3686400 ROI pixels','HUD protected through full color/tone chain'],
 'production_regression.log':['ModelSim regression passed.','PASS green highlights','PASS ROI height'],
 'main_synthesis.log':['elaborate module roi_center_osd','camera_to_dsi_display_gate.db'],
 'main_route_bitgen.log':['camera_to_dsi_display_pr.db','bitgen -bit camera_to_dsi_display.bit']}
for name,markers in checks.items():
 s=(case/name).read_text(errors='replace');assert all(m in s for m in markers),(name,'missing required PASS/completion')
 assert '** Fatal:' not in s and not re.search(r'Errors: [1-9]|\bERROR\b|Run .* failed|invalid command',s),(name,'failure in log')
qor=(phy/'route.qor').read_text()
def metric(name):
 m=re.search(r'\|\s*'+re.escape(name)+r'\s*\|\s*(-?\d+)',qor);assert m,name;return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
assert metric('#slices')<=21216 and metric('#RAMs')<=108 and metric('#DSPs')<=40
source=phy/'camera_to_dsi_display.bit';assert source.stat().st_size>1000000
latest=max((root/p).stat().st_mtime for p in ['user_source/hdl_source/hdmi_mixer.v','user_source/hdl_source/video/roi_center_osd.v'])
gate=runs/'syn_1/camera_to_dsi_display_gate.db';route=phy/'camera_to_dsi_display_pr.db'
assert source.stat().st_mtime>route.stat().st_mtime>gate.stat().st_mtime>latest,'stale build artifact'
assert (phy/'.bitgen.end.f').stat().st_mtime>latest
previous=root/'sim/build/SC520_main_edge_refined_20261010.bit';old=json.loads(previous.with_name(previous.stem+'_manifest.json').read_text());assert hashlib.sha256(previous.read_bytes()).hexdigest()==old['bit_sha256']
artifact=root/'sim/build/SC520_roi_center_20261011.bit';shutil.copy2(source,artifact)
paths=list(old['source_sha256'])+['user_source/hdl_source/video/roi_center_osd.v','doc/ROI_CENTER_20261011.md','sim/tb/tb_roi_center_osd.sv','sim/tb/tb_roi_center_display.sv','sim/modelsim/run_roi_center_unit.do','sim/modelsim/run_roi_center_display.do','sim/modelsim/run_display.do','sim/modelsim/run_color_probe_vtc.do']+[p.relative_to(root).as_posix() for p in (root/'tools/roi_center').glob('*.py')]
manifest={'build':'full current main project synthesis, place/route and bitgen in its normal syn_1/phy_1 directories using official TD DefaultFlow; source snapshots verified against main .al',
 'td_version':'6.2.168116','main_project':'td_project/camera_to_dsi_display.al','main_bit':source.relative_to(root).as_posix(),'artifact':artifact.name,
 'bit_sha256':hashlib.sha256(artifact.read_bytes()).hexdigest(),'main_bit_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'bit_bytes':source.stat().st_size,'bit_mtime_local':datetime.datetime.fromtimestamp(source.stat().st_mtime).isoformat(),
 'timing_ps':timing,'slices':metric('#slices'),'eram':metric('#RAMs'),'dsp':metric('#DSPs'),
 'purpose':'frame-stable decimal ROI bounding-box center HUD; ROI X:dddd Y:dddd; invalid target uses ----',
 'coordinate_origin':'upper left (0,0), x increases right, y increases down; pixel units; integer midpoint rounded down',
 'hud_rectangle':[375,160,918,191],'user_confirmed_previous_color_solution':True,'new_bit_board_result_confirmed':False,
 'additional_display_latency_cycles':0,'new_external_pins':0,'scope':'add coordinate OSD only; all accepted color processing, ROI tracker/white rejection/stability/height, servo and DDR/sensor/constraints unchanged',
 'source_audit':json.loads((case/'source_audit.json').read_text()),'validation_checks':checks,
 'source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in dict.fromkeys(paths)},'rollback_bit':previous.name,
 'limitations':'New coordinate HUD has been simulated and routed; board confirmation of the new bit is pending. Coordinates describe stable logical ROI bounds, excluding decorative display padding. Tracker hold frames are preserved.'}
assert manifest['bit_sha256']==manifest['main_bit_sha256'];artifact.with_name(artifact.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(artifact);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

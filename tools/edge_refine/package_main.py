from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,datetime
root=Path(__file__).resolve().parents[2];case=root/'sim/build/edge_refine_20261010';runs=root/'td_project/camera_to_dsi_display_Runs';phy=runs/'phy_1'
subprocess.run([sys.executable,str(root/'tools/edge_refine/audit_main.py')],check=True,cwd=root.parent)
checks={
 'run_display_edge_refine.log':['PASS display_edge_color: 921600 pixels','complete 15-cycle display/tone controls'],
 'run_logo_isolation_refined.log':['PASS logo_isolation: actual mixer on/off','full 720p ROI and displayed camera identical outside OSD'],
 'production_regression.log':['ModelSim regression passed.','PASS green highlights','PASS ROI height'],
 'main_synthesis.log':['elaborate module raw_measured_shading','elaborate module awb_frame_stable','elaborate module display_edge_color','camera_to_dsi_display_gate.db'],
 'main_route_bitgen.log':['camera_to_dsi_display_pr.db','bitgen -bit camera_to_dsi_display.bit']}
for name,markers in checks.items():
 s=(case/name).read_text(errors='replace');assert all(m in s for m in markers),(name,'missing completion marker')
 assert '** Fatal:' not in s and not re.search(r'Errors: [1-9]|\bERROR\b|Run .* failed|invalid command',s),(name,'reported failure')
qor=(phy/'route.qor').read_text()
def metric(name):
 m=re.search(r'\|\s*'+re.escape(name)+r'\s*\|\s*(-?\d+)',qor);assert m,name;return int(m[1])
timing={n:metric(n) for n in ['Setup WNS','Setup TNS','Hold WNS','Hold TNS']}
assert timing['Setup WNS']>=0 and timing['Hold WNS']>=0 and timing['Setup TNS']==timing['Hold TNS']==0,timing
assert metric('#slices')<=21216 and metric('#RAMs')<=108 and metric('#DSPs')<=40
source=phy/'camera_to_dsi_display.bit';assert source.stat().st_size>1000000
assert source.stat().st_mtime>(root/'user_source/hdl_source/video/display_edge_color.v').stat().st_mtime,'stale bit'
assert (runs/'syn_1/camera_to_dsi_display_gate.db').stat().st_mtime>(root/'user_source/hdl_source/video/display_edge_color.v').stat().st_mtime,'stale gate DB'
assert (phy/'.bitgen.end.f').exists() and (phy/'.opt_route.end.f').exists()
previous=root/'sim/build/SC520_edge_color_20261009.bit';old=json.loads(previous.with_name(previous.stem+'_manifest.json').read_text());assert hashlib.sha256(previous.read_bytes()).hexdigest()==old['bit_sha256']
artifact=root/'sim/build/SC520_main_edge_refined_20261010.bit';shutil.copy2(source,artifact)
paths=list(old['source_sha256'])+['doc/EDGE_REFINE_MAIN_20261010.md','sim/tb/tb_display_edge_refine.sv','sim/tb/tb_logo_isolation.sv','sim/modelsim/run_display_edge_refine.do','sim/modelsim/run_logo_isolation.do']+[p.relative_to(root).as_posix() for p in (root/'tools/edge_refine').glob('*.py')]
paths+=['td_project/camera_to_dsi_display_Runs/'+stage+'/'+name for stage in ['syn_1','phy_1'] for name in ['camera_to_dsi_display.prj','settings.cfg']]
# Record generated IP wrappers, memories and constraint sources as well as edited HDL.
paths += [p.relative_to(root).as_posix() for p in (root/'user_source').rglob('*') if p.is_file() and p.suffix.lower() in ['.v','.sv','.vh','.xml','.ipc','.adc','.sdc','.tcl','.hex','.mif','.coe']]
flow=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl')
manifest={
 'build':'full production main project synthesis, place-and-route and bitgen in its normal syn_1 / phy_1 run directories; official TD DefaultFlow using verified main-project snapshots',
 'td_version':'6.2.168116','official_default_flow_sha256':hashlib.sha256(flow.read_bytes()).hexdigest(),
 'main_project':'td_project/camera_to_dsi_display.al','main_bit':source.relative_to(root).as_posix(),
 'artifact':artifact.name,'bit_sha256':hashlib.sha256(artifact.read_bytes()).hexdigest(),'main_bit_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'bit_bytes':source.stat().st_size,
 'bit_mtime_local':datetime.datetime.fromtimestamp(source.stat().st_mtime).isoformat(),'timing_ps':timing,'slices':metric('#slices'),'eram':metric('#RAMs'),'dsp':metric('#DSPs'),
 'physical_board_result_confirmed':False,'previous_user_self_compiled_bit_path_confirmed':False,
 'scope':'red residual edge coefficients only; upper-left and top/bottom stronger; center, blue, ROI input/classifier, RAW/AWB, tone, DDR, sensor, servo and constraints unchanged',
 'digital_logo_leakage_test_passed':True,'new_pipeline_cycles_added':0,
 'source_audit':json.loads((case/'source_audit.json').read_text()),'edge_calibration':json.loads((case/'edge_calibration.json').read_text()),'model_checks':json.loads((case/'model_checks.json').read_text()),
 'validation_checks':checks,'source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in dict.fromkeys(paths)},
 'rollback_bit':previous.name,'limitations':'Feedback-based bounded residual tuning; physical white-board color uniformity requires confirmation with this exact bit. Digital OSD isolation does not rule out optical bloom in a photographed screen.'}
assert manifest['bit_sha256']==manifest['main_bit_sha256']
artifact.with_name(artifact.stem+'_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(artifact);print('Timing:',timing);print('Slices/ERAM/DSP:',manifest['slices'],manifest['eram'],manifest['dsp']);print('SHA256:',manifest['bit_sha256'])

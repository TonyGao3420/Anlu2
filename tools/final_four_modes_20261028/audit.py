from pathlib import Path
import json,hashlib,re
r=Path(__file__).resolve().parents[2];b=r/'sim/build/final_four_modes_20261028'
m=json.loads((b/'merge_record.json').read_text(encoding='utf-8'));backup=Path(m['backup'])
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(r/n)==h for n,h in m['production_sha256'].items()),'Merged production differs from verified four-mode hardware'
frozen=json.loads((r/'sim/reference/final_four_modes_20261028/before_source_sha256.json').read_text(encoding='utf-8'))
changed=[p.relative_to(r).as_posix() for p in sorted((r/'user_source').rglob('*')) if p.is_file() and sha(p)!=frozen['source_sha256'][p.relative_to(r).as_posix()]]
assert changed==m['changed_hardware'],changed
assert sha(r/'td_project/camera_to_dsi_display.sdc')==frozen['sdc_sha256']
al=(r/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8')
assert 'Path="'+(r/'td_project').as_posix()+'"' in al
for n in re.findall(r'<File\s+Path="([^"]+)"',al):assert (r/'td_project'/n).exists(),n
entrances=[p.relative_to(r).as_posix() for folder in [r,r/'prj',r/'td_project'] for p in folder.glob('*.al')]
assert entrances==['td_project/camera_to_dsi_display.al'],'Multiple active project entrances remain'
pin=(r/'user_source/constraints_source/pin.adc').read_text(encoding='utf-8');assert 'I_sw3 } { LOCATION = E11;' in pin
top=(r/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8');assert '.MULTI_ENABLE(1),.MAX_TARGETS(8)' in top
assert '.I_video_in_data   (S_multi_rgb)' in top and '.sw2_async(I_sw3)' in top
assert 'module anlogic_logo_eram(' in (r/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8')
result={'authoritative_project':str(r/'td_project/camera_to_dsi_display.al'),'project_root_corrected':True,
 'single_project_entrance':True,'exact_four_mode_production':True,'unchanged_original_timing_constraints':True,
 'changed_hardware':changed,'previous_main_backup':str(backup),'SW3_pin':'E11'}
(b/'source_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS final source audit: one Anlu2 project; current path fixed; all four-mode RTL/IP/MIF exact; only six reviewed hardware files changed; original ISP/color/rotation/servo/trail and timing retained')

"""Merge the fingerprint-verified four-mode release into the Anlu2 main project."""
from pathlib import Path
import hashlib,json,shutil,re
r=Path(__file__).resolve().parents[2];ws=r.parent
four=ws/'Anlu2_MultiTarget_20261028';backup=ws/'recovery_backups/Anlu2_before_final_four_mode_merge_20261028'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not backup.exists(),'Backup exists; do not merge twice'
before=json.loads((r/'sim/build/roi_original_20261027/manifest.json').read_text(encoding='utf-8'))
release=json.loads((four/'sim/build/multi_target_20261028/manifest.json').read_text(encoding='utf-8'))
assert all(sha(r/n)==h for n,h in before['source_sha256'].items()),'Main project has unreviewed hardware changes'
assert all(sha(four/n)==h for n,h in release['production_sha256'].items()),'Four-mode release differs from verified snapshot'
changed=[n for n in release['production_sha256'] if n.startswith('user_source/') and sha(r/n)!=sha(four/n)]
expected=['user_source/constraints_source/pin.adc','user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/hdmi_mixer.v','user_source/hdl_source/track2/roi_target_tracker.v','user_source/hdl_source/video_in.v','user_source/hdl_source/video_out.v']
assert sorted(changed)==expected,changed
main_al=r/'td_project/camera_to_dsi_display.al';four_al=four/'td_project/camera_to_dsi_display.al'
project_root_pattern=r'(<Project\b[^>]*\bPath=")[^"]*(")'
normalize=lambda s:re.sub(project_root_pattern,lambda m:m[1]+'PROJECT_ROOT'+m[2],s,count=1).strip()
assert normalize(four_al.read_text(encoding='utf-8'))==normalize(main_al.read_text(encoding='utf-8')),'Project source lists unexpectedly differ'
assert sha(r/'td_project/camera_to_dsi_display.sdc')==sha(four/'td_project/camera_to_dsi_display.sdc')
backup.mkdir(parents=True)
shutil.copytree(r/'user_source',backup/'user_source',copy_function=shutil.copy2)
for n in ['README.md','td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display.sdc']:
 p=backup/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(r/n,p)
main_al.write_text(re.sub(project_root_pattern,lambda m:m[1]+(r/'td_project').as_posix()+m[2],main_al.read_text(encoding='utf-8'),count=1),encoding='utf-8')
for folder in ['trail_1s','track2_20261026','model_style_20261026']:
 p=r/'tools'/folder/'rebuild.ps1';dst=backup/'tools'/folder/'rebuild.ps1';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
oldruns=(r/'td_project/camera_to_dsi_display_Runs').resolve();saved=(backup/'implementation_runs').resolve()
assert oldruns.is_relative_to(ws.resolve()) and saved.is_relative_to(ws.resolve()) and not saved.exists()
try:oldruns.rename(saved)
except PermissionError:
 # A GUI may retain a working-directory handle. Back up its files without
 # forcing the application closed; CLI compilation still starts at read_design.
 shutil.copytree(oldruns,saved,copy_function=shutil.copy2)
for run in ['syn_1','phy_1']:
 dst=oldruns/run;dst.mkdir(parents=True,exist_ok=True)
 for n in ['camera_to_dsi_display.prj','settings.cfg']:shutil.copy2(four/'td_project/camera_to_dsi_display_Runs'/run/n,dst/n)
for n in changed:shutil.copyfile(four/n,r/n)
# Remove the stale, unused .al entrance from normal project selection, while
# keeping it recoverable. Its source tree is not deleted.
legacy=r/'prj/Anlu2.al'
if legacy.exists():
 target=(backup/'legacy_entry/Anlu2.al').resolve();target.parent.mkdir(parents=True)
 assert legacy.resolve().is_relative_to(ws.resolve()) and target.is_relative_to(ws.resolve());legacy.rename(target)
 (r/'prj/README_CURRENT_PROJECT.md').write_text('唯一总工程入口：../td_project/camera_to_dsi_display.al。旧Anlu2.al已归档到recovery_backups/Anlu2_before_final_four_mode_merge_20261028/legacy_entry/。\n',encoding='utf-8')
build=r/'sim/build/final_four_modes_20261028';build.mkdir(parents=True,exist_ok=True)
reference=r/'sim/reference/final_four_modes_20261028';reference.mkdir(parents=True,exist_ok=True)
shutil.copy2(backup/'user_source/hdl_source/design_top_wrapper.v',reference/'three_mode_top.v')
before_hashes={p.relative_to(backup).as_posix():sha(p) for p in (backup/'user_source').rglob('*') if p.is_file()}
(reference/'before_source_sha256.json').write_text(json.dumps({'source_sha256':before_hashes,'sdc_sha256':sha(backup/'td_project/camera_to_dsi_display.sdc')},indent=2),encoding='utf-8')
s=(backup/'user_source/hdl_source/track2/roi_target_tracker.v').read_text(encoding='utf-8').replace('roi_target_tracker','baseline_roi_target_tracker').replace('green_region_tracker','baseline_green_region_tracker')
(reference/'three_mode_tracker.v').write_text(s,encoding='utf-8')
models=r/'sim/models/final_four_modes_20261028';models.mkdir(parents=True,exist_ok=True)
shutil.copy2(four/'sim/models/logo.v',models/'logo.v')
fixtures={
 'tb_final_four_modes_vtc.sv':ws/'Anlu2_MultiTarget_SW3Diag_20261028/sim/tb/tb_four_modes_vtc.sv',
 'tb_final_coldboot.sv':ws/'Anlu2_MultiTarget_SW3Diag_20261028/sim/tb/tb_sw3_coldboot.sv',
 'tb_final_multi_tracker.sv':four/'sim/tb/tb_multi_tracker.sv',
 'tb_final_multi_slots.sv':four/'sim/tb/tb_multi_slots.sv',
 'tb_final_latency.sv':four/'sim/tb/tb_multi_units.sv'}
tbdir=r/'sim/tb/final_four_modes_20261028';tbdir.mkdir(parents=True,exist_ok=True)
for name,src in fixtures.items():shutil.copy2(src,tbdir/name)
record={'merged_from':str(four),'authoritative_project':str(r),'backup':str(backup),'changed_hardware':expected,
 'reference_four_mode_bit_sha256':release['bit_sha256'],'previous_main_bit_sha256':before['bit_sha256'],
 'production_sha256':{n:sha(r/n) for n in release['production_sha256'] if n.startswith('user_source/')},
 'timing_constraints_unchanged':True,'project_source_list_unchanged':True,'new_main_bit_generated':False}
(build/'merge_record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
assert all(sha(r/n)==h for n,h in record['production_sha256'].items())
old_bit=r/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
if old_bit.exists():old_bit.rename(old_bit.with_suffix('.bit.before_final_merge'))
print('PASS merge: six verified files integrated into Anlu2; complete prior sources/outputs backed up; fresh run directories; single .al entrance; main bit awaits fresh compilation')

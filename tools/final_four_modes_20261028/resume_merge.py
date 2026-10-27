from pathlib import Path
import hashlib,json,shutil,re
r=Path(__file__).resolve().parents[2];ws=r.parent
four=ws/'Anlu2_MultiTarget_20261028';backup=ws/'recovery_backups/Anlu2_before_final_four_mode_merge_20261028'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
release=json.loads((four/'sim/build/multi_target_20261028/manifest.json').read_text(encoding='utf-8'))
before=json.loads((r/'sim/build/roi_original_20261027/manifest.json').read_text(encoding='utf-8'))
assert all(sha(r/n)==h for n,h in before['source_sha256'].items() if n.startswith('user_source/'))
assert all(sha(four/n)==h for n,h in release['production_sha256'].items())
expected=changed=['user_source/constraints_source/pin.adc','user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/hdmi_mixer.v','user_source/hdl_source/track2/roi_target_tracker.v','user_source/hdl_source/video_in.v','user_source/hdl_source/video_out.v']
oldruns=(r/'td_project/camera_to_dsi_display_Runs').resolve();saved=(backup/'implementation_runs').resolve()
assert oldruns.is_relative_to(ws.resolve()) and saved.is_relative_to(ws.resolve()) and not saved.exists()
shutil.copytree(oldruns,saved,copy_function=shutil.copy2)
main_al=r/'td_project/camera_to_dsi_display.al'
source=(r/'tools/final_four_modes_20261028/merge.py').read_text(encoding='utf-8')
tail="for run in ['syn_1','phy_1']:"+source.split("for run in ['syn_1','phy_1']:",1)[1]
exec(compile(tail,'merge-resume','exec'))

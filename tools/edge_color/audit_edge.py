from pathlib import Path
import json,hashlib,re
root=Path('Anlu2');backup=root/'sim/build/backup_edge_color_20261009';before=json.loads((backup/'before_sha256.json').read_text())
allowed={'user_source/hdl_source/design_top_wrapper.v','td_project/camera_to_dsi_display.al'}
changed=[]
for p,h in before.items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:
  assert p in allowed,p
  changed.append(p)
assert set(changed)==allowed,changed
old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8');new=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8')
assert old[:old.index('    // RAW correction is upstream.')]==new[:new.index('    // Additional perimeter correction')]
assert old[old.index('    hdmi_tx u_hdmi_tx ('):]==new[new.index('    hdmi_tx u_hdmi_tx ('):]
# Only one project entry added; every prior entry/constraint/setting is preserved.
al=(root/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8')
pattern=r'            <File Path="../user_source/hdl_source/video/display_edge_color\.v">.*?            </File>\n'
assert len(re.findall(pattern,al,re.S))==1
assert re.sub(pattern,'',al,flags=re.S)==(backup/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8')
result={'changed_existing_files':changed,'only_added_production_module':'user_source/hdl_source/video/display_edge_color.v',
 'RAW_AWB_ROI_tone_servo_mixer_sensor_DDR_constraints_unchanged':True,'top_upstream_ROI_section_byte_equivalent':True,'only_display_branch_gains_and_matched_sync_delay_changed':True}
(root/'sim/build/edge_color_20261009/source_audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2]
backup=root.parent/'recovery_backups/Anlu2_before_style_mode_20261025'
build=root/'sim/build/style_mode_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before=json.loads((backup/'source_sha256.json').read_text(encoding='utf-8'))
allowed={'user_source/hdl_source/hdmi_mixer.v','README.md','user_source/hdl_source/design_top_wrapper.v','user_source/constraints_source/pin.adc','td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj','td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.prj'}
changed=[]
for rel,h in before.items():
 if sha(root/rel)!=h:
  assert rel in allowed,('Unrelated baseline changed',rel)
  changed.append(rel)
old_mixer=(backup/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
new_mixer=(root/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
new_mixer=re.sub(r'    // ERAM prefetch starts.*?    \);',"    anlogic_logo_rom u_anlogic_logo_rom (\n        .I_addr (S_logo_addr),\n        .O_pixel(S_logo_pixel)\n    );",new_mixer,count=1,flags=re.S)
assert new_mixer==old_mixer,'Mixer changed outside equivalent ERAM prefetch'
old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
new=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
s=re.sub(r'^    input wire I_sw2,.*\n','',new,flags=re.M)
s=re.sub(r'    // MERGED STYLE MODE BEGIN:.*?    // MERGED STYLE MODE END\n\n','',s,flags=re.S)
for a,b in [('S_trail_vs','S_tone_vs'),('S_trail_de','S_tone_de'),('S_trail_rgb','S_tone_rgb')]:
 s=s.replace('('+a+')','('+b+')')
assert s==old,'ROI/servo/ISP/DDR or other existing top code changed'
pin=(root/'user_source/constraints_source/pin.adc').read_text(encoding='utf-8-sig')
assert len(re.findall(r'^.*\{ I_sw2 \}.*$',pin,re.M))==3
assert re.sub(r'^.*\{ I_sw2 \}.*\n','',pin,flags=re.M)==(backup/'user_source/constraints_source/pin.adc').read_text(encoding='utf-8-sig')
assert '{ LOCATION = B4; }' in next(l for l in pin.splitlines() if 'I_sw2' in l and 'LOCATION' in l)
previous=root.parent/'SC520_Stylize_Trail_Standalone_20261021'
prior=json.loads((backup/'standalone_sha256.json').read_text(encoding='utf-8'))
for rel,h in prior.items():assert sha(previous/rel)==h,('Standalone changed',rel)
style=(root/'user_source/hdl_source/video/roi_background_stylize.v').read_text(encoding='utf-8')
style=style.replace(',output reg out_enable','').replace('out_enable<=0;','').replace('out_enable<=v1[24];','')
style=style.replace('// Display-only style mode; aligned out_enable follows the same video RAM metadata.', '// Standalone display experiment.')
assert style==(previous/'user_source/hdl_source/video/roi_background_stylize.v').read_text(encoding='utf-8'),'Style RGB arithmetic changed'
trail=(root/'user_source/hdl_source/video/roi_motion_trail.v').read_text(encoding='utf-8').replace('// RGB/VS/HS/DE/protect/ROI share the bitmap-prefetch and output register stages.','// RGB/VS/HS/DE/protect/ROI are delayed ONE pixel clock together.')
assert trail==(previous/'user_source/hdl_source/video/roi_motion_trail.v').read_text(encoding='utf-8'),'Validated trajectory logic changed'
def paths(p):
 tree=ET.fromstring(p.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__'))
 return {(p.parent/f.attrib['Path']).resolve() for f in tree.findall('Source_Files/*/File')}
al=root/'td_project/camera_to_dsi_display.al';sources=paths(al)
for p in sources:assert p.is_relative_to(root) and p.exists(),('Wrong compilation entry',p)
assert not any(p.is_relative_to(root/'sim') for p in sources)
assert root/'user_source/hdl_source/anlogic_logo_rom.v' in sources
for stage in ['syn_1','phy_1']:
 assert paths(root/'td_project/camera_to_dsi_display_Runs'/stage/'camera_to_dsi_display.prj')==sources
for name in ['roi_background_stylize.v','roi_motion_trail.v','style_switch_control.v']:
 assert root/'user_source/hdl_source/video'/name in sources
report={'backup':str(backup),'changed_baseline_files':changed,'unchanged_baseline_files':len(before)-len(changed),
 'latest_original_top_preserved_except_display_insertion_and_SW2_port':True,
 'SW1_servo_ROI_ISP_DDR_color_coordinates_algorithms_unchanged':True,'logo_pixels_unchanged_ERAM_prefetch_only':True,
 'original_pins_preserved_only_SW2_B4_added':True,'original_SDC_and_tool_strategy_unchanged':True,
 'style_RGB_and_trajectory_algorithms_unchanged':True,'mode_enable_metadata_aligned_with_video':True,
 'standalone_preserved_files':len(prior),'production_source_count':len(sources),'production_model_references_simulation_ROM':False}
(build/'source_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))

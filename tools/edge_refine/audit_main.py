from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET
def parse(p):
 return ET.fromstring(p.read_text(encoding="utf-8-sig").replace("&", "&amp;").replace("::", "__"))
root=Path(__file__).resolve().parents[2];case=root/'sim/build/edge_refine_20261010';bak=root/'sim/build/backup_edge_refine_20261010'
before=json.loads((bak/'before_sha256.json').read_text());changed=[]
allowed={'user_source/hdl_source/video/display_edge_color.v','td_project/camera_to_dsi_display.al'}
for p,h in before.items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:
  assert p in allowed,p
  changed.append(p)
assert 'user_source/hdl_source/video/display_edge_color.v' in changed
old=parse(bak/'main_build_before/td_project/camera_to_dsi_display.al');new=parse(root/'td_project/camera_to_dsi_display.al')
for name in ['HardWare','TOP_MODULE','Configurations']:
 assert ET.tostring(old.find(name))==ET.tostring(new.find(name)),name
# Compile order / AutoExcluded are tool metadata; explicitly enabled source and constraint files must stay identical.
def source_flags(tree):
 return {f.attrib['Path']:sorted((a.attrib['Name'],a.attrib['Val']) for a in f.findall('FileInfo/Attr') if a.attrib['Name'] in ['UsedInSyn','UsedInP&R','BelongTo']) for f in tree.findall('Source_Files/*/File')}
assert source_flags(old)==source_flags(new),'source set or enabled flags changed'
project=root/'td_project/camera_to_dsi_display.al'
paths={(project.parent/f.attrib['Path']).resolve() for f in new.findall('Source_Files/*/File')}
for stage in ['syn_1','phy_1']:
 run=root/'td_project/camera_to_dsi_display_Runs'/stage
 p=run/'camera_to_dsi_display.prj'
 assert p.exists(),p
 if p.exists():
  tree=parse(p);snapshot={(p.parent/f.attrib['Path']).resolve() for f in tree.findall('Source_Files/*/File')}
  assert snapshot==paths,(stage,'snapshot source set mismatch',paths-snapshot,snapshot-paths)
  assert all(p.exists() for p in snapshot),'source file missing'
 # Keep original user and IP timing / pin constraints, except selecting the full compile step range.
 now=(run/'settings.cfg').read_text().splitlines();original=(bak/'main_build_before/td_project/camera_to_dsi_display_Runs'/stage/'settings.cfg').read_text().splitlines()
 for prefix in ['set ADCList','set IpADCList','set IpSDCList','set SDCList','set device_name','set package_name','set speed','set top_model_name']:
  assert [s for s in now if s.startswith(prefix)]==[s for s in original if s.startswith(prefix)],(stage,prefix)
report={'changed_existing_manifest_files':changed,'all_other_manifest_sources_byte_identical':True,'main_project_source_set_top_device_boot_and_constraints_unchanged':True,'main_run_snapshot_source_set_matches_main_al':True,'ROI_RAW_AWB_mixer_servo_tone_unchanged':True,'change_scope':'red edge coefficients only; center and blue coefficients unchanged; same six-cycle display stage; no additional clocks; final mapped DSP count is 40 versus previous 39','user_observed_self_compiled_artifact_path_unconfirmed':True}
(case/'source_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))

from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET
root=Path('Anlu2');bak=root/'sim/build/backup_raw_color_bright_20261009';before=json.loads((bak/'before_sha256.json').read_text())
allowed={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/isp/isp_top.v','user_source/hdl_source/video/scene_color_stream.v','td_project/camera_to_dsi_display.al'}
changed=[]
for p,h in before.items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:
  assert p in allowed,p
  changed.append(p)
assert set(changed)==allowed,changed
s=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8')
assert '.RGB_SHADING_ENABLE(0)' in s and '.RGB_GAIN_Q8(256)' in s
assert '.in_rgb          (S_color_roi_rgb)' in s
project_text=(root/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8')
source_fragment=project_text[project_text.index('<Source_Files>'):project_text.index('</Source_Files>')+len('</Source_Files>')]
project=ET.ElementTree(ET.fromstring(source_fragment.replace('&','&amp;')))
for f in ['awb_frame_stable.v','isp/raw_measured_shading.v','video/display_common_tone.v']:
 matches=[node for node in project.iter('File') if node.attrib.get('Path')=='../user_source/hdl_source/'+f]
 assert len(matches)==1,f
 for field in ['UsedInSyn','UsedInP&R']:assert any(a.attrib.get('Name')==field and a.attrib['Val']=='true' for a in matches[0].iter('Attr'))
cal=json.loads((root/'sim/build/raw_color_bright_20261009/calibration.json').read_text());rows=cal['raw_BGGR'];gains=cal['gain_q10_BGGR'];black=64
beforeR=[];afterR=[];beforeB=[];afterB=[]
for a,g in zip(rows,gains):
 corrected=[v if v<=black else black+(((v-black)*gain+512)>>10) for v,gain in zip(a,g)]
 for rr,bb,aa in [(beforeR,beforeB,a),(afterR,afterB,corrected)]:
  green=(aa[1]+aa[2])/2-black;rr.append((aa[3]-black)/green);bb.append((aa[0]-black)/green)
result={'changed_existing_files':changed,'all_other_prior_manifest_sources_unchanged':True,
 'neutral_RAW_ratio_spread':{'R_before_max_minus_min':max(beforeR)-min(beforeR),'R_after_max_minus_min':max(afterR)-min(afterR),'B_before_max_minus_min':max(beforeB)-min(beforeB),'B_after_max_minus_min':max(afterB)-min(afterB)},
 'calibration_test_is_numeric_model_not_new_hardware_measurement':True}
(root/'sim/build/raw_color_bright_20261009/source_audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))


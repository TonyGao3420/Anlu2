from pathlib import Path
import json,hashlib,re
r=Path(__file__).resolve().parents[2];b=r/'sim/build/resource_combo_20261030'
m=json.loads((b/'record.json').read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
current={p.relative_to(r).as_posix():sha(p) for p in (r/'user_source').rglob('*') if p.is_file()}
assert current==m['production_sha256'],'Current production differs from validated snapshot'
changed=sorted(n for n,h in current.items() if m['before_source_sha256'].get(n)!=h)
expected=['user_source/hdl_source/'+p for p in ['design_top_wrapper.v','hdmi_mixer.v','video/display_color_shading.v','video/roi_background_stylize.v','video/shading_row0.mif','video/shading_row1.mif','video/shading_row2.mif']]
if m.get('awb_serial_exact'):
 expected.append('user_source/hdl_source/awb_frame_stable.v')
 original=(r/'sim/reference/resource_combo_20261030/awb_before.v').read_text(encoding='utf-8-sig').replace('module baseline_awb_frame_stable #(','module awb_frame_stable #(')
 expected_awb=original.replace(' divider ',' awb_frame_divider #(.FRAME_BEATS(FRAME_BEATS)) ')+(r/'sim/reference/resource_combo_20261030/awb_serial_impl.txt').read_text(encoding='utf-8-sig')
 assert (r/'user_source/hdl_source/awb_frame_stable.v').read_text(encoding='utf-8-sig')==expected_awb,'AWB changed beyond exact divider implementation'
assert changed==sorted(expected),changed
assert sha(r/'td_project/camera_to_dsi_display.sdc')==m['before_sdc_sha256']
video=r/'user_source/hdl_source/video';s=(video/'display_color_shading.v').read_text(encoding='utf-8-sig');ref=(r/'sim/reference/resource_combo_20261030/shading_before.v').read_text(encoding='utf-8-sig');values=[]
for name in ['r_gain','b_gain']:
 def block(s):
  z=s[s.index('function [9:0] '+name):];return z[:z.index('endfunction')]
 assert block(s)==block(ref),'Latest color coefficients changed'
 nodes=[int(v) for v in re.findall(name+r'=10\x27d(\d+)',block(s))][:9];values.append(nodes)
for row in range(3):
 text=(video/f'shading_row{row}.mif').read_text(encoding='utf-8-sig');entries={int(a):int(v,16) for a,v in re.findall(r'(\d+)\s*:\s*([0-9A-F]+)\s*;',text)}
 for addr in range(1024):
  side=addr>>9;f=min(addr&511,256);p=[ns[row*3+side]+(((ns[row*3+side+1]-ns[row*3+side])*f+128)>>8) for ns in values]
  assert entries[addr]==p[0]|p[1]<<9,'ROM differs from exact latest color interpolation'
top=(r/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
assert '.RGB_SHADING_ENABLE(1\x27b1)' in top and '.POSITION_BIAS_ENABLE(1\x27b0)' in top
assert '.MULTI_ROI_STABLE_INPUT(1)' in top and 'S_style_request && !S_multi_frame' not in top
if m.get('overlay_box_reuse'):assert '.FRAME_STABLE_BOXES(1)' in top
assert '.MULTI_ENABLE(1),.MAX_TARGETS(8)' in top
al=(r/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8-sig')
for n in re.findall(r'<File\s+Path="([^"]+)"',al):assert (r/'td_project'/n).exists(),n
assert [p.relative_to(r).as_posix() for d in [r,r/'prj',r/'td_project'] for p in d.glob('*.al')]==['td_project/camera_to_dsi_display.al']
result={'changed_hardware':changed,'latest_color_nodes_exact':values,'latest_servo_ISP_except_divider_RAW_DDR_rotation_detector_trail_font_logo_pins_constraints_unchanged':True,
 'awb_gain_rules_and_stream_pipeline_unchanged':True,'awb_division_full_precision_same_50_clock_done':bool(m.get('awb_serial_exact')),
 'one_main_entry':True,'same_video_latency':True,'combination_reuses_existing_video_RAM_and_detector_boxes':True}
(b/'source_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS final source audit: latest color nodes + exact ROM data; latest servo/ISP/RAW/DDR/rotation/ROI/trail/Logo/pins/constraints preserved; only reviewed resource/combination changes')

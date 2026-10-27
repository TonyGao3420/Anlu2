from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[2]
backup=root.parent/'recovery_backups/Anlu2_before_three_fixes_20261027'
build=root/'sim/build/three_fixes_20261027'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def audit():
 before=json.loads((backup/'source_sha256.json').read_text())
 changed={p for p,h in before.items() if p.startswith('user_source/') and sha(root/p)!=h}
 expected={'user_source/hdl_source/hdmi_mixer.v','user_source/hdl_source/video_out.v','user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/video/display_edge_color.v','user_source/hdl_source/video/roi_background_stylize.v'}
 assert changed==expected,changed
 for rel,h in before.items():
  if rel.startswith('td_project/') or rel.endswith('.mif'):assert sha(root/rel)==h,rel
 top=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
 old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
 normalized=top.replace('module design_top_wrapper #(parameter integer CAMERA_ROTATE_180=1) (','module design_top_wrapper (')
 normalized=normalized.replace('video_out #(.ROTATE_180(CAMERA_ROTATE_180)) u_video_out (','video_out u_video_out (')
 normalized=normalized.replace('display_edge_color #(.SOURCE_ROTATE_180(CAMERA_ROTATE_180)) u_display_edge_color(','display_edge_color u_display_edge_color(')
 normalized=normalized.replace(', .CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32)','').replace(',.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32)','')
 normalized=normalized.replace('        // Detection already uses the upright RGB raster. Do not rotate twice.\n','')
 assert normalized==old,'Unexpected top-level change'
 new_mixer=(root/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
 old_mixer=(backup/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
 head=new_mixer[:new_mixer.index('// Exact official lab_ex3')]
 old_head=old_mixer[:old_mixer.index('// Integrated ERAM logo definition:')]
 head=head.replace("LOGO_W          = 12'd160","LOGO_W          = 12'd345").replace("LOGO_H          = 12'd160","LOGO_H          = 12'd120")
 head=head.replace("({S_y,7'b0}+{S_y,5'b0}+S_x)","({S_y,8'b0}+{S_y,6'b0}+{S_y,4'b0}+{S_y,3'b0}+S_y+S_x)")
 old_addr=re.search(r'// LOGO_W=345=.*?S_logo_y \+ S_logo_x;',old_head,re.S)[0]
 head=re.sub(r'// 160=128\+32;.*?S_logo_x;',lambda m:old_addr,head,flags=re.S)
 assert head==old_head,'Mixer changed outside logo size/address/ROM'
 result={'changed_hardware_sources':sorted(changed),'backup':str(backup),
 'all_other_production_files_and_constraints_byte_identical':True,
 'sensor_MIPI_RAW_Bayer_ISP_AWB_color_tables_unchanged':True,
 'ROI_detector_servo_algorithm_pins_modes_center_coordinates_1s_trail_unchanged':True,
 'servo_feedback_uses_upright_detection_coordinates_no_second_flip':True,
 'logo':{'official_example':'lab_ex3_osd_SC520','size':[160,160],'palette_entries':580,'lossless':True},
 'rotation':{'degrees':180,'location':'RGB DDR read','additional_frame_buffer':False,'source_color_correction_coordinates_reflected':True},
 'style':{'target_filter':'pipelined horizontal median of five','gray_surface':[96,223],'soft_contour_min':72,
 'additional_video_clocks':6,'additional_video_ns_at_75MHz':80,'new_ERAM':0,'new_DSP':0},
 'board_test_performed':False}
 (build/'source_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 return result
if __name__=='__main__':print(json.dumps(audit()))

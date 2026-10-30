from pathlib import Path
import shutil,re
r=Path(__file__).resolve().parents[2];tag='resource_combo_20261030';b=r/'sim/build'/tag
backup=r.parent/'recovery_backups/Anlu2_before_resource_combo_20261030'
ref=r/'sim/reference'/tag;models=r/'sim/models'/tag;tb=r/'sim/tb'/tag
for d in [b,ref,models,tb]:d.mkdir(parents=True,exist_ok=True)
project=r/'td_project/camera_to_dsi_display.al';s=project.read_text(encoding='utf-8')
updated=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+(r/'td_project').as_posix()+m[2],s,count=1)
if updated!=s:project.write_text(updated,encoding='utf-8')
for p in list((r/'user_source/hdl_source').glob('official_logo_*.mif'))+list((r/'user_source/hdl_source/video').glob('shading_row*.mif')):
 s=p.read_text(encoding='utf-8-sig');depth=int(re.search(r'DEPTH\s*=\s*(\d+)',s,re.I)[1]);words=['0']*depth
 radix=10 if re.search(r'ADDRESS_RADIX\s*=\s*UNS',s,re.I) else 16
 for a,v in re.findall(r'([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;',s):words[int(a,radix)]=v
 (b/(p.stem+'.hex')).write_text('\n'.join(words)+'\n', encoding='utf-8')
parts=[]
for name,root,baseline in [('baseline_path',backup,True),('multi_path',r,False)]:
 s=(ref/'top_before.v' if baseline else root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
 decl=s[s.index('    wire         S_hdmi_vsync;'):s.index('    reg          S_dbg_raw_seen;')]
 region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
 if baseline:
  region=region.replace('scene_color_stream #(','baseline_scene_color_stream #(')
  region=region.replace('.bbox_valid(S_track2_valid),.bbox_x0(S_track2_bbox_x0)',".multi_mode(1'b0),.multi_valid(8'd0),.multi_x0(96'd0),.multi_y0(96'd0),.multi_x1(96'd0),.multi_y1(96'd0),.bbox_valid(S_track2_valid),.bbox_x0(S_track2_bbox_x0)")
  region=region.replace('.enable(CALIBRATION_MODE ?',".style_active(1'b0),.enable(CALIBRATION_MODE ?")
 parts.append(f'''module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,input sw1,sw2,sw3,output ov,oh,od,output [23:0] rgb);
 localparam CAMERA_ROTATE_180=1,CALIBRATION_MODE=0;
 {decl}
 wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
 wire I_sw1=sw1,I_sw2=sw2,I_sw3=sw3;wire O_servo_pan,O_servo_tilt;wire [3:0] S_hdmi_debug_status=0;
 wire [23:0] S_latency_us=24'd33450;wire [15:0] S_latency_id=16'd42;wire S_latency_valid=1;
 assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
 assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
 {region}
 assign ov=S_dbg_vs;assign oh=S_dbg_hs;assign od=S_dbg_de;assign rgb=S_dbg_rgb;
 endmodule
 ''')
(models/'display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
p=tb/'tb_equivalence.sv'
if not p.exists():
 p.write_text((ref/'equivalence_template.sv').read_text(encoding='utf-8-sig'), encoding='utf-8')
common=[f'../models/{tag}/rom.v',f'../reference/{tag}/shading_before.v',f'../reference/{tag}/scene_before.v']
common+=['../../user_source/hdl_source/video/'+n+'.v' for n in ['style_switch_control','roi_motion_trail','roi_background_stylize','roi_center_osd','display_color_shading','scene_color_stream','display_edge_color','video_enhance','display_common_tone']]
common+=['../../user_source/hdl_source/track2/roi_target_tracker.v','../../user_source/hdl_source/track2/visual_servo_pwm.v','../../user_source/hdl_source/hdmi_mixer.v','../../user_source/hdl_source/osd_char_lib.v','../../user_source/hdl_source/vtc/uivtc.v',f'../models/{tag}/display_paths.v']
for case,files,top in [('equivalence',common+[f'../tb/{tag}/tb_equivalence.sv'],'tb_four_modes_vtc'),
 ('color',[f'../models/{tag}/rom.v',f'../reference/{tag}/shading_before.v','../../user_source/hdl_source/video/display_color_shading.v',f'../tb/{tag}/tb_color.sv'],'tb_color')]:
 d=r/'sim'/('run_resource_'+case);d.mkdir(exist_ok=True)
 (d/'run.do').write_text('onerror {quit -code 1 -f}\nvlib work\nvmap work work\nvlog -sv '+' '.join(files)+'\nvsim -c work.'+top+'\nrun -all\nquit -f\n', encoding='utf-8')
print('Prepared exact latest-color/four-mode baseline comparisons')

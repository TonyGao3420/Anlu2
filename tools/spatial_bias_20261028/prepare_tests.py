from pathlib import Path
import re
r=Path(__file__).resolve().parents[2];tag='spatial_bias_20261028'
b=r/'sim/build'/tag;models=r/'sim/models'/tag;reference=r/'sim/reference'/tag;tbdir=r/'sim/tb'/tag
for p in [b,models,reference,tbdir]:p.mkdir(parents=True,exist_ok=True)
project=r/'td_project/camera_to_dsi_display.al'
s=project.read_text(encoding='utf-8')
updated=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+(r/'td_project').as_posix()+m[2],s,count=1)
if updated!=s:project.write_text(updated,encoding='utf-8')
logo=(models/'logo.v').read_text(encoding='utf-8').replace('../build/three_fixes_20261027/','../build/'+tag+'/')
(models/'logo.v').write_text(logo,encoding='utf-8')
for p in (r/'user_source/hdl_source').glob('official_logo_*.mif'):
 s=p.read_text();depth=int(re.search(r'DEPTH\s*=\s*(\d+)',s,re.I)[1]);words=['0']*depth
 radix=10 if re.search(r'ADDRESS_RADIX\s*=\s*UNS',s,re.I) else 16
 entries=re.findall(r'([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;',s)
 assert len(entries)==depth
 for addr,value in entries:words[int(addr,radix)]=value
 (b/(p.stem+'.hex')).write_text('\n'.join(words)+'\n')
parts=[]
for name,source,baseline in [('baseline_path',reference/'three_mode_top.v',True),('multi_path',r/'user_source/hdl_source/design_top_wrapper.v',False)]:
 s=source.read_text(encoding='utf-8-sig')
 decl=s[s.index('    wire         S_hdmi_vsync;'):s.index('    reg          S_dbg_raw_seen;')]
 region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
 if baseline:region=region.replace('roi_target_tracker #(','baseline_roi_target_tracker #(')
 parts.append(f'''module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,input sw1,sw2,sw3,output ov,oh,od,output [23:0] rgb);
 localparam CAMERA_ROTATE_180=1;
 {decl}
 wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
 wire I_sw1=sw1,I_sw2=sw2,I_sw3=sw3;wire O_servo_pan,O_servo_tilt;wire [3:0] S_hdmi_debug_status=0;
 wire [23:0] S_latency_us=24'd33450;wire [15:0] S_latency_id=16'd42;wire S_latency_valid=1;
 assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
 assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
 {region}
 assign ov={'S_trail_vs' if baseline else 'S_multi_vs'};assign oh={'S_trail_hs' if baseline else 'S_multi_hs'};assign od={'S_trail_de' if baseline else 'S_multi_de'};assign rgb={'S_trail_rgb' if baseline else 'S_multi_rgb'};
 endmodule
 ''')
(models/'display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
p=tbdir/'tb_final_four_modes_vtc.sv';t=p.read_text(encoding='utf-8')
t=t.replace('delayed[0:3]','delayed[0:2]').replace('i<4','i<3').replace('delayed[3]','delayed[2]').replace('exactly 4 clocks','exactly 3 clocks')
t=t.replace('if(!(ox>=1008 && ox<1264 && oy>=128 && oy<144) && nrgb!==delayed[2][23:0])','if(nrgb!==delayed[2][23:0])')
t=t.replace('RGB exact outside V4B strip +4 clocks','all original-mode RGB exact +3 aligned clocks').replace('PASS four_modes_vtc:','PASS final_main_vtc:')
p.write_text(t,encoding='utf-8')
p=tbdir/'tb_final_coldboot.sv';t=p.read_text(encoding='utf-8')
t=t.replace('!dut.u_multi_overlay.level_frame || !dut.u_multi_overlay.request_frame','!dut.S_multi_frame || !dut.S_multi_request').replace('PASS sw3_coldboot:','PASS final_coldboot:')
p.write_text(t,encoding='utf-8')
common=[f'../models/{tag}/logo.v',f'../reference/{tag}/three_mode_tracker.v']
common+=['../../user_source/hdl_source/video/'+n+'.v' for n in ['style_switch_control','roi_motion_trail','roi_background_stylize','roi_center_osd','display_color_shading','scene_color_stream','display_edge_color','video_enhance','display_common_tone']]
common+=['../../user_source/hdl_source/track2/roi_target_tracker.v','../../user_source/hdl_source/track2/visual_servo_pwm.v','../../user_source/hdl_source/hdmi_mixer.v','../../user_source/hdl_source/osd_char_lib.v','../../user_source/hdl_source/vtc/uivtc.v',f'../models/{tag}/display_paths.v']
cases=[('main',common+[f'../tb/{tag}/tb_final_four_modes_vtc.sv'],'tb_four_modes_vtc'),
 ('coldboot',common+[f'../tb/{tag}/tb_final_coldboot.sv'],'tb_sw3_coldboot'),
 ('tracker',['../../user_source/hdl_source/track2/roi_target_tracker.v',f'../reference/{tag}/three_mode_tracker.v',f'../tb/{tag}/tb_final_multi_tracker.sv'],'tb_multi_tracker'),
 ('slots',['../../user_source/hdl_source/track2/roi_target_tracker.v',f'../tb/{tag}/tb_final_multi_slots.sv'],'tb_multi_slots'),
 ('latency',['../../user_source/hdl_source/video_out.v','../../user_source/hdl_source/hdmi_mixer.v',f'../tb/{tag}/tb_final_latency.sv'],'tb_frame_latency')]
for name,files,top in cases:
 w=r/'sim'/('run_final_'+name);w.mkdir(exist_ok=True)
 (w/'run.do').write_text('onerror {quit -code 1 -f}\nvlib work\nvmap work work\nvlog -sv '+' '.join(files)+'\nvsim -c work.'+top+'\nrun -all\nquit -f\n')
print('Prepared tests from merged Anlu2 RTL, frozen original three-mode baseline, exact production MIFs, and real uivtc')
w=r/'sim/run_spatial_color';w.mkdir(exist_ok=True)
(w/'run.do').write_text('onerror {quit -code 1 -f}\nvlib work\nvmap work work\nvlog -sv ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../tb/spatial_bias_20261028/tb_spatial_bias.sv\nvsim -c work.tb_spatial_bias\nrun -all\nquit -f\n')

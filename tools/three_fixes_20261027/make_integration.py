from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[2]
build=root/'sim/build/three_fixes_20261027'
(build/'movie').mkdir(exist_ok=True)
models=root/'sim/models/three_fixes_20261027';models.mkdir(exist_ok=True)
runpy.run_path(str(root/'tools/three_fixes_20261027/prepare_tests.py'),run_name='__main__')
reference=root/'tools/three_fixes_20261027/reference_sources'
old=(reference/'design_top_wrapper.v').read_text(encoding='utf-8-sig')
new=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
parts=[]
for name,s,baseline in [('baseline_current_path',old,True),('extended_current_path',new,False)]:
 decl=s[s.index('    wire         S_hdmi_vsync;'):s.index('    reg          S_dbg_raw_seen;')]
 region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
 if baseline:region=region.replace('roi_background_stylize #(','roi_background_stylize_baseline #(')
 parts.append(f'''module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,input sw1,sw2,output ov,oh,od,output [23:0] rgb);
 localparam CAMERA_ROTATE_180=1;
 {decl}
 wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
 wire I_sw1=sw1,I_sw2=sw2;wire O_servo_pan,O_servo_tilt;wire [3:0] S_hdmi_debug_status=0;
 assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
 assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
 {region}
 assign ov=S_trail_vs;assign oh=S_trail_hs;assign od=S_trail_de;assign rgb=S_trail_rgb;
 endmodule
 ''')
(models/'display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
style=(reference/'roi_background_stylize.v').read_text(encoding='utf-8')
(models/'baseline_style.v').write_text(style.replace('module roi_background_stylize #(','module roi_background_stylize_baseline #(').replace('style_status_osd','style_status_osd_baseline'),encoding='utf-8')
files=['../models/three_fixes_20261027/logo_rom_model.v','../models/three_fixes_20261027/baseline_style.v']
files+=['../../user_source/hdl_source/video/'+n+'.v' for n in ['style_switch_control','roi_motion_trail','roi_background_stylize','roi_center_osd','display_color_shading','scene_color_stream','display_edge_color','video_enhance','display_common_tone']]
files+=['../../user_source/hdl_source/track2/roi_target_tracker.v','../../user_source/hdl_source/track2/visual_servo_pwm.v','../../user_source/hdl_source/hdmi_mixer.v','../../user_source/hdl_source/osd_char_lib.v','../models/three_fixes_20261027/display_paths.v','../tb/tb_main_three_fixes_20261027.sv']
prefix='onerror {quit -code 1 -f}\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv '
for folder,script,tb,compile_files in [('modelsim_three_fixes_integration_final_20261027','run_main.do','tb_main_track2',files),
 ('modelsim_three_fixes_small_20261027','run_motion_small.do','tb_motion_style',['../models/three_fixes_20261027/baseline_style.v','../../user_source/hdl_source/video/roi_background_stylize.v','../tb/tb_three_fixes_style_20261027.sv']),
 ('modelsim_three_fixes_full_20261027','run_motion_full.do','tb_motion_style_full',['../models/three_fixes_20261027/baseline_style.v','../../user_source/hdl_source/video/roi_background_stylize.v','../tb/tb_three_fixes_style_20261027.sv'])]:
 work=root/'sim'/folder;work.mkdir(exist_ok=True)
 (work/script).write_text(prefix+' '.join(compile_files)+'\nvsim -c work.'+tb+'\nrun -all\nquit -f\n')
legacy=root/'sim/modelsim_three_fixes_legacy_20261027';legacy.mkdir(exist_ok=True)
for name in ['roi','display','color','raw10','bilinear_color','official_awb','roi_extent_720p']:
 s=(root/f'sim/modelsim/run_{name}.do').read_text()
 if 'hdmi_mixer.v' in s:s=s.replace('vlog -sv ','vlog -sv ../models/three_fixes_20261027/logo_rom_model.v ',1)
 (legacy/f'run_{name}.do').write_text('onerror {quit -code 1 -f}\n'+s)
fixture=root/'sim/build/style_mode_20261025/vectors/trajectory_camera.hex'
line_bytes=fixture.stat().st_size//(1280*720*8)
assert line_bytes in [7,8] and fixture.stat().st_size==line_bytes*1280*720*8
with fixture.open('rb') as source:
 for frame in range(8):
  data=source.read(line_bytes*1280*720);assert len(data)==line_bytes*1280*720
  (build/f'main_camera_{frame}.hex').write_bytes(data)
 assert source.read()==b''
print('Prepared stage2-vs-final paths and streamed-frame main fixture')

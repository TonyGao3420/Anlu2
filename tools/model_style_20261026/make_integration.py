"""Extract current/pre-extension real display paths; model read-only ERAM IP."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/model_style_20261026'
backup = root.parent / 'recovery_backups/Anlu2_before_model_style_20261026'
models = root / 'sim/models/model_style_20261026';models.mkdir(parents=True,exist_ok=True)
work = root / 'sim/modelsim_model_style_integration_20261026';work.mkdir(exist_ok=True)
old = (backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
new = (root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
parts=[]
for name, s, baseline in [('baseline_current_path',old,True),('extended_current_path',new,False)]:
    decl=s[s.index('    wire         S_hdmi_vsync;'):s.index('    reg          S_dbg_raw_seen;')]
    region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
    if baseline:region=region.replace('roi_background_stylize #(', 'roi_background_stylize_baseline #(')
    parts.append(f'''module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,
input sw1,sw2,output ov,oh,od,output [23:0] rgb);
{decl}
wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
wire I_sw1=sw1,I_sw2=sw2;wire O_servo_pan,O_servo_tilt;
wire [3:0] S_hdmi_debug_status=0;
assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
{region}
assign ov=S_trail_vs;assign oh=S_trail_hs;assign od=S_trail_de;assign rgb=S_trail_rgb;
endmodule
''')
(models/'display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
style=(backup/'user_source/hdl_source/video/roi_background_stylize.v').read_text(encoding='utf-8')
(models/'baseline_style.v').write_text(style.replace('module roi_background_stylize #(', 'module roi_background_stylize_baseline #(').replace('style_status_osd','style_status_osd_baseline'),encoding='utf-8')

# Copy only the public macro interface from installed vendor declarations.
# Behavioral model supports just the ROM configuration this logo uses; writes
# are rejected. Hardware synthesis uses the actual Anlogic primitive.
macro=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/arch/ph1p_macro.v').read_text()
start=macro.index('module PH1P_LOGIC_ERAM (');end=macro.index('endmodule',start)
model=macro[start:end]
model+='''
reg [DATA_WIDTH_B-1:0] mem[0:DATA_DEPTH_B-1];
reg [DATA_WIDTH_B-1:0] b_out;
assign dob=b_out;assign doa=0;assign ecc_sbiterr=0;assign ecc_dbiterr=0;
initial begin
if(MODE!="DP" || REGMODE_B!="OUTREG")$fatal(1,"ROM model used with unsupported IP mode");
'''
for i,name in enumerate(['logo_index0','logo_index1','logo_index2','logo_index3','logo_palette']):
    text=(root/f'user_source/hdl_source/{name}.mif').read_text()
    depth=int(re.search(r'DEPTH\s*=\s*(\d+)',text)[1]);width=int(re.search(r'WIDTH\s*=\s*(\d+)',text)[1])
    words={int(a):int(v,16) for a,v in re.findall(r'^\s*(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',text,re.M)}
    assert len(words)==depth and all(0<=v<(1<<width) for v in words.values())
    (build/f'{name}.hex').write_text(''.join(f'{words[a]:0{(width+3)//4}x}\n' for a in range(depth)))
    model+=('if' if i==0 else 'else if')+f'(INIT_FILE=="{name}.mif")$readmemh("../build/model_style_20261026/{name}.hex",mem);\n'
model+='''else $fatal(1,"Unknown logo ROM file %s",INIT_FILE);
end
always @(posedge clkb)begin
if(web || wea)$fatal(1,"Unexpected write to logo ROM");
if(ceb && oceb)b_out<=mem[addrb];
end
endmodule
'''
(models/'logo_rom_model.v').write_text(model)
files=['../models/model_style_20261026/logo_rom_model.v','../models/model_style_20261026/baseline_style.v',
       '../../user_source/hdl_source/video/style_switch_control.v','../../user_source/hdl_source/video/roi_motion_trail.v',
       '../../user_source/hdl_source/video/roi_background_stylize.v','../../user_source/hdl_source/track2/roi_target_tracker.v',
       '../../user_source/hdl_source/track2/visual_servo_pwm.v','../../user_source/hdl_source/video/roi_center_osd.v',
       '../../user_source/hdl_source/hdmi_mixer.v','../../user_source/hdl_source/osd_char_lib.v']
files += ['../../user_source/hdl_source/video/'+n+'.v' for n in ['display_color_shading','scene_color_stream','display_edge_color','video_enhance','display_common_tone']]
files+=['../models/model_style_20261026/display_paths.v','../tb/tb_main_model_style_20261026.sv']
(work/'run_main.do').write_text('onerror {quit -code 1 -f}\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv '+' '.join(files)+'\nvsim -c work.tb_main_track2\nrun -all\nquit -f\n')
print('Generated current-vs-current baseline display extraction and read-only ERAM simulation model')

for folder, script, tb in [('modelsim_model_style_20261026','run_motion_small.do','tb_motion_style'),
                          ('modelsim_model_style_full_20261026','run_motion_full.do','tb_motion_style_full')]:
    target=root/'sim'/folder;target.mkdir(exist_ok=True)
    (target/script).write_text('onerror {quit -code 1 -f}\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv ../models/model_style_20261026/baseline_style.v ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_model_style_20261026.sv\nvsim -c work.'+tb+'\nrun -all\nquit -f\n')

legacy=root/'sim/modelsim_model_style_legacy_20261026';legacy.mkdir(exist_ok=True)
names=['roi','display','color','raw10','bilinear_color','official_awb','roi_extent_720p']
for name in names:
    script=(root/f'sim/modelsim/run_{name}.do').read_text()
    if 'hdmi_mixer.v' in script:
        script=script.replace('vlog -sv ', 'vlog -sv ../models/model_style_20261026/logo_rom_model.v ',1)
    (legacy/f'run_{name}.do').write_text('onerror {quit -code 1 -f}\n'+script)

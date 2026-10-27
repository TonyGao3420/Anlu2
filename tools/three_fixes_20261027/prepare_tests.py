from pathlib import Path
import re

root=Path(__file__).resolve().parents[2];build=root/'sim/build/three_fixes_20261027'
models=root/'sim/models/three_fixes_20261027';models.mkdir(exist_ok=True)
macro=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/arch/ph1p_macro.v').read_text()
start=macro.index('module PH1P_LOGIC_ERAM (');end=macro.index('endmodule',start)
model=macro[start:end]
model+='''reg [DATA_WIDTH_B-1:0] mem[0:DATA_DEPTH_B-1];
reg [DATA_WIDTH_B-1:0] b_out;
assign dob=b_out;assign doa=0;assign ecc_sbiterr=0;assign ecc_dbiterr=0;
initial begin
if(MODE!="DP" || REGMODE_B!="OUTREG")$fatal(1,"Unsupported ROM mode");
'''
for n,p in enumerate(sorted((root/'user_source/hdl_source').glob('*logo*.mif'))):
    text=p.read_text();depth=int(re.search(r'DEPTH\s*=\s*(\d+)',text)[1]);width=int(re.search(r'WIDTH\s*=\s*(\d+)',text)[1])
    words={int(a):int(v,16) for a,v in re.findall(r'^\s*(\d+)\s*:\s*([0-9a-fA-F]+)\s*;',text,re.M)}
    assert len(words)==depth
    (build/(p.stem+'.hex')).write_text(''.join(f'{words[a]:0{(width+3)//4}x}\n' for a in range(depth)))
    model+=('if' if n==0 else 'else if')+f'(INIT_FILE=="{p.name}")$readmemh("../build/three_fixes_20261027/{p.stem}.hex",mem);\n'
model+='''else $fatal(1,"Unknown logo MIF %s",INIT_FILE);
end
always @(posedge clkb)begin
if(web || wea)$fatal(1,"Unexpected logo write");
if(ceb && oceb)b_out<=mem[addrb];
end
endmodule
'''
(models/'logo_rom_model.v').write_text(model)
work=root/'sim/modelsim_three_fixes_20261027';work.mkdir(exist_ok=True)
(work/'run_logo.do').write_text('''onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/three_fixes_20261027/logo_rom_model.v ../../user_source/hdl_source/hdmi_mixer.v ../tb/tb_official_logo_20261027.sv
vsim -c work.tb_official_logo
run -all
quit -f
''')
(work/'run_logo_mixer.do').write_text('''onerror {quit -code 1 -f}
if {[file exists logo_mixer_work/_info]} { vdel -lib logo_mixer_work -all }
vlib logo_mixer_work
vmap logo_mixer_work logo_mixer_work
vlog -work logo_mixer_work -sv ../models/three_fixes_20261027/logo_rom_model.v ../../../lab_ex3_osd_SC520/src/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/osd_char_lib.v ../tb/tb_official_logo_mixer_20261027.sv
vsim -c logo_mixer_work.tb_official_logo_mixer
run -all
quit -f
''')
for name,library,files,tb in [
 ('rotate','rotate_work',['../../user_source/hdl_source/video_out.v','../tb/tb_rotate180_20261027.sv'],'tb_rotate180'),
 ('orientation','orient_work',['../../user_source/hdl_source/video/display_edge_color.v','../../user_source/hdl_source/track2/visual_servo_pwm.v','../tb/tb_orientation_preserve_20261027.sv'],'tb_orientation_preserve')]:
    (work/f'run_{name}.do').write_text(f'onerror {{quit -code 1 -f}}\nif {{[file exists {library}/_info]}} {{ vdel -lib {library} -all }}\nvlib {library}\nvmap {library} {library}\nvlog -work {library} -sv '+ ' '.join(files)+f'\nvsim -c {library}.{tb}\nrun -all\nquit -f\n')

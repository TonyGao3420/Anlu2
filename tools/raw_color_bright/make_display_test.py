from pathlib import Path
p=Path('Anlu2/sim/tb/tb_shared_color_roi.sv');s=p.read_text().replace('module tb_shared_color_roi;','module tb_raw_corrected_roi_display;').replace('scene_color_stream stream(','scene_color_stream #(.RGB_SHADING_ENABLE(0)) stream(').replace('camera=shade_camera(a,b,wanted);','camera=wanted;').replace('camera=shade_camera(0,0,wanted);','camera=wanted;')
pos=s.index('wire valid,update;')
s=s[:pos]+'''// Same display branch and protect delay as the production top.
wire ev,eh,ed;wire [23:0] ergb;reg [5:0] protect6=0;
always @(posedge clk)if(!rst)protect6<=0;else protect6<={protect6[4:0],op};
video_enhance #(.ENABLE(0),.GAMMA_ENABLE(0),.SHARPEN_ENABLE(0),.CONTRAST_ENABLE(0),.SATURATION_ENABLE(0),.RGB_GAIN_Q8(256))
 enhance(.clk(clk),.rst_n(rst),.in_vsync(ov),.in_hsync(oh),.in_de(od),.in_protect(op),.in_rgb(display_rgb),.out_vsync(ev),.out_hsync(eh),.out_de(ed),.out_rgb(ergb));
wire tv,th,td;wire [23:0] trgb;
display_common_tone tone(.clk(clk),.rst_n(rst),.in_vs(ev),.in_hs(eh),.in_de(ed),.in_protect(protect6[5]),.in_rgb(ergb),.out_vs(tv),.out_hs(th),.out_de(td),.out_rgb(trgb));
reg [9:0] gains[0:255];initial $readmemh("../build/raw_color_bright_20261009/tone_gain.hex",gains);
function automatic [23:0] tone_model(input [23:0] rgb);
integer j,v,gain,maxv,scaled;begin
maxv=rgb[23:16];if(rgb[15:8]>maxv)maxv=rgb[15:8];if(rgb[7:0]>maxv)maxv=rgb[7:0];gain=gains[maxv];
for(j=0;j<3;j=j+1)begin v=rgb[j*8+:8];scaled=v<=14?v:14+(((v-14)*gain+128)>>8);tone_model[j*8+:8]=scaled>255?255:scaled;end
end endfunction
reg [23:0] toneq[0:8];reg [2:0] ctrq[0:8];integer j;
always @(posedge clk)begin
if(!rst)for(j=0;j<9;j=j+1)begin toneq[j]=0;ctrq[j]=0;end
else begin
 for(j=8;j>0;j=j-1)begin toneq[j]=toneq[j-1];ctrq[j]=ctrq[j-1];end
 toneq[0]=!od?0:op?display_rgb:tone_model(display_rgb);ctrq[0]={ov,oh,od};
 #1;if({tv,th,td,trgb}!=={ctrq[8],toneq[8]})$fatal(1,"Production display tone/OSD alignment mismatch got %h want %h",trgb,toneq[8]);
end
end
'''+s[pos:]
s=s.replace('PASS shared_color_roi:', 'PASS raw_corrected_roi_display:')
Path('Anlu2/sim/tb/tb_raw_corrected_roi_display.sv').write_text(s)
import json
gains=json.loads(Path('Anlu2/sim/build/raw_color_bright_20261009/tone_gain.json').read_text());Path('Anlu2/sim/build/raw_color_bright_20261009/tone_gain.hex').write_text('\n'.join(f'{g:03x}' for g in gains)+'\n')
s=Path('Anlu2/sim/modelsim/run_shared_color_roi.do').read_text();s=s.replace('transcript file ../build/shared_color_roi_20261009/run_shared_color_roi.log\n','').replace('../tb/tb_shared_color_roi.sv','../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/tb_raw_corrected_roi_display.sv').replace('work.tb_shared_color_roi','work.tb_raw_corrected_roi_display');Path('Anlu2/sim/modelsim/run_raw_corrected_roi_display.do').write_text(s)
print('Production display + ROI branch test generated.')

from pathlib import Path
import json
root=Path('Anlu2');hdl=root/'user_source/hdl_source'
old=(hdl/'awb.v').read_bytes().split(b'module awb')[0]
awb=r'''// Frame-consistent derivative of official AWB: same stream buffering and IP.
// Complete-frame statistics, measured black subtraction, update only at SOF.
module awb_frame_stable #(
 parameter IMG_HEIGHT=720,IMG_WIDTH=1280,BLACK_LEVEL=14,MIN_SAMPLES=256
)(input I_clk,I_rst_n,I_tlast,I_tuser,input [95:0] I_tdata,input I_tvalid,
 output I_tready,O_tlast,O_tuser,output [95:0] O_tdata,output O_tvalid,input O_tready);
 localparam integer FRAME_BEATS=IMG_HEIGHT*(IMG_WIDTH/4);
 reg [95:0] input0,input1;reg valid0,valid1;
 reg [31:0] sum_r,sum_g,sum_b,samples;
 reg [19:0] beats;reg launch,frame_eligible;
 wire [7:0] r=input0[23:16],g=input0[15:8],b=input0[7:0];
 wire [9:0] pixel_sum={2'b0,r}+{2'b0,g}+{2'b0,b};
 function [7:0] signal_value;
 input [7:0] value;
 begin signal_value=value>BLACK_LEVEL?value-BLACK_LEVEL:0;end
 endfunction
 wire eligible=(pixel_sum<720) && (r>BLACK_LEVEL+7) && (g>BLACK_LEVEL+7) && (b>BLACK_LEVEL+7);
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin input0<=0;input1<=0;valid0<=0;valid1<=0;end
 else begin input0<=I_tdata;input1<=input0;valid0<=I_tvalid;valid1<=valid0;end
 end
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin sum_r<=1;sum_g<=1;sum_b<=1;samples<=0;beats<=0;launch<=0;frame_eligible<=0;end
 else begin
 launch<=0;
 if(I_tuser)begin sum_r<=1;sum_g<=1;sum_b<=1;samples<=0;beats<=0;frame_eligible<=0;end
 else if(valid0 && beats<FRAME_BEATS)begin
  beats<=beats+1'b1;
  if(eligible)begin
   sum_r<=sum_r+signal_value(r);sum_g<=sum_g+signal_value(g);sum_b<=sum_b+signal_value(b);samples<=samples+1'b1;
  end
  if(beats==FRAME_BEATS-1)begin launch<=1;frame_eligible<=(samples+(eligible?1:0)>=MIN_SAMPLES);end
 end
 end end
 wire [47:0] qr,qb;wire done;
 divider div_gen_G_R_r1(.clk(I_clk),.rst(!I_rst_n),.start(launch),.denominator(sum_r),.numerator({sum_g,16'd0}),.quotient(qr),.done(done));
 divider divide_G_B_r1(.clk(I_clk),.rst(!I_rst_n),.start(launch),.denominator(sum_b),.numerator({sum_g,16'd0}),.quotient(qb),.done());
 reg [19:0] in_r_r1,in_b_r1,candidate_r,candidate_b;
 reg candidate_valid,gain_initialized;
 function [19:0] clamp_gain;
 input [47:0] q;
 begin clamp_gain=(|q[47:20])?20'hfffff:q[19:0];end
 endfunction
 function [19:0] approach;
 input [19:0] previous,target;
 begin
 if(target>=previous)approach=previous+((target-previous+20'd3)>>2);
 else approach=previous-((previous-target+20'd3)>>2);
 end endfunction
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 in_r_r1<=20'h10000;in_b_r1<=20'h10000;candidate_r<=20'h10000;candidate_b<=20'h10000;
 candidate_valid<=0;gain_initialized<=0;
 end else begin
 if(done && frame_eligible)begin candidate_r<=clamp_gain(qr);candidate_b<=clamp_gain(qb);candidate_valid<=1;end
 if(I_tuser)begin
  candidate_valid<=0;
  if(candidate_valid)begin
   in_r_r1<=gain_initialized?approach(in_r_r1,candidate_r):candidate_r;
   in_b_r1<=gain_initialized?approach(in_b_r1,candidate_b):candidate_b;
   gain_initialized<=1;
  end
 end
 end end
 wire [95:0] delayed;wire delayed_valid;
 signal_delay #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH),.DATA_WIDTH(96),.DELAY_CYCLE(50))
 signal_delay_d(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),.I_valid(valid1),.I_data(input1),.O_valid(delayed_valid),.O_data(delayed),.O_tuser());
 reg [95:0] pixels,original;reg pixels_valid,product_valid;
 reg [27:0] red_product[0:3],blue_product[0:3];integer i;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 pixels<=0;original<=0;pixels_valid<=0;product_valid<=0;
 for(i=0;i<4;i=i+1)begin red_product[i]<=0;blue_product[i]<=0;end
 end else begin
 pixels<=delayed;pixels_valid<=delayed_valid;product_valid<=pixels_valid;
 if(pixels_valid)begin
  original<=pixels;
  for(i=0;i<4;i=i+1)begin
   red_product[i]<=in_r_r1*signal_value(pixels[i*24+16+:8]);
   blue_product[i]<=in_b_r1*signal_value(pixels[i*24+:8]);
  end
 end
 end end
 function [7:0] restored;
 input [7:0] raw;input [27:0] product;
 reg [12:0] value;
 begin
 value=(product>>16)+BLACK_LEVEL;
 restored=raw<=BLACK_LEVEL?raw:(value>255?8'd255:value[7:0]);
 end endfunction
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin: output_pixels
 assign O_tdata[lane*24+:24]=O_tvalid?{restored(original[lane*24+16+:8],red_product[lane]),original[lane*24+8+:8],restored(original[lane*24+:8],blue_product[lane])}:24'd0;
 end endgenerate
 assign O_tvalid=product_valid;
 assign O_tlast=!pixels_valid && product_valid;
 // Early frame reset is required by the downstream asynchronous FIFO.
 assign O_tuser=I_tuser;assign I_tready=O_tready;
endmodule
'''
(hdl/'awb_frame_stable.v').write_bytes(old+awb.encode())
# Per-pixel common gain: no differential RGB gamma/saturation change.
gains=[];prev=0
for v in range(256):
 s=max(v-14,0);gain=512 if s==0 else min(512,max(256,round(256*(s/241)**(-.35))))
 while s and 14+((s*gain+128)>>8)<prev:gain+=1
 out=v if v<=14 else min(255,14+((s*gain+128)>>8));prev=out;gains.append(gain)
cases='\n'.join(f"8'd{v}:gain_lut=10'd{g};" for v,g in enumerate(gains))
tone=r'''// Three-cycle display tone. All channels share a gain selected by max(R,G,B).
// Black floor stays unchanged, midtones lift, white stays white. ROI is upstream.
module display_common_tone(input clk,rst_n,in_vs,in_hs,in_de,in_protect,input [23:0] in_rgb,
 output out_vs,out_hs,out_de,output reg [23:0] out_rgb);
 function [9:0] gain_lut;input [7:0] maximum;begin case(maximum)
@CASES@
 default:gain_lut=256;
 endcase end endfunction
 wire [7:0] rg=in_rgb[23:16]>in_rgb[15:8]?in_rgb[23:16]:in_rgb[15:8];
 wire [7:0] maximum=rg>in_rgb[7:0]?rg:in_rgb[7:0];
 reg [2:0] vp,hp,dp,pp;
 reg [23:0] raw1,raw2;reg [9:0] gain1;
 reg [7:0] signal1[0:2];reg [17:0] product2[0:2];integer i;
 function [7:0] finish;
 input [7:0] original;input [17:0] product;
 reg [10:0] value;
 begin value=14+((product+18'd128)>>8);
 finish=original<=14?original:(value>255?8'd255:value[7:0]);end endfunction
 assign out_vs=vp[2];assign out_hs=hp[2];assign out_de=dp[2];
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin vp<=0;hp<=0;dp<=0;pp<=0;raw1<=0;raw2<=0;gain1<=256;out_rgb<=0;
 for(i=0;i<3;i=i+1)begin signal1[i]<=0;product2[i]<=0;end
 end else begin
 vp<={vp[1:0],in_vs};hp<={hp[1:0],in_hs};dp<={dp[1:0],in_de};pp<={pp[1:0],in_protect};
 raw1<=in_rgb;raw2<=raw1;gain1<=gain_lut(maximum);
 for(i=0;i<3;i=i+1)begin
 signal1[i]<=in_rgb[i*8+:8]>14?in_rgb[i*8+:8]-14:0;
 product2[i]<=signal1[i]*gain1;
 out_rgb[i*8+:8]<=!dp[1]?8'd0:(pp[1]?raw2[i*8+:8]:finish(raw2[i*8+:8],product2[i]));
 end
 end end
endmodule
'''.replace('@CASES@',cases)
(hdl/'video/display_common_tone.v').write_text(tone)
p=hdl/'isp/isp_top.v';s=p.read_text(encoding="utf-8");idx=s.index('demosaic #(')
s=s[:idx]+'''// Measured sensor-space correction precedes interpolation and white balance.
wire [39:0] raw_corrected;wire [9:0] raw_dest;
wire raw_valid,raw_user,raw_last;
raw_measured_shading raw_shading(.clk(axi4s_video_aclk),.rst_n(I_rst_n),
 .in_data(I_tdata),.in_dest(I_tdest),.in_valid(I_tvalid),.in_user(I_tuser),.in_last(I_tlast),
 .out_data(raw_corrected),.out_dest(raw_dest),.out_valid(raw_valid),.out_user(raw_user),.out_last(raw_last));

'''+s[idx:]
start=s.index('u_demosaic');end=s.index('data128_96',start)
a=s[start:end]
for x,y in [('I_tdata','raw_corrected'),('I_tdest','raw_dest'),('I_tvalid','raw_valid'),('I_tuser','raw_user'),('I_tlast','raw_last')]:a=a.replace('('+x+')','('+y+')')
s=s[:start]+a+s[end:];s=s.replace('awb #(\n','awb_frame_stable #(\n',1);p.write_text(s,encoding="utf-8")
p=hdl/'video/scene_color_stream.v';s=p.read_text(encoding="utf-8").replace('parameter integer W=1280,H=720','parameter integer W=1280,H=720,RGB_SHADING_ENABLE=1').replace('display_color_shading corrector(','display_color_shading #(.ENABLE(RGB_SHADING_ENABLE)) corrector(');p.write_text(s,encoding="utf-8")
p=hdl/'design_top_wrapper.v';s=p.read_text(encoding="utf-8");s=s.replace('scene_color_stream u_scene_color_stream(','scene_color_stream #(.RGB_SHADING_ENABLE(0)) u_scene_color_stream(')
s=s.replace('// Shared measured color correction followed by uniform 17/16 display-only gain.','// RAW correction is upstream. Keep this existing six-cycle stage at unity,\n    // then apply a display-only common RGB tone curve.');s=s.replace('.RGB_GAIN_Q8(272)','.RGB_GAIN_Q8(256)')
pos=s.index('    hdmi_tx u_hdmi_tx (')
s=s[:pos]+'''    reg [5:0] S_tone_protect;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) S_tone_protect<=0;
        else S_tone_protect<={S_tone_protect[4:0],S_color_protect};
    wire S_tone_vs,S_tone_hs,S_tone_de;wire [23:0] S_tone_rgb;
    display_common_tone u_display_common_tone(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_enhanced_vsync),.in_hs(S_hdmi_enhanced_hsync),
        .in_de(S_hdmi_enhanced_de),.in_protect(S_tone_protect[5]),.in_rgb(S_hdmi_enhanced_data),
        .out_vs(S_tone_vs),.out_hs(S_tone_hs),.out_de(S_tone_de),.out_rgb(S_tone_rgb));

'''+s[pos:]
pos=s.index('    hdmi_tx u_hdmi_tx (');a=s[pos:]
for x,y in [('S_hdmi_enhanced_vsync','S_tone_vs'),('S_hdmi_enhanced_de','S_tone_de'),('S_hdmi_enhanced_data','S_tone_rgb')]:a=a.replace('('+x+')','('+y+')')
s=s[:pos]+a;p.write_text(s,encoding="utf-8")
newfiles=['awb_frame_stable.v','isp/raw_measured_shading.v','video/display_common_tone.v']
p=root/'td_project/camera_to_dsi_display.al';s=p.read_text(encoding="utf-8");entries=''
for n,f in enumerate(newfiles):
 entries+=f'''            <File Path="../user_source/hdl_source/{f}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{180+n}"/>
                </FileInfo>
            </File>
'''
s=s.replace('        </Verilog>',entries+'        </Verilog>',1);p.write_text(s,encoding="utf-8")
s=(root/'td_project/rebuild_validation_shared_color_roi_20261009.tcl').read_text(encoding="utf-8").replace('td_validation_shared_color_roi_20261009','td_validation_raw_color_bright_20261009')
s=s.replace('launch_runs -step gate syn_1',''.join(f'add_files {{{(hdl/f).resolve().as_posix()}}}\n' for f in newfiles)+'launch_runs -step gate syn_1',1)
(root/'td_project/rebuild_validation_raw_color_bright_20261009.tcl').write_text(s)
(root/'sim/build/raw_color_bright_20261009/tone_gain.json').write_text(json.dumps(gains))
print('Tone gray input/output:',[(v,v if v<=14 else min(255,14+((max(v-14,0)*gains[v]+128)>>8))) for v in [0,14,32,64,128,192,255]])
print('Integrated RAW shading, frame AWB, common display tone in main project.')


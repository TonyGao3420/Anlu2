`timescale 1ns/1ps
module tb_display_color_shading;
reg clk=0;always #5 clk=~clk;
reg rst=0,vs=0,hs=0,de=0,protect=0;
reg [11:0] x=0,y=0;reg [23:0] rgb=0,expected=0;
wire ov,oh,od,op,bv,bh,bd,bp,fv,fh,fd;
wire [23:0] result,bypass,final_rgb;
display_color_shading dut(clk,rst,vs,hs,de,protect,x,y,rgb,ov,oh,od,op,result);
display_color_shading #(.ENABLE(0)) bypass_dut(clk,rst,vs,hs,de,protect,x,y,rgb,bv,bh,bd,bp,bypass);
video_enhance #(.ENABLE(0),.GAMMA_ENABLE(0),.SHARPEN_ENABLE(0),.CONTRAST_ENABLE(0),
 .SATURATION_ENABLE(0),.BRIGHTNESS_OFFSET(0),.RGB_GAIN_Q8(272)) enhance
 (.clk(clk),.rst_n(rst),.in_vsync(ov),.in_hsync(oh),.in_de(od),.in_protect(op),
  .in_rgb(result),.out_vsync(fv),.out_hsync(fh),.out_de(fd),.out_rgb(final_rgb));
reg [23:0] expq[0:13],bypassq[0:7];
reg [3:0] ctrl[0:13];
integer i,cycles=0,checks=0;
function [7:0] brighten(input [7:0] c);
 integer a;begin a=(c*272+128)>>8;brighten=(a>255)?255:a;end
endfunction
reg [23:0] exp_final;
always @(posedge clk) begin
 if(!rst) begin
  for(i=0;i<14;i=i+1) begin expq[i]=0;ctrl[i]=0;end
  for(i=0;i<8;i=i+1) bypassq[i]=0;
  cycles=0;
 end else begin
  for(i=13;i>0;i=i-1) begin expq[i]=expq[i-1];ctrl[i]=ctrl[i-1];end
  for(i=7;i>0;i=i-1) bypassq[i]=bypassq[i-1];
  expq[0]=expected;ctrl[0]={vs,hs,de,protect};bypassq[0]=de?rgb:0;
  cycles=cycles+1;
  #1;
  if({ov,oh,od,op}!==ctrl[7] || result!==expq[7])
    $fatal(1,"Correction mismatch cycle=%0d got=%h exp=%h",cycles,result,expq[7]);
  if({bv,bh,bd,bp}!==ctrl[7] || bypass!==bypassq[7]) $fatal(1,"Bypass mismatch");
  exp_final=(!ctrl[13][1])?0:(ctrl[13][0]?expq[13]:
    {brighten(expq[13][23:16]),brighten(expq[13][15:8]),brighten(expq[13][7:0])});
  if({fv,fh,fd}!==ctrl[13][3:1] || final_rgb!==exp_final)
    $fatal(1,"Final path mismatch cycle=%0d got=%h exp=%h",cycles,final_rgb,exp_final);
  checks=checks+1;
 end
end
integer file_id,code,lines=0;
initial begin
 repeat(5) @(negedge clk);rst=1;
 file_id=$fopen("../build/color_trial_20261009/correction_vectors.txt","r");
 if(!file_id) $fatal(1,"Vectors missing");
 while(!$feof(file_id)) begin
  code=$fscanf(file_id,"%h %h %h %h %h %h %h %h\n",x,y,rgb,protect,de,vs,hs,expected);
  if(code!=8) $fatal(1,"Malformed vector %0d",lines);
  lines=lines+1;@(negedge clk);
 end
 $fclose(file_id);de=0;rgb=0;vs=0;hs=0;protect=0;expected=0;
 repeat(20) @(negedge clk);
 $display("PASS display_color_shading: %0d vectors; eight-cycle sync, exact OSD/bypass/darks, clipping, uniform RGB brightness",lines);
 $finish;
end
initial begin #5000000;$fatal(1,"Timeout");end
endmodule

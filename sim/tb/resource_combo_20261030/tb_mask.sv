`timescale 1ns/1ps
module tb_mask;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,en=1,mm=0;
 reg [7:0] valid=255;reg [95:0] x0=0,y0=0,x1=0,y1=0;
 wire ov,oh,od,op,roi,oe;wire [23:0] rgb;
 reg [7:0] live_valid=255;wire lv,lh,ld,lp,lr,le;wire [23:0] live_rgb;
 roi_background_stylize #(.IMG_W(128),.IMG_H(72),.LINE_TOTAL(160),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MULTI_ROI_ENABLE(1),.MULTI_ROI_STABLE_INPUT(1)) shared(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(1'b0),.in_enable(en),.in_rgb(24'hb040d0),.in_gray(8'd100),
 .bbox_valid(1'b1),.bbox_x0(16'd32),.bbox_y0(16'd24),.bbox_x1(16'd47),.bbox_y1(16'd39),
 .multi_mode(mm),.multi_valid(live_valid),.multi_x0(x0),.multi_y0(y0),.multi_x1(x1),.multi_y1(y1),
 .out_vs(lv),.out_hs(lh),.out_de(ld),.out_protect(lp),.out_rgb(live_rgb),.out_roi(lr),.out_enable(le));
 roi_background_stylize #(.IMG_W(128),.IMG_H(72),.LINE_TOTAL(160),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MULTI_ROI_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(1'b0),.in_enable(en),.in_rgb(24'hb040d0),.in_gray(8'd100),
 .bbox_valid(1'b1),.bbox_x0(16'd32),.bbox_y0(16'd24),.bbox_x1(16'd47),.bbox_y1(16'd39),
 .multi_mode(mm),.multi_valid(valid),.multi_x0(x0),.multi_y0(y0),.multi_x1(x1),.multi_y1(y1),
 .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_rgb(rgb),.out_roi(roi),.out_enable(oe));
 integer f,yy,xx,k,ox=0,oy=0,of=-1,pixels=0,kept=0,bg=0;reg vd=0,inside_roi;
 always @(posedge clk)begin #1;if(rst)begin
  if({ov,oh,od,op,roi,oe,rgb}!=={lv,lh,ld,lp,lr,le,live_rgb})$fatal(1,"Shared detector boxes differ from local frame snapshot");
  if(ov && !vd)begin of=of+1;ox=0;oy=0;end vd=ov;
  if(od && of>=0)begin
   inside_roi=0;
   if(of==0 || of==3)inside_roi=(ox>=32 && ox<=47 && oy>=24 && oy<=39);
   else for(k=0;k<8;k=k+1)if((of==1 || k%2==0) && ox>=(k%4)*40 && ox<=(k%4)*40+7 && oy>=(k/4)*64 && oy<=(k/4)*64+7)inside_roi=1;
   if(roi!==inside_roi)$fatal(1,"Union/frame-atomic mask f%0d x%0d y%0d got%0d expected%0d",of,ox,oy,roi,inside_roi);
   if(oe!==(of!=4))$fatal(1,"Independent style enable lost");
   if(inside_roi || !oe)begin if(rgb!==24'hb040d0)$fatal(1,"ROI did not retain complete original RGB");kept=kept+1;end
   else begin if(rgb[23:16]!==rgb[15:8] || rgb[15:8]!==rgb[7:0])$fatal(1,"Background not gray");bg=bg+1;end
   pixels=pixels+1;
   if(pixels==5*128*72)begin if(kept<9000 || bg<20000)$fatal(1,"Coverage");$display("PASS union_mask: eight full-color rectangular ROIs, all four corners, invalid slots, frame-atomic latch under midframe changes, style-only restore and multi-only bypass, gray exterior, original video RAM/latency");$finish;end
   if(ox==127)begin ox=0;oy=oy==71?0:oy+1;end else ox=ox+1;
  end
 end end
 integer j;
 initial begin
  for(j=0;j<8;j=j+1)begin x0[j*12+:12]=(j%4)*40;y0[j*12+:12]=(j/4)*64;x1[j*12+:12]=(j%4)*40+7;y1[j*12+:12]=(j/4)*64+7;end
  repeat(6)@(negedge clk);rst=1;
  for(f=0;f<5;f=f+1)begin
   @(negedge clk);mm=(f!=0 && f!=3);valid=(f==1)?255:85;live_valid=valid;en=f!=4;vs=1;
   repeat(5)@(negedge clk);vs=0;repeat(30)@(negedge clk);
   for(yy=0;yy<72;yy=yy+1)begin
    for(xx=0;xx<128;xx=xx+1)begin @(negedge clk);de=1;if(yy==10 && xx==0)begin if(f==1)valid=0;if(f==2)mm=0;end end
    @(negedge clk);de=0;repeat(31)@(negedge clk);
   end
   repeat(2000)@(negedge clk);
  end
 end
 initial begin #2000000;$fatal(1,"Mask timeout");end
endmodule

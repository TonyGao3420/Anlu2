`timescale 1ns/1ps
module roi_original_test #(parameter W=320,H=192,HT=400,FULL=0);
 localparam LAT=8*HT+8,VT=H+20,N=3;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,prot=0,en=0;
 reg [23:0] rgb=0;reg [7:0] gray=0;
 wire v,h,d,p,r,e,bv,bh,bd,bp,br,be;wire [23:0] out,old;
 roi_background_stylize #(.IMG_W(W),.IMG_H(H),.LINE_TOTAL(HT),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32))
  dut(clk,rst,vs,hs,de,prot,en,rgb,gray,1'b1,16'(W/4),16'(H/3),16'(W*3/4),16'(H*2/3),v,h,d,p,out,r,e);
 roi_background_stylize_before_roi #(.IMG_W(W),.IMG_H(H),.LINE_TOTAL(HT),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32))
  baseline(clk,rst,vs,hs,de,prot,en,rgb,gray,1'b1,16'(W/4),16'(H/3),16'(W*3/4),16'(H*2/3),bv,bh,bd,bp,old,br,be);
 reg [23:0] pipe[0:LAT-1];reg [23:0] raw;integer pos=0,i,f,y,x,checked=0,roi_pixels=0,other_pixels=0;
 always @(posedge clk)begin
  if(!rst)begin for(i=0;i<LAT;i=i+1)pipe[i]=0;pos=0;end else begin
   raw=pipe[pos];pipe[pos]=rgb;pos=(pos==LAT-1)?0:pos+1;
   #1;if({v,h,d,p,r,e}!=={bv,bh,bd,bp,br,be})$fatal(1,"ROI restore changed video timing/metadata");
   if(d)begin
    if(e && r && !p)begin if(out!==raw)$fatal(1,"ROI not exact original RGB FULL%0d pixel%0d got%h want%h",FULL,checked,out,raw);roi_pixels=roi_pixels+1;end
    else begin if(out!==old)$fatal(1,"Non-ROI/normal/OSD pixel changed");other_pixels=other_pixels+1;end
    checked=checked+1;
   end
  end
 end
 initial begin
  repeat(6)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)begin
   en=f!=1;
   for(y=0;y<VT;y=y+1)for(x=0;x<HT;x=x+1)begin
    @(negedge clk);vs=y<3;hs=x>=W+4 && x<W+12;de=y>=6 && y<H+6 && x<W;
    rgb=24'((x*8191+(y-6)*137+f*31337)^24'h319a72);gray=8'(x+y*3);prot=de && x>W/2-8 && x<W/2+8 && y>H/2 && y<H/2+16;
    if(de && x>=W/4 && x<=W*3/4)case(x%8)0:rgb=24'hffffff;1:rgb=24'hff2000;2:rgb=24'h143bff;3:rgb=24'h11140a;4:rgb=24'h123456;5:rgb=24'h00ff00;default:rgb=rgb;endcase
   end
  end
  @(negedge clk);de=0;vs=0;hs=0;rgb=0;prot=0;repeat(LAT+4)@(negedge clk);
  if(checked!=W*H*N || roi_pixels<W*H/4 || other_pixels<W*H)$fatal(1,"ROI restore coverage");
  $display("PASS ROI_original FULL%0d: %0d pixels; ROI exact normal RGB including red/blue/white/dark/noise; all exterior/OSD/normal-mode/timing bit-exact; roi_pixels%0d other_pixels%0d",FULL,checked,roi_pixels,other_pixels);$finish;
 end
endmodule
module tb_roi_original_small;roi_original_test test();endmodule
module tb_roi_original_full;roi_original_test #(.W(1280),.H(720),.HT(1650),.FULL(1)) test();endmodule


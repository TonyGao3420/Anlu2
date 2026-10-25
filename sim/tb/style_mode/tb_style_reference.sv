`timescale 1ns/1ps
module tb_style_reference #(parameter W=64,H=48,HT=80,VT=64,N=12,FULL=0);
 localparam LAT=8*HT+2,TOTAL=W*H*N;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,protect=0,enable=1,valid=0;
 reg [23:0] rgb=0,expected_rgb=0;
 reg [7:0] gray=0;
 reg [15:0] x0=0,y0=0,x1=0,y1=0;
 wire ov,oh,od,op,oroi,oe;wire[23:0] out;reg ref_roi=0;
 roi_background_stylize #(.IMG_W(W),.IMG_H(H),.LINE_TOTAL(HT)) dut(
  clk,rst,vs,hs,de,protect,enable,rgb,gray,valid,x0,y0,x1,y1,ov,oh,od,op,out,oroi,oe);
 reg[32:0] stimulus[0:TOTAL-1];reg[23:0] golden[0:TOTAL-1];reg[65:0] metadata[0:N-1];
 reg[28:0] pipe[0:LAT-1];reg[28:0] want;
 reg enable_pipe[0:LAT-1];reg want_enable;
 integer f,line,col,index,phase;
 integer i,ptr=0,checked=0,cycles=0,ppm=0;
 always @(posedge clk)begin
  if(!rst)begin
   for(i=0;i<LAT;i=i+1)begin pipe[i]=0;enable_pipe[i]=0;end ptr=0;checked=0;cycles=0;
  end else begin
   want_enable=enable_pipe[ptr];enable_pipe[ptr]=metadata[f][65];
   want=pipe[ptr];pipe[ptr]={vs,hs,de,protect,ref_roi,(de?expected_rgb:24'd0)};
   ptr=(ptr==LAT-1)?0:ptr+1;
   #1;
   if({ov,oh,od,op,oroi,out}!==want)$fatal(1,"Reference mismatch FULL%0d cycle%0d pixel%0d got %h expected %h",FULL,cycles,checked,{ov,oh,od,op,oroi,out},want);
   if(od)begin
    if(oe!==want_enable)$fatal(1,"Aligned mode metadata differs from original frame selection");
    if(FULL && checked<W*H)$fwrite(ppm,"%c%c%c",out[23:16],out[15:8],out[7:0]);
    checked=checked+1;
   end
   cycles=cycles+1;
  end
 end
 task run_frames;
 begin
  for(f=0;f<N;f=f+1)begin
   @(negedge clk);{enable,valid,x0,y0,x1,y1}=metadata[f];
   for(line=0;line<VT;line=line+1)begin
    for(col=0;col<HT;col=col+1)begin
     @(negedge clk);vs=(line<3);hs=(col>=W+4 && col<W+10);
     de=(line>=6 && line<6+H && col<W);protect=0;rgb=0;gray=0;expected_rgb=0;ref_roi=0;
     if(de)begin
      index=f*W*H+(line-6)*W+col;
      {gray,protect,rgb}=stimulus[index];expected_rgb=golden[index];
      ref_roi=metadata[f][64] && metadata[f][63:48]<=metadata[f][31:16] && metadata[f][47:32]<=metadata[f][15:0] &&
       metadata[f][31:16]<W && metadata[f][15:0]<H && col>=metadata[f][63:48] && col<=metadata[f][31:16] &&
       line-6>=metadata[f][47:32] && line-6<=metadata[f][15:0];
      // These ports deliberately change during a frame; only the next SOF may
      // change the ROI or mode. Reinitialize them from metadata next frame.
      if(line==6+H/2 && col==W/2)begin enable=~enable;valid=~valid;x0=0;y0=0;x1=0;y1=0;end
     end
    end
   end
  end
  @(negedge clk);de=0;vs=0;hs=0;protect=0;rgb=0;expected_rgb=0;ref_roi=0;
  repeat(LAT+8)@(negedge clk);
  if(checked!=TOTAL)$fatal(1,"Missing output pixels %0d expected%0d",checked,TOTAL);
 end endtask
 initial begin
  if(FULL)begin
   $readmemh("../build/style_mode_20261025/vectors/720p_stim.hex",stimulus);
   $readmemh("../build/style_mode_20261025/vectors/720p_expected.hex",golden);
   $readmemh("../build/style_mode_20261025/vectors/720p_meta.hex",metadata);
   ppm=$fopen("../build/style_mode_20261025/preview/rtl_output.ppm","wb");
   $fwrite(ppm,"P6\n%0d %0d\n255\n",W,H);
  end else begin
   $readmemh("../build/style_mode_20261025/vectors/small_stim.hex",stimulus);
   $readmemh("../build/style_mode_20261025/vectors/small_expected.hex",golden);
   $readmemh("../build/style_mode_20261025/vectors/small_meta.hex",metadata);
  end
  repeat(6)@(negedge clk);rst=1;
  run_frames;
  if(!FULL)begin
   // Abort an in-flight raster, reset, and verify warmup never exposes RAM X.
   @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;
   repeat(100)begin @(negedge clk);de=1;gray=77;rgb=24'h123456;expected_rgb=24'h123456;end
   @(negedge clk);rst=0;de=0;repeat(5)@(negedge clk);rst=1;
   run_frames;
  end
  if(FULL)$fclose(ppm);
  $display("PASS style_reference FULL%0d: %0d pixels per run; independent complete-frame mean/gradient reference, ROI/OSD exact color, current-frame changes, invalid/bypass, latched metadata, sync and warmup/reset",FULL,TOTAL);
  $finish;
 end
 initial begin #100000000;$fatal(1,"Reference simulation timeout");end
endmodule
module tb_style_small;tb_style_reference test();endmodule
module tb_style_720p;tb_style_reference #(.W(1280),.H(720),.HT(1650),.VT(750),.N(3),.FULL(1)) test();endmodule

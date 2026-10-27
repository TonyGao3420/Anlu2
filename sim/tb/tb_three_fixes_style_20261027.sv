`timescale 1ns/1ps
module tb_motion_style #(parameter W=320,H=192,HT=400,N=20,FULL=0);
 localparam TOTAL=W*H*N,LAT=8*HT+8,VT=H+20;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,prot=0,en=0,valid=0;
 reg [23:0] rgb=0;reg [7:0] gray=0;
 reg [15:0] x0=0,y0=0,x1=0,y1=0;
 wire ov,oh,od,op,roi,oe;wire [23:0] out;
 wire bv,bh,bd,bp,br,be;wire [23:0] base;
 roi_background_stylize #(.IMG_W(W),.IMG_H(H),.LINE_TOTAL(HT),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32),.FRAME_TIMEOUT_CYCLES(2*HT*VT)) dut(
  clk,rst,vs,hs,de,prot,en,rgb,gray,valid,x0,y0,x1,y1,ov,oh,od,op,out,roi,oe);
 wire bv0,bh0,bd0,bp0,br0,be0;wire [23:0] base0;
 reg [29:0] base_delay[0:5];integer d;
 roi_background_stylize_baseline #(.IMG_W(W),.IMG_H(H),.LINE_TOTAL(HT),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.FRAME_TIMEOUT_CYCLES(2*HT*VT)) old(
  clk,rst,vs,hs,de,prot,en,rgb,gray,valid,x0,y0,x1,y1,bv0,bh0,bd0,bp0,base0,br0,be0);
 always @(posedge clk)if(!rst)begin for(d=0;d<6;d=d+1)base_delay[d]<=0;end else begin
  base_delay[0]<={bv0,bh0,bd0,bp0,br0,be0,base0};for(d=1;d<6;d=d+1)base_delay[d]<=base_delay[d-1];end
 assign {bv,bh,bd,bp,br,be,base}=base_delay[5];
 reg [32:0] stim[0:TOTAL-1];reg [25:0] gold[0:TOTAL-1],oldgold[0:TOTAL-1];
 reg [65:0] meta[0:N-1];reg [15:0] counts[0:N-1];
 reg [28:0] pipe[0:LAT-1],oldpipe[0:LAT-1];reg enpipe[0:LAT-1];
 reg [28:0] want,oldwant,expected=0,oldexpected=0;reg mode_expected=0,want_mode;
 integer ptr=0,checked=0,f,l,x,idx,i,run,ppm=0,oldppm=0,hits=0;
 always @(posedge clk)begin
  if(!rst)begin
   for(i=0;i<LAT;i=i+1)begin pipe[i]=0;oldpipe[i]=0;enpipe[i]=0;end
   ptr=0;checked=0;hits=0;
  end else begin
   want=pipe[ptr];oldwant=oldpipe[ptr];want_mode=enpipe[ptr];
   pipe[ptr]=expected;oldpipe[ptr]=oldexpected;enpipe[ptr]=mode_expected;
   ptr=(ptr==LAT-1)?0:ptr+1;
   #1;
   if({ov,oh,od,op,roi,out}!==want)$fatal(1,"motion style mismatch FULL%0d input_f%0d output_pixel%0d got%h expected%h",FULL,f,checked,{ov,oh,od,op,roi,out},want);
   if({bv,bh,bd,bp,br,base}!==oldwant)$fatal(1,"legacy style changed FULL%0d pixel%0d",FULL,checked);
   if(od)begin
    if(oe!==want_mode || be!==want_mode)$fatal(1,"Mode metadata misaligned");
    if(out[23:16]==out[15:8] && out[15:8]==out[7:0] && out[7:0]>=56)hits=hits+1;
    if(run==0 && (!FULL || checked/(W*H)==0 || checked/(W*H)==4 || checked/(W*H)==7))begin
     if(checked%(W*H)==0)begin
      if(FULL)begin
       ppm=$fopen($sformatf("../build/three_fixes_20261027/movie/full_new_%02d.ppm",checked/(W*H)),"wb");
       oldppm=$fopen($sformatf("../build/three_fixes_20261027/movie/full_old_%02d.ppm",checked/(W*H)),"wb");
      end else begin
       ppm=$fopen($sformatf("../build/three_fixes_20261027/movie/new_%02d.ppm",checked/(W*H)),"wb");
       oldppm=$fopen($sformatf("../build/three_fixes_20261027/movie/old_%02d.ppm",checked/(W*H)),"wb");
      end
      if(!ppm || !oldppm)$fatal(1,"Cannot create RTL raster dump");
      $fwrite(ppm,"P6\n%0d %0d\n255\n",W,H);$fwrite(oldppm,"P6\n%0d %0d\n255\n",W,H);
     end
     $fwrite(ppm,"%c%c%c",out[23:16],out[15:8],out[7:0]);
     $fwrite(oldppm,"%c%c%c",base[23:16],base[15:8],base[7:0]);
     if(checked%(W*H)==W*H-1)begin $fclose(ppm);$fclose(oldppm);ppm=0;oldppm=0;end
    end
    checked=checked+1;
   end
  end
 end
 initial begin
  if(FULL)begin
   $readmemh("../build/three_fixes_20261027/full_stim.hex",stim);
   $readmemh("../build/three_fixes_20261027/full_gold.hex",gold);
   $readmemh("../build/three_fixes_20261027/full_old.hex",oldgold);
   $readmemh("../build/three_fixes_20261027/full_meta.hex",meta);
   $readmemh("../build/three_fixes_20261027/full_counts.hex",counts);
  end else begin
   $readmemh("../build/three_fixes_20261027/small_stim.hex",stim);
   $readmemh("../build/three_fixes_20261027/small_gold.hex",gold);
   $readmemh("../build/three_fixes_20261027/small_old.hex",oldgold);
   $readmemh("../build/three_fixes_20261027/small_meta.hex",meta);
   $readmemh("../build/three_fixes_20261027/small_counts.hex",counts);
  end
  for(run=0;run<(FULL?1:3);run=run+1)begin
   if(run!=1)begin
    rst=0;vs=0;hs=0;de=0;prot=0;expected=0;oldexpected=0;repeat(5)@(negedge clk);rst=1;
   end else begin checked=0;hits=0;end
   for(f=0;f<N;f=f+1)begin
    {en,valid,x0,y0,x1,y1}=meta[f];
    for(l=0;l<VT;l=l+1)for(x=0;x<HT;x=x+1)begin
     @(negedge clk);vs=l<3;hs=x>=W+4 && x<W+10;de=l>=6 && l<H+6 && x<W;
     rgb=0;gray=0;prot=0;expected={vs,hs,de,26'd0};oldexpected=expected;
     mode_expected=meta[f][65];
     if(de)begin
      idx=f*W*H+(l-6)*W+x;{gray,prot,rgb}=stim[idx];
      expected={vs,hs,de,gold[idx]};oldexpected={vs,hs,de,oldgold[idx]};
      if(l==6+H/2 && x==W/2)begin en=~en;valid=~valid;x0=0;x1=0;y0=0;y1=0;end
     end
    end
    if(dut.completed_motion_count!==counts[f])$fatal(1,"Motion count mismatch frame%0d got%0d expected%0d",f,dut.completed_motion_count,counts[f]);
   end
   @(negedge clk);vs=0;hs=0;de=0;prot=0;expected=0;oldexpected=0;repeat(LAT+4)@(negedge clk);
   if(checked!=TOTAL || hits==0)$fatal(1,"Incomplete pixel/motion coverage checked%0d hits%0d",checked,hits);
   $display("PASS model_style FULL%0d run%0d: %0d RGB/timing pixels; independent bright planes/soft contours/selective green/HUD and preserved motion reference, same latency, frame-atomic switch and preceding-release comparison",FULL,run,checked);
   if(!FULL)begin
    repeat(2*HT*VT+4)@(negedge clk);
    if(dut.motion.history_valid || dut.completed_motion_count!=0)$fatal(1,"Interrupted video retained stale motion history");
    $display("PASS motion watchdog: interrupted stream clears and may resume without reset");
   end
  end
  $finish;
 end
 initial begin #300000000;$fatal(1,"motion style timeout");end
endmodule
module tb_motion_style_full;
 tb_motion_style #(.W(1280),.H(720),.HT(1650),.N(8),.FULL(1)) test();
endmodule


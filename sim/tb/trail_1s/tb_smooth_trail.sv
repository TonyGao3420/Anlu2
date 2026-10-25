`timescale 1ns/1ps
module tb_smooth_trail;
 localparam W=256,H=144,HT=320,N=240,CELLS=(W/4)*(H/4);
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,prot=0,roi=0,en=1,clear=0,pv=0;
 reg[23:0] rgb=0;reg[15:0] now_ms=0,px=0,py=0;
 reg[50:0] stimulus[0:N-1];reg[41:0] metadata[0:N-1];
 reg[CELLS-1:0] masks[0:N-1],raw_masks[0:N-1];
 wire ov,oh,od,op,hit,busy,bank;wire[23:0] out;wire[8:0] count;
 wire rv,rh,rd,rp,rhit,rb;wire[23:0] raw_out;
 roi_motion_trail #(.IMG_W(W),.IMG_H(H),.MAX_JUMP_PIXELS(128),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50),.JITTER_PIXELS(4)) dut(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),.in_enable(en),.in_clear(clear),
 .in_rgb(rgb),.ms_now(now_ms),.point_valid(pv),.point_x(px),.point_y(py),.out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_hit(hit),.out_rgb(out),.render_busy(busy),.point_count(count),.bank_valid(bank));
 roi_motion_trail #(.IMG_W(W),.IMG_H(H),.TTL_MS(3000),.MAX_JUMP_PIXELS(128),.SMOOTH_ENABLE(0),.SAMPLE_INTERVAL_MS(0)) old(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),.in_enable(en),.in_clear(clear),
 .in_rgb(rgb),.ms_now(now_ms),.point_valid(pv),.point_x(px),.point_y(py),.out_vs(rv),.out_hs(rh),.out_de(rd),.out_protect(rp),.out_hit(rhit),.out_rgb(raw_out),.render_busy(),.point_count(),.bank_valid(rb));
 reg[28:0] expected=0,old_expected=0,delayed=0,old_delayed=0,want=0,old_want=0;
 integer pixels=0,hits=0,raw_hits=0,f,x,y,index,ppm=0,raw_ppm=0;
 always @(posedge clk)begin
  if(!rst)begin delayed=0;old_delayed=0;end
  else begin
   if(dut.sof)begin
    if(dut.record!==metadata[f][41])$fatal(1,"Sampling cadence mismatch frame%0d",f);
    if(en && !clear && pv && px<W && py<H && {dut.plot_x,dut.plot_y}!==metadata[f][31:0])$fatal(1,"Filter reference mismatch frame%0d got(%0d,%0d) expected(%0d,%0d)",f,dut.plot_x,dut.plot_y,metadata[f][31:16],metadata[f][15:0]);
   end
   want=delayed;old_want=old_delayed;delayed=expected;old_delayed=old_expected;
   #1;
   if({ov,oh,od,op,hit,out}!==want)$fatal(1,"Smooth complete-frame RGB/timing mismatch frame%0d pixel%0d",f,pixels);
   if({rv,rh,rd,rp,rhit,raw_out}!==old_want)$fatal(1,"Baseline bitmap oracle mismatch frame%0d pixel%0d",f,pixels);
   if(od)begin
    pixels=pixels+1;if(hit)hits=hits+1;if(rhit)raw_hits=raw_hits+1;
    if(ppm)$fwrite(ppm,"%c%c%c",out[23:16],out[15:8],out[7:0]);
    if(raw_ppm)$fwrite(raw_ppm,"%c%c%c",raw_out[23:16],raw_out[15:8],raw_out[7:0]);
   end
  end
 end
 reg expected_hit,raw_hit;
 initial begin
  $readmemh("../build/trail_1s_20261025/smooth_stim.hex",stimulus);
  $readmemh("../build/trail_1s_20261025/smooth_meta.hex",metadata);
  $readmemh("../build/trail_1s_20261025/smooth_front.hex",masks);
  $readmemh("../build/trail_1s_20261025/raw_front.hex",raw_masks);
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)begin
   if(busy)$fatal(1,"Smoothed renderer overran frame");
   @(negedge clk);{en,clear,pv,now_ms,px,py}=stimulus[f];vs=1;de=0;hs=0;prot=0;roi=0;
   expected={1'b1,28'd0};old_expected=expected;
   repeat(6)@(negedge clk);vs=0;expected=0;old_expected=0;
   if(f%4==0)begin
    ppm=$fopen($sformatf("../build/trail_1s_20261025/movie/new_%03d.ppm",f),"wb");
    raw_ppm=$fopen($sformatf("../build/trail_1s_20261025/movie/old_%03d.ppm",f),"wb");
    $fwrite(ppm,"P6\n%0d %0d\n255\n",W,H);$fwrite(raw_ppm,"P6\n%0d %0d\n255\n",W,H);
   end
   for(y=0;y<H;y=y+1)for(x=0;x<HT;x=x+1)begin
    @(negedge clk);de=(x<W);hs=(x>=W+4 && x<W+10);
    prot=de && y==H/2 && x>=W/4 && x<3*W/4;
    roi=de && pv && px<W && py<H && x>=int'(px)-7 && x<=int'(px)+7 && y>=int'(py)-7 && y<=int'(py)+7;
    rgb=roi?24'h20dc60:24'h808080;if(prot)rgb=24'hffff20;
    expected_hit=de && en && !clear && !prot && !roi && masks[f][(y/4)*(W/4)+(x/4)];
    raw_hit=de && en && !clear && !prot && !roi && raw_masks[f][(y/4)*(W/4)+(x/4)];
    expected={vs,hs,de,(prot || expected_hit),expected_hit,(de?(expected_hit?24'hff8800:rgb):24'd0)};
    old_expected={vs,hs,de,(prot || raw_hit),raw_hit,(de?(raw_hit?24'hff8800:rgb):24'd0)};
   end
   @(negedge clk);de=0;hs=0;prot=0;roi=0;expected=0;old_expected=0;repeat(4)@(negedge clk);
   if(count!==metadata[f][40:32])$fatal(1,"Sample/history count mismatch frame%0d got%0d expected%0d",f,count,metadata[f][40:32]);
   if(ppm)begin $fclose(ppm);$fclose(raw_ppm);ppm=0;raw_ppm=0;end
  end
  if(pixels!=W*H*N || hits==0 || raw_hits==0)$fatal(1,"Incomplete smooth-trail coverage");
  $display("PASS smooth_trail: %0d pixels; independent median/IIR/deadband/cadence/bitmap reference, 1s expiry, counter wrap, outlier, loss/reacquire, mode clear, protected overlays, baseline comparison",pixels);$finish;
 end
 initial begin #200000000;$fatal(1,"Smooth trail timeout");end
endmodule

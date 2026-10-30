`timescale 1ns/1ps
module tb_multi_trail;
 localparam W=256,H=128,HT=300,N=320,CELLS=W*H/16;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,prot=0,roi=0;
 reg [23:0] rgb=0;reg [15:0] now_ms=0;
 reg [7:0] valid=0;reg [95:0] xs=0,ys=0;
 wire ov,oh,od,op,hit,busy,bank;wire [23:0] out;wire [8:0] count;
 roi_motion_trail #(.IMG_W(W),.IMG_H(H),.MULTI_ENABLE(1),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50)) dut(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),.in_enable(1'b1),.in_clear(1'b0),
 .in_rgb(rgb),.ms_now(now_ms),.point_valid(valid[0]),.point_x({4'd0,xs[11:0]}),.point_y({4'd0,ys[11:0]}),
 .multi_mode(1'b1),.multi_valid(valid),.multi_x0(xs),.multi_x1(xs),.multi_y0(ys),.multi_y1(ys),
 .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_hit(hit),.out_rgb(out),.render_busy(busy),.point_count(count),.bank_valid(bank));
 wire aov,aoh,aod,aop,ahit,bov,boh,bod,bop,bhit;wire [23:0] ar,br;
 roi_motion_trail #(.IMG_W(W),.IMG_H(H),.MULTI_ENABLE(1),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50)) single_new(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),.in_enable(1'b1),.in_clear(1'b0),
 .in_rgb(rgb),.ms_now(now_ms),.point_valid(valid[0]),.point_x({4'd0,xs[11:0]}),.point_y({4'd0,ys[11:0]}),
 .multi_mode(1'b0),.multi_valid(valid),.multi_x0(xs),.multi_x1(xs),.multi_y0(ys),.multi_y1(ys),
 .out_vs(aov),.out_hs(aoh),.out_de(aod),.out_protect(aop),.out_hit(ahit),.out_rgb(ar),.render_busy(),.point_count(),.bank_valid());
 before_roi_motion_trail #(.IMG_W(W),.IMG_H(H),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50)) single_old(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),.in_enable(1'b1),.in_clear(1'b0),
 .in_rgb(rgb),.ms_now(now_ms),.point_valid(valid[0]),.point_x({4'd0,xs[11:0]}),.point_y({4'd0,ys[11:0]}),
 .out_vs(bov),.out_hs(boh),.out_de(bod),.out_protect(bop),.out_hit(bhit),.out_rgb(br),.render_busy(),.point_count(),.bank_valid());
 reg [215:0] stimulus[0:N-1];reg [CELLS-1:0] masks[0:N-1];reg [8:0] counts[0:N-1];
 reg [28:0] expected=0,delayed=0,want;reg expected_hit;
 integer f,x,y,i,pixels=0,hits=0,lane_hits[0:7];
 always @(posedge clk)begin
  if(!rst)delayed=0;
  else begin
   want=delayed;delayed=expected;
   #1;
   if({ov,oh,od,op,hit,out}!==want)$fatal(1,"Eight-path bitmap/RGB/control mismatch frame%0d xy%0d,%0d actual%h expected%h",f,x,y,{ov,oh,od,op,hit,out},want);
   if({aov,aoh,aod,aop,ahit,ar}!=={bov,boh,bod,bop,bhit,br})$fatal(1,"Existing single-target trajectory changed");
   if(od)begin pixels=pixels+1;if(hit)hits=hits+1;end
  end
 end
 initial begin
  $readmemh("../build/multi_trail_20261030/stim.hex",stimulus);
  $readmemh("../build/multi_trail_20261030/mask.hex",masks);
  $readmemh("../build/multi_trail_20261030/counts.hex",counts);
  for(i=0;i<8;i=i+1)lane_hits[i]=0;
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)begin
   if(busy)$fatal(1,"Multi-trail renderer exceeded frame budget");
   @(negedge clk);{now_ms,valid,xs,ys}=stimulus[f];vs=1;de=0;hs=0;prot=0;roi=0;expected={1'b1,28'd0};
   repeat(6)@(negedge clk);vs=0;expected=0;
   for(y=0;y<H;y=y+1)for(x=0;x<HT;x=x+1)begin
    @(negedge clk);de=x<W;hs=x>=W+4 && x<W+10;
    prot=de && x==31;roi=de && x>=int'(xs[11:0])-3 && x<=int'(xs[11:0])+3;
    rgb=prot?24'hffff20:(roi?24'h20b050:24'h939393);
    expected_hit=de && !prot && !roi && masks[f][(y/4)*(W/4)+x/4];
    expected={vs,hs,de,prot || expected_hit,expected_hit,de?(expected_hit?24'hff8800:rgb):24'd0};
    if(expected_hit && f>=15 && f<=30)lane_hits[y/16]=lane_hits[y/16]+1;
   end
   @(negedge clk);de=0;hs=0;prot=0;roi=0;expected=0;repeat(4)@(negedge clk);
   if(count!==counts[f])$fatal(1,"Eight-path history cadence/count mismatch frame%0d got%0d expected%0d",f,count,counts[f]);
   if(f%25==0)$display("TRACE multi-trail frame%0d history%0d",f,count);
  end
  for(i=0;i<8;i=i+1)if(lane_hits[i]==0)$fatal(1,"Target %0d has no visible trajectory",i);
  if(pixels!=W*H*N || hits==0)$fatal(1,"Incomplete eight-path display coverage");
  $display("PASS multi_trail: %0d pixels; eight simultaneous continuous independent paths, first/other target loss and reacquisition, one-second expiry, 16-bit time wrap, independent integer bitmap oracle, overlay/ROI protection, original single path RGB/control bit exact",pixels);$finish;
 end
 initial begin #150000000;$fatal(1,"Multi-trail timeout");end
endmodule

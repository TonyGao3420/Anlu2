`timescale 1ns/1ps
module tb_multi_trail_budget;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,de=0;wire busy;
 roi_motion_trail #(.MULTI_ENABLE(1),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50)) dut(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(1'b0),.in_de(de),.in_protect(1'b0),.in_roi(1'b0),.in_enable(1'b1),.in_clear(1'b0),
 .in_rgb(24'h808080),.ms_now(16'd1000),.point_valid(1'b0),.point_x(16'd0),.point_y(16'd0),
 .multi_mode(1'b1),.multi_valid(8'd0),.multi_x0(96'd0),.multi_x1(96'd0),.multi_y0(96'd0),.multi_y1(96'd0),
 .out_vs(),.out_hs(),.out_de(),.out_protect(),.out_hit(),.out_rgb(),.render_busy(busy),.point_count(),.bank_valid());
 integer i,id,c,cycles,a,x,y;reg want;reg [8:0] xx;reg [7:0] yy;
 initial begin
  repeat(5)@(negedge clk);rst=1;vs=1;repeat(3)@(negedge clk);vs=0;de=1;
  repeat(2)@(negedge clk);de=0;repeat(30)@(negedge clk);
  // Fill the real 256-entry RAM to stress the shared builder: eight interleaved
  // lanes, 32 samples each, each segment spanning the full permitted 80 cells.
  for(i=0;i<256;i=i+1)begin
   id=i%8;c=i/8;xx=c%2?80:0;yy=10+id*20;
   dut.history[i]={16'd1000,1'b1,(c!=0),xx,yy,2'd0,3'(id)};
  end
  dut.head=0;dut.count=256;
  vs=1;repeat(3)@(negedge clk);vs=0;de=1;repeat(2)@(negedge clk);de=0;
  cycles=0;
  while(!dut.ready && cycles<1237500)begin @(negedge clk);cycles=cycles+1;end
  if(!dut.ready || busy)$fatal(1,"1280x720 eight-path rebuild missed 60 Hz deadline");
  for(y=0;y<180;y=y+1)for(x=0;x<320;x=x+1)begin
   want=x<=80 && y>=10 && (y-10)%20==0 && y<=150;a=y*320+x;
   if(dut.mask1[a]!==want)$fatal(1,"Interleaved eight-lane worst-case path bridged or missing %0d,%0d",x,y);
  end
  $display("PASS multi_trail_budget: 1280x720, all 256 history records, eight interleaved maximum-link paths, complete bitmap exact; %0d clocks versus 1237500 clocks/frame",cycles);$finish;
 end
 initial begin #15000000;$fatal(1,"Budget timeout");end
endmodule

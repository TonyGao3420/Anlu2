`timescale 1ns/1ps
module tb_trail_budget;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,de=0;
 reg [15:0] ms=0,px=0,py=0;reg valid=1;wire ov,oh,od,op,hit,busy,bv;wire[23:0] rgb;wire[8:0] count;
 roi_motion_trail dut(.clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(1'b0),.in_de(de),
  .in_protect(1'b0),.in_roi(1'b0),.in_enable(1'b1),.in_clear(1'b0),.in_rgb(24'h606060),
  .ms_now(ms),.point_valid(valid),.point_x(px),.point_y(py),
  .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_hit(hit),.out_rgb(rgb),
  .render_busy(busy),.point_count(count),.bank_valid(bv));
 integer k,n,max_cycles=0,x,y,checked=0;reg check=0;
 reg[26:0] expected=0,want=0;reg expected_hit=0;
 always @(posedge clk)if(rst && check)begin
  want=expected;expected={de,(de && expected_hit),(de && expected_hit),de?(expected_hit?24'hff8800:24'h606060):24'd0};
  #1;if({od,op,hit,rgb}!==want)$fatal(1,"Default-geometry raster reference mismatch at pixel%0d",checked);
  if(od)checked=checked+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  // 256 live entries and one overwrite; long allowed segments each way.
  for(k=0;k<257;k=k+1)begin
   @(negedge clk);vs=1;de=0;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);
   px=(k%2)?320:0;ms=k*2;de=1;
   @(negedge clk);de=0;n=0;
   while(busy)begin @(negedge clk);n=n+1;if(n>150000)$fatal(1,"Renderer exceeded bound");end
   if(n>max_cycles)max_cycles=n;
   if(count!=((k<256)?k+1:256))$fatal(1,"Default history count mismatch");
  end
  if(dut.head!=1 || dut.history[0][39:24]!=512)$fatal(1,"Live circular overwrite failed");
  @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);
  px=1279;py=719;ms=514;de=1;@(negedge clk);de=0;n=0;
  while(busy)begin @(negedge clk);n=n+1;if(n>150000)$fatal(1,"Corner rebuild exceeded bound");end
  if(n>max_cycles)max_cycles=n;
  @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);
  valid=0;ms=516;check=1;
  for(y=0;y<720;y=y+1)for(x=0;x<1650;x=x+1)begin
   @(negedge clk);de=(x<1280);expected_hit=(y<4 && x<=323) || (y>=716 && x>=1276 && x<1280);
  end
  @(negedge clk);de=0;expected_hit=0;repeat(3)@(negedge clk);
  if(checked!=921600 || max_cycles>=1650*750)$fatal(1,"Budget or edge raster incomplete");
  $display("PASS trail_budget: 257 live records/overwrite, max rebuild %0d clocks <1237500-frame budget, 921600 default-geometry pixels including painted origin and bottom-right cell57599",max_cycles);$finish;
 end
 initial begin #220000000;$fatal(1,"Budget timeout");end
endmodule

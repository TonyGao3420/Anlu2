`timescale 1ns/1ps
module tb_trail_watchdog;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,de=0;reg[15:0] ms=0;reg valid=1;
 wire ov,oh,od,op,hit,busy,bv;wire[23:0] rgb;wire[8:0] count;
 roi_motion_trail #(.IMG_W(64),.IMG_H(48),.HISTORY_DEPTH(16)) dut(
  .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(1'b0),.in_de(de),.in_protect(1'b0),.in_roi(1'b0),
  .in_enable(1'b1),.in_clear(1'b0),.in_rgb(24'h808080),.ms_now(ms),
  .point_valid(valid),.point_x(16'd20),.point_y(16'd20),
  .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_hit(hit),.out_rgb(rgb),
  .render_busy(busy),.point_count(count),.bank_valid(bv));
 task frame_pulse;
 begin
  @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);
  de=1;@(negedge clk);de=0;
  while(busy)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;frame_pulse;
  @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;
  if(!bv || count!=1)$fatal(1,"Watchdog test failed to publish initial trail");
  ms=249;repeat(3)@(negedge clk);if(!bv)$fatal(1,"Watchdog cleared too early");
  ms=250;repeat(3)@(negedge clk);if(bv || count!=0 || busy)$fatal(1,"Video interruption did not clear cache and history");
  ms=0;valid=0;frame_pulse; // A complete 16-bit wall-time wrap cannot revive stale RAM.
  @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;
  repeat(1800)begin @(negedge clk);de=1;if(hit)$fatal(1,"Old trail returned after timeout/wrap");end
  @(negedge clk);de=0;
  $display("PASS trail_watchdog: retain before 250ms, clear on interrupted video, no stale cache after resume or timestamp wrap");$finish;
 end
 initial begin #1000000;$fatal(1,"Watchdog timeout");end
endmodule

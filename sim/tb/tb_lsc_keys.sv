`timescale 1ns/1ps
module tb_lsc_keys;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,fs=0,kcal=1,kclear=1;
 wire cal,clear;integer nc=0,nr=0;
 lsc_cal_keys #(.HOLD_FRAMES(3)) dut(.clk(clk),.rst_n(rst_n),.frame_start(fs),
  .cal_key_n(kcal),.clear_key_n(kclear),.cal_request(cal),.clear_request(clear));
 always @(posedge clk)begin #1;if(cal)nc=nc+1;if(clear)nr=nr+1;end
 task frame_pulse;begin @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(3)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  kcal=0;repeat(4)@(negedge clk);frame_pulse();kcal=1;repeat(6)@(negedge clk);
  if(nc || nr)$fatal(1,"Short key press triggered calibration");
  kcal=0;repeat(4)@(negedge clk);repeat(5)frame_pulse();
  if(nc)$fatal(1,"Calibration started before release");
  kcal=1;repeat(8)@(negedge clk);if(nc!=1)$fatal(1,"Long key release missing/duplicated pulse");
  repeat(4)frame_pulse();if(nc!=1)$fatal(1,"Spurious repeat request");
  kclear=0;repeat(4)@(negedge clk);repeat(3)frame_pulse();kclear=1;
  repeat(8)@(negedge clk);if(nr!=1 || nc!=1)$fatal(1,"Independent clear request failed");
  $display("PASS LSC keys: short press ignored; long release one-shot; clear independent");$finish;
 end
endmodule

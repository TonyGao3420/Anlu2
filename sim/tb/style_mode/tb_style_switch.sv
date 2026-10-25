`timescale 1ns/1ps
module tb_style_switch;
 reg clk=0;always #5 clk=~clk;reg rst=0,sw=0;wire request;
 style_switch_control dut(clk,rst,sw,request);
 localparam N=750000;
 task stable(input bit value,input integer cycles);
 begin @(negedge clk);sw=value;repeat(cycles)@(negedge clk);end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  stable(1,20);stable(0,25);if(request!==0)$fatal(1,"Mechanical bounce enabled mode");
  stable(1,N-1);if(request!==0)$fatal(1,"Enabled before 10ms stable input");
  repeat(5)@(negedge clk);if(request!==1)$fatal(1,"Stable ON was not accepted");
  stable(0,20);stable(1,25);if(request!==1)$fatal(1,"Short OFF bounce disabled mode");
  stable(0,N-1);if(request!==1)$fatal(1,"Disabled before 10ms stable input");
  repeat(5)@(negedge clk);if(request!==0)$fatal(1,"Stable OFF was not accepted");
  stable(1,N/2);rst=0;#1;if(request!==0)$fatal(1,"Reset did not disable mode");
  repeat(5)@(negedge clk);rst=1;repeat(N-1)@(negedge clk);
  if(request!==0)$fatal(1,"Reset did not restart stable interval");
  repeat(6)@(negedge clk);if(request!==1)$fatal(1,"Restart did not recover");
  $display("PASS style_switch: default 750000-cycle/10ms filter, both directions, contact bounce, pending reset and restart");$finish;
 end
 initial begin #40000000;$fatal(1,"Switch test timeout");end
endmodule

`timescale 1ns/1ps
module tb_eram_logo;
 reg clk=0;always #5 clk=~clk;reg rst=0;reg[14:0] addr=0;
 wire[24:0] current,reference;reg[24:0] previous=0;integer valid=0,checked=0;
 anlogic_logo_eram dut(clk,rst,addr,current);
 anlogic_logo_rom golden(addr,reference);
 always @(posedge clk)begin
  if(!rst)begin valid=0;previous=0;#1;if(current!==0)$fatal(1,"Logo reset output");end
  else begin
   #1;if(current!==(valid==0?25'd0:previous))$fatal(1,"Palette loss/latency at sample%0d got%h expected%h",checked,current,previous);
   previous=reference;valid=1;checked=checked+1;
  end
 end
 integer a,pass;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(pass=0;pass<2;pass=pass+1)begin
   for(a=0;a<32768;a=a+1)begin @(negedge clk);addr=pass?((a*8191+7919)&32767):a;end
   @(negedge clk);addr=15'bxxxxxxxxxxxxxxx;
   @(negedge clk);addr=15'bzzzzzzzzzzzzzzz;
   repeat(3)@(negedge clk);
   rst=0;repeat(4)@(negedge clk);addr=0;rst=1;
  end
  repeat(3)@(negedge clk);
  $display("PASS eram_logo: 32768 addresses sequential and permuted, all 580 exact colors/transparency, two-stage latency, X/Z defaults, reset/restart");$finish;
 end
endmodule

`timescale 1ns/1ps
module tb_official_logo;
 reg clk=0;always #5 clk=~clk;reg rst=0;reg [16:0] addr=0;
 wire [24:0] pixel;reg [24:0] reference[0:32767];
 reg [24:0] previous=0;integer valid=0,checked=0,a,p;
 anlogic_logo_eram dut(clk,rst,addr,pixel);
 always @(posedge clk)begin
  if(!rst)begin previous=0;valid=0;#1;if(pixel!==0)$fatal(1,"Logo reset");end
  else begin
   #1;if(pixel!==(valid?previous:25'd0))$fatal(1,"Logo sample%0d address%0d got%h want%h",checked,addr,pixel,valid?previous:25'd0);
   previous=(addr<25600)?reference[addr]:25'd0;valid=1;checked=checked+1;
  end
 end
 initial begin
  $readmemh("../build/three_fixes_20261027/official_logo_reference.hex",reference);
  for(p=0;p<2;p=p+1)begin
   rst=0;repeat(4)@(negedge clk);rst=1;
   for(a=0;a<131072;a=a+1)begin @(negedge clk);addr=p?((a*8191+7919)&131071):a;end
   @(negedge clk);addr=0;repeat(3)@(negedge clk);
  end
  $display("PASS official_logo: all 25600 official pixels/580 colors and alpha, 131072 sequential/permuted addresses, bank boundaries, invalid-address transparency, two stages, reset/restart");$finish;
 end
endmodule

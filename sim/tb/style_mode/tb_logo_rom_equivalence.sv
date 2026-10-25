`timescale 1ns/1ps
module tb_logo_rom_equivalence;
 reg[14:0] address=0;wire[24:0] actual,reference;integer n;
 anlogic_logo_rom fast(address,actual);
 anlogic_logo_rom_reference original(address,reference);
 initial begin
  for(n=0;n<32768;n=n+1)begin address=n;#1;if(actual!==reference)$fatal(1,"ROM mismatch address%0d",n);end
  address=15'hxxxx;#1;if(actual!==reference)$fatal(1,"Unknown ROM address behavior differs");
  $display("PASS logo_rom_equivalence: all 32768 addresses and unknown/default behavior bit identical to production ROM");$finish;
 end
endmodule

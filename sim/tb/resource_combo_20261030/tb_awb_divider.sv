`timescale 1ns/1ps
module tb_awb_divider;
 reg clk=0,rst=1,start=0;reg [31:0] denominator=1;reg [47:0] numerator=0;
 wire a_done,b_done;wire [47:0] aq,bq;integer cycle=0,sent=0,received=0,i;
 reg [47:0] expected[0:511];reg [47:0] n;reg [31:0] d;
 always #5 clk=~clk;
 divider original(.clk(clk),.rst(rst),.start(start),.numerator(numerator),.denominator(denominator),.quotient(aq),.done(a_done));
 awb_frame_divider serial(.clk(clk),.rst(rst),.start(start),.numerator(numerator),.denominator(denominator),.quotient(bq),.done(b_done));
 always @(posedge clk)begin
  cycle=cycle+1;#1;
  if(!rst && cycle>60)begin
   if(a_done!==b_done)$fatal(1,"DONE latency mismatch cycle=%0d vendor=%b serial=%b",cycle,a_done,b_done);
   if(a_done)begin
    if(aq!==bq || bq!==expected[received])$fatal(1,"QUOTIENT mismatch id=%0d vendor=%h serial=%h math=%h",received,aq,bq,expected[received]);
    received=received+1;
   end
  end
 end
 task submit(input [47:0] value,input [31:0] divisor);begin
  @(negedge clk);numerator=value;denominator=divisor;start=1;
  expected[sent]=(divisor==0)?48'hffffffffffff:value/divisor;sent=sent+1;
  @(negedge clk);start=0;repeat(50)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;repeat(60)@(negedge clk);
  submit(0,1);submit(48'hffffffffffff,1);submit(48'hffffffffffff,32'hffffffff);
  submit(48'hffffffffffff,0);submit(48'h123456789abc,0);submit(1,32'hffffffff);
  submit(48'h000100000000,32'h00010000);submit(48'hffffff000000,32'hffffffff);
  for(i=0;i<128;i=i+1)begin n={$random,$random};d=$random;submit(n,d);end
  repeat(60)@(negedge clk);
  if(received!=sent)$fatal(1,"Missing quotient %0d/%0d",received,sent);
  $display("PASS awb_divider: %0d official 50-clock IP comparisons, exact done and 48-bit quotient, zero/one/max divisors and random full-width inputs",received);$finish;
 end
endmodule

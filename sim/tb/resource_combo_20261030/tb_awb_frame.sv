`timescale 1ns/1ps
module tb_awb_frame;
 reg clk=0,rst=0,user=0,last=0,valid=0,ready=1;reg [95:0] data=0;
 wire ardy,al,au,av,brdy,bl,bu,bv;wire [95:0] ad,bd;
 integer f,n,lane,cycles=0,compared=0,gain_changes=0;reg [19:0] previous=20'h10000;
 reg [7:0] red,green,blue;reg [95:0] value;
 always #5 clk=~clk;
 baseline_awb_frame_stable #(.IMG_WIDTH(64),.IMG_HEIGHT(16),.MIN_SAMPLES(64)) original(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ardy),
 .O_tlast(al),.O_tuser(au),.O_tdata(ad),.O_tvalid(av),.O_tready(ready));
 awb_frame_stable #(.IMG_WIDTH(64),.IMG_HEIGHT(16),.MIN_SAMPLES(64)) candidate(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(brdy),
 .O_tlast(bl),.O_tuser(bu),.O_tdata(bd),.O_tvalid(bv),.O_tready(ready));
 task tick(input u,v,t,input [95:0] p);begin
  @(negedge clk);cycles=cycles+1;
  if(rst)begin
   if({ardy,al,au,av,ad}!=={brdy,bl,bu,bv,bd})$fatal(1,"AWB stream mismatch frame=%0d word=%0d cycle=%0d",f,n,cycles);
   if({original.in_r_r1,original.in_b_r1,original.candidate_r,original.candidate_b,original.candidate_valid,original.gain_initialized}!==
      {candidate.in_r_r1,candidate.in_b_r1,candidate.candidate_r,candidate.candidate_b,candidate.candidate_valid,candidate.gain_initialized})
    $fatal(1,"AWB gain/update-time mismatch frame=%0d cycle=%0d",f,cycles);
   if(original.in_r_r1!=previous)begin gain_changes=gain_changes+1;previous=original.in_r_r1;end
   if(av)compared=compared+4;
  end
  user=u;valid=v;last=t;data=p;ready=(cycles%7)!=0;
 end endtask
 initial begin
  repeat(5)tick(0,0,0,0);rst=1;repeat(65)tick(0,0,0,0);
  for(f=0;f<16;f=f+1)begin
   tick(1,0,0,0);repeat(3)tick(0,0,0,0);
   for(n=0;n<((f==9)?128:256);n=n+1)begin
    for(lane=0;lane<4;lane=lane+1)begin
     case(f%8)
      0:begin red=120;green=125;blue=130;end
      1:begin red=150;green=120;blue=70;end
      2:begin red=70;green=100;blue=140;end
      3:begin red=255;green=255;blue=255;end
      4:begin red=16;green=200;blue=16;end
      5:begin red=30;green=32;blue=34;end
      6:begin red=n[0]?255:100;green=n[0]?255:140;blue=n[0]?255:90;end
      default:begin red=$random;green=$random;blue=$random;end
     endcase
     value[lane*24+:24]={red,green,blue};
    end
    tick(0,1,n%16==15,value);
    if(n%19==0)repeat(2)tick(0,0,0,0);
   end
   if(f==8)begin repeat(12)tick(0,0,0,0);rst=0;repeat(3)tick(0,0,0,0);rst=1;end
   // Both adequate and deliberately short blanking, as well as an aborted frame.
   repeat((f%4==2)?8:80)tick(0,0,0,0);
  end
  repeat(100)tick(0,0,0,0);
  if(compared<10000 || gain_changes<4)$fatal(1,"Insufficient gain/pixel exercise %0d %0d",compared,gain_changes);
  $display("PASS awb_frame: %0d four-lane pixels, 16 frames; RGB/control/ready and exact gain/candidate update cycles, warm/cool/white/green/dark/random, invalid samples, short blanking, aborted frame and reset identical",compared);$finish;
 end
endmodule

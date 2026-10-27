`timescale 1ns/1ps
module tb_frame_latency;
 reg sys=0,raw=0,ddr=0,pix=0;always #10 sys=~sys;always #4.85 raw=~raw;always #7.5 ddr=~ddr;always #6.666 pix=~pix;
 reg rst=0,sof=0,ws=0,we=0,rs=0;reg [1:0] wb=0,rb=0;reg [24:0] addr=0;
 wire [23:0] age;wire [15:0] id;wire valid;
 frame_latency dut(sys,rst,raw,sof,ddr,ws,wb,we,addr,rs,rb,pix,age,id,valid);
 task capture;begin @(negedge raw);sof=1;@(negedge raw);sof=0;repeat(30)@(negedge ddr);end endtask
 task write_begin(input [1:0] b);begin @(negedge ddr);wb=b;ws=1;@(negedge ddr);ws=0;end endtask
 task complete(input [1:0] b);begin @(negedge ddr);addr=1382392+7000000*b;we=1;@(negedge ddr);we=0;end endtask
 task read_begin(input [1:0] b);begin @(negedge ddr);rb=b;rs=1;@(negedge ddr);rs=0;repeat(8)@(negedge pix);end endtask
 reg [23:0] stamp0,expected;
 initial begin
  repeat(5)@(negedge sys);rst=1;#12000;
  read_begin(0);if(valid)$fatal(1,"Unwritten bank valid");
  capture();stamp0=dut.raw_stamp;write_begin(0);#10000;complete(0);
  capture();write_begin(1);#5000;read_begin(1);if(valid)$fatal(1,"Incomplete frame valid");complete(1);
  read_begin(0);expected=dut.pix_now-stamp0;
  if(!valid || id!=1 || age!=expected || age<14)$fatal(1,"Bank0 latency not associated with its captured frame %d %d",id,age);
  read_begin(1);if(!valid || id!=2)$fatal(1,"Bank1 ID wrong");
  capture();write_begin(0);read_begin(0);if(valid)$fatal(1,"Rewritten incomplete bank retained old validity");complete(0);
  read_begin(0);if(!valid || id!=3)$fatal(1,"Rewritten bank identity wrong");
  read_begin(1);if(!valid || id!=2)$fatal(1,"Older selected frame identity changed");
  $display("PASS frame_latency: asynchronous 50/103/66/75MHz, actual DDR bank association, repeated/older reads, incomplete invalidation; exact decoded timestamp subtraction");$finish;
 end
 initial begin #1000000;$fatal(1,"Latency timeout");end
endmodule

module tb_multi_overlay;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,protect=0,en=0;
 reg [23:0] rgb=0;reg [7:0] v=3;reg [95:0] x0=0,y0=0,x1=0,y1=0;
 reg [23:0] age=33450;reg [15:0] fid=42;wire ov,oh,od;wire [23:0] out;
 multi_target_overlay dut(.clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(protect),.in_rgb(rgb),
 .enable(en),.valid(v),.x0(x0),.y0(y0),.x1(x1),.y1(y1),.count(4'd2),.total(16'd2),.process_us(16'd550),.overflow(1'b0),.late(1'b0),
 .age_us(age),.frame_id(fid),.latency_valid(1'b1),.out_vs(ov),.out_hs(oh),.out_de(od),.out_rgb(out));
 reg [26:0] delayed[0:2];reg [11:0] xp[0:2],yp[0:2],sample_x=0,sample_y=0;reg pp[0:2];integer i,x,y,f,checked=0,boxes=0,hud=0;
 always @(posedge clk)begin
  delayed[0]<={vs,hs,de,rgb};xp[0]<=sample_x;yp[0]<=sample_y;pp[0]<=protect;
  for(i=1;i<3;i=i+1)begin delayed[i]<=delayed[i-1];xp[i]<=xp[i-1];yp[i]<=yp[i-1];pp[i]<=pp[i-1];end
  #1;if(rst && f>=0)begin
   if({ov,oh,od}!==delayed[2][26:24])$fatal(1,"Overlay controls not exactly 3 clocks");
   if(od)begin
    checked=checked+1;
    if(f==0 || pp[2])begin if(out!==delayed[2][23:0])$fatal(1,"Disabled/protected RGB changed");end
    else if(xp[2]==400 && yp[2]>=200 && yp[2]<=300)begin if(out!=24'h00ffff)$fatal(1,"Box1 missing");boxes=boxes+1;end
    else if(xp[2]==700 && yp[2]>=400 && yp[2]<=500)begin if(out!=24'hffb030)$fatal(1,"Box2 missing");boxes=boxes+1;end
    else if(xp[2]>=1008 && xp[2]<1264 && yp[2]>=16 && yp[2]<112)hud=hud+1;
   end
  end
 end
 initial begin
  f=-1;x=0;y=0;repeat(6)@(negedge clk);rst=1;
  x0[0+:12]=400;x1[0+:12]=500;y0[0+:12]=200;y1[0+:12]=300;
  x0[12+:12]=700;x1[12+:12]=800;y0[12+:12]=400;y1[12+:12]=500;
  for(f=0;f<3;f=f+1)begin
   en=f!=0;
   @(negedge clk);vs=1;repeat(10)@(negedge clk);vs=0;repeat(8)@(negedge clk);
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1650;x=x+1)begin @(negedge clk);sample_x=x;sample_y=y;de=x<1280;hs=x>=1390 && x<1430;protect=x<160 && y<160;
     rgb={8'(x),8'(y),8'(x^y)};
     if(y==10 && x==0)begin v=8'hff;age=99999;fid=43;end // Inputs change mid-frame, snapshot must not.
    end
    de=0;
   end
   repeat(20)@(negedge clk);
   if(f==1 && (dut.fc!=2 || dut.age_bcd!=24'h033450 || dut.us_bcd!=24'h000550 || dut.total_bcd!=24'h000002 || dut.fid!=43))begin
    // First enabled frame starts with values modified during disabled frame.
    if(dut.age_bcd!=24'h099999 || dut.fid!=43)$fatal(1,"HUD decimal conversion/snapshot wrong %h %d",dut.age_bcd,dut.fid);
   end
  end
  if(checked!=2764800 || boxes!=404 || hud!=49152)$fatal(1,"Overlay coverage %d %d %d",checked,boxes,hud);
  $display("PASS multi_overlay: 2764800 pixels, two independent boxes/colors, first-pixel atomic metadata, protected Logo, 3 aligned clocks, decimal latency");$finish;
 end
 initial begin #100000000;$fatal(1,"Overlay timeout");end
endmodule

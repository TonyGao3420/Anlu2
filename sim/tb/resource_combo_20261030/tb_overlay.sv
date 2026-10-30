`timescale 1ns/1ps
module tb_overlay;
 reg clk=0,rst=0,vs=0,hs=0,de=0,protect=0,enable=0,style=0;
 reg [23:0] rgb=0;reg [7:0] valid=0;reg [95:0] x0=0,y0=0,x1=0,y1=0;
 wire av,ah,ad,bv,bh,bd;wire [23:0] ar,br;
 integer f,x,y,z,pixels=0,cycles=0;
 always #5 clk=~clk;
 multi_target_overlay #(.COMBO_STATUS(1)) snapshot(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(protect),.in_rgb(rgb),
 .style_active(style),.enable(enable),.valid(valid),.x0(x0),.y0(y0),.x1(x1),.y1(y1),
 .count(4'd8),.total(16'd12345),.process_us(16'd333),.overflow(1'b0),.late(1'b0),
 .age_us(24'd16789),.frame_id(16'd17),.latency_valid(1'b1),.out_vs(av),.out_hs(ah),.out_de(ad),.out_rgb(ar));
 multi_target_overlay #(.COMBO_STATUS(1),.FRAME_STABLE_BOXES(1)) reuse(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(protect),.in_rgb(rgb),
 .style_active(style),.enable(enable),.valid(valid),.x0(x0),.y0(y0),.x1(x1),.y1(y1),
 .count(4'd8),.total(16'd12345),.process_us(16'd333),.overflow(1'b0),.late(1'b0),
 .age_us(24'd16789),.frame_id(16'd17),.latency_valid(1'b1),.out_vs(bv),.out_hs(bh),.out_de(bd),.out_rgb(br));
 task tick(input v,h,d,input [23:0] c);begin
  @(negedge clk);cycles=cycles+1;
  if(rst && cycles>8 && {av,ah,ad,ar}!=={bv,bh,bd,br})
   $fatal(1,"Overlay reuse mismatch frame=%0d x=%0d y=%0d",f,x,y);
  if(ad)pixels=pixels+1;
  vs=v;hs=h;de=d;rgb=c;protect=d && c[7:0]==8'h55;
 end endtask
 initial begin
  repeat(5)tick(0,0,0,0);rst=1;
  for(f=0;f<4;f=f+1)begin
   // Update only in blanking, exactly as the main detector's SOF contract.
   enable=f!=2;style=f[0];valid=(f==0)?8'hff:((f==1)?8'h7f:((f==2)?8'h00:8'h81));
   for(z=0;z<8;z=z+1)begin
    x0[z*12+:12]=40+z*120+f;y0[z*12+:12]=100+z*55;
    x1[z*12+:12]=100+z*120+f;y1[z*12+:12]=150+z*55;
   end
   x0[0+:12]=0;y0[0+:12]=0;x1[0+:12]=30;y1[0+:12]=30;
   x0[12+:12]=1249;y0[12+:12]=0;x1[12+:12]=1279;y1[12+:12]=30;
   x0[24+:12]=0;y0[24+:12]=689;x1[24+:12]=30;y1[24+:12]=719;
   x0[36+:12]=1249;y0[36+:12]=689;x1[36+:12]=1279;y1[36+:12]=719;
   tick(1,0,0,0);repeat(8)tick(0,0,0,0);
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)tick(0,x==0,1,$random);
    repeat(7)tick(0,0,0,0);
   end
   repeat(12)tick(0,0,0,0);
  end
  repeat(10)tick(0,0,0,0);
  if(pixels!=3686400)$fatal(1,"Wrong compared pixel count %0d",pixels);
  $display("PASS overlay_reuse: 3686400 full-resolution pixels; all eight boxes, corners, invalid slots, normal/multi/style header, protected overlays, RGB and three-clock control exact");
  $finish;
 end
endmodule

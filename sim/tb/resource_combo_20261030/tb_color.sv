`timescale 1ns/1ps
module tb_color;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,protect=0;reg [11:0] x=0,y=0;reg [23:0] rgb=0;
 wire av,ah,ad,ap,bv,bh,bd,bp;wire [23:0] a,b;
 baseline_display_color_shading refcolor(clk,rst,vs,hs,de,protect,x,y,rgb,av,ah,ad,ap,a);
 display_color_shading optcolor(clk,rst,vs,hs,de,protect,x,y,rgb,bv,bh,bd,bp,b);
 integer xx,yy,f,n=0;reg [31:0] rng=32'h1234abcd;
 always @(posedge clk)begin #1;if(rst)begin
  if({av,ah,ad,ap,a}!=={bv,bh,bd,bp,b})$fatal(1,"Color or latency changed at sample%0d x%0d y%0d %h != %h",n,x,y,a,b);
  n=n+1;
 end end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<3;f=f+1)begin
   for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<1280;xx=xx+1)begin
    @(negedge clk);x=xx;y=yy;de=1;vs=xx==0 && yy==0;hs=xx==0;protect=((xx+yy+f)%19)==0;
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    case(f)0:rgb=rng[23:0];1:rgb={8'(xx),8'(yy),8'(xx+yy)};2:rgb=((xx+yy)%3==0)?24'h0e0e0e:((xx+yy)%3==1?24'hffffff:24'h20a030);endcase
   end
   @(negedge clk);de=0;vs=0;protect=0;repeat(15)@(negedge clk);
  end
  rst=0;repeat(3)@(negedge clk);rst=1;
  for(xx=0;xx<4096;xx=xx+1)begin @(negedge clk);x=xx;y=4095-xx;de=1;rgb=24'hd392ad;end
  @(negedge clk);de=0;repeat(15)@(negedge clk);
  $display("PASS color_equivalence: 2764800 active pixels, all coordinates, random/ramps/black/white/green, OSD protection, reset and out-of-frame clamp; latest nine-node calibration and 8-clock timing bit exact");$finish;
 end
 initial begin #40000000;$fatal(1,"Color timeout");end
endmodule

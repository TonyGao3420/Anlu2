`timescale 1ns/1ps
module w128_d512_fifo(input rst,clkw,we,input [127:0] di,output afull,full_flag,output [8:0] wrusedw,
 input clkr,re,output reg [127:0] dout,output [8:0] rdusedw,output valid,empty_flag,aempty);
 reg [127:0] mem[0:511];integer wp=0,rp=0;
 always @(posedge clkw)if(rst)wp<=0;else if(we)begin mem[wp%512]<=di;wp<=wp+1;end
 always @(posedge clkr)if(rst)begin rp<=0;dout<=0;end else if(re)begin
  if(wp==rp)$fatal(1,"Rotate FIFO underflow");dout<=mem[rp%512];rp<=rp+1;end
 assign wrusedw=wp-rp;assign rdusedw=wp-rp;assign empty_flag=wp==rp;
 assign valid=re;assign full_flag=(wp-rp)>=512;assign afull=0;assign aempty=0;
endmodule
module tb_rotate180;
 localparam W=1280,H=720,PIXELS=W*H,WORDS=PIXELS*3/16;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,de=0,busy=1,ready=0,dvalid=0;
 reg [1:0] bank=0;wire req;wire [24:0] addr;reg [127:0] data=0;wire [23:0] rgb;
 video_out #(.ROTATE_180(1)) dut(rst,clk,,busy,bank,req,addr,ready,dvalid,data,clk,vs,de,rgb);
 function [23:0] pattern(input integer pixel);
  integer x,y;begin x=pixel%W;y=pixel/W;pattern={8'(x^y),8'(y+17),8'((x>>3)+y*3+71)};end
 endfunction
 function [127:0] word_data(input integer word_index);
  integer j,pos;reg [23:0] v;begin
   for(j=0;j<16;j=j+1)begin pos=word_index*16+j;v=pattern(pos/3);word_data[127-j*8-:8]=v[23-(pos%3)*8-:8];end
  end
 endfunction
 integer cycle=0,expected_word=WORDS-1,base=0,requests=0,seen=0,total=0;
 reg [1:0] valid_pipe=0;
 always @(posedge clk)begin
  cycle=cycle+1;dvalid<=rst && req;
  if(rst && req)begin
   if(addr!==base+expected_word*8)$fatal(1,"Rotation address/buffer got%0d want%0d",addr,base+expected_word*8);
   data<=word_data(expected_word);expected_word=(expected_word==0)?WORDS-1:expected_word-1;requests=requests+1;
  end
  valid_pipe={valid_pipe[0],de};
  #1;if(rst && valid_pipe[1])begin
   if(rgb!==pattern(PIXELS-1-seen))$fatal(1,"Rotation RGB index%0d got%h want%h",seen,rgb,pattern(PIXELS-1-seen));
   seen=seen+1;total=total+1;
  end
 end
 integer b,y,x;
 initial begin
  repeat(10)@(negedge clk);rst=1;
  for(b=0;b<4;b=b+1)begin
   busy=1;ready=0;repeat(300)@(negedge clk);
   bank=b;base=b*7000000;expected_word=WORDS-1;vs=1;
   repeat(6)@(negedge clk);vs=0;repeat(30)@(negedge clk);
   seen=0;busy=0;
   for(x=0;x<400;x=x+1)begin ready=(cycle%7!=0);@(negedge clk);end
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<W+370;x=x+1)begin de=x<W;ready=(cycle%7!=0);@(negedge clk);end
   end
   de=0;repeat(4)@(negedge clk);if(seen!=PIXELS)$fatal(1,"Rotation missing pixels");
   // Finish any issued burst before changing selected frame/buffer.
   busy=1;ready=1;repeat(300)@(negedge clk);
  end
  $display("PASS rotate180: %0d 720p RGB pixels, four frame buffers, full row/column reversal, RGB byte order, cross-word pixels 5/10, request stalls, safe over-prefetch wrap, unchanged reader latency",total);$finish;
 end
 initial begin #100000000;$fatal(1,"Rotation timeout");end
endmodule

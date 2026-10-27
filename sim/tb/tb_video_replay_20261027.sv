`timescale 1ns/1ps
module tb_video_replay;
 localparam W=1280,H=720,HT=1650,VT=750,LAT=8*HT+8,TOTAL=W*H;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0;reg [23:0] rgb=0;reg [7:0] gray=0;
 wire ov,oh,od,op,roi,en;wire [23:0] out;
 roi_background_stylize #(.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32))
  dut(clk,rst,vs,hs,de,1'b0,1'b1,rgb,gray,1'b1,16'd800,16'd450,16'd1200,16'd719,ov,oh,od,op,out,roi,en);
 reg [32:0] stim[0:TOTAL-1];reg [25:0] gold[0:TOTAL-1];reg [28:0] pipe[0:LAT-1];
 reg [28:0] expected=0,want;integer p=0,i,y,x,index,seen=0,fd;
 always @(posedge clk)begin
  if(!rst)begin for(i=0;i<LAT;i=i+1)pipe[i]=0;p=0;end else begin
   want=pipe[p];pipe[p]=expected;p=(p==LAT-1)?0:p+1;#1;
   if({ov,oh,od,op,roi,out}!==want)$fatal(1,"Real-video replay mismatch pixel%0d got%h want%h",seen,{ov,oh,od,op,roi,out},want);
   if(od)begin $fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);seen=seen+1;end
  end
 end
 initial begin
  $readmemh("../build/three_fixes_20261027/replay_stim.hex",stim);$readmemh("../build/three_fixes_20261027/replay_gold.hex",gold);
  fd=$fopen("../build/three_fixes_20261027/movie/replay_new.ppm","wb");if(!fd)$fatal(1,"Replay dump");$fwrite(fd,"P6\n1280 720\n255\n");
  repeat(6)@(negedge clk);rst=1;
  for(y=0;y<VT;y=y+1)for(x=0;x<HT;x=x+1)begin
   @(negedge clk);vs=y<3;hs=x>=1390 && x<1430;de=y>=6 && y<H+6 && x<W;
   expected={vs,hs,de,26'd0};rgb=0;gray=0;
   if(de)begin index=(y-6)*W+x;{gray,rgb}={stim[index][32:25],stim[index][23:0]};expected={vs,hs,de,gold[index]};end
  end
  @(negedge clk);vs=0;hs=0;de=0;expected=0;repeat(LAT+4)@(negedge clk);$fclose(fd);
  if(seen!=TOTAL)$fatal(1,"Replay pixel count");$display("PASS video_replay: 921600 supplied-video RGB pixels match independent reference, not an SC520 board capture");$finish;
 end
endmodule

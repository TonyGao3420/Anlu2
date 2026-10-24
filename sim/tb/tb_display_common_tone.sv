`timescale 1ns/1ps
module tb_display_common_tone;
reg clk=0;always #5 clk=~clk;reg rst_n=0,vs=0,hs=0,de=0,p=0;reg [23:0] rgb=0,e=0;
wire ov,oh,od;wire [23:0] o;
display_common_tone dut(clk,rst_n,vs,hs,de,p,rgb,ov,oh,od,o);
reg [23:0] ep[0:2];reg [2:0] vp=0,hp=0,dp=0;integer j,checked=0;
always @(posedge clk)if(rst_n)begin
 ep[2]=ep[1];ep[1]=ep[0];ep[0]=e;vp={vp[1:0],vs};hp={hp[1:0],hs};dp={dp[1:0],de};
 #1;if({ov,oh,od,o}!=={vp[2],hp[2],dp[2],ep[2]})$fatal(1,"Tone mismatch %0d got%h expected%h",checked,o,ep[2]);checked=checked+1;
end
integer fd,n,a,b,c,d,count=0;
initial begin
 for(j=0;j<3;j=j+1)ep[j]=0;
 repeat(5)@(negedge clk);rst_n=1;
 fd=$fopen("../build/raw_color_bright_20261009/tone_vectors.txt","r");
 while(!$feof(fd))begin
 @(negedge clk);n=$fscanf(fd,"%h %h %d %d %d %d\n",rgb,e,a,b,c,d);if(n!=6)$fatal(1,"Bad tone vector");de=a;p=b;vs=c;hs=d;count=count+1;
 end
 @(negedge clk);de=0;p=0;vs=0;hs=0;rgb=0;e=0;repeat(5)@(negedge clk);
 $display("PASS display_common_tone: %0d gray/color/highlight/OSD and timing vectors",count);$finish;
end
endmodule

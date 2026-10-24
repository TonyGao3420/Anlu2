`timescale 1ns/1ps
module tb_isp_raw_color;
reg clk=0;always #5 clk=~clk;reg rst_n=0,v=0,u=0,l=0;reg [39:0] d=0;wire ov,ou,ol,ready;wire [127:0] od;
isp_top dut(.axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_tlast(l),.I_tuser(u),.I_tdata(d),.I_tvalid(v),.I_tdest(10'd0),.O_tready(1'b1),.O_tdata(od),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.I_tready(ready));
reg [39:0] raw[0:230399];integer f=0,x,y,n,packed_count=0,awb_count=0,checks=0;
integer i,r,g,b,minc,maxc;reg [23:0] p;reg [19:0] frozen_r,frozen_b;
always @(posedge clk)begin
 #1;
 if(rst_n)begin
 if(ov)begin if((^od)===1'bx)$fatal(1,"Packed unknown data");packed_count=packed_count+1;end
 if(dut.awb_O_tvalid)begin
  if(awb_count==0)begin frozen_r=dut.u_awb.in_r_r1;frozen_b=dut.u_awb.in_b_r1;end
  if(dut.u_awb.in_r_r1!==frozen_r || dut.u_awb.in_b_r1!==frozen_b)$fatal(1,"ISP AWB gain scan variation");
  if(f==2 && awb_count/320>16 && awb_count/320<704 && awb_count%320>4 && awb_count%320<316)begin
   for(i=0;i<4;i=i+1)begin
    p=dut.awb_O_tdata[i*24+:24];r=p[23:16];g=p[15:8];b=p[7:0];
    minc=(r<g?r:g);if(b<minc)minc=b;maxc=(r>g?r:g);if(b>maxc)maxc=b;
    if((^p)===1'bx || maxc-minc>3 || minc<55 || maxc>65)$fatal(1,"Integrated neutral shading wrong beat%0d lane%0d rgb%h",awb_count,i,p);
    checks=checks+1;
   end
  end
  awb_count=awb_count+1;
 end
 end
end
initial begin
 $readmemh("../build/raw_color_bright_20261009/isp_flat_inverse.txt",raw);
 repeat(8)@(negedge clk);rst_n=1;
 for(f=1;f<=2;f=f+1)begin
 packed_count=0;awb_count=0;
 for(y=0;y<720;y=y+1)begin
 for(x=0;x<320;x=x+1)begin @(negedge clk);v=1;u=(x==0&&y==0);l=(x==319);d=raw[y*320+x];end
 @(negedge clk);v=0;u=0;l=0;d=0;
 // First-line data has not reached AWB yet; its SOF precedes active output.
 if(y==0)begin repeat(1100)@(negedge clk);frozen_r=dut.u_awb.in_r_r1;frozen_b=dut.u_awb.in_b_r1;end
 else repeat(100)@(negedge clk);
 end
 repeat(3000)@(negedge clk);
 $display("ISP f%0d AWB beats %0d packed %0d samples %0d candidate %b",f,awb_count,packed_count,dut.u_awb.samples,dut.u_awb.candidate_valid);
 if(awb_count!=230400 || packed_count!=172800 || dut.u_awb.beats!=230400 || !dut.u_awb.candidate_valid)$fatal(1,"ISP complete-frame length/candidate failed");
 end
 if(checks<800000)$fatal(1,"Missing neutral spatial coverage");
 $display("PASS isp_raw_color: two complete 720p frames through real RAW/demosaic/AWB/packer RTL; %0d neutral pixels; constant frame gains",checks);$finish;
end
initial begin #9000000;$fatal(1,"ISP timeout");end
endmodule

`timescale 1ns/1ps
module tb_awb_frame_stable;
localparam W=1280,H=8,N=W/4*H,F=6;
reg clk=0;always #5 clk=~clk;reg rst_n=0,v=0,u=0,l=0;reg [95:0] data=0;
wire ov,ou,ol,ready;wire [95:0] od;
awb_frame_stable #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) dut(clk,rst_n,l,u,data,v,ready,ol,ou,od,ov,1'b1);
function automatic [23:0] sample(input integer f,beat,lane);
 reg [7:0] r,g,b;
 begin
 if(f==2)begin r=14;g=14;b=14;end
 else if(f==3)begin r=100;g=100;b=100;end
 else if(lane==0)begin r=100;g=140;b=80;if(beat<160 && f==1)begin r=50;g=160;b=40;end end
 else begin r=40+((beat*3+lane*7)%215);g=30+((beat+lane)%200);b=20+((beat*7+lane*11)%230);end
 sample={r,g,b};
 end
endfunction
function automatic [7:0] correct(input [7:0] v,input [19:0] gain);
 reg [31:0] product;integer t;
 begin product=(v>14?v-14:0)*gain;t=(product>>16)+14;correct=v<=14?v:(t>255?255:t);end
endfunction
function automatic [19:0] approach(input [19:0] a,b);
 begin approach=b>=a?a+((b-a+3)>>2):a-((a-b+3)>>2);end
endfunction
reg [19:0] gr[0:F-1],gb[0:F-1];integer out_count=0,fidx,bidx,j,clipped=0;reg [23:0] pix,expected;
always @(posedge clk)begin
 #1;
 if(rst_n && ov)begin
 fidx=out_count/N;bidx=out_count%N;if(fidx>=F)$fatal(1,"Extra AWB pixels");
 for(j=0;j<4;j=j+1)begin
 pix=sample(fidx,bidx,j);expected={correct(pix[23:16],gr[fidx]),pix[15:8],correct(pix[7:0],gb[fidx])};
 if(od[j*24+:24]!==expected)$fatal(1,"Frame AWB value/order f%0d beat%0d lane%0d got%h expected%h",fidx,bidx,j,od[j*24+:24],expected);
 if(expected[23:16]==255 || expected[7:0]==255)clipped=clipped+1;
 end
 if(dut.in_r_r1!==gr[fidx] || dut.in_b_r1!==gb[fidx])$fatal(1,"AWB changed gain within active frame");
 out_count=out_count+1;
 end
end
integer f,y,x,k;reg [31:0] sr,sg,sb;reg [19:0] cr,cb;reg [23:0] p;
initial begin
 repeat(5)@(negedge clk);rst_n=1;cr=65536;cb=65536;
 for(f=0;f<F;f=f+1)begin
 if(f==0)begin gr[f]=65536;gb[f]=65536;end
 else if(f==1)begin gr[f]=cr;gb[f]=cb;end
 else if(f==3)begin gr[f]=gr[f-1];gb[f]=gb[f-1];end
 else begin gr[f]=approach(gr[f-1],cr);gb[f]=approach(gb[f-1],cb);end
 sr=1;sg=1;sb=1;
 for(y=0;y<H;y=y+1)begin
 for(x=0;x<W/4;x=x+1)begin
 @(negedge clk);v=1;u=(x==0&&y==0);l=(x==W/4-1);
 for(k=0;k<4;k=k+1)data[k*24+:24]=sample(f,y*(W/4)+x,k);
 p=sample(f,y*(W/4)+x,0);if(f!=2)begin sr=sr+p[23:16]-14;sg=sg+p[15:8]-14;sb=sb+p[7:0]-14;end
 end
 @(negedge clk);v=0;u=0;l=0;data=0;repeat(120)@(negedge clk);
 end
 repeat(200)@(negedge clk);
 if(f!=2)begin cr=({16'd0,sg,16'd0}/sr);cb=({16'd0,sg,16'd0}/sb);
 if(!dut.candidate_valid || dut.candidate_r!==cr || dut.candidate_b!==cb)$fatal(1,"Completed frame statistics wrong f%0d samples%0d got%h/%h expected%h/%h",f,dut.samples,dut.candidate_r,dut.candidate_b,cr,cb);
 end else if(dut.candidate_valid)$fatal(1,"Covered lens replaced AWB gains");
 if(out_count!=(f+1)*N)$fatal(1,"AWB stream count f%0d got%0d",f,out_count);
 end
 if(clipped==0 || ready!==1)$fatal(1,"Missing coverage");
 $display("PASS awb_frame_stable: six frames, full-frame statistics, frozen gains, black, empty frame hold, slew, four-lane order and saturation");$finish;
end
initial begin #500000;$fatal(1,"Frame AWB timeout");end
endmodule

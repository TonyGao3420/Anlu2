// Static measured BGGR shading, before demosaic/AWB. Four pixels per beat.
// Eight clocks: fixed latency for data/valid/user/last/dest, no backpressure.
// Black 64 is measured, not guessed. No key-driven calibration or new pins.
module raw_measured_shading #(
 parameter integer W=1280,H=720,BLACK_LEVEL=64,ENABLE=1
)(
 input wire clk,rst_n,in_valid,in_user,in_last,
 input wire [39:0] in_data,input wire [9:0] in_dest,
 output wire out_valid,out_user,out_last,
 output reg [39:0] out_data,output wire [9:0] out_dest
);
 reg [11:0] x,y;
 wire [11:0] px=in_user?12'd0:x,py=in_user?12'd0:y;
 function [11:0] gain_node;
 input [5:0] index;
 begin case(index)
            6'd0: gain_node=12'd1041;
            6'd1: gain_node=12'd1012;
            6'd2: gain_node=12'd1037;
            6'd3: gain_node=12'd779;
            6'd4: gain_node=12'd1097;
            6'd5: gain_node=12'd1037;
            6'd6: gain_node=12'd1012;
            6'd7: gain_node=12'd986;
            6'd8: gain_node=12'd1002;
            6'd9: gain_node=12'd1000;
            6'd10:gain_node=12'd1050;
            6'd11:gain_node=12'd806;
            6'd12:gain_node=12'd1046;
            6'd13:gain_node=12'd1003;
            6'd14:gain_node=12'd1046;
            6'd15:gain_node=12'd814;
            6'd16:gain_node=12'd1195;
            6'd17:gain_node=12'd1022;
            6'd18:gain_node=12'd1026;
            6'd19:gain_node=12'd1259;
            6'd20:gain_node=12'd1016;
            6'd21:gain_node=12'd1024;
            6'd22:gain_node=12'd1024;
            6'd23:gain_node=12'd870;
            6'd24:gain_node=12'd1086;
            6'd25:gain_node=12'd992;
            6'd26:gain_node=12'd1058;
            6'd27:gain_node=12'd867;
            6'd28:gain_node=12'd1114;
            6'd29:gain_node=12'd1016;
            6'd30:gain_node=12'd1032;
            6'd31:gain_node=12'd1112;
            6'd32:gain_node=12'd1018;
            6'd33:gain_node=12'd1021;
            6'd34:gain_node=12'd1027;
            6'd35:gain_node=12'd891;
 default:gain_node=12'd1024;
 endcase end endfunction
 reg [7:0] vp,up,lp;
 reg [39:0] raw[0:6];reg [9:0] dest[0:7];
 assign out_valid=vp[7];assign out_user=up[7];assign out_last=lp[7];assign out_dest=dest[7];
 reg [8:0] fx1[0:3],fy1,fy2,fy3;
 reg [11:0] a[0:3],b[0:3],c[0:3],d[0:3];
 reg signed [23:0] top_product[0:3],bottom_product[0:3],vertical[0:3];
 reg [11:0] top_base2[0:3],bottom_base2[0:3],top3[0:3],bottom3[0:3],base4[0:3],gain5[0:3],gain6[0:3];
 reg [9:0] signal6[0:3];reg [21:0] product7[0:3];
 integer i,l,xx,tl,ch,index,fy,dy;
 function [9:0] finish;
 input [9:0] original;input [21:0] product;
 reg [22:0] lifted;
 begin
 lifted=BLACK_LEVEL+((product+23'd512)>>10);
 if(!ENABLE || original<=BLACK_LEVEL)finish=original;
 else if(lifted>1023)finish=1023;
 else finish=lifted[9:0];
 end endfunction
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 x<=0;y<=0;vp<=0;up<=0;lp<=0;out_data<=0;fy1<=0;fy2<=0;fy3<=0;
 for(i=0;i<7;i=i+1)raw[i]<=0;
 for(i=0;i<8;i=i+1)dest[i]<=0;
 for(l=0;l<4;l=l+1)begin
  fx1[l]<=0;a[l]<=1024;b[l]<=1024;c[l]<=1024;d[l]<=1024;
  top_product[l]<=0;bottom_product[l]<=0;vertical[l]<=0;
  top_base2[l]<=1024;bottom_base2[l]<=1024;top3[l]<=1024;bottom3[l]<=1024;
  base4[l]<=1024;gain5[l]<=1024;gain6[l]<=1024;signal6[l]<=0;product7[l]<=0;
 end
 end else begin
 if(in_user)begin x<=0;y<=0;end
 if(in_valid)begin
  if(in_last)begin x<=0;y<=py+1'b1;end else begin x<=px+4;y<=py;end
 end
 vp<={vp[6:0],in_valid};up<={up[6:0],in_user};lp<={lp[6:0],in_last};
 raw[0]<=in_data;for(i=1;i<7;i=i+1)raw[i]<=raw[i-1];
 dest[0]<=in_dest;for(i=1;i<8;i=i+1)dest[i]<=dest[i-1];
 if(py<=90)fy=0;else if(py>=630)fy=256;
 else begin dy=(py<360)?py-90:py-360;fy=(dy*243+128)>>8;end
 fy1<=fy;fy2<=fy1;fy3<=fy2;
 for(l=0;l<4;l=l+1)begin
  xx=px+l;tl=((py<360)?0:3)+((xx<640)?0:1);
  ch=(py[0]?2:0)+(l%2);index=tl*4+ch;
  a[l]<=gain_node(index);b[l]<=gain_node(index+4);c[l]<=gain_node(index+12);d[l]<=gain_node(index+16);
  if(xx<=128)fx1[l]<=0;else if(xx>=1152)fx1[l]<=256;
  else fx1[l]<=(xx-((xx<640)?128:640))>>1;
  top_product[l]<=($signed({1'b0,b[l]})-$signed({1'b0,a[l]}))*$signed({1'b0,fx1[l]});
  bottom_product[l]<=($signed({1'b0,d[l]})-$signed({1'b0,c[l]}))*$signed({1'b0,fx1[l]});
  top_base2[l]<=a[l];bottom_base2[l]<=c[l];
  top3[l]<=$signed({1'b0,top_base2[l]})+((top_product[l]+24'sd128)>>>8);
  bottom3[l]<=$signed({1'b0,bottom_base2[l]})+((bottom_product[l]+24'sd128)>>>8);
  vertical[l]<=($signed({1'b0,bottom3[l]})-$signed({1'b0,top3[l]}))*$signed({1'b0,fy3});
  base4[l]<=top3[l];gain5[l]<=$signed({1'b0,base4[l]})+((vertical[l]+24'sd128)>>>8);
  signal6[l]<=(raw[4][l*10+:10]>BLACK_LEVEL)?raw[4][l*10+:10]-BLACK_LEVEL:0;
  gain6[l]<=gain5[l];product7[l]<=signal6[l]*gain6[l];
  out_data[l*10+:10]<=finish(raw[6][l*10+:10],product7[l]);
 end
 end end
endmodule

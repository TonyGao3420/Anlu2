// Display-only residual edge correction. The ROI stream never enters this module.
// Six clocks for RGB/VS/HS/DE/protect. Black/OSD remain exact; green is unchanged.
// Coefficients are bounded residual tuning from spatial feedback, not RAW measurements.
module display_edge_color #(
 parameter integer W=1280,H=720,ENABLE=1,BLACK_LEVEL=14
)(input clk,rst_n,in_vs,in_hs,in_de,in_protect,input [23:0] in_rgb,
 output out_vs,out_hs,out_de,out_protect,output reg [23:0] out_rgb);
 reg [11:0] x,y;reg vs_d;
 reg [5:0] vp,hp,dp,pp;
 reg [23:0] raw[0:4];
 reg [8:0] left1,right1,left2,right2;
 reg [7:0] top1,bottom1;reg [8:0] top2,bottom2;
 reg [11:0] red_gain3,blue_gain3,red_gain4,blue_gain4;
 reg [7:0] red_signal4,blue_signal4;
 reg [19:0] red_product5,blue_product5;
 function [8:0] x_weight;
 input [8:0] distance;reg [17:0] scaled;
 begin scaled=distance*9'd171+18'd128;
 x_weight=(scaled>>8)>256?9'd256:(scaled>>8);end endfunction
 function [7:0] finish;
 input [7:0] original;input [19:0] product;reg [11:0] value;
 begin value=BLACK_LEVEL+((product+20'd512)>>10);
 finish=original<=BLACK_LEVEL?original:(value>255?8'd255:value[7:0]);end endfunction
 assign out_vs=vp[5];assign out_hs=hp[5];assign out_de=dp[5];assign out_protect=pp[5];
 wire [10:0] bottom_tripled={2'b0,bottom2}+({2'b0,bottom2}<<1);
 wire [7:0] left_coeff=8'd160+(top2>>2)-(bottom_tripled>>3);
 wire [7:0] right_coeff=8'd80-(top2>>3)+(bottom2>>4);
 integer i,red_loss,blue_loss;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 x<=0;y<=0;vs_d<=0;vp<=0;hp<=0;dp<=0;pp<=0;
 left1<=0;right1<=0;left2<=0;right2<=0;top1<=0;bottom1<=0;top2<=0;bottom2<=0;
 red_gain3<=1024;blue_gain3<=1024;red_gain4<=1024;blue_gain4<=1024;
 red_signal4<=0;blue_signal4<=0;red_product5<=0;blue_product5<=0;out_rgb<=0;
 for(i=0;i<5;i=i+1)raw[i]<=0;
 end else begin
 vs_d<=in_vs;
 if(in_vs && !vs_d)begin x<=0;y<=0;end
 else if(in_de)begin
 if(x==W-1)begin x<=0;y<=y==H-1?12'd0:y+1'b1;end else x<=x+1'b1;
 end
 vp<={vp[4:0],in_vs};hp<={hp[4:0],in_hs};dp<={dp[4:0],in_de};pp<={pp[4:0],in_protect};
 raw[0]<=in_rgb;for(i=1;i<5;i=i+1)raw[i]<=raw[i-1];
 // P1: full-frame distances; zero correction in the central rectangle.
 left1<=(x<384)?384-x:0;right1<=(x>896)?((x>=1280)?384:x-896):0;
 top1<=(y<216)?216-y:0;bottom1<=(y>504)?((y>=720)?216:y-504):0;
 // P2: normalized edge weights.
 left2<=x_weight(left1);right2<=x_weight(right1);
 top2<=(top1*9'd303+18'd128)>>8;bottom2<=(bottom1*9'd303+18'd128)>>8;
 // P3: directional residual gains; stronger upper-left and full top/bottom edges.
 // The central rectangle is still exact unity; blue tuning is unchanged.
 red_loss=(left2*left_coeff+right2*right_coeff+top2*96+bottom2*64+128)>>8;
 blue_loss=($signed({1'b0,left2})*32+$signed({1'b0,top2})*32+$signed({1'b0,bottom2})*16-$signed({1'b0,right2})*64+128)>>>8;
 red_gain3<=1024-red_loss;blue_gain3<=1024-blue_loss;
 // P4: black-subtracted signal; P5: multiply; P6: restore and protect.
 red_gain4<=red_gain3;blue_gain4<=blue_gain3;
 red_signal4<=raw[2][23:16]>BLACK_LEVEL?raw[2][23:16]-BLACK_LEVEL:0;
 blue_signal4<=raw[2][7:0]>BLACK_LEVEL?raw[2][7:0]-BLACK_LEVEL:0;
 red_product5<=red_signal4*red_gain4;blue_product5<=blue_signal4*blue_gain4;
 if(!dp[4])out_rgb<=0;
 else if(!ENABLE || pp[4])out_rgb<=raw[4];
 else out_rgb<={finish(raw[4][23:16],red_product5),raw[4][15:8],finish(raw[4][7:0],blue_product5)};
 end end
endmodule

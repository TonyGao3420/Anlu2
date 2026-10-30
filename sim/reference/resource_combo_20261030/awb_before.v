/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
// Frame-consistent derivative of official AWB: same stream buffering and IP.
// Complete-frame statistics, measured black subtraction, update only at SOF.
module baseline_awb_frame_stable #(
 parameter IMG_HEIGHT=720,IMG_WIDTH=1280,BLACK_LEVEL=14,MIN_SAMPLES=256
)(input I_clk,I_rst_n,I_tlast,I_tuser,input [95:0] I_tdata,input I_tvalid,
 output I_tready,O_tlast,O_tuser,output [95:0] O_tdata,output O_tvalid,input O_tready);
 localparam integer FRAME_BEATS=IMG_HEIGHT*(IMG_WIDTH/4);
 reg [95:0] input0,input1;reg valid0,valid1;
 reg [31:0] sum_r,sum_g,sum_b,samples;
 reg [19:0] beats;reg launch,frame_eligible;
 wire [7:0] r=input0[23:16],g=input0[15:8],b=input0[7:0];
 wire [9:0] pixel_sum={2'b0,r}+{2'b0,g}+{2'b0,b};
 function [7:0] signal_value;
 input [7:0] value;
 begin signal_value=value>BLACK_LEVEL?value-BLACK_LEVEL:0;end
 endfunction
 wire eligible=(pixel_sum<720) && (r>BLACK_LEVEL+7) && (g>BLACK_LEVEL+7) && (b>BLACK_LEVEL+7);
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin input0<=0;input1<=0;valid0<=0;valid1<=0;end
 else begin input0<=I_tdata;input1<=input0;valid0<=I_tvalid;valid1<=valid0;end
 end
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin sum_r<=1;sum_g<=1;sum_b<=1;samples<=0;beats<=0;launch<=0;frame_eligible<=0;end
 else begin
 launch<=0;
 if(I_tuser)begin sum_r<=1;sum_g<=1;sum_b<=1;samples<=0;beats<=0;frame_eligible<=0;end
 else if(valid0 && beats<FRAME_BEATS)begin
  beats<=beats+1'b1;
  if(eligible)begin
   sum_r<=sum_r+signal_value(r);sum_g<=sum_g+signal_value(g);sum_b<=sum_b+signal_value(b);samples<=samples+1'b1;
  end
  if(beats==FRAME_BEATS-1)begin launch<=1;frame_eligible<=(samples+(eligible?1:0)>=MIN_SAMPLES);end
 end
 end end
 wire [47:0] qr,qb;wire done;
 divider div_gen_G_R_r1(.clk(I_clk),.rst(!I_rst_n),.start(launch),.denominator(sum_r),.numerator({sum_g,16'd0}),.quotient(qr),.done(done));
 divider divide_G_B_r1(.clk(I_clk),.rst(!I_rst_n),.start(launch),.denominator(sum_b),.numerator({sum_g,16'd0}),.quotient(qb),.done());
 reg [19:0] in_r_r1,in_b_r1,candidate_r,candidate_b;
 reg candidate_valid,gain_initialized;
 function [19:0] clamp_gain;
 input [47:0] q;
 begin clamp_gain=(|q[47:20])?20'hfffff:q[19:0];end
 endfunction
 function [19:0] approach;
 input [19:0] previous,target;
 begin
 if(target>=previous)approach=previous+((target-previous+20'd3)>>2);
 else approach=previous-((previous-target+20'd3)>>2);
 end endfunction
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 in_r_r1<=20'h10000;in_b_r1<=20'h10000;candidate_r<=20'h10000;candidate_b<=20'h10000;
 candidate_valid<=0;gain_initialized<=0;
 end else begin
 if(done && frame_eligible)begin candidate_r<=clamp_gain(qr);candidate_b<=clamp_gain(qb);candidate_valid<=1;end
 if(I_tuser)begin
  candidate_valid<=0;
  if(candidate_valid)begin
   in_r_r1<=gain_initialized?approach(in_r_r1,candidate_r):candidate_r;
   in_b_r1<=gain_initialized?approach(in_b_r1,candidate_b):candidate_b;
   gain_initialized<=1;
  end
 end
 end end
 wire [95:0] delayed;wire delayed_valid;
 signal_delay #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH),.DATA_WIDTH(96),.DELAY_CYCLE(50))
 signal_delay_d(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),.I_valid(valid1),.I_data(input1),.O_valid(delayed_valid),.O_data(delayed),.O_tuser());
 reg [95:0] pixels,original;reg pixels_valid,product_valid;
 reg [27:0] red_product[0:3],blue_product[0:3];integer i;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 pixels<=0;original<=0;pixels_valid<=0;product_valid<=0;
 for(i=0;i<4;i=i+1)begin red_product[i]<=0;blue_product[i]<=0;end
 end else begin
 pixels<=delayed;pixels_valid<=delayed_valid;product_valid<=pixels_valid;
 if(pixels_valid)begin
  original<=pixels;
  for(i=0;i<4;i=i+1)begin
   red_product[i]<=in_r_r1*signal_value(pixels[i*24+16+:8]);
   blue_product[i]<=in_b_r1*signal_value(pixels[i*24+:8]);
  end
 end
 end end
 function [7:0] restored;
 input [7:0] raw;input [27:0] product;
 reg [12:0] value;
 begin
 value=(product>>16)+BLACK_LEVEL;
 restored=raw<=BLACK_LEVEL?raw:(value>255?8'd255:value[7:0]);
 end endfunction
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin: output_pixels
 assign O_tdata[lane*24+:24]=O_tvalid?{restored(original[lane*24+16+:8],red_product[lane]),original[lane*24+8+:8],restored(original[lane*24+:8],blue_product[lane])}:24'd0;
 end endgenerate
 assign O_tvalid=product_valid;
 assign O_tlast=!pixels_valid && product_valid;
 // Early frame reset is required by the downstream asynchronous FIFO.
 assign O_tuser=I_tuser;assign I_tready=O_tready;
endmodule

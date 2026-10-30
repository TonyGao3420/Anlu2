// Behavioral quotient/token model checked independently against the official IP
// by tb_awb_divider. These modules are simulation-only, never production sources.
module divider(input clk,rst,start,input [31:0] denominator,input [47:0] numerator,
 output [47:0] quotient,output done);
 reg [49:0] vp;reg [47:0] qp[0:49];integer i;
 assign done=vp[49];assign quotient=qp[49];
 always @(posedge clk or posedge rst)if(rst)begin
  vp<=0;for(i=0;i<50;i=i+1)qp[i]<=0;
 end else begin
  vp<={vp[48:0],start};
  if(start)qp[0]<=denominator==0?48'hffffffffffff:numerator/denominator;
  for(i=1;i<50;i=i+1)qp[i]<=qp[i-1];
 end
endmodule
// The unchanged stream-buffer module is common to both AWB implementations.
module signal_delay #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280,DATA_WIDTH=96,DELAY_CYCLE=50)(
 input I_clk,I_rst_n,I_tuser,I_valid,input [DATA_WIDTH-1:0] I_data,
 output O_valid,output [DATA_WIDTH-1:0] O_data,output O_tuser);
 reg [DELAY_CYCLE-1:0] valid,user;reg [DATA_WIDTH-1:0] data[0:DELAY_CYCLE-1];integer i;
 assign O_valid=valid[DELAY_CYCLE-1];assign O_data=data[DELAY_CYCLE-1];assign O_tuser=user[DELAY_CYCLE-1];
 always @(posedge I_clk or negedge I_rst_n)if(!I_rst_n)begin
  valid<=0;user<=0;for(i=0;i<DELAY_CYCLE;i=i+1)data[i]<=0;
 end else begin
  valid<={valid[DELAY_CYCLE-2:0],I_valid};user<={user[DELAY_CYCLE-2:0],I_tuser};data[0]<=I_data;
  for(i=1;i<DELAY_CYCLE;i=i+1)data[i]<=data[i-1];
 end
endmodule

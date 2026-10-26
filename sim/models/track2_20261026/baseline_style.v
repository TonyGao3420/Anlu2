// Display-only style mode; aligned out_enable follows the same video RAM metadata. The detector/DDR/ISP never consume this output.
// Same-frame BxB mean luminance + 8-level posterization + coarse gradients.
// Full-color ROI and protected overlays are delayed bit-for-bit with the raster.
// Each input line MUST contain LINE_TOTAL clocks and IMG_W active pixels.
// IMG_W and IMG_H must be multiples of B=2**BLOCK_LOG2 (default 8).
// Runtime enable and validated bbox are latched at the first active pixel.
// Latency: B*LINE_TOTAL + 2 clocks. No full-frame history and no multipliers.
module roi_background_stylize_baseline #(
 parameter integer IMG_W=1280,IMG_H=720,LINE_TOTAL=1650,
 parameter integer BLOCK_LOG2=3,EDGE_THRESHOLD=40
)(
 input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,in_enable,
 input wire [23:0] in_rgb,
 // Camera luma before display-only edge/tone gains, aligned with in_rgb.
 input wire [7:0] in_gray,
 input wire bbox_valid,
 input wire [15:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1,
 output reg out_vs,out_hs,out_de,out_protect,
 output reg [23:0] out_rgb,output reg out_roi,output reg out_enable
);
 localparam integer B=1<<BLOCK_LOG2,COLS=IMG_W>>BLOCK_LOG2;
 localparam integer CW=(COLS<2)?1:$clog2(COLS);
 localparam integer HS_W=8+BLOCK_LOG2,SUM_W=8+2*BLOCK_LOG2;
 localparam integer DELAY=B*LINE_TOTAL,DEPTH=DELAY+1;
 localparam integer PW=$clog2(DEPTH),FW=$clog2(DELAY+1);

 reg vs_d,armed;
 reg [11:0] x,y;
 reg frame_enable,frame_valid;
 reg [15:0] fx0,fy0,fx1,fy1;
 wire first_pixel=in_de && armed && x==0 && y==0;
 wire bounds_ok=bbox_valid && bbox_x0<=bbox_x1 && bbox_y0<=bbox_y1 && bbox_x1<IMG_W && bbox_y1<IMG_H;
 wire use_valid=first_pixel?bounds_ok:frame_valid;
 wire use_enable=first_pixel?in_enable:frame_enable;
 wire [15:0] use_x0=first_pixel?bbox_x0:fx0,use_y0=first_pixel?bbox_y0:fy0;
 wire [15:0] use_x1=first_pixel?bbox_x1:fx1,use_y1=first_pixel?bbox_y1:fy1;
 wire keep_roi=use_valid && {4'd0,x}>=use_x0 && {4'd0,x}<=use_x1 &&
                           {4'd0,y}>=use_y0 && {4'd0,y}<=use_y1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   vs_d<=0;armed<=0;x<=0;y<=0;frame_enable<=0;frame_valid<=0;fx0<=0;fy0<=0;fx1<=0;fy1<=0;
  end else begin
   vs_d<=in_vs;
   if(in_vs && !vs_d)begin armed<=1;x<=0;y<=0;end
   else if(in_de && armed)begin
    if(x==IMG_W-1)begin x<=0;y<=(y==IMG_H-1)?12'd0:y+1'b1;end
    else x<=x+1'b1;
   end
   if(first_pixel)begin
    frame_enable<=in_enable;frame_valid<=bounds_ok;
    fx0<=bbox_x0;fy0<=bbox_y0;fx1<=bbox_x1;fy1<=bbox_y1;
   end
  end
 end

 // Separate read/write addresses are always one slot apart: no RAM collision
 // behavior is relied upon. Uninitialized RAM is masked during FIFO warmup.
 reg [29:0] video_ram[0:DEPTH-1];
 reg [PW-1:0] write_ptr,read_ptr;
 reg [FW-1:0] filled;
 reg video_ready;
 reg [29:0] video_q;
 always @(posedge clk)if(rst_n)begin
  video_ram[write_ptr]<={in_vs,in_hs,in_de,in_protect,keep_roi,use_enable,in_rgb};
  video_q<=video_ram[read_ptr];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin write_ptr<=0;read_ptr<=1;filled<=0;video_ready<=0;end
  else begin
   write_ptr<=(write_ptr==DEPTH-1)?0:write_ptr+1'b1;
   read_ptr<=(read_ptr==DEPTH-1)?0:read_ptr+1'b1;
   if(filled<DELAY)filled<=filled+1'b1;
   else video_ready<=1;
  end
 end
 wire [29:0] q=video_ready?video_q:30'd0;

 // One partial vertical sum per tile column; RAMs have synchronous reads and
 // no reset. Every tile is initialized on its first row before it is consumed.
 reg [SUM_W-1:0] column_sum[0:COLS-1];
 reg [7:0] above_gray[0:COLS-1];
 reg [7:0] background_row[0:COLS-1];
 reg [SUM_W-1:0] sum_q;
 reg [7:0] above_q,left_gray;
 reg [HS_W-1:0] horizontal_sum;
 wire [CW-1:0] col=x>>BLOCK_LOG2;
 wire [HS_W-1:0] row_sum=(x[BLOCK_LOG2-1:0]==0)?{{BLOCK_LOG2{1'b0}},in_gray}:
                           horizontal_sum+{{BLOCK_LOG2{1'b0}},in_gray};
 wire [SUM_W-1:0] extended_row={{BLOCK_LOG2{1'b0}},row_sum};
 wire [SUM_W-1:0] block_sum=(y[BLOCK_LOG2-1:0]==0)?extended_row:sum_q+extended_row;
 wire [7:0] mean_gray=block_sum[SUM_W-1:2*BLOCK_LOG2];
 wire [7:0] dx=(col==0)?8'd0:((mean_gray>=left_gray)?mean_gray-left_gray:left_gray-mean_gray);
 wire [7:0] dy=(y<B)?8'd0:((mean_gray>=above_q)?mean_gray-above_q:above_q-mean_gray);
 wire [8:0] gradient={1'b0,dx}+{1'b0,dy};
 wire [7:0] levels={mean_gray[7:5],mean_gray[7:5],mean_gray[7:6]};
 wire [7:0] styled_gray=(gradient>=EDGE_THRESHOLD)?8'd0:levels;
 always @(posedge clk)if(rst_n && in_de && armed && x<IMG_W && y<IMG_H)begin
  if(x[BLOCK_LOG2-1:0]==B-3)begin
   sum_q<=column_sum[col];above_q<=above_gray[col];
  end
  if(x[BLOCK_LOG2-1:0]==B-1)begin
   column_sum[col]<=block_sum;
   if(y[BLOCK_LOG2-1:0]==B-1)begin
    above_gray[col]<=mean_gray;background_row[col]<=styled_gray;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin horizontal_sum<=0;left_gray<=0;end
  else if(in_de && armed)begin
   horizontal_sum<=row_sum;
   if(x[BLOCK_LOG2-1:0]==B-1 && y[BLOCK_LOG2-1:0]==B-1)left_gray<=mean_gray;
  end
 end

 // Raster reconstructed on the delayed stream. Fetch each tile only at its
 // first pixel, before the next input tile-row overwrites the shared row RAM.
 reg q_vs_d,q_armed;
 reg [11:0] qx,qy;
 reg [7:0] background_q;
 reg [29:0] v1;
 always @(posedge clk)if(rst_n && q[27] && q_armed && qx[BLOCK_LOG2-1:0]==0)
  background_q<=background_row[qx>>BLOCK_LOG2];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   q_vs_d<=0;q_armed<=0;qx<=0;qy<=0;v1<=0;
   out_vs<=0;out_hs<=0;out_de<=0;out_protect<=0;out_rgb<=0;out_roi<=0;out_enable<=0;
  end else begin
   q_vs_d<=q[29];
   if(q[29] && !q_vs_d)begin q_armed<=1;qx<=0;qy<=0;end
   else if(q[27] && q_armed)begin
    if(qx==IMG_W-1)begin qx<=0;qy<=(qy==IMG_H-1)?12'd0:qy+1'b1;end
    else qx<=qx+1'b1;
   end
   v1<=q;
   out_vs<=v1[29];out_hs<=v1[28];out_de<=v1[27];out_protect<=v1[26];out_roi<=v1[27] && v1[25];out_enable<=v1[24];
   if(!v1[27])out_rgb<=0;
   else if(v1[26] || v1[25] || !v1[24])out_rgb<=v1[23:0];
   else out_rgb<={background_q,background_q,background_q};
  end
 end
 // synthesis translate_off
 initial begin
  if(BLOCK_LOG2<2 || IMG_W%B!=0 || IMG_H%B!=0 || LINE_TOTAL<=IMG_W)
   $fatal(1,"Unsupported stylizer geometry (B>=4, whole tiles, positive blanking required)");
 end
 // synthesis translate_on
endmodule

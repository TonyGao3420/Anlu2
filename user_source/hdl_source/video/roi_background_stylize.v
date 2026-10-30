// Display-only style mode; aligned out_enable follows the same video RAM metadata. The detector/DDR/ISP never consume this output.
// Same-frame BxB mean luminance; optional bright neutral model-like surfaces.
// Model mode retains green pixels only inside the tracked ROI. Overlays and
// rectangular ROI metadata still follow the original raster exactly.
// Each input line MUST contain LINE_TOTAL clocks and IMG_W active pixels.
// IMG_W and IMG_H must be multiples of B=2**BLOCK_LOG2 (default 8).
// Runtime enable and validated bbox are latched at the first active pixel.
// Latency: B*LINE_TOTAL + 2 clocks. No full-frame RGB history or multipliers.
module roi_background_stylize #(
 parameter integer IMG_W=1280,IMG_H=720,LINE_TOTAL=1650,
 parameter integer BLOCK_LOG2=3,EDGE_THRESHOLD=40,
 parameter integer MOTION_ENABLE=0,STATUS_ENABLE=0,MOTION_HIGH=12,MOTION_LOW=6,
 parameter integer MODEL_STYLE_ENABLE=0,MODEL_EDGE_THRESHOLD=24,
 parameter integer CLEAN_STYLE_ENABLE=0,MULTI_ROI_ENABLE=0,MULTI_ROI_STABLE_INPUT=0,
 parameter integer FRAME_TIMEOUT_CYCLES=18750000
)(
 input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,in_enable,
 input wire [23:0] in_rgb,
 // Camera luma before display-only edge/tone gains, aligned with in_rgb.
 input wire [7:0] in_gray,
 input wire bbox_valid,
 input wire [15:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1,
 output wire out_vs,out_hs,out_de,out_protect,
 output wire [23:0] out_rgb,output wire out_roi,output wire out_enable,
 input wire multi_mode,input wire [7:0] multi_valid,
 input wire [95:0] multi_x0,multi_y0,multi_x1,multi_y1
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
 wire keep_single=use_valid && {4'd0,x}>=use_x0 && {4'd0,x}<=use_x1 &&
                           {4'd0,y}>=use_y0 && {4'd0,y}<=use_y1;
 // Reuse the existing one-bit ROI metadata and video RAM for the union.
 wire keep_roi;
 generate if(MULTI_ROI_ENABLE)begin: multi_roi
  reg fm;wire [7:0] fv;wire [95:0] fx0,fy0,fx1,fy1;
  if(MULTI_ROI_STABLE_INPUT)begin: stable_source
   // The detector already publishes atomic SOF results, stable for active video.
   assign fv=multi_valid;assign fx0=multi_x0;assign fy0=multi_y0;assign fx1=multi_x1;assign fy1=multi_y1;
   // synthesis translate_off
   reg [391:0] held;
   always @(posedge clk)if(first_pixel)held<={multi_valid,multi_x0,multi_y0,multi_x1,multi_y1};
   else if(rst_n && in_de && armed && {multi_valid,multi_x0,multi_y0,multi_x1,multi_y1}!==held)$fatal(1,"Detector box contract violated during active frame");
   // synthesis translate_on
  end else begin: snapshot_source
   reg [7:0] sv;reg [95:0] sx0,sy0,sx1,sy1;
   always @(posedge clk or negedge rst_n)if(!rst_n)begin sv<=0;sx0<=0;sy0<=0;sx1<=0;sy1<=0;end
   else if(first_pixel)begin sv<=multi_valid;sx0<=multi_x0;sy0<=multi_y0;sx1<=multi_x1;sy1<=multi_y1;end
   assign fv=sv;assign fx0=sx0;assign fy0=sy0;assign fx1=sx1;assign fy1=sy1;
  end
  wire [7:0] roi_hits,first_hits;
  genvar ri;
  for(ri=0;ri<8;ri=ri+1)begin: target
   assign roi_hits[ri]=fv[ri] && x>=fx0[ri*12+:12] && x<=fx1[ri*12+:12] && y>=fy0[ri*12+:12] && y<=fy1[ri*12+:12];
   // At first_pixel x=y=0, unsigned upper bounds always include zero.
   assign first_hits[ri]=multi_valid[ri] && multi_x0[ri*12+:12]==0 && multi_y0[ri*12+:12]==0;
  end
  always @(posedge clk or negedge rst_n)if(!rst_n)fm<=0;else if(first_pixel)fm<=multi_mode;
  assign keep_roi=first_pixel?(multi_mode?(|first_hits):keep_single):(fm?(|roi_hits):keep_single);
 end else begin: single_roi
  assign keep_roi=keep_single;
 end endgenerate
 // Display-only green selection with the detector's existing hue/saturation
 // and bright-white rejection rules. It never feeds back into detection.
 wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
 wire [7:0] rb_min=(r<b)?r:b,rb_max=(r>b)?r:b;
 wire [7:0] rb_diff=(r>b)?r-b:b-r;
 wire [7:0] chroma=(g>rb_min)?g-rb_min:8'd0;
 wire [7:0] both_gap=(g>rb_max)?g-rb_max:8'd0;
 wire keep_green=keep_roi && g>=r && g>=b && g>=24 &&
                 ({1'b0,rb_diff,1'b0}<={2'b0,chroma}) &&
                 chroma>=12 && chroma>=(g>>2) && (g<248 || both_gap>=(g>>2));
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
 reg [30:0] video_ram[0:DEPTH-1];
 reg [PW-1:0] write_ptr,read_ptr;
 reg [FW-1:0] filled;
 reg video_ready;
 reg [30:0] video_q;
 always @(posedge clk)if(rst_n)begin
  video_ram[write_ptr]<={MODEL_STYLE_ENABLE && keep_green,in_vs,in_hs,in_de,in_protect,keep_roi,use_enable,in_rgb};
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
 wire [30:0] q=video_ready?video_q:31'd0;

 // One partial vertical sum per tile column; RAMs have synchronous reads and
 // no reset. Every tile is initialized on its first row before it is consumed.
 reg [SUM_W-1:0] column_sum[0:COLS-1];
 reg [7:0] above_gray[0:COLS-1];
 reg [10:0] background_row[0:COLS-1];
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
 // Sixteen light-gray surfaces, 96..246, retain scene structure even when
 // camera exposure is low. Contours darken only a two-pixel tile boundary;
 // unlike the legacy style, a whole edge tile is never painted black.
 wire [7:0] model_levels=8'd96+{1'b0,mean_gray[7:4],3'b0}+{3'b0,mean_gray[7:4],1'b0};
 // Smooth low-contrast tile noise without averaging across strong boundaries.
 wire [7:0] smooth_left=(col!=0 && dx<=12)?left_gray:mean_gray;
 wire [7:0] smooth_above=(y>=B && dy<=12)?above_q:mean_gray;
 wire [9:0] surface_sum={1'b0,mean_gray,1'b0}+{2'b0,smooth_left}+{2'b0,smooth_above};
 wire [7:0] smooth_surface=surface_sum[9:2];
 wire [7:0] clean_levels=8'd96+{1'b0,smooth_surface[7:1]};
 wire [1:0] model_edges=MODEL_STYLE_ENABLE?{dy>=MODEL_EDGE_THRESHOLD,dx>=MODEL_EDGE_THRESHOLD}:2'd0;
 wire [7:0] styled_gray=MODEL_STYLE_ENABLE?(CLEAN_STYLE_ENABLE?clean_levels:model_levels):((gradient>=EDGE_THRESHOLD)?8'd0:levels);
 always @(posedge clk)if(rst_n && in_de && armed && x<IMG_W && y<IMG_H)begin
  if(x[BLOCK_LOG2-1:0]==B-3)begin
   sum_q<=column_sum[col];above_q<=above_gray[col];
  end
  if(x[BLOCK_LOG2-1:0]==B-1)begin
   column_sum[col]<=block_sum;
   if(y[BLOCK_LOG2-1:0]==B-1)begin
    above_gray[col]<=mean_gray;
    if(!MOTION_ENABLE)background_row[col]<={model_edges,1'b0,styled_gray};
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

 // Full 16x16 mean frame difference reuses the existing 8x8 means and
 // above-row RAM. Only one luminance byte plus hysteresis per coarse cell.
 // The displayed mask/statistic both describe the preceding completed frame.
 localparam integer ROWS=IMG_H>>BLOCK_LOG2,MCOLS=COLS/2,MROWS=ROWS/2,CELLS=MCOLS*MROWS;
 localparam integer MAW=(CELLS<2)?1:$clog2(CELLS);
 wire tile_done=in_de && armed && x[BLOCK_LOG2-1:0]==B-1 && y[BLOCK_LOG2-1:0]==B-1;
 wire coarse_bottom=y[BLOCK_LOG2];
 wire coarse_done=tile_done && coarse_bottom && col[0];
 reg [8:0] left_vertical;
 wire [8:0] vertical_pair={1'b0,mean_gray}+{1'b0,above_q};
 wire [9:0] coarse_sum={1'b0,vertical_pair}+{1'b0,left_vertical};
 wire [7:0] coarse_mean=coarse_sum[9:2];
 always @(posedge clk or negedge rst_n)
  if(!rst_n)left_vertical<=0;
  else if(tile_done && coarse_bottom && !col[0])left_vertical<=vertical_pair;
 wire [15:0] completed_motion_count;
 generate if(MOTION_ENABLE)begin: motion
  reg [15:0] complete_count;
  assign completed_motion_count=complete_count;
  reg [8:0] previous_mean[0:CELLS-1];
  reg [8:0] history_q,past;
  reg [MAW-1:0] row_base,pending_addr;
  reg [CW-1:0] pending_col;
  reg [7:0] sample_mean,sample_gray;
  reg [1:0] sample_edges;
  reg pending,pending_coarse,pending_enabled,pending_history_valid,pending_last,pending_global;
  reg history_valid,frame_complete,frame_global;
  reg [15:0] active_count;
  localparam integer AGE_W=$clog2(FRAME_TIMEOUT_CYCLES+1);
  reg [AGE_W-1:0] frame_age;
  wire [MAW-1:0] address=row_base+(col>>1);
  wire [7:0] magnitude=(sample_mean>=past[7:0])?sample_mean-past[7:0]:past[7:0]-sample_mean;
  wire detected=pending_enabled && pending_history_valid &&
                (magnitude>=MOTION_HIGH || (past[8] && magnitude>=MOTION_LOW));
  always @(posedge clk)if(rst_n)begin
   if(in_de && armed && x[BLOCK_LOG2-1:0]==B-3)history_q<=previous_mean[address];
   if(pending)begin
    if(pending_enabled && pending_coarse)previous_mean[pending_addr]<={detected,sample_mean};
    background_row[pending_col]<={sample_edges,pending_enabled && pending_history_valid && past[8] && !pending_global,sample_gray};
   end
  end
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    row_base<=0;pending<=0;pending_coarse<=0;pending_addr<=0;pending_col<=0;
    sample_mean<=0;sample_gray<=0;sample_edges<=0;past<=0;pending_enabled<=0;
    pending_history_valid<=0;pending_last<=0;pending_global<=0;
    history_valid<=0;frame_complete<=0;frame_global<=0;active_count<=0;complete_count<=0;frame_age<=0;
   end else begin
    pending<=tile_done;
    if(frame_age<FRAME_TIMEOUT_CYCLES)frame_age<=frame_age+1'b1;
    if(frame_age==FRAME_TIMEOUT_CYCLES-1)begin history_valid<=0;complete_count<=0;frame_complete<=0;frame_global<=0;end
    if(in_vs && !vs_d)begin
     row_base<=0;frame_complete<=0;
     if(!frame_complete)begin history_valid<=0;complete_count<=0;end
    end
    else if(in_de && armed && x==IMG_W-1 && y[BLOCK_LOG2:0]==2*B-1)
     row_base<=(y==IMG_H-1)?0:row_base+MCOLS;
    if(first_pixel)begin
     active_count<=0;frame_complete<=0;frame_global<=completed_motion_count>=(CELLS+2)/3;frame_age<=0;
     if(!in_enable)begin history_valid<=0;complete_count<=0;end
    end
    if(tile_done)begin
     sample_mean<=coarse_mean;sample_gray<=styled_gray;sample_edges<=model_edges;past<=history_q;pending_coarse<=coarse_done;
     pending_addr<=address;pending_col<=col;pending_enabled<=use_enable;
     pending_history_valid<=history_valid;pending_global<=frame_global;
     pending_last<=x==IMG_W-1 && y==IMG_H-1;
    end
    if(pending && pending_coarse)begin
     active_count<=active_count+detected;
     if(pending_last)begin
      complete_count<=pending_enabled?(active_count+detected):16'd0;
      frame_complete<=1;history_valid<=pending_enabled;
     end
    end
   end
  end
 end else begin: no_motion
  assign completed_motion_count=16'd0;
 end endgenerate

 // Raster reconstructed on the delayed stream. Fetch each tile only at its
 // first pixel, before the next input tile-row overwrites the shared row RAM.
 reg q_vs_d,q_armed;
 reg [11:0] qx,qy;
 reg [10:0] background_q;
 reg [11:0] v1_x,v1_y;
 wire status_hit;wire [23:0] status_rgb;
 generate if(STATUS_ENABLE)begin: status
  style_status_osd #(.IMG_W(IMG_W),.CELLS(CELLS)) hud(
   .clk(clk),.rst_n(rst_n),.frame_start(q[27] && q_armed && qx==0 && qy==0),
   .style(q[24]),.motion_count(completed_motion_count),.x(v1_x),.y(v1_y),
   .hit(status_hit),.rgb(status_rgb));
 end else begin: no_status
  assign status_hit=1'b0;assign status_rgb=24'd0;
 end endgenerate
 reg [30:0] v1;
 wire edge_x=background_q[9],edge_y=background_q[10];
 wire contour_core=(edge_x && v1_x[BLOCK_LOG2-1:0]==0) || (edge_y && v1_y[BLOCK_LOG2-1:0]==0);
 wire contour_soft=(edge_x && v1_x[BLOCK_LOG2-1:0]==1) || (edge_y && v1_y[BLOCK_LOG2-1:0]==1);
 wire [7:0] model_gray=background_q[7:0]-(contour_core?(CLEAN_STYLE_ENABLE?8'd24:8'd40):(contour_soft?(CLEAN_STYLE_ENABLE?8'd12:8'd20):8'd0));
 reg stage_vs,stage_hs,stage_de,stage_protect,stage_roi,stage_enable;
 reg [23:0] stage_rgb,stage_raw;reg [7:0] stage_background;
 generate if(CLEAN_STYLE_ENABLE)begin: clean_output
  style_target_clean clean(
   .clk(clk),.rst_n(rst_n),.in_vs(stage_vs),.in_hs(stage_hs),.in_de(stage_de),
   .in_protect(stage_protect),.in_roi(stage_roi),.in_enable(stage_enable),
   .in_rgb(stage_rgb),.in_raw(stage_raw),.in_background(stage_background),
   .out_vs(out_vs),.out_hs(out_hs),.out_de(out_de),.out_protect(out_protect),
   .out_roi(out_roi),.out_enable(out_enable),.out_rgb(out_rgb));
 end else begin: original_output
  assign {out_vs,out_hs,out_de,out_protect,out_roi,out_enable,out_rgb}=
         {stage_vs,stage_hs,stage_de,stage_protect,stage_roi,stage_enable,stage_rgb};
 end endgenerate
 wire visible_status=status_hit && !v1[26] && !v1[25];
 always @(posedge clk)if(rst_n && q[27] && q_armed && qx[BLOCK_LOG2-1:0]==0)
  background_q<=background_row[qx>>BLOCK_LOG2];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   q_vs_d<=0;q_armed<=0;qx<=0;qy<=0;v1<=0;v1_x<=0;v1_y<=0;
   stage_vs<=0;stage_hs<=0;stage_de<=0;stage_protect<=0;stage_rgb<=0;stage_roi<=0;stage_enable<=0;stage_raw<=0;stage_background<=0;
  end else begin
   q_vs_d<=q[29];
   if(q[29] && !q_vs_d)begin q_armed<=1;qx<=0;qy<=0;end
   else if(q[27] && q_armed)begin
    if(qx==IMG_W-1)begin qx<=0;qy<=(qy==IMG_H-1)?12'd0:qy+1'b1;end
    else qx<=qx+1'b1;
   end
   v1<=q;v1_x<=qx;v1_y<=qy;
   stage_vs<=v1[29];stage_hs<=v1[28];stage_de<=v1[27];stage_protect<=v1[26] || (v1[27] && visible_status);stage_roi<=v1[27] && v1[25];stage_enable<=v1[24];
   stage_raw<=v1[23:0];stage_background<=model_gray;
   if(!v1[27])stage_rgb<=0;
   else if(v1[26] || v1[25])stage_rgb<=v1[23:0];
   else if(visible_status)stage_rgb<=status_rgb;
   else if(!v1[24])stage_rgb<=v1[23:0];
   else if(MODEL_STYLE_ENABLE)stage_rgb<={model_gray,model_gray,model_gray};
   else if(background_q[8])stage_rgb<=(background_q[7:0]==0)?24'h30c8d8:
       {1'b0,background_q[7:1],background_q[7:0],background_q[7:0]};
   else stage_rgb<={background_q[7:0],background_q[7:0],background_q[7:0]};
  end
 end
 // synthesis translate_off
 initial begin
  if((MOTION_ENABLE && (LINE_TOTAL-IMG_W<4 || IMG_W%(2*B)!=0 || IMG_H%(2*B)!=0 || CELLS>65535 || MOTION_LOW>MOTION_HIGH)) || BLOCK_LOG2<2 || IMG_W%B!=0 || IMG_H%B!=0 || LINE_TOTAL<=IMG_W)
   $fatal(1,"Unsupported stylizer geometry (B>=4, whole tiles, positive blanking required)");
 end
 // synthesis translate_on
endmodule

// Five-pixel horizontal median for target rendering only. The center sample
// and all metadata are delayed together by six clocks. No line/frame RAM.
// Protected overlays never enter a median window; normal-mode RGB is exact.
module style_target_clean(input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,in_roi,in_enable,
 input wire [23:0] in_rgb,in_raw,input wire [7:0] in_background,
 output reg out_vs,out_hs,out_de,out_protect,out_roi,out_enable,output reg [23:0] out_rgb);
 // [61:56] VS HS DE protect ROI enable; [55:32] display, [31:8] raw, [7:0] gray.
 wire [61:0] current={in_vs,in_hs,in_de,in_protect,in_roi,in_enable,in_rgb,in_raw,in_background};
 reg [61:0] history[0:3];
 function [7:0] median3;
  input [7:0] a,b,c;
  begin
   median3=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));
  end
 endfunction
 wire window_ok=current[59] && history[0][59] && history[1][59] && history[2][59] && history[3][59] &&
                !current[58] && !history[0][58] && !history[1][58] && !history[2][58] && !history[3][58];
 reg [7:0] low_ab[0:2],high_ab[0:2],low_cd[0:2],high_cd[0:2],fifth_a[0:2];
 reg [7:0] middle_lo[0:2],middle_hi[0:2],fifth_b[0:2];
 reg [61:0] meta_a,meta_b,center;
 reg filter_a,filter_b;reg [23:0] filtered;
 wire [7:0] r=filtered[23:16],g=filtered[15:8],b=filtered[7:0];
 wire [7:0] lo=(r<b)?r:b,hi=(r>b)?r:b;
 wire [7:0] chroma=(g>lo)?g-lo:8'd0,delta=hi-lo;
 wire [8:0] required_green={1'b0,hi}+9'd2;
 // Rendering inside a tracked green object also keeps olive/dark faces.
 // Detection remains strict upstream; do not turn its narrow hue test into
 // pixel-sized holes in a dim surface. Neutral/white/red/blue still fail.
 wire green=g>=8 && {1'b0,g}>=required_green && chroma>=6 && chroma>=(g>>2) &&
            (g<248 || ({1'b0,g}-{1'b0,hi})>=(g>>2));
 integer i,ch;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   for(i=0;i<4;i=i+1)history[i]<=0;
   for(ch=0;ch<3;ch=ch+1)begin
    low_ab[ch]<=0;high_ab[ch]<=0;low_cd[ch]<=0;high_cd[ch]<=0;fifth_a[ch]<=0;
    middle_lo[ch]<=0;middle_hi[ch]<=0;fifth_b[ch]<=0;
   end
   meta_a<=0;meta_b<=0;center<=0;filter_a<=0;filter_b<=0;filtered<=0;
   out_vs<=0;out_hs<=0;out_de<=0;out_protect<=0;out_roi<=0;out_enable<=0;out_rgb<=0;
  end else begin
   history[0]<=current;for(i=1;i<4;i=i+1)history[i]<=history[i-1];
   meta_a<=history[1];meta_b<=meta_a;center<=meta_b;
   filter_a<=window_ok;filter_b<=filter_a;
   // median5(a,b,c,d,e) = median3(min(max(a,b),max(c,d)),
   // max(min(a,b),min(c,d)),e). Split comparisons across registers.
   for(ch=0;ch<3;ch=ch+1)begin
    low_ab[ch]<=(history[3][8+ch*8+:8]<history[2][8+ch*8+:8])?history[3][8+ch*8+:8]:history[2][8+ch*8+:8];
    high_ab[ch]<=(history[3][8+ch*8+:8]>history[2][8+ch*8+:8])?history[3][8+ch*8+:8]:history[2][8+ch*8+:8];
    low_cd[ch]<=(history[1][8+ch*8+:8]<history[0][8+ch*8+:8])?history[1][8+ch*8+:8]:history[0][8+ch*8+:8];
    high_cd[ch]<=(history[1][8+ch*8+:8]>history[0][8+ch*8+:8])?history[1][8+ch*8+:8]:history[0][8+ch*8+:8];
    fifth_a[ch]<=current[8+ch*8+:8];
    middle_lo[ch]<=(high_ab[ch]<high_cd[ch])?high_ab[ch]:high_cd[ch];
    middle_hi[ch]<=(low_ab[ch]>low_cd[ch])?low_ab[ch]:low_cd[ch];
    fifth_b[ch]<=fifth_a[ch];
    filtered[ch*8+:8]<=filter_b?median3(middle_lo[ch],middle_hi[ch],fifth_b[ch]):meta_b[8+ch*8+:8];
   end
   {out_vs,out_hs,out_de,out_protect,out_roi,out_enable}<=center[61:56];
   if(!center[59])out_rgb<=0;
   else if(center[58] || !center[56])out_rgb<=center[55:32];
   // The complete selected rectangle is the normal camera image. Never
   // threshold or median-filter its pixels; only its exterior is stylized.
   else if(center[57])out_rgb<=center[31:8];
   else out_rgb<={center[7:0],center[7:0],center[7:0]};
  end
 end
endmodule

// Compact frame-stable algorithm/activity HUD. Counts describe the preceding
// completed frame, in tiles, not independent objects or pixels per second.
module style_status_osd #(
 parameter integer IMG_W=1280,CELLS=14400,
 parameter integer HUD_X=(IMG_W>=288)?IMG_W-272:0,HUD_Y=16
)(input wire clk,rst_n,frame_start,style,input wire [15:0] motion_count,
 input wire [11:0] x,y,output wire hit,output wire [23:0] rgb);
 reg mode,global_scene;
 reg [15:0] binary;
 reg [19:0] bcd,digits;
 reg [4:0] remaining;
 function [19:0] adjust;
  input [19:0] v;integer n;reg [19:0] a;
  begin a=v;for(n=0;n<5;n=n+1)if(v[n*4+:4]>=5)a[n*4+:4]=v[n*4+:4]+4'd3;adjust=a;end
 endfunction
 wire [19:0] next_bcd=(adjust(bcd)<<1)|{19'd0,binary[15]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mode<=0;global_scene<=0;binary<=0;bcd<=0;digits<=0;remaining<=0;end
  else if(frame_start)begin
   mode<=style;global_scene<=motion_count>=(CELLS+2)/3;
   binary<=motion_count;bcd<=0;remaining<=16;
  end else if(remaining!=0)begin
   binary<=binary<<1;bcd<=next_bcd;remaining<=remaining-1'b1;
   if(remaining==1)digits<=next_bcd;
  end
 end
 wire [11:0] lx=x-HUD_X,ly=y-HUD_Y;
 wire [3:0] index=lx[7:4];
 reg [7:0] ch;
 always @*begin
  ch=" ";
  if(!ly[4])begin
   case(index)
    0:ch="M";1:ch="O";2:ch="D";3:ch="E";4:ch=":";
    5:ch=mode?"S":"C";6:ch=mode?"T":"O";7:ch="L";
    8:ch=mode?"L":"O";9:ch=mode?"E":"R";
    default:ch=" ";
   endcase
   if(mode && index==7)ch="Y";
  end else begin
   case(index)
    0:ch="M";1:ch="O";2:ch="T";3:ch=":";
    4:ch=mode?{4'h3,digits[19:16]}:"-";
    5:ch=mode?{4'h3,digits[15:12]}:"-";
    6:ch=mode?{4'h3,digits[11:8]}:"-";
    7:ch=mode?{4'h3,digits[7:4]}:"-";
    8:ch=mode?{4'h3,digits[3:0]}:"-";
    10:ch=mode?(global_scene?"G":"L"):" ";
    11:ch=mode?(global_scene?"L":"O"):" ";
    12:ch=mode?(global_scene?"O":"C"):" ";
    13:ch=mode?(global_scene?"B":"A"):" ";
    14:ch=mode?(global_scene?"A":"L"):" ";
    15:ch=mode && global_scene?"L":" ";
    default:ch=" ";
   endcase
  end
 end
 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "G":glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
   "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
   "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
   "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   "Y":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
   "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
   default:glyph=35'd0;
  endcase end
 endfunction
 wire [34:0] bitmap=glyph(ch);
 reg [4:0] row;
 always @*case(ly[3:1])
  0:row=bitmap[34:30];1:row=bitmap[29:25];2:row=bitmap[24:20];3:row=bitmap[19:15];
  4:row=bitmap[14:10];5:row=bitmap[9:5];6:row=bitmap[4:0];default:row=0;
 endcase
 wire ink=(lx[3:1]<5) && row[4-lx[3:1]];
 assign hit=x>=HUD_X && x<HUD_X+256 && y>=HUD_Y && y<HUD_Y+32;
 assign rgb=ink?(mode?24'h30e8ff:24'hfff200):24'h080c10;
endmodule

// Display-only style mode; aligned out_enable follows the same video RAM metadata. The detector/DDR/ISP never consume this output.
// Same-frame BxB mean luminance + 8-level posterization + coarse gradients.
// Full-color ROI and protected overlays are delayed bit-for-bit with the raster.
// Each input line MUST contain LINE_TOTAL clocks and IMG_W active pixels.
// IMG_W and IMG_H must be multiples of B=2**BLOCK_LOG2 (default 8).
// Runtime enable and validated bbox are latched at the first active pixel.
// Latency: B*LINE_TOTAL + 2 clocks. No full-frame history and no multipliers.
module roi_background_stylize_baseline #(
 parameter integer IMG_W=1280,IMG_H=720,LINE_TOTAL=1650,
 parameter integer BLOCK_LOG2=3,EDGE_THRESHOLD=40,
 parameter integer MOTION_ENABLE=0,STATUS_ENABLE=0,MOTION_HIGH=12,MOTION_LOW=6,
 parameter integer FRAME_TIMEOUT_CYCLES=18750000
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
 reg [8:0] background_row[0:COLS-1];
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
    above_gray[col]<=mean_gray;
    if(!MOTION_ENABLE)background_row[col]<={1'b0,styled_gray};
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
    background_row[pending_col]<={pending_enabled && pending_history_valid && past[8] && !pending_global,sample_gray};
   end
  end
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    row_base<=0;pending<=0;pending_coarse<=0;pending_addr<=0;pending_col<=0;
    sample_mean<=0;sample_gray<=0;past<=0;pending_enabled<=0;
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
     sample_mean<=coarse_mean;sample_gray<=styled_gray;past<=history_q;pending_coarse<=coarse_done;
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
 reg [8:0] background_q;
 reg [11:0] v1_x,v1_y;
 wire status_hit;wire [23:0] status_rgb;
 generate if(STATUS_ENABLE)begin: status
  style_status_osd_baseline #(.IMG_W(IMG_W),.CELLS(CELLS)) hud(
   .clk(clk),.rst_n(rst_n),.frame_start(q[27] && q_armed && qx==0 && qy==0),
   .style(q[24]),.motion_count(completed_motion_count),.x(v1_x),.y(v1_y),
   .hit(status_hit),.rgb(status_rgb));
 end else begin: no_status
  assign status_hit=1'b0;assign status_rgb=24'd0;
 end endgenerate
 reg [29:0] v1;
 wire visible_status=status_hit && !v1[26] && !v1[25];
 always @(posedge clk)if(rst_n && q[27] && q_armed && qx[BLOCK_LOG2-1:0]==0)
  background_q<=background_row[qx>>BLOCK_LOG2];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   q_vs_d<=0;q_armed<=0;qx<=0;qy<=0;v1<=0;v1_x<=0;v1_y<=0;
   out_vs<=0;out_hs<=0;out_de<=0;out_protect<=0;out_rgb<=0;out_roi<=0;out_enable<=0;
  end else begin
   q_vs_d<=q[29];
   if(q[29] && !q_vs_d)begin q_armed<=1;qx<=0;qy<=0;end
   else if(q[27] && q_armed)begin
    if(qx==IMG_W-1)begin qx<=0;qy<=(qy==IMG_H-1)?12'd0:qy+1'b1;end
    else qx<=qx+1'b1;
   end
   v1<=q;v1_x<=qx;v1_y<=qy;
   out_vs<=v1[29];out_hs<=v1[28];out_de<=v1[27];out_protect<=v1[26] || (v1[27] && visible_status);out_roi<=v1[27] && v1[25];out_enable<=v1[24];
   if(!v1[27])out_rgb<=0;
   else if(v1[26] || v1[25])out_rgb<=v1[23:0];
   else if(visible_status)out_rgb<=status_rgb;
   else if(!v1[24])out_rgb<=v1[23:0];
   else if(background_q[8])out_rgb<=(background_q[7:0]==0)?24'h30c8d8:
       {1'b0,background_q[7:1],background_q[7:0],background_q[7:0]};
   else out_rgb<={background_q[7:0],background_q[7:0],background_q[7:0]};
  end
 end
 // synthesis translate_off
 initial begin
  if((MOTION_ENABLE && (LINE_TOTAL-IMG_W<4 || IMG_W%(2*B)!=0 || IMG_H%(2*B)!=0 || CELLS>65535 || MOTION_LOW>MOTION_HIGH)) || BLOCK_LOG2<2 || IMG_W%B!=0 || IMG_H%B!=0 || LINE_TOTAL<=IMG_W)
   $fatal(1,"Unsupported stylizer geometry (B>=4, whole tiles, positive blanking required)");
 end
 // synthesis translate_on
endmodule

// Compact frame-stable algorithm/activity HUD. Counts describe the preceding
// completed frame, in tiles, not independent objects or pixels per second.
module style_status_osd_baseline #(
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

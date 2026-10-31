// Recent target-center polyline. Entirely display-only; no camera/ROI feedback.
// History stores millisecond timestamps, not an assumed number of video frames.
// Rebuild an inactive 1-bit quarter-resolution bitmap; publish only at VS.
// RGB/VS/HS/DE/protect/ROI share the bitmap-prefetch and output register stages.
module roi_motion_trail #(
 parameter integer IMG_W=1280,IMG_H=720,SCALE_LOG2=2,HISTORY_DEPTH=256,
 parameter integer TTL_MS=1000,MAX_LINK_GAP_MS=150,MAX_JUMP_PIXELS=320,FRAME_TIMEOUT_MS=250,
 parameter integer MULTI_ENABLE=0,SMOOTH_ENABLE=0,SAMPLE_INTERVAL_MS=0,JITTER_PIXELS=4,
 parameter [23:0] TRAIL_RGB=24'hff8800
)(
 input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,in_roi,in_enable,in_clear,
 input wire [23:0] in_rgb,
 input wire [15:0] ms_now,
 input wire point_valid,
 input wire [15:0] point_x,point_y,
 output reg out_vs,out_hs,out_de,out_protect,out_hit,
 output reg [23:0] out_rgb,
 output wire render_busy,output wire [8:0] point_count,output wire bank_valid,
 input wire multi_mode,input wire [7:0] multi_valid,
 input wire [95:0] multi_x0,multi_y0,multi_x1,multi_y1
);
 localparam integer GW=(IMG_W+(1<<SCALE_LOG2)-1)>>SCALE_LOG2;
 localparam integer GH=(IMG_H+(1<<SCALE_LOG2)-1)>>SCALE_LOG2;
 localparam integer CELLS=GW*GH,AW=(CELLS<2)?1:$clog2(CELLS);
 localparam integer HW=$clog2(HISTORY_DEPTH);
 localparam [2:0] IDLE=0,CLEAR=1,REQ=2,USE=3,DRAW=4,ADV=5;
 reg [2:0] state;
 reg front_bank,front_valid,ready;
 reg vs_d,armed,frame_enable;
 reg [11:0] rx,ry;
 reg [AW-1:0] raster_row;
 wire sof=in_de && armed && rx==0 && ry==0;
 wire vs_start=in_vs && !vs_d;
 reg stream_seen;
 reg [15:0] last_frame_ms;
 wire [15:0] frame_gap=ms_now-last_frame_ms;
 wire video_timeout=(FRAME_TIMEOUT_MS!=0) && stream_seen && frame_gap>=FRAME_TIMEOUT_MS;
 wire clear_frame=sof && (!in_enable || in_clear);
 reg multi_frame;
 wire use_multi=MULTI_ENABLE && (sof?multi_mode:multi_frame);
 wire mode_change=MULTI_ENABLE && sof && multi_mode!=multi_frame;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)multi_frame<=0;else if(sof)multi_frame<=MULTI_ENABLE && multi_mode;
 wire clear_event=clear_frame || video_timeout || mode_change;
 // Rebuild/expire at every frame; storage samples have an independent cadence.
 wire rebuild_frame=sof && in_enable && !in_clear && !video_timeout && !mode_change;
 wire mode=sof?in_enable:frame_enable;
 wire point_ok=point_valid && point_x<IMG_W && point_y<IMG_H;
 wire [15:0] plot_x,plot_y;
 generate if(SMOOTH_ENABLE)begin: smooth_path
  roi_trail_point_filter #(.IMG_W(IMG_W),.IMG_H(IMG_H),.JITTER_PIXELS(JITTER_PIXELS),
   .MAX_JUMP_PIXELS(MAX_JUMP_PIXELS),.MAX_LINK_GAP_MS(MAX_LINK_GAP_MS)) point_filter(
   .clk(clk),.rst_n(rst_n),.update(rebuild_frame),.clear(clear_event),
   .ms_now(ms_now),.point_valid(point_ok),.point_x(point_x),.point_y(point_y),
   .filtered_x(plot_x),.filtered_y(plot_y));
 end else begin: direct_path
  assign plot_x=point_x;assign plot_y=point_y;
 end endgenerate
 reg previous_valid;
 reg sample_started;
 reg [15:0] next_sample_ms;
 wire [15:0] due_age=ms_now-next_sample_ms;
 wire sample_due=(SAMPLE_INTERVAL_MS==0) || !sample_started || !due_age[15];
 // Always record loss, so decimation cannot reconnect across a missing target.
 wire single_record=rebuild_frame && !use_multi && (!point_ok || !previous_valid || sample_due);
 wire multi_record,multi_done;wire [39:0] multi_entry;
 reg multi_start;
 // Clear old-mode history at SOF, then sample the new mode one clock later.
 // Entering multi+style therefore does not discard its first frame of points.
 always @(posedge clk or negedge rst_n)
  if(!rst_n)multi_start<=0;
  else multi_start<=MULTI_ENABLE && sof && use_multi && in_enable && !in_clear && !video_timeout;
 generate if(MULTI_ENABLE)begin: multi_samples
  roi_multi_trail_samples #(.IMG_W(IMG_W),.IMG_H(IMG_H),.SCALE_LOG2(SCALE_LOG2),
   .SAMPLE_INTERVAL_MS(SAMPLE_INTERVAL_MS),.JITTER_PIXELS(JITTER_PIXELS),
   .MAX_LINK_GAP_MS(MAX_LINK_GAP_MS),.MAX_JUMP_PIXELS(MAX_JUMP_PIXELS)) samples(
   .clk(clk),.rst_n(rst_n),.start(multi_start),.clear(clear_event),
   .ms_now(ms_now),.valid(multi_valid),.x0(multi_x0),.y0(multi_y0),.x1(multi_x1),.y1(multi_y1),
   .record(multi_record),.entry(multi_entry),.done(multi_done));
 end else begin: no_multi_samples
  assign multi_record=0;assign multi_done=0;assign multi_entry=0;
 end endgenerate
 wire record=single_record || multi_record;
 wire render_start=use_multi?multi_done:rebuild_frame;
 wire [8:0] gx=plot_x>>SCALE_LOG2;
 wire [7:0] gy=plot_y>>SCALE_LOG2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sample_started<=0;next_sample_ms<=0;end
  else if(clear_event)begin sample_started<=0;next_sample_ms<=0;end
  else if(single_record)begin
   sample_started<=point_ok;
   if(!point_ok || !sample_started || !previous_valid || due_age>=SAMPLE_INTERVAL_MS)
    next_sample_ms<=ms_now+SAMPLE_INTERVAL_MS;
   else next_sample_ms<=next_sample_ms+SAMPLE_INTERVAL_MS;
  end
 end
 reg [8:0] previous_x;
 reg [7:0] previous_y;
 reg [15:0] previous_ms;
 wire [15:0] sample_gap=ms_now-previous_ms;

 reg [39:0] history[0:HISTORY_DEPTH-1];
 reg [HW-1:0] head,scan_addr;
 reg [HW:0] count,scan_left;
 wire [HW-1:0] next_head=head+1'b1;
 wire [HW:0] next_count=(count<HISTORY_DEPTH)?count+1'b1:count;
 wire [HW-1:0] rebuild_head=record?next_head:head;
 wire [HW:0] rebuild_count=record?next_count:count;
 reg [39:0] entry_q;
 reg [15:0] build_ms;
 wire [15:0] entry_age=build_ms-entry_q[39:24];
 wire expired=entry_age>=TTL_MS;
 // Capture a sample at SOF, then validate its segment link on the next clock.
 // The bitmap CLEAR pass precedes all history reads, so this write retiming
 // preserves timestamps/publication while breaking the filter-to-ERAM path.
 reg record_pending,multi_pending;reg [39:0] multi_entry_pending;
 reg [HW-1:0] pending_addr;
 reg [15:0] pending_ms;
 reg pending_good,pending_link_base;
 reg [8:0] pending_x,pending_previous_x;
 reg [7:0] pending_y,pending_previous_y;
 wire [8:0] pending_move_x=(pending_x>=pending_previous_x)?
                         pending_x-pending_previous_x:pending_previous_x-pending_x;
 wire [7:0] pending_move_y=(pending_y>=pending_previous_y)?
                         pending_y-pending_previous_y:pending_previous_y-pending_y;
 wire pending_link=pending_link_base &&
   pending_move_x<=(MAX_JUMP_PIXELS>>SCALE_LOG2) && pending_move_y<=(MAX_JUMP_PIXELS>>SCALE_LOG2);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   record_pending<=0;multi_pending<=0;multi_entry_pending<=0;pending_addr<=0;pending_ms<=0;pending_good<=0;pending_link_base<=0;
   pending_x<=0;pending_y<=0;pending_previous_x<=0;pending_previous_y<=0;
  end else begin
   record_pending<=record && !clear_event;
   multi_pending<=multi_record;
   if(multi_record)multi_entry_pending<=multi_entry;
   if(record)begin
    pending_addr<=head;pending_ms<=ms_now;pending_good<=point_ok;
    pending_link_base<=previous_valid && point_ok && sample_gap<=MAX_LINK_GAP_MS;
    pending_x<=gx;pending_y<=gy;pending_previous_x<=previous_x;pending_previous_y<=previous_y;
   end
  end
 end
 always @(posedge clk)if(rst_n)begin
  if(record_pending && !clear_event)
   history[pending_addr]<=multi_pending?multi_entry_pending:{pending_ms,pending_good,pending_link,pending_x,pending_y,5'd0};
  else if(state==USE && entry_q[23] && expired)
   history[scan_addr]<={entry_q[39:24],1'b0,entry_q[22:0]};
  // An expired entry is permanently invalidated, so a 16-bit time wrap cannot
  // resurrect an old trace during a long period with no target.
  if(state==REQ)entry_q<=history[scan_addr];
 end

 reg mask0[0:CELLS-1];reg mask1[0:CELLS-1];
 reg bit0,bit1;
 reg [AW-1:0] clear_addr;
 reg have_previous;
 reg [7:0] multi_have_previous;
 reg [8:0] multi_last_x[0:7];reg [7:0] multi_last_y[0:7];
 wire [2:0] entry_id=entry_q[2:0];
 reg [8:0] last_x,draw_x,end_x;
 reg [7:0] last_y,draw_y,end_y;
 reg step_x_positive,step_y_positive;
 reg signed [12:0] delta_x,delta_y,error;
 wire signed [13:0] twice_error=$signed({error[12],error})<<<1;
 wire step_x=twice_error>=-$signed({delta_y[12],delta_y});
 wire step_y=twice_error<=$signed({delta_x[12],delta_x});
 wire signed [12:0] next_error=error-(step_x?delta_y:13'sd0)+(step_y?delta_x:13'sd0);
 wire [8:0] ex=entry_q[21:13];wire [7:0] ey=entry_q[12:5];
 wire connect=(use_multi?multi_have_previous[entry_id]:have_previous) && entry_q[22];
 wire [8:0] sx=connect?(use_multi?multi_last_x[entry_id]:last_x):ex;
 wire [7:0] sy=connect?(use_multi?multi_last_y[entry_id]:last_y):ey;
 wire [8:0] abs_dx=(ex>=sx)?ex-sx:sx-ex;
 wire [7:0] abs_dy=(ey>=sy)?ey-sy:sy-ey;
 // Constant shift/add, deliberately avoiding a pixel-address DSP multiplier.
 function [AW-1:0] row_address;
  input [7:0] yy;integer k;reg [AW-1:0] a,wide_y;
  begin
   a=0;wide_y=yy;
   for(k=0;k<12;k=k+1)if((GW>>k)&1)a=a+(wide_y<<k);
   row_address=a;
  end
 endfunction
 wire [AW-1:0] draw_addr=row_address(draw_y)+draw_x;
 wire [AW-1:0] read_addr=raster_row+(rx>>SCALE_LOG2);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin stream_seen<=0;last_frame_ms<=0;end
  else if(video_timeout)stream_seen<=0;
  else if(sof)begin stream_seen<=1;last_frame_ms<=ms_now;end
 end
 always @(posedge clk)if(rst_n)begin
  if(in_de && armed)begin bit0<=mask0[read_addr];bit1<=mask1[read_addr];end
  // The front bitmap is never written. Reads from an inactive bank are unused.
  if(state==CLEAR)begin
   if(front_bank)mask0[clear_addr]<=0;else mask1[clear_addr]<=0;
  end else if(state==DRAW)begin
   if(front_bank)mask0[draw_addr]<=1;else mask1[draw_addr]<=1;
  end
 end

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   vs_d<=0;armed<=0;frame_enable<=0;rx<=0;ry<=0;raster_row<=0;
  end else begin
   vs_d<=in_vs;
   if(vs_start)begin armed<=1;rx<=0;ry<=0;raster_row<=0;end
   else if(in_de && armed)begin
    if(rx==IMG_W-1)begin
     rx<=0;
     if(ry==IMG_H-1)begin ry<=0;raster_row<=0;end
     else begin
      ry<=ry+1'b1;
      if(ry[SCALE_LOG2-1:0]==(1<<SCALE_LOG2)-1)raster_row<=raster_row+GW;
     end
    end else rx<=rx+1'b1;
   end
   if(sof)frame_enable<=in_enable;
  end
 end

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;front_bank<=0;front_valid<=0;ready<=0;
   head<=0;count<=0;previous_valid<=0;previous_x<=0;previous_y<=0;previous_ms<=0;
   scan_addr<=0;scan_left<=0;build_ms<=0;clear_addr<=0;have_previous<=0;
   multi_have_previous<=0;last_x<=0;last_y<=0;draw_x<=0;draw_y<=0;end_x<=0;end_y<=0;
   step_x_positive<=0;step_y_positive<=0;delta_x<=0;delta_y<=0;error<=0;
  end else begin
   if(vs_start && ready)begin front_bank<=~front_bank;front_valid<=1;ready<=0;end
   if(clear_event)begin
    state<=IDLE;ready<=0;front_valid<=0;head<=0;count<=0;previous_valid<=0;have_previous<=0;multi_have_previous<=0;
   end else begin
    if(record)begin
     head<=next_head;count<=next_count;
     if(single_record)begin
      previous_valid<=point_ok;previous_ms<=ms_now;
      if(point_ok)begin previous_x<=gx;previous_y<=gy;end
     end
    end
    case(state)
     IDLE:if(render_start && !ready && rebuild_count!=0)begin
      build_ms<=ms_now;clear_addr<=0;have_previous<=0;multi_have_previous<=0;
      scan_addr<=rebuild_head-rebuild_count[HW-1:0];scan_left<=rebuild_count;state<=CLEAR;
     end
     CLEAR:if(clear_addr==CELLS-1)state<=REQ;else clear_addr<=clear_addr+1'b1;
     REQ:state<=USE;
     USE:if(entry_q[23] && !expired)begin
      draw_x<=sx;draw_y<=sy;end_x<=ex;end_y<=ey;
      delta_x<=$signed({4'd0,abs_dx});delta_y<=$signed({5'd0,abs_dy});
      error<=$signed({4'd0,abs_dx})-$signed({5'd0,abs_dy});
      step_x_positive<=sx<ex;step_y_positive<=sy<ey;
      last_x<=ex;last_y<=ey;have_previous<=1;
      if(MULTI_ENABLE && use_multi)begin
       multi_last_x[entry_id]<=ex;multi_last_y[entry_id]<=ey;multi_have_previous[entry_id]<=1;
      end
      state<=DRAW;
     end else begin
      have_previous<=0;if(MULTI_ENABLE && use_multi)multi_have_previous[entry_id]<=0;state<=ADV;
     end
     DRAW:if(draw_x==end_x && draw_y==end_y)state<=ADV;
      else begin
       error<=next_error;
       if(step_x)draw_x<=step_x_positive?draw_x+1'b1:draw_x-1'b1;
       if(step_y)draw_y<=step_y_positive?draw_y+1'b1:draw_y-1'b1;
      end
     ADV:if(scan_left==1)begin state<=IDLE;ready<=1;end
      else begin scan_left<=scan_left-1'b1;scan_addr<=scan_addr+1'b1;state<=REQ;end
     default:state<=IDLE;
    endcase
   end
  end
 end

 reg pvs,phs,pde,pprotect,proi,pmode,pbank,pvalid;
 reg [23:0] prgb;
 wire hit=pde && pmode && pvalid && !pprotect && !proi && (pbank?bit1:bit0);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pvs<=0;phs<=0;pde<=0;pprotect<=0;proi<=0;pmode<=0;pbank<=0;pvalid<=0;prgb<=0;
   out_vs<=0;out_hs<=0;out_de<=0;out_protect<=0;out_hit<=0;out_rgb<=0;
  end else begin
   pvs<=in_vs;phs<=in_hs;pde<=in_de;pprotect<=in_protect;proi<=in_roi;pmode<=mode;
   pbank<=front_bank;pvalid<=front_valid && !clear_event;prgb<=in_rgb;
   out_vs<=pvs;out_hs<=phs;out_de<=pde;out_protect<=pprotect || hit;out_hit<=hit;
   out_rgb<=!pde?24'd0:(hit?TRAIL_RGB:prgb);
  end
 end
 assign render_busy=(state!=IDLE);assign point_count=count;assign bank_valid=front_valid;
 // synthesis translate_off
 initial begin
  if(SCALE_LOG2<1 || GW>512 || GH>256 || HISTORY_DEPTH<2 || HISTORY_DEPTH>256 ||
     (HISTORY_DEPTH&(HISTORY_DEPTH-1))!=0 || TTL_MS<1 || TTL_MS>=32768 || SAMPLE_INTERVAL_MS<0 || SAMPLE_INTERVAL_MS>=32768)
   $fatal(1,"Unsupported trajectory geometry/history/time parameters");
 end
 // synthesis translate_on
endmodule

// Display-only trajectory conditioner. Detector coordinates/servo are untouched.
// Combinational candidate is consumed at update by both history and filter state.
module roi_trail_point_filter #(
 parameter integer IMG_W=1280,IMG_H=720,JITTER_PIXELS=4,
 parameter integer MAX_JUMP_PIXELS=320,MAX_LINK_GAP_MS=150
)(input wire clk,rst_n,update,clear,input wire [15:0] ms_now,
 input wire point_valid,input wire [15:0] point_x,point_y,
 output wire [15:0] filtered_x,filtered_y);
 reg seeded;reg [1:0] history_count;
 reg [15:0] raw_x0,raw_x1,raw_y0,raw_y1,last_ms;
 reg [17:0] smooth_x_q2,smooth_y_q2;
 wire good=point_valid && point_x<IMG_W && point_y<IMG_H;
 wire [15:0] gap=ms_now-last_ms;
 wire restart=!seeded || gap>MAX_LINK_GAP_MS;
 function [15:0] median3;
  input [15:0] a,b,c;
  begin
   if(a>b)median3=(b>c)?b:((a>c)?c:a);
   else median3=(a>c)?a:((b>c)?c:b);
  end
 endfunction
 wire [15:0] mx=(history_count!=0)?median3(point_x,raw_x0,raw_x1):point_x;
 wire [15:0] my=(history_count!=0)?median3(point_y,raw_y0,raw_y1):point_y;
 wire [18:0] round_x={1'b0,smooth_x_q2}+19'd2;
 wire [18:0] round_y={1'b0,smooth_y_q2}+19'd2;
 wire [15:0] current_x=round_x[17:2],current_y=round_y[17:2];
 wire [15:0] dx=(mx>=current_x)?mx-current_x:current_x-mx;
 wire [15:0] dy=(my>=current_y)?my-current_y:current_y-my;
 wire [18:0] average_x={1'b0,smooth_x_q2}+{1'b0,mx,2'b0}+19'd1;
 wire [18:0] average_y={1'b0,smooth_y_q2}+{1'b0,my,2'b0}+19'd1;
 wire [17:0] candidate_x=restart?{point_x,2'b0}:
  ((dx>MAX_JUMP_PIXELS)?{mx,2'b0}:((dx<=JITTER_PIXELS)?smooth_x_q2:average_x[18:1]));
 wire [17:0] candidate_y=restart?{point_y,2'b0}:
  ((dy>MAX_JUMP_PIXELS)?{my,2'b0}:((dy<=JITTER_PIXELS)?smooth_y_q2:average_y[18:1]));
 wire [18:0] result_x={1'b0,candidate_x}+19'd2,result_y={1'b0,candidate_y}+19'd2;
 assign filtered_x=result_x[17:2];assign filtered_y=result_y[17:2];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   seeded<=0;history_count<=0;raw_x0<=0;raw_x1<=0;raw_y0<=0;raw_y1<=0;
   last_ms<=0;smooth_x_q2<=0;smooth_y_q2<=0;
  end else if(clear)begin seeded<=0;history_count<=0;end
  else if(update)begin
   if(!good)begin seeded<=0;history_count<=0;end
   else begin
    seeded<=1;last_ms<=ms_now;smooth_x_q2<=candidate_x;smooth_y_q2<=candidate_y;
    raw_x0<=point_x;raw_y0<=point_y;
    raw_x1<=restart?point_x:raw_x0;raw_y1<=restart?point_y:raw_y0;
    if(restart)history_count<=1;else if(history_count<2)history_count<=history_count+1'b1;
   end
  end
 end
endmodule

module video_ms_clock #(parameter integer CLK_HZ=75000000)(
 input wire clk,rst_n,output reg [15:0] ms_now
);
 localparam integer DIV=CLK_HZ/1000,CW=(DIV<2)?1:$clog2(DIV);
 reg [CW-1:0] cycles;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cycles<=0;ms_now<=0;end
  else if(cycles==DIV-1)begin cycles<=0;ms_now<=ms_now+1'b1;end
  else cycles<=cycles+1'b1;
 end
 // synthesis translate_off
 initial if(CLK_HZ<1000 || CLK_HZ%1000!=0)$fatal(1,"Clock must be an integer number of kHz");
 // synthesis translate_on
endmodule

// Eight independently conditioned paths, time-sharing ONE arithmetic datapath.
// The existing detector's stable slot indices identify paths. No detector,
// camera, color, ROI or servo state is written by this display-only observer.
// Emit at most one 40-bit record/clock into the original 256-entry history.
// Slot ID occupies three previously unused low bits; no additional ERAM.
module roi_multi_trail_samples #(
 parameter integer IMG_W=1280,IMG_H=720,SCALE_LOG2=2,
 parameter integer SAMPLE_INTERVAL_MS=50,JITTER_PIXELS=4,
 parameter integer MAX_LINK_GAP_MS=150,MAX_JUMP_PIXELS=320
)(input wire clk,rst_n,start,clear,input wire [15:0] ms_now,
 input wire [7:0] valid,input wire [95:0] x0,y0,x1,y1,
 output reg record,output reg [39:0] entry,output reg done);
 reg busy;reg [2:0] slot;reg [1:0] phase;
 reg [15:0] batch_ms;
 reg [7:0] seeded,sampled,linked;
 // Dimensions bound these registers; arithmetic candidates use wider temporaries.
 reg [10:0] raw_x0[0:7],raw_x1[0:7];
 reg [9:0] raw_y0[0:7],raw_y1[0:7];
 reg [12:0] smooth_x[0:7];reg [11:0] smooth_y[0:7];
 reg [15:0] last_ms[0:7],sample_ms[0:7];
 reg [8:0] previous_x[0:7];reg [7:0] previous_y[0:7];

 // Stage 1: capture one slot's raw bbox and history. This breaks the long
 // 96-bit array mux path away from the median/guard arithmetic.
 reg [11:0] cap_x0,cap_x1,cap_y0,cap_y1;
 reg cap_valid,cap_good,cap_seeded,cap_sampled,cap_linked;
 reg [15:0] cap_last_ms,cap_sample_ms;
 reg [12:0] cap_smooth_x;reg [11:0] cap_smooth_y;
 reg [10:0] cap_raw_x0,cap_raw_x1;reg [9:0] cap_raw_y0,cap_raw_y1;
 reg [8:0] cap_previous_x;reg [7:0] cap_previous_y;

 // Stage 2: center/median/guard differences.
 reg [11:0] mid_px,mid_py,mid_mx,mid_my,mid_dx,mid_dy;
 reg mid_restart;

 function [11:0] median3;
  input [11:0] a,b,c;
  begin median3=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));end
 endfunction

 wire [12:0] cap_sum_x={1'b0,cap_x0}+{1'b0,cap_x1};
 wire [12:0] cap_sum_y={1'b0,cap_y0}+{1'b0,cap_y1};
 wire [11:0] cap_px=cap_sum_x[12:1],cap_py=cap_sum_y[12:1];
 wire [15:0] cap_gap=batch_ms-cap_last_ms;
 wire cap_restart=!cap_seeded || cap_gap>MAX_LINK_GAP_MS;
 wire [11:0] cap_mx=cap_restart?cap_px:median3(cap_px,{1'b0,cap_raw_x0},{1'b0,cap_raw_x1});
 wire [11:0] cap_my=cap_restart?cap_py:median3(cap_py,{2'b0,cap_raw_y0},{2'b0,cap_raw_y1});
 wire [13:0] cap_round_x={1'b0,cap_smooth_x}+14'd2;
 wire [12:0] cap_round_y={1'b0,cap_smooth_y}+13'd2;
 wire [11:0] cap_current_x={1'b0,cap_round_x[12:2]};
 wire [11:0] cap_current_y={2'b0,cap_round_y[11:2]};
 wire [11:0] cap_dx=(cap_mx>=cap_current_x)?cap_mx-cap_current_x:cap_current_x-cap_mx;
 wire [11:0] cap_dy=(cap_my>=cap_current_y)?cap_my-cap_current_y:cap_current_y-cap_my;

 wire [14:0] average_x={2'b0,cap_smooth_x}+{1'b0,mid_mx,2'b0}+15'd1;
 wire [14:0] average_y={3'b0,cap_smooth_y}+{1'b0,mid_my,2'b0}+15'd1;
 wire [13:0] candidate_x=mid_restart?{mid_px,2'b0}:
  ((mid_dx>MAX_JUMP_PIXELS)?{mid_mx,2'b0}:((mid_dx<=JITTER_PIXELS)?{1'b0,cap_smooth_x}:average_x[14:1]));
 wire [13:0] candidate_y=mid_restart?{mid_py,2'b0}:
  ((mid_dy>MAX_JUMP_PIXELS)?{mid_my,2'b0}:((mid_dy<=JITTER_PIXELS)?{2'b0,cap_smooth_y}:average_y[14:1]));
 wire [14:0] result_x={1'b0,candidate_x}+15'd2,result_y={1'b0,candidate_y}+15'd2;
 wire [8:0] gx=result_x[12:2]>>SCALE_LOG2;
 wire [7:0] gy=result_y[11:2]>>SCALE_LOG2;
 wire [8:0] move_x=gx>=cap_previous_x?gx-cap_previous_x:cap_previous_x-gx;
 wire [7:0] move_y=gy>=cap_previous_y?gy-cap_previous_y:cap_previous_y-gy;
 wire [15:0] sample_gap=batch_ms-cap_sample_ms;
 wire due=!cap_sampled || SAMPLE_INTERVAL_MS==0 || sample_gap>=SAMPLE_INTERVAL_MS;
 wire link=cap_linked && sample_gap<=MAX_LINK_GAP_MS &&
  move_x<=(MAX_JUMP_PIXELS>>SCALE_LOG2) && move_y<=(MAX_JUMP_PIXELS>>SCALE_LOG2);
 wire final_record=cap_good && due && !clear;

 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;slot<=0;phase<=0;done<=0;batch_ms<=0;seeded<=0;sampled<=0;linked<=0;
   record<=0;entry<=0;
   cap_x0<=0;cap_x1<=0;cap_y0<=0;cap_y1<=0;cap_valid<=0;cap_good<=0;
   cap_seeded<=0;cap_sampled<=0;cap_linked<=0;cap_last_ms<=0;cap_sample_ms<=0;
   cap_smooth_x<=0;cap_smooth_y<=0;cap_raw_x0<=0;cap_raw_x1<=0;
   cap_raw_y0<=0;cap_raw_y1<=0;cap_previous_x<=0;cap_previous_y<=0;
   mid_px<=0;mid_py<=0;mid_mx<=0;mid_my<=0;mid_dx<=0;mid_dy<=0;mid_restart<=0;
   for(i=0;i<8;i=i+1)begin
    raw_x0[i]<=0;raw_x1[i]<=0;raw_y0[i]<=0;raw_y1[i]<=0;
    smooth_x[i]<=0;smooth_y[i]<=0;last_ms[i]<=0;sample_ms[i]<=0;
    previous_x[i]<=0;previous_y[i]<=0;
   end
  end else begin
   done<=0;record<=0;
   if(clear)begin busy<=0;phase<=0;seeded<=0;sampled<=0;linked<=0;end
   else if(start)begin busy<=1;slot<=0;phase<=0;batch_ms<=ms_now;end
   else if(busy)begin
    case(phase)
     2'd0:begin
      cap_x0<=x0[slot*12+:12];cap_x1<=x1[slot*12+:12];
      cap_y0<=y0[slot*12+:12];cap_y1<=y1[slot*12+:12];
      cap_valid<=valid[slot];
      cap_good<=valid[slot] && x0[slot*12+:12]<=x1[slot*12+:12] &&
       y0[slot*12+:12]<=y1[slot*12+:12] && x1[slot*12+:12]<IMG_W && y1[slot*12+:12]<IMG_H;
      cap_seeded<=seeded[slot];cap_sampled<=sampled[slot];cap_linked<=linked[slot];
      cap_last_ms<=last_ms[slot];cap_sample_ms<=sample_ms[slot];
      cap_smooth_x<=smooth_x[slot];cap_smooth_y<=smooth_y[slot];
      cap_raw_x0<=raw_x0[slot];cap_raw_x1<=raw_x1[slot];
      cap_raw_y0<=raw_y0[slot];cap_raw_y1<=raw_y1[slot];
      cap_previous_x<=previous_x[slot];cap_previous_y<=previous_y[slot];
      phase<=1;
     end
     2'd1:begin
      mid_px<=cap_px;mid_py<=cap_py;
      mid_restart<=cap_restart;
      mid_mx<=cap_mx;mid_my<=cap_my;
      mid_dx<=cap_dx;mid_dy<=cap_dy;
      phase<=2;
     end
     default:begin
      if(!cap_good)begin
       seeded[slot]<=0;linked[slot]<=0;
      end else begin
       seeded[slot]<=1;last_ms[slot]<=batch_ms;
       smooth_x[slot]<=candidate_x[12:0];smooth_y[slot]<=candidate_y[11:0];
       raw_x0[slot]<=mid_px[10:0];raw_y0[slot]<=mid_py[9:0];
       raw_x1[slot]<=mid_restart?mid_px[10:0]:cap_raw_x0;
       raw_y1[slot]<=mid_restart?mid_py[9:0]:cap_raw_y0;
       if(final_record)begin
        sampled[slot]<=1;sample_ms[slot]<=batch_ms;linked[slot]<=1;
        previous_x[slot]<=gx;previous_y[slot]<=gy;
       end
      end
      if(final_record)begin
       record<=1;
       entry<={batch_ms,1'b1,link,gx,gy,2'd0,slot};
      end
      if(slot==7)begin busy<=0;done<=1;end
      else begin slot<=slot+1'b1;phase<=0;end
     end
    endcase
   end
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(rst_n && start && busy)$fatal(1,"Overlapping multi-trail batches");
 initial if(IMG_W>2048 || IMG_H>1024)$fatal(1,"Multi-trail coordinate widths exceeded");
 // synthesis translate_on
endmodule

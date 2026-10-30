from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'user_source/hdl_source/video/roi_motion_trail.v'
s=p.read_text(encoding='utf-8-sig')
assert 'MULTI_ENABLE' not in s
s=s.replace('parameter integer SMOOTH_ENABLE=0,','parameter integer MULTI_ENABLE=0,SMOOTH_ENABLE=0,')
s=s.replace('output wire render_busy,output wire [8:0] point_count,output wire bank_valid\n',
'''output wire render_busy,output wire [8:0] point_count,output wire bank_valid,
 input wire multi_mode,input wire [7:0] multi_valid,
 input wire [95:0] multi_x0,multi_y0,multi_x1,multi_y1
''')
s=s.replace('wire clear_event=clear_frame || video_timeout;', '''reg multi_frame;
 wire use_multi=MULTI_ENABLE && (sof?multi_mode:multi_frame);
 wire mode_change=MULTI_ENABLE && sof && multi_mode!=multi_frame;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)multi_frame<=0;else if(sof)multi_frame<=MULTI_ENABLE && multi_mode;
 wire clear_event=clear_frame || video_timeout || mode_change;''')
s=s.replace('!in_clear && !video_timeout;', '!in_clear && !video_timeout && !mode_change;')
s=s.replace('wire record=rebuild_frame && (!point_ok || !previous_valid || sample_due);', '''wire single_record=rebuild_frame && !use_multi && (!point_ok || !previous_valid || sample_due);
 wire multi_record,multi_done;wire [39:0] multi_entry;
 generate if(MULTI_ENABLE)begin: multi_samples
  roi_multi_trail_samples #(.IMG_W(IMG_W),.IMG_H(IMG_H),.SCALE_LOG2(SCALE_LOG2),
   .SAMPLE_INTERVAL_MS(SAMPLE_INTERVAL_MS),.JITTER_PIXELS(JITTER_PIXELS),
   .MAX_LINK_GAP_MS(MAX_LINK_GAP_MS),.MAX_JUMP_PIXELS(MAX_JUMP_PIXELS)) samples(
   .clk(clk),.rst_n(rst_n),.start(rebuild_frame && use_multi),.clear(clear_event),
   .ms_now(ms_now),.valid(multi_valid),.x0(multi_x0),.y0(multi_y0),.x1(multi_x1),.y1(multi_y1),
   .record(multi_record),.entry(multi_entry),.done(multi_done));
 end else begin: no_multi_samples
  assign multi_record=0;assign multi_done=0;assign multi_entry=0;
 end endgenerate
 wire record=single_record || multi_record;
 wire render_start=use_multi?multi_done:rebuild_frame;''')
s=s.replace('else if(record)begin\n   sample_started', 'else if(single_record)begin\n   sample_started')
s=s.replace('reg record_pending;', 'reg record_pending,multi_pending;reg [39:0] multi_entry_pending;')
s=s.replace('record_pending<=0;pending_addr', 'record_pending<=0;multi_pending<=0;multi_entry_pending<=0;pending_addr')
s=s.replace('record_pending<=record && !clear_event;', '''record_pending<=record && !clear_event;
   multi_pending<=multi_record;
   if(multi_record)multi_entry_pending<=multi_entry;''')
s=s.replace('history[pending_addr]<={pending_ms,pending_good,pending_link,pending_x,pending_y,5\'d0};',
            "history[pending_addr]<=multi_pending?multi_entry_pending:{pending_ms,pending_good,pending_link,pending_x,pending_y,5'd0};")
s=s.replace('reg have_previous;', '''reg have_previous;
 reg [7:0] multi_have_previous;
 reg [8:0] multi_last_x[0:7];reg [7:0] multi_last_y[0:7];
 wire [2:0] entry_id=entry_q[2:0];''')
s=s.replace('wire connect=have_previous && entry_q[22];', 'wire connect=(use_multi?multi_have_previous[entry_id]:have_previous) && entry_q[22];')
s=s.replace('wire [8:0] sx=connect?last_x:ex;wire [7:0] sy=connect?last_y:ey;', '''wire [8:0] sx=connect?(use_multi?multi_last_x[entry_id]:last_x):ex;
 wire [7:0] sy=connect?(use_multi?multi_last_y[entry_id]:last_y):ey;''')
# Only bitmap-builder predecessor state is indexed; history and both mask banks are unchanged in size.
s=s.replace('last_x<=0;last_y<=0;draw_x', 'multi_have_previous<=0;last_x<=0;last_y<=0;draw_x')
s=s.replace('have_previous<=0;\n   end else begin', 'have_previous<=0;multi_have_previous<=0;\n   end else begin')
s=s.replace('head<=next_head;count<=next_count;previous_valid<=point_ok;previous_ms<=ms_now;\n     if(point_ok)begin previous_x<=gx;previous_y<=gy;end', '''head<=next_head;count<=next_count;
     if(single_record)begin
      previous_valid<=point_ok;previous_ms<=ms_now;
      if(point_ok)begin previous_x<=gx;previous_y<=gy;end
     end''')
s=s.replace('IDLE:if(rebuild_frame && !ready && rebuild_count!=0)', 'IDLE:if(render_start && !ready && rebuild_count!=0)')
s=s.replace('build_ms<=ms_now;clear_addr<=0;have_previous<=0;', 'build_ms<=ms_now;clear_addr<=0;have_previous<=0;multi_have_previous<=0;')
s=s.replace('last_x<=ex;last_y<=ey;have_previous<=1;state<=DRAW;', '''last_x<=ex;last_y<=ey;have_previous<=1;
      if(MULTI_ENABLE && use_multi)begin
       multi_last_x[entry_id]<=ex;multi_last_y[entry_id]<=ey;multi_have_previous[entry_id]<=1;
      end
      state<=DRAW;''')
s=s.replace('end else begin have_previous<=0;state<=ADV;end', '''end else begin
      have_previous<=0;if(MULTI_ENABLE && use_multi)multi_have_previous[entry_id]<=0;state<=ADV;
     end''')
helper=(root/'tools/multi_trail_20261030/sampler.v.txt').read_text(encoding='utf-8')
p.write_text(s+'\n'+helper,encoding='utf-8')
p=root/'user_source/hdl_source/design_top_wrapper.v'
s=p.read_text(encoding='utf-8-sig')
s=s.replace('roi_motion_trail #(.TTL_MS(1000)', 'roi_motion_trail #(.MULTI_ENABLE(1),.TTL_MS(1000)')
needle='.point_valid(S_track2_valid),.point_x(S_track2_cx),.point_y(S_track2_cy),'
assert s.count(needle)==1
s=s.replace(needle,needle+'''
        .multi_mode(S_multi_frame),.multi_valid(S_multi_valid),
        .multi_x0(S_multi_x0),.multi_y0(S_multi_y0),.multi_x1(S_multi_x1),.multi_y1(S_multi_y1),''')
p.write_text(s,encoding='utf-8')
print('Updated only trajectory source and its top-level inputs')

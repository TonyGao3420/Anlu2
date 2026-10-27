// Green-only detector. Read-only tap: no pixel modification or video backpressure.
// 90..150 degree hue, >=25% saturation, >=12 chroma, G>=MIN_VALUE.
// Near-clipped G additionally needs >=25% separation from BOTH R and B.
// Connected tile regions are evaluated separately; outputs change only at SOF.
module roi_target_tracker #(
    parameter integer IMG_W=1280, IMG_H=720,
    // Kept for project compatibility; detection now covers the entire frame.
    parameter integer ROI_HALF_W=320, ROI_HALF_H=180,
    parameter integer ROI_MIN_HALF_W=96, ROI_MIN_HALF_H=72,
    parameter integer ROI_MARGIN_X=48, ROI_MARGIN_Y=32,
    parameter integer MIN_VALUE=24, MIN_AREA=128, MAX_AREA=120000,
    parameter integer MULTI_ENABLE=0,MAX_TARGETS=8,
    parameter integer HIGHLIGHT_G=248
)(
    input wire clk, rst_n, in_frame_start, in_de, in_line_last,
    input wire [23:0] in_rgb,
    output wire [MAX_TARGETS-1:0] multi_valid,
    output wire [MAX_TARGETS*12-1:0] multi_x0,multi_y0,multi_x1,multi_y1,
    output wire [3:0] multi_count,
    output wire [15:0] multi_total,multi_us,
    output wire multi_overflow,multi_late,
    output wire target_valid,
    output wire [15:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1,centroid_x,centroid_y,
    output wire [19:0] target_area,
    output wire frame_done,result_update,mask_valid,green_mask,
    output wire [11:0] mask_x,mask_y,
    output reg dbg_roi_valid,dbg_color_match
);
    reg [11:0] x_count,y_count,x_pipe,y_pipe,x_match,y_match;
    reg [23:0] rgb_pipe;
    reg de_rgb,de_match,match_pipe;
    wire [7:0] rb_min=(rgb_pipe[23:16]<rgb_pipe[7:0])?rgb_pipe[23:16]:rgb_pipe[7:0];
    wire [7:0] rb_diff=(rgb_pipe[23:16]<rgb_pipe[7:0])?
                       rgb_pipe[7:0]-rgb_pipe[23:16]:rgb_pipe[23:16]-rgb_pipe[7:0];
    wire [7:0] chroma=(rgb_pipe[15:8]>rb_min)?rgb_pipe[15:8]-rb_min:8'd0;
    wire [7:0] rb_max=(rgb_pipe[23:16]>rgb_pipe[7:0])?rgb_pipe[23:16]:rgb_pipe[7:0];
    wire [7:0] both_green_gap=(rgb_pipe[15:8]>rb_max)?rgb_pipe[15:8]-rb_max:8'd0;
    // Keep saturated pure/light greens. Reject ambiguous near-clipped whites
    // when only the lower of R/B made the old saturation test look green.
    wire highlight_ok=(rgb_pipe[15:8]<HIGHLIGHT_G) ||
                      (both_green_gap>=(rgb_pipe[15:8]>>2));
    wire green_match=(rgb_pipe[15:8]>=rgb_pipe[23:16]) &&
                     (rgb_pipe[15:8]>=rgb_pipe[7:0]) &&
                     ({1'b0,rb_diff,1'b0}<={2'b0,chroma}) &&
                     (chroma>=12) && (chroma>=(rgb_pipe[15:8]>>2)) &&
                     (rgb_pipe[15:8]>=MIN_VALUE) && highlight_ok;
    reg [IMG_W-1:0] line1,line2;
    reg t1,t2,m1,m2,b1,b2;
    wire t0=(y_match>=2)?line2[x_match]:1'b0;
    wire m0=(y_match>=1)?line1[x_match]:1'b0;
    wire [3:0] neighbors={3'b0,t2}+{3'b0,t1}+{3'b0,t0}+
                         {3'b0,m2}+{3'b0,m1}+{3'b0,m0}+
                         {3'b0,b2}+{3'b0,b1}+{3'b0,match_pipe};
    assign mask_valid=de_match && x_match>=1 && y_match>=1;
    assign green_mask=mask_valid && m1 && neighbors>=3;
    assign mask_x=x_match-12'd1;
    assign mask_y=y_match-12'd1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x_count<=0;y_count<=0;x_pipe<=0;y_pipe<=0;x_match<=0;y_match<=0;
            rgb_pipe<=0;de_rgb<=0;de_match<=0;match_pipe<=0;
            t1<=0;t2<=0;m1<=0;m2<=0;b1<=0;b2<=0;
            dbg_roi_valid<=0;dbg_color_match<=0;
        end else begin
            if(in_frame_start) begin x_count<=in_de?12'd1:12'd0;y_count<=0;end
            else if(in_de) begin
                if(in_line_last) begin x_count<=0;if(y_count<IMG_H-1)y_count<=y_count+1'b1;end
                else if(x_count<IMG_W-1)x_count<=x_count+1'b1;
            end
            x_pipe<=in_frame_start?12'd0:x_count;
            y_pipe<=in_frame_start?12'd0:y_count;
            rgb_pipe<=in_rgb;de_rgb<=in_de;
            x_match<=x_pipe;y_match<=y_pipe;de_match<=de_rgb;
            match_pipe<=de_rgb && green_match;
            dbg_roi_valid<=in_de;dbg_color_match<=green_mask;
            if(de_match) begin
                if(x_match==0) begin t1<=t0;t2<=0;m1<=m0;m2<=0;b1<=match_pipe;b2<=0;end
                else begin t2<=t1;t1<=t0;m2<=m1;m1<=m0;b2<=b1;b1<=match_pipe;end
                line2[x_match]<=(y_match==0)?1'b0:line1[x_match];
                line1[x_match]<=match_pipe;
            end
        end
    end
    green_region_tracker #(.IMG_W(IMG_W),.IMG_H(IMG_H),.MIN_AREA(MIN_AREA),
        .MULTI_ENABLE(MULTI_ENABLE),.MAX_TARGETS(MAX_TARGETS),
        .MAX_AREA(MAX_AREA),.MARGIN_X(ROI_MARGIN_X),.MARGIN_Y(ROI_MARGIN_Y)) regions(
        .clk(clk),.rst_n(rst_n),.sof(in_frame_start),
        .pixel_valid(mask_valid),.pixel_green(green_mask),.px(mask_x),.py(mask_y),
        .target_valid(target_valid),.bbox_x0(bbox_x0),.bbox_y0(bbox_y0),
        .bbox_x1(bbox_x1),.bbox_y1(bbox_y1),.centroid_x(centroid_x),.centroid_y(centroid_y),
        .multi_valid(multi_valid),.multi_x0(multi_x0),.multi_y0(multi_y0),
        .multi_x1(multi_x1),.multi_y1(multi_y1),.multi_count(multi_count),
        .multi_total(multi_total),.multi_us(multi_us),.multi_overflow(multi_overflow),.multi_late(multi_late),
        .target_area(target_area),.frame_done(frame_done),.result_update(result_update));
endmodule

// 16x16 spatial buckets retain exact pixel bounds and counts. Four-neighbor
// flood fill during vertical blank keeps disconnected regions out of one box.
// Neighbor bounds must also touch within two pixels, avoiding tile-edge merges.
// At 1280x720 the worst dense flood is <49,500 clocks (vertical blank budget).
module green_region_tracker #(
    parameter integer IMG_W=1280,IMG_H=720,MIN_AREA=128,MAX_AREA=120000,
    parameter integer MARGIN_X=48,MARGIN_Y=32,
    parameter integer MULTI_ENABLE=0,MAX_TARGETS=8,
    parameter integer DEAD_BAND=2,HOLD_FRAMES=2
)(
    input wire clk,rst_n,sof,pixel_valid,pixel_green,
    input wire [11:0] px,py,
    output wire [MAX_TARGETS-1:0] multi_valid,
    output wire [MAX_TARGETS*12-1:0] multi_x0,multi_y0,multi_x1,multi_y1,
    output wire [3:0] multi_count,
    output wire [15:0] multi_total,multi_us,
    output wire multi_overflow,multi_late,
    output reg target_valid,
    output reg [15:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1,centroid_x,centroid_y,
    output reg [19:0] target_area,
    output reg frame_done,result_update
);
    localparam integer GW=(IMG_W+15)/16,GH=(IMG_H+15)/16,CELLS=GW*GH;
    localparam integer AW=(CELLS<=2)?1:$clog2(CELLS);
    localparam [3:0] CLEAR=0,CAPTURE=1,DRAIN=2,SCAN_REQ=3,SCAN_USE=4,
        POP_REQ=5,POP_USE=6,N_REQ=7,N_USE=8,COMPLETE=9,NEXT=10,FINISH=11;
    reg [3:0] state;
    // One synchronous read port plus one synchronous write port. No RAM reset.
    reg [31:0] grid[0:CELLS-1];
    reg [47:0] stack[0:CELLS-1];
    reg [31:0] rd_word;
    reg [47:0] stack_q;
    reg [AW-1:0] rd_addr,wr_addr,cursor;
    reg [31:0] wr_word;
    reg wr_en;
    reg [AW:0] sp;
    reg [7:0] scan_x,scan_y,cell_x,cell_y,nx,ny;
    reg [15:0] cell_bounds;
    reg [AW-1:0] cell_addr,naddr;
    reg [1:0] direction;
    reg neighbor_valid;
    reg cap_valid;
    reg [AW-1:0] cap_addr,last_wr_addr;
    reg [3:0] cap_x,cap_y;
    reg last_wr_en;
    reg [31:0] last_wr_word;
    wire [AW-1:0] pixel_addr=(py>>4)*GW+(px>>4);
    wire [31:0] old_word=(last_wr_en && last_wr_addr==cap_addr)?last_wr_word:rd_word;
    reg [31:0] updated;
    reg [19:0] comp_area,best_area;
    reg [11:0] comp_x0,comp_x1,comp_y0,comp_y1,best_x0,best_x1,best_y0,best_y1;
    reg best_valid,best_near,ready;
    reg [12:0] best_distance;
    reg [2:0] misses,settle;
    reg [15:0] next_x0,next_x1,next_y0,next_y1;
    wire [11:0] nb_x0={nx,rd_word[15:12]},nb_x1={nx,rd_word[11:8]};
    wire [11:0] nb_y0={ny,rd_word[7:4]},nb_y1={ny,rd_word[3:0]};
    wire [11:0] here_x0={cell_x,cell_bounds[15:12]},here_x1={cell_x,cell_bounds[11:8]};
    wire [11:0] here_y0={cell_y,cell_bounds[7:4]},here_y1={cell_y,cell_bounds[3:0]};
    wire neighbor_touches=({1'b0,nb_x0}<={1'b0,here_x1}+13'd3) &&
                          ({1'b0,here_x0}<={1'b0,nb_x1}+13'd3) &&
                          ({1'b0,nb_y0}<={1'b0,here_y1}+13'd3) &&
                          ({1'b0,here_y0}<={1'b0,nb_y1}+13'd3);
    wire [12:0] comp_cx_sum={1'b0,comp_x0}+{1'b0,comp_x1};
    wire [12:0] comp_cy_sum={1'b0,comp_y0}+{1'b0,comp_y1};
    wire [11:0] comp_cx=comp_cx_sum[12:1],comp_cy=comp_cy_sum[12:1];
    wire [11:0] dist_x=(comp_cx>=centroid_x)?comp_cx-centroid_x:centroid_x-comp_cx;
    wire [11:0] dist_y=(comp_cy>=centroid_y)?comp_cy-centroid_y:centroid_y-comp_cy;
    wire [12:0] distance={1'b0,dist_x}+{1'b0,dist_y};
    wire comp_near=target_valid &&
        ({4'b0,comp_x0}<=bbox_x1+MARGIN_X) && ({4'b0,comp_x1}+MARGIN_X>=bbox_x0) &&
        ({4'b0,comp_y0}<=bbox_y1+MARGIN_Y) && ({4'b0,comp_y1}+MARGIN_Y>=bbox_y0);
    wire acceptable=comp_area>=MIN_AREA && comp_area<=MAX_AREA &&
                    comp_x1>=comp_x0+5 && comp_y1>=comp_y0+5;
    generate if(MULTI_ENABLE)begin:g_multi
        multi_target_slots #(.W(IMG_W),.H(IMG_H),.N(MAX_TARGETS)) slots(
          .clk(clk),.rst_n(rst_n),.sof(sof),
          .scan_start(state==CAPTURE && pixel_valid && px==IMG_W-2 && py==IMG_H-2),
          .scan_end(state==FINISH),
          .component_valid(state==COMPLETE && comp_area>=MIN_AREA && comp_x1>=comp_x0+5 && comp_y1>=comp_y0+5),
          .component_x0(comp_x0),.component_y0(comp_y0),.component_x1(comp_x1),.component_y1(comp_y1),.component_area(comp_area),
          .valid(multi_valid),.x0(multi_x0),.y0(multi_y0),.x1(multi_x1),.y1(multi_y1),
          .count(multi_count),.total(multi_total),.process_us(multi_us),.overflow(multi_overflow),.late(multi_late));
    end else begin:g_no_multi
        assign multi_valid=0;assign multi_x0=0;assign multi_y0=0;assign multi_x1=0;assign multi_y1=0;
        assign multi_count=0;assign multi_total=0;assign multi_us=0;assign multi_overflow=0;assign multi_late=0;
    end endgenerate
    wire select_comp=acceptable && (!best_valid ||
        (comp_near && !best_near) ||
        (comp_near && best_near && (distance<best_distance ||
          (distance==best_distance && comp_area>best_area))) ||
        (!comp_near && !best_near && comp_area>best_area));
    // Stable envelope: ignore <=2px noise; expand promptly; contract by 1/4
    // only after two settled frames. Large translations acquire a fresh box.
    function [15:0] stable_edge;
        input [15:0] previous,measured;
        input lower_edge,allow_shrink;
        reg [15:0] delta,step_size;
        begin
            delta=(previous>measured)?previous-measured:measured-previous;
            step_size=delta>>2;if(step_size==0)step_size=1;
            if(delta<=DEAD_BAND)stable_edge=previous;
            else if((lower_edge && measured<previous)||(!lower_edge && measured>previous))
                stable_edge=measured;
            else if(!allow_shrink)stable_edge=previous;
            else stable_edge=(previous>measured)?previous-step_size:previous+step_size;
        end
    endfunction
    always @* begin
        updated=old_word;
        updated[31:26]=0;
        if(old_word[24:16]==0)begin
            updated[24:16]=1;updated[15:0]={cap_x,cap_x,cap_y,cap_y};
        end else begin
            if(old_word[24:16]<256)updated[24:16]=old_word[24:16]+1'b1;
            if(cap_x<old_word[15:12])updated[15:12]=cap_x;
            if(cap_x>old_word[11:8])updated[11:8]=cap_x;
            if(cap_y<old_word[7:4])updated[7:4]=cap_y;
            if(cap_y>old_word[3:0])updated[3:0]=cap_y;
        end
        updated[25]=(updated[24:16]>=3);
        nx=cell_x;ny=cell_y;naddr=cell_addr;neighbor_valid=1;
        case(direction)
            0:begin nx=cell_x-1'b1;naddr=cell_addr-1'b1;neighbor_valid=(cell_x!=0);end
            1:begin nx=cell_x+1'b1;naddr=cell_addr+1'b1;neighbor_valid=(cell_x<GW-1);end
            2:begin ny=cell_y-1'b1;naddr=cell_addr-GW;neighbor_valid=(cell_y!=0);end
            3:begin ny=cell_y+1'b1;naddr=cell_addr+GW;neighbor_valid=(cell_y<GH-1);end
        endcase
        rd_addr=0;
        if(state==CAPTURE)rd_addr=pixel_addr;
        else if(state==SCAN_REQ)rd_addr=cursor;
        else if(state==N_REQ && neighbor_valid)rd_addr=naddr;
        wr_en=cap_valid;wr_addr=cap_addr;wr_word=updated;
        if(state==CLEAR)begin wr_en=1;wr_addr=cursor;wr_word=0;end
        if(state==SCAN_USE)begin
            wr_en=1;wr_addr=cursor;
            wr_word=rd_word[25]?(rd_word & 32'hfdffffff):32'd0;
        end
        if(state==POP_USE)begin wr_en=1;wr_addr=stack_q[AW-1:0];wr_word=0;end
        if(state==N_USE && neighbor_valid && rd_word[25] && neighbor_touches)begin
            wr_en=1;wr_addr=naddr;wr_word=rd_word & 32'hfdffffff;
        end
        next_x0={4'b0,best_x0};next_x1={4'b0,best_x1};
        next_y0={4'b0,best_y0};next_y1={4'b0,best_y1};
        if(target_valid && best_near && best_distance<=16) begin
            next_x0=stable_edge(bbox_x0,{4'b0,best_x0},1'b1,settle>=2);
            next_x1=stable_edge(bbox_x1,{4'b0,best_x1},1'b0,settle>=2);
            next_y0=stable_edge(bbox_y0,{4'b0,best_y0},1'b1,settle>=2);
            next_y1=stable_edge(bbox_y1,{4'b0,best_y1},1'b0,settle>=2);
        end
    end
    wire stack_write_seed=(state==SCAN_USE && rd_word[25]);
    wire stack_write_neighbor=(state==N_USE && neighbor_valid && rd_word[25] && neighbor_touches);
    wire stack_we=stack_write_seed || stack_write_neighbor;
    wire [AW-1:0] stack_wa=stack_write_seed?{AW{1'b0}}:sp[AW-1:0];
    wire [AW-1:0] stack_ra=sp[AW-1:0]-1'b1;
    wire [47:0] stack_d=stack_write_seed?
        {scan_y,scan_x,rd_word[15:0],{{(16-AW){1'b0}},cursor}}:
        {ny,nx,rd_word[15:0],{{(16-AW){1'b0}},naddr}};
    always @(posedge clk)begin
        rd_word<=grid[rd_addr];
        if(wr_en)grid[wr_addr]<=wr_word;
    end
    always @(posedge clk)begin
        stack_q<=stack[stack_ra];
        if(stack_we)stack[stack_wa]<=stack_d;
    end
    task advance_scan;
        begin
            if(cursor==CELLS-1)state<=FINISH;
            else begin
                cursor<=cursor+1'b1;
                if(scan_x==GW-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end
                else scan_x<=scan_x+1'b1;
                state<=SCAN_REQ;
            end
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=CLEAR;cursor<=0;scan_x<=0;scan_y<=0;sp<=0;
            cap_valid<=0;cap_addr<=0;cap_x<=0;cap_y<=0;
            last_wr_en<=0;last_wr_addr<=0;last_wr_word<=0;
            cell_addr<=0;cell_x<=0;cell_y<=0;cell_bounds<=0;direction<=0;
            comp_area<=0;comp_x0<=0;comp_x1<=0;comp_y0<=0;comp_y1<=0;
            best_area<=0;best_x0<=0;best_x1<=0;best_y0<=0;best_y1<=0;
            best_valid<=0;best_near<=0;best_distance<=0;ready<=0;
            target_valid<=0;bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;
            centroid_x<=0;centroid_y<=0;target_area<=0;frame_done<=0;result_update<=0;
            misses<=0;settle<=0;
        end else begin
            frame_done<=0;result_update<=0;
            last_wr_en<=wr_en;last_wr_addr<=wr_addr;last_wr_word<=wr_word;
            cap_valid<=state==CAPTURE && pixel_valid && pixel_green;
            cap_addr<=pixel_addr;cap_x<=px[3:0];cap_y<=py[3:0];
            case(state)
                CLEAR:if(cursor==CELLS-1)begin cursor<=0;state<=CAPTURE;end else cursor<=cursor+1'b1;
                CAPTURE:if(pixel_valid && px==IMG_W-2 && py==IMG_H-2)begin
                    state<=DRAIN;best_valid<=0;best_near<=0;best_area<=0;
                    cursor<=0;scan_x<=0;scan_y<=0;ready<=0;
                end
                DRAIN:state<=SCAN_REQ;
                SCAN_REQ:state<=SCAN_USE;
                SCAN_USE:begin
                    if(rd_word[25])begin
                        sp<=1;comp_area<={11'b0,rd_word[24:16]};
                        comp_x0<={scan_x,rd_word[15:12]};comp_x1<={scan_x,rd_word[11:8]};
                        comp_y0<={scan_y,rd_word[7:4]};comp_y1<={scan_y,rd_word[3:0]};
                        state<=POP_REQ;
                    end else advance_scan();
                end
                POP_REQ:if(sp==0)state<=COMPLETE;else begin sp<=sp-1'b1;state<=POP_USE;end
                POP_USE:begin
                    cell_y<=stack_q[47:40];cell_x<=stack_q[39:32];cell_bounds<=stack_q[31:16];
                    cell_addr<=stack_q[AW-1:0];direction<=0;state<=N_REQ;
                end
                N_REQ:state<=N_USE;
                N_USE:begin
                    if(neighbor_valid && rd_word[25] && neighbor_touches)begin
                        sp<=sp+1'b1;comp_area<=comp_area+rd_word[24:16];
                        if(nb_x0<comp_x0)comp_x0<=nb_x0;if(nb_x1>comp_x1)comp_x1<=nb_x1;
                        if(nb_y0<comp_y0)comp_y0<=nb_y0;if(nb_y1>comp_y1)comp_y1<=nb_y1;
                    end
                    if(direction==3)begin
                        if(sp==0 && !(neighbor_valid && rd_word[25] && neighbor_touches))state<=COMPLETE;
                        else state<=POP_REQ;
                    end
                    else begin direction<=direction+1'b1;state<=N_REQ;end
                end
                COMPLETE:begin
                    if(select_comp)begin
                        best_valid<=1;best_near<=comp_near;best_area<=comp_area;best_distance<=distance;
                        best_x0<=comp_x0;best_x1<=comp_x1;best_y0<=comp_y0;best_y1<=comp_y1;
                    end
                    advance_scan();
                end
                NEXT:begin
                    if(cursor==CELLS-1)state<=FINISH;
                    else begin
                        cursor<=cursor+1'b1;
                        if(scan_x==GW-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end
                        else scan_x<=scan_x+1'b1;
                        state<=SCAN_REQ;
                    end
                end
                FINISH:begin ready<=1;state<=CAPTURE;end
                default:state<=CLEAR;
            endcase
            // Atomic SOF commit: stable for the entire displayed frame.
            if(sof)begin
                frame_done<=1;
                if(ready)begin
                    ready<=0;result_update<=1;
                    if(best_valid && (!target_valid || best_near || misses>=HOLD_FRAMES))begin
                        target_valid<=1;bbox_x0<=next_x0;bbox_x1<=next_x1;bbox_y0<=next_y0;bbox_y1<=next_y1;
                        centroid_x<=(next_x0+next_x1)>>1;centroid_y<=(next_y0+next_y1)>>1;
                        target_area<=best_area;misses<=0;
                        if(best_near && best_distance<=16)begin if(settle<7)settle<=settle+1'b1;end else settle<=0;
                    end else if(target_valid && misses<HOLD_FRAMES)begin misses<=misses+1'b1;settle<=0;end
                    else begin
                        target_valid<=0;bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;
                        centroid_x<=0;centroid_y<=0;target_area<=0;misses<=0;settle<=0;
                    end
                end
            end
        end
    end
endmodule

// Appended to roi_target_tracker.v. Shares its component walk and all ERAM.
module multi_target_slots #(
 parameter integer W=1280,H=720,N=8,ASSOC_DISTANCE=128,HOLD_FRAMES=1
)(input wire clk,rst_n,sof,scan_start,scan_end,component_valid,
 input wire [11:0] component_x0,component_y0,component_x1,component_y1,
 input wire [19:0] component_area,
 output reg [N-1:0] valid,
 output reg [N*12-1:0] x0,y0,x1,y1,
 output reg [3:0] count,output reg [15:0] total,process_us,
 output reg overflow,late);
 localparam [3:0] IDLE=0,MIN_SCAN=1,MATCH_INIT=2,MATCH_SCAN=3,MATCH_SAVE=4,
  ALLOC_INIT=5,ALLOC_SCAN=6,ALLOC_SAVE=7,COAST=8,DONE=9;
 localparam [11:0] W_LAST=W-1,H_LAST=H-1;
 reg [3:0] state;
 reg [10:0] cx0[0:N-1],cx1[0:N-1];reg [9:0] cy0[0:N-1],cy1[0:N-1];
 reg [19:0] area[0:N-1];
 reg [N-1:0] working_valid,old_used,assigned;
 reg [10:0] wx0[0:N-1],wx1[0:N-1];reg [9:0] wy0[0:N-1],wy1[0:N-1];
 reg [1:0] miss[0:N-1],working_miss[0:N-1];
 reg [3:0] kept,ci,si,best_slot,min_slot,free_slot;
 reg [19:0] min_area;
 reg [12:0] best_distance;
 reg found,free_found,free_is_empty;
 reg [15:0] found_total,working_total,elapsed_us,working_us;
 reg [6:0] us_div;
 reg end_wait,ready,seen_scan,measuring,overflow_work,working_overflow;
 // Register component events so the observer adds only register loads to
 // the existing flood-fill engine; it never stalls or alters its state.
 reg event_q;reg [47:0] box_q;reg [19:0] area_q;
 reg [47:0] incoming_box;reg [19:0] incoming_area;
 wire [12:0] cand_sum_x={1'b0,cx0[ci]}+{1'b0,cx1[ci]};
 wire [12:0] cand_sum_y={1'b0,cy0[ci]}+{1'b0,cy1[ci]};
 wire [12:0] old_sum_x={1'b0,x0[si*12+:12]}+{1'b0,x1[si*12+:12]};
 wire [12:0] old_sum_y={1'b0,y0[si*12+:12]}+{1'b0,y1[si*12+:12]};
 wire [11:0] cand_center_x=cand_sum_x[12:1],cand_center_y=cand_sum_y[12:1];
 wire [11:0] old_center_x=old_sum_x[12:1],old_center_y=old_sum_y[12:1];
 wire [11:0] dx=(cand_center_x>old_center_x)?cand_center_x-old_center_x:old_center_x-cand_center_x;
 wire [11:0] dy=(cand_center_y>old_center_y)?cand_center_y-old_center_y:old_center_y-cand_center_y;
 wire [12:0] distance={1'b0,dx}+{1'b0,dy};
 wire better=valid[si] && !old_used[si] && distance<=ASSOC_DISTANCE && (!found || distance<best_distance);
 wire [3:0] minimum=(area[si]<min_area)?si:min_slot;
 wire [11:0] measured_x0=(cx0[ci]>1)?cx0[ci]-12'd2:12'd0;
 wire [11:0] measured_y0=(cy0[ci]>1)?cy0[ci]-12'd2:12'd0;
 wire [11:0] measured_x1=(cx1[ci]<W-2)?cx1[ci]+12'd2:W_LAST;
 wire [11:0] measured_y1=(cy1[ci]<H-2)?cy1[ci]+12'd2:H_LAST;
 function [11:0] stable_edge;
  input [11:0] previous,measured;input lower;
  reg [11:0] delta,step;
  begin
   delta=(previous>measured)?previous-measured:measured-previous;
   step=delta>>2;if(step==0)step=1;
   if((lower && measured<previous)||(!lower && measured>previous))stable_edge=measured;
   else if(delta<=2)stable_edge=previous;
   else stable_edge=(previous>measured)?previous-step:previous+step;
  end
 endfunction
 integer i,pop_i;reg [3:0] num_valid;
 always @*begin num_valid=0;for(pop_i=0;pop_i<N;pop_i=pop_i+1)num_valid=num_valid+working_valid[pop_i];end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;valid<=0;x0<=0;y0<=0;x1<=0;y1<=0;count<=0;total<=0;process_us<=0;overflow<=0;late<=0;
   working_valid<=0;old_used<=0;assigned<=0;kept<=0;ci<=0;si<=0;best_slot<=0;min_slot<=0;free_slot<=0;
   min_area<=20'hfffff;best_distance<=0;found<=0;free_found<=0;free_is_empty<=0;
   found_total<=0;working_total<=0;elapsed_us<=0;working_us<=0;us_div<=0;
   end_wait<=0;ready<=0;seen_scan<=0;measuring<=0;overflow_work<=0;working_overflow<=0;
   event_q<=0;box_q<=0;area_q<=0;incoming_box<=0;incoming_area<=0;
   for(i=0;i<N;i=i+1)begin cx0[i]<=0;cy0[i]<=0;cx1[i]<=0;cy1[i]<=0;area[i]<=0;wx0[i]<=0;wy0[i]<=0;wx1[i]<=0;wy1[i]<=0;miss[i]<=0;working_miss[i]<=0;end
  end else begin
   event_q<=component_valid;
   if(component_valid)begin box_q<={component_x0,component_y0,component_x1,component_y1};area_q<=component_area;end
   if(scan_end)end_wait<=1;
   if(measuring)begin
    if(us_div==74)begin us_div<=0;if(elapsed_us!=16'hffff)elapsed_us<=elapsed_us+1'b1;end else us_div<=us_div+1'b1;
   end
   // In production each accepted component consumes >=12 engine clocks;
   // the eight-entry replacement scan completes before the next event.
   if(event_q && state!=IDLE)overflow_work<=1;
   case(state)
    IDLE:begin
     if(event_q)begin
      if(found_total!=16'hffff)found_total<=found_total+1'b1;
      if(kept<N)begin
       cx0[kept]<=box_q[47:36];cy0[kept]<=box_q[35:24];cx1[kept]<=box_q[23:12];cy1[kept]<=box_q[11:0];area[kept]<=area_q;kept<=kept+1'b1;
      end else begin
       overflow_work<=1;incoming_box<=box_q;incoming_area<=area_q;si<=0;min_area<=20'hfffff;min_slot<=0;state<=MIN_SCAN;
      end
     end else if(end_wait)begin
      end_wait<=0;working_valid<=0;old_used<=0;assigned<=0;ci<=0;si<=0;state<=MATCH_INIT;
      working_total<=found_total;working_overflow<=overflow_work;
     end
    end
    MIN_SCAN:begin
     if(area[si]<min_area)begin min_area<=area[si];min_slot<=si;end
     if(si==N-1)begin
      if(incoming_area<=(area[si]<min_area?area[si]:min_area))begin end
      else begin
       cx0[minimum]<=incoming_box[47:36];cy0[minimum]<=incoming_box[35:24];cx1[minimum]<=incoming_box[23:12];cy1[minimum]<=incoming_box[11:0];area[minimum]<=incoming_area;
      end
      state<=IDLE;
     end else si<=si+1'b1;
    end
    MATCH_INIT:begin
     si<=0;found<=0;best_distance<=13'h1fff;best_slot<=0;
     if(ci<kept)state<=MATCH_SCAN;else begin ci<=0;state<=ALLOC_INIT;end
    end
    MATCH_SCAN:begin
     if(better)begin found<=1;best_distance<=distance;best_slot<=si;end
     if(si==N-1)state<=MATCH_SAVE;else si<=si+1'b1;
    end
    MATCH_SAVE:begin
     if(found)begin
      working_valid[best_slot]<=1;old_used[best_slot]<=1;assigned[ci]<=1;working_miss[best_slot]<=0;
      wx0[best_slot]<=(best_distance<=16)?stable_edge(x0[best_slot*12+:12],measured_x0,1'b1):measured_x0;
      wy0[best_slot]<=(best_distance<=16)?stable_edge(y0[best_slot*12+:12],measured_y0,1'b1):measured_y0;
      wx1[best_slot]<=(best_distance<=16)?stable_edge(x1[best_slot*12+:12],measured_x1,1'b0):measured_x1;
      wy1[best_slot]<=(best_distance<=16)?stable_edge(y1[best_slot*12+:12],measured_y1,1'b0):measured_y1;
     end
     ci<=ci+1'b1;state<=MATCH_INIT;
    end
    ALLOC_INIT:begin
     si<=0;free_found<=0;free_is_empty<=0;free_slot<=0;
     if(ci==kept)begin si<=0;state<=COAST;end
     else if(assigned[ci])ci<=ci+1'b1;
     else state<=ALLOC_SCAN;
    end
    ALLOC_SCAN:begin
     if(!working_valid[si] && (!free_found || (!valid[si] && !free_is_empty)))begin free_found<=1;free_slot<=si;free_is_empty<=!valid[si];end
     if(si==N-1)state<=ALLOC_SAVE;else si<=si+1'b1;
    end
    ALLOC_SAVE:begin
     if(free_found)begin
      working_valid[free_slot]<=1;working_miss[free_slot]<=0;
      wx0[free_slot]<=measured_x0;wy0[free_slot]<=measured_y0;wx1[free_slot]<=measured_x1;wy1[free_slot]<=measured_y1;
     end else working_overflow<=1;
     ci<=ci+1'b1;state<=ALLOC_INIT;
    end
    COAST:begin
     if(!working_valid[si] && valid[si] && miss[si]<HOLD_FRAMES)begin
      working_valid[si]<=1;working_miss[si]<=miss[si]+1'b1;
      wx0[si]<=x0[si*12+:12];wy0[si]<=y0[si*12+:12];wx1[si]<=x1[si*12+:12];wy1[si]<=y1[si*12+:12];
     end
     if(si==N-1)state<=DONE;else si<=si+1'b1;
    end
    DONE:begin ready<=1;measuring<=0;working_us<=elapsed_us;state<=IDLE;end
    default:state<=IDLE;
   endcase
   if(sof)begin
    if(ready)begin
     valid<=working_valid;count<=num_valid;total<=working_total;overflow<=working_overflow;process_us<=working_us;ready<=0;late<=0;
     for(i=0;i<N;i=i+1)begin x0[i*12+:12]<=wx0[i];y0[i*12+:12]<=wy0[i];x1[i*12+:12]<=wx1[i];y1[i*12+:12]<=wy1[i];miss[i]<=working_miss[i];end
    end else if(seen_scan)late<=1;
   end
   if(scan_start)begin
    state<=IDLE;kept<=0;found_total<=0;overflow_work<=0;end_wait<=0;ready<=0;event_q<=0;seen_scan<=1;measuring<=1;elapsed_us<=0;us_div<=0;
   end
  end
 end
 // synthesis translate_off
 initial if(N<1 || N>8)$fatal(1,"Multi target capacity must be 1..8");
 // synthesis translate_on
endmodule

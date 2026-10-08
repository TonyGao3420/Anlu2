// Green-only detector. Read-only tap: no pixel modification or video backpressure.
// 90..150 degree hue, >=25% saturation, >=12 chroma, G>=MIN_VALUE.
// Connected tile regions are evaluated separately; outputs change only at SOF.
module roi_target_tracker #(
    parameter integer IMG_W=1280, IMG_H=720,
    // Kept for project compatibility; detection now covers the entire frame.
    parameter integer ROI_HALF_W=320, ROI_HALF_H=180,
    parameter integer ROI_MIN_HALF_W=96, ROI_MIN_HALF_H=72,
    parameter integer ROI_MARGIN_X=48, ROI_MARGIN_Y=32,
    parameter integer MIN_VALUE=24, MIN_AREA=128, MAX_AREA=120000
)(
    input wire clk, rst_n, in_frame_start, in_de, in_line_last,
    input wire [23:0] in_rgb,
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
    wire green_match=(rgb_pipe[15:8]>=rgb_pipe[23:16]) &&
                     (rgb_pipe[15:8]>=rgb_pipe[7:0]) &&
                     ({1'b0,rb_diff,1'b0}<={2'b0,chroma}) &&
                     (chroma>=12) && (chroma>=(rgb_pipe[15:8]>>2)) &&
                     (rgb_pipe[15:8]>=MIN_VALUE);
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
        .MAX_AREA(MAX_AREA),.MARGIN_X(ROI_MARGIN_X),.MARGIN_Y(ROI_MARGIN_Y)) regions(
        .clk(clk),.rst_n(rst_n),.sof(in_frame_start),
        .pixel_valid(mask_valid),.pixel_green(green_mask),.px(mask_x),.py(mask_y),
        .target_valid(target_valid),.bbox_x0(bbox_x0),.bbox_y0(bbox_y0),
        .bbox_x1(bbox_x1),.bbox_y1(bbox_y1),.centroid_x(centroid_x),.centroid_y(centroid_y),
        .target_area(target_area),.frame_done(frame_done),.result_update(result_update));
endmodule

// 16x16 spatial buckets retain exact pixel bounds and counts. Four-neighbor
// flood fill during vertical blank keeps disconnected regions out of one box.
// Neighbor bounds must also touch within two pixels, avoiding tile-edge merges.
// At 1280x720 the worst dense flood is <49,500 clocks (vertical blank budget).
module green_region_tracker #(
    parameter integer IMG_W=1280,IMG_H=720,MIN_AREA=128,MAX_AREA=120000,
    parameter integer MARGIN_X=48,MARGIN_Y=32,
    parameter integer DEAD_BAND=2,HOLD_FRAMES=2
)(
    input wire clk,rst_n,sof,pixel_valid,pixel_green,
    input wire [11:0] px,py,
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

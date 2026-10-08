// Four-pixel BGGR color-shading correction, independently implemented for PH1P35.
// References and pinned upstream code: doc/OPEN_SOURCE_LSC_20261008.md.
// Explicit flat-field calibration only; ordinary scenes NEVER update the map.
// 3x3 nodes x four Bayer planes, Q10 gains, bilinear interpolation, 5-cycle stream.
// Unity after reset/clear; transactional validation and frame-boundary map commit.
module raw_color_shading #(
    parameter integer IMG_W=1280, IMG_H=720,
    parameter integer X_STEP_LOG=9, Y_STEP_LOG=8,
    parameter integer SAMPLE_HALF_X=32, SAMPLE_HALF_Y=16,
    parameter integer BLACK_LEVEL=0,
    parameter integer MIN_MEAN=80, MAX_MEAN=900,
    parameter integer MIN_GAIN=768, MAX_GAIN=1536
)(
    input wire clk, rst_n,
    input wire cal_request, clear_request,
    input wire in_valid, in_user, in_last,
    input wire [39:0] in_data,
    input wire [9:0] in_dest,
    output wire out_valid, out_user, out_last,
    output wire [39:0] out_data,
    output wire [9:0] out_dest,
    output reg map_valid, cal_busy, cal_failed
);
    localparam integer X0=IMG_W/2-(1<<X_STEP_LOG), X1=IMG_W/2,
                       X2=IMG_W/2+(1<<X_STEP_LOG);
    localparam integer Y0=IMG_H/2-(1<<Y_STEP_LOG), Y1=IMG_H/2,
                       Y2=IMG_H/2+(1<<Y_STEP_LOG);
    localparam integer SAMPLES=SAMPLE_HALF_X*SAMPLE_HALF_Y;
    localparam [2:0] IDLE=0, ARMED=1, CAPTURE=2, INIT_DIV=3, DIVIDE=4, READY=5;
    reg [2:0] state;
    reg [11:0] x_count,y_count;
    wire [11:0] px=in_user ? 12'd0 : x_count;
    wire [11:0] py=in_user ? 12'd0 : y_count;
    reg [11:0] gain[0:35];
    reg [11:0] pending_gain[0:35];
    reg [23:0] sums[0:35];
    reg [15:0] counts[0:8];
    reg capture_bad;
    reg clear_pending;
    reg [5:0] div_index;
    reg [31:0] dividend, quotient;
    reg [23:0] divisor;
    reg [24:0] remainder;
    reg [5:0] div_left;
    wire [24:0] rem_shift={remainder[23:0],dividend[31]};
    wire take_bit=rem_shift>={1'b0,divisor};
    wire [24:0] rem_next=take_bit ? rem_shift-{1'b0,divisor}:rem_shift;
    wire [31:0] quotient_next={quotient[30:0],take_bit};
    wire [3:0] div_node=div_index>>2;
    wire [25:0] green_sum={2'b0,sums[div_node*4+1]}+{2'b0,sums[div_node*4+2]};
    wire [31:0] div_numerator={green_sum[22:0],9'b0};
    integer sample_x,sample_y,sample_node;
    wire [9:0] raw0=in_data[9:0], raw1=in_data[19:10];
    wire [9:0] raw2=in_data[29:20],raw3=in_data[39:30];
    function [9:0] subtract_black;
        input [9:0] value;
        begin subtract_black=(value>BLACK_LEVEL)?value-BLACK_LEVEL:0; end
    endfunction
    wire [10:0] even_sum={1'b0,subtract_black(raw0)}+{1'b0,subtract_black(raw2)};
    wire [10:0] odd_sum ={1'b0,subtract_black(raw1)}+{1'b0,subtract_black(raw3)};
    wire sampled_clipped=(raw0>=1000)||(raw1>=1000)||(raw2>=1000)||(raw3>=1000);
    always @* begin
        sample_x=-1; sample_y=-1;
        if(px>=X0-SAMPLE_HALF_X && px<X0+SAMPLE_HALF_X) sample_x=0;
        if(px>=X1-SAMPLE_HALF_X && px<X1+SAMPLE_HALF_X) sample_x=1;
        if(px>=X2-SAMPLE_HALF_X && px<X2+SAMPLE_HALF_X) sample_x=2;
        if(py>=Y0-SAMPLE_HALF_Y && py<Y0+SAMPLE_HALF_Y) sample_y=0;
        if(py>=Y1-SAMPLE_HALF_Y && py<Y1+SAMPLE_HALF_Y) sample_y=1;
        if(py>=Y2-SAMPLE_HALF_Y && py<Y2+SAMPLE_HALF_Y) sample_y=2;
        sample_node=sample_y*3+sample_x;
    end
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; x_count<=0; y_count<=0;
            map_valid<=0; cal_busy<=0; cal_failed<=0;
            capture_bad<=0; clear_pending<=0; div_index<=0;
            dividend<=0; quotient<=0; divisor<=1; remainder<=0; div_left<=0;
            for(i=0;i<36;i=i+1) begin gain[i]<=1024;pending_gain[i]<=1024;sums[i]<=0;end
            for(i=0;i<9;i=i+1) counts[i]<=0;
        end else begin
            if(in_valid) begin
                if(in_last) begin x_count<=0; y_count<=py+1'b1;end
                else begin x_count<=px+4; y_count<=py;end
            end else if(in_user) begin x_count<=0;y_count<=0;end
            if(clear_request) clear_pending<=1;
            if(state==IDLE && cal_request && !clear_pending) begin
                state<=ARMED; cal_busy<=1; cal_failed<=0;
            end
            case(state)
                ARMED: if(in_user) begin
                    state<=CAPTURE; capture_bad<=0;
                    for(i=0;i<36;i=i+1) sums[i]<=0;
                    for(i=0;i<9;i=i+1) counts[i]<=0;
                end
                CAPTURE: begin
                    if(in_valid && sample_x>=0 && sample_y>=0) begin
                        // All sample windows have even dimensions and aligned words.
                        // Each Bayer plane has exactly SAMPLES pixels per node.
                        counts[sample_node]<=counts[sample_node]+2;
                        if(py[0]) begin
                            sums[sample_node*4+2]<=sums[sample_node*4+2]+even_sum;
                            sums[sample_node*4+3]<=sums[sample_node*4+3]+odd_sum;
                        end else begin
                            sums[sample_node*4]<=sums[sample_node*4]+even_sum;
                            sums[sample_node*4+1]<=sums[sample_node*4+1]+odd_sum;
                        end
                        if(sampled_clipped) capture_bad<=1;
                    end
                    // Start computation immediately after the final raster word,
                    // not on the next frame's first pixel.
                    if(in_valid && in_last && py==IMG_H-1) begin
                        div_index<=0;state<=INIT_DIV;
                    end
                end
                INIT_DIV: begin
                    if(capture_bad || counts[div_node]!=2*SAMPLES ||
                       sums[div_index]<MIN_MEAN*SAMPLES ||
                       sums[div_index]>MAX_MEAN*SAMPLES) begin
                        state<=IDLE; cal_busy<=0; cal_failed<=1;
                    end else begin
                        dividend<=div_numerator; divisor<=sums[div_index];
                        quotient<=0;remainder<=0;div_left<=32;state<=DIVIDE;
                    end
                end
                DIVIDE: begin
                    dividend<={dividend[30:0],1'b0};quotient<=quotient_next;remainder<=rem_next;
                    div_left<=div_left-1'b1;
                    if(div_left==1) begin
                        if(quotient_next<MIN_GAIN || quotient_next>MAX_GAIN) begin
                            state<=IDLE;cal_busy<=0;cal_failed<=1;
                        end else begin
                            pending_gain[div_index]<=quotient_next[11:0];
                            if(div_index==35) state<=READY;
                            else begin div_index<=div_index+1'b1;state<=INIT_DIV;end
                        end
                    end
                end
                READY: if(in_user) begin
                    for(i=0;i<36;i=i+1) gain[i]<=pending_gain[i];
                    map_valid<=1;cal_busy<=0;cal_failed<=0;state<=IDLE;
                end
                default: begin end
            endcase
            // A clear cancels any unfinished calibration. Commit only at SOF.
            if((clear_pending || clear_request) && in_user) begin
                for(i=0;i<36;i=i+1) gain[i]<=1024;
                map_valid<=0;cal_busy<=0;cal_failed<=0;clear_pending<=0;state<=IDLE;
            end
        end
    end

    // Coordinates -> mesh corners and fractions. Power-of-two node intervals
    // avoid per-pixel division; each of the four lanes uses its own x fraction.
    integer lane,xx,ix,iy,wx,wy,ch,corner;
    reg [39:0] raw_s0,raw_s1,raw_s2;
    reg [9:0] dest_pipe[0:4];
    reg [4:0] valid_pipe,user_pipe,last_pipe;
    reg signed [12:0] g00[0:3],g10[0:3],g01[0:3],g11[0:3];
    reg [8:0] wx_s0[0:3],wy_s0,wy_s1;
    reg signed [22:0] htop[0:3],hbot[0:3];
    reg [11:0] gain_s2[0:3];
    reg [21:0] product_s3[0:3];
    reg [39:0] corrected_s4;
    // Separate signed temporaries prevent unsigned wrap on attenuation slopes.
    reg signed [31:0] vertical_value;
    reg [22:0] rounded;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            raw_s0<=0;raw_s1<=0;raw_s2<=0; corrected_s4<=0;
            valid_pipe<=0;user_pipe<=0;last_pipe<=0;wy_s0<=0;wy_s1<=0;
            for(lane=0;lane<5;lane=lane+1) dest_pipe[lane]<=0;
            for(lane=0;lane<4;lane=lane+1) begin
                g00[lane]<=1024;g10[lane]<=1024;g01[lane]<=1024;g11[lane]<=1024;
                wx_s0[lane]<=0;htop[lane]<=262144;hbot[lane]<=262144;
                gain_s2[lane]<=1024;product_s3[lane]<=0;
            end
        end else begin
            valid_pipe<={valid_pipe[3:0],in_valid};
            user_pipe<={user_pipe[3:0],in_user};
            last_pipe<={last_pipe[3:0],in_last};
            dest_pipe[0]<=in_dest;
            for(lane=1;lane<5;lane=lane+1) dest_pipe[lane]<=dest_pipe[lane-1];
            raw_s0<=in_data;raw_s1<=raw_s0;raw_s2<=raw_s1;
            if(py<=Y0) begin iy=0;wy=0;end
            else if(py<Y1) begin iy=0;wy=((py-Y0)<<8)>>Y_STEP_LOG;end
            else if(py<Y2) begin iy=1;wy=((py-Y1)<<8)>>Y_STEP_LOG;end
            else begin iy=1;wy=256;end
            wy_s0<=wy;wy_s1<=wy_s0;
            for(lane=0;lane<4;lane=lane+1) begin
                xx=px+lane;
                if(xx<=X0) begin ix=0;wx=0;end
                else if(xx<X1) begin ix=0;wx=((xx-X0)<<8)>>X_STEP_LOG;end
                else if(xx<X2) begin ix=1;wx=((xx-X1)<<8)>>X_STEP_LOG;end
                else begin ix=1;wx=256;end
                ch=(py[0]?2:0)+(lane%2);corner=(iy*3+ix)*4+ch;
                // When committing at SOF, the first pixel must see the new bank too.
                if((clear_pending || clear_request) && in_user) begin
                    g00[lane]<=1024;g10[lane]<=1024;g01[lane]<=1024;g11[lane]<=1024;
                end else if(state==READY && in_user) begin
                    g00[lane]<=$signed({1'b0,pending_gain[corner]});
                    g10[lane]<=$signed({1'b0,pending_gain[corner+4]});
                    g01[lane]<=$signed({1'b0,pending_gain[corner+12]});
                    g11[lane]<=$signed({1'b0,pending_gain[corner+16]});
                end else begin
                    g00[lane]<=$signed({1'b0,gain[corner]});g10[lane]<=$signed({1'b0,gain[corner+4]});
                    g01[lane]<=$signed({1'b0,gain[corner+12]});g11[lane]<=$signed({1'b0,gain[corner+16]});
                end
                wx_s0[lane]<=wx;
                htop[lane]<=($signed(g00[lane])<<<8)+
                            ($signed(g10[lane]-g00[lane])*$signed({1'b0,wx_s0[lane]}));
                hbot[lane]<=($signed(g01[lane])<<<8)+
                            ($signed(g11[lane]-g01[lane])*$signed({1'b0,wx_s0[lane]}));
                vertical_value=($signed(htop[lane])<<<8)+
                               (($signed(hbot[lane]-htop[lane]))*$signed({1'b0,wy_s1}));
                gain_s2[lane]<=(vertical_value+32768)>>>16;
                product_s3[lane]<=subtract_black(raw_s2[lane*10+:10])*gain_s2[lane];
                rounded={1'b0,product_s3[lane]}+512+(BLACK_LEVEL<<10);
                if(rounded>=1048576) corrected_s4[lane*10+:10]<=1023;
                else corrected_s4[lane*10+:10]<=rounded[19:10];
            end
        end
    end
    assign out_valid=valid_pipe[4];assign out_user=user_pipe[4];assign out_last=last_pipe[4];
    assign out_dest=dest_pipe[4];assign out_data=corrected_s4;
endmodule

// Dedicated board KEY3/KEY4, active-low, synchronized in the RAW clock domain.
// Hold >=120 SOF pulses (~2 s at 60 fps), then RELEASE to request an operation.
// One request per press; no reuse or alteration of the existing gain buttons.
module lsc_cal_keys #(parameter integer HOLD_FRAMES=120)(
    input wire clk,rst_n,frame_start,cal_key_n,clear_key_n,
    output reg cal_request,clear_request
);
    (* async_reg="true" *) reg [1:0] cal_sync,clear_sync;
    reg [7:0] cal_count,clear_count;
    reg cal_was_down,clear_was_down;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cal_sync<=3;clear_sync<=3;cal_count<=0;clear_count<=0;
            cal_was_down<=0;clear_was_down<=0;cal_request<=0;clear_request<=0;
        end else begin
            cal_sync<={cal_sync[0],cal_key_n};clear_sync<={clear_sync[0],clear_key_n};
            cal_request<=0;clear_request<=0;
            cal_was_down<=!cal_sync[1];clear_was_down<=!clear_sync[1];
            if(!cal_sync[1]) begin
                if(frame_start && cal_count<HOLD_FRAMES) cal_count<=cal_count+1'b1;
            end else begin
                if(cal_was_down && cal_count>=HOLD_FRAMES) cal_request<=1;
                cal_count<=0;
            end
            if(!clear_sync[1]) begin
                if(frame_start && clear_count<HOLD_FRAMES) clear_count<=clear_count+1'b1;
            end else begin
                if(clear_was_down && clear_count>=HOLD_FRAMES) clear_request<=1;
                clear_count<=0;
            end
        end
    end
endmodule

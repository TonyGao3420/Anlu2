// One corrected camera stream feeds both ROI and display.
// Raster coordinates are reconstructed from VS/DE, independent of mixer's
// one-pixel SOF coordinate convention. Never modifies DDR request timing.
// Camera RGB is registered alongside mixer RGB, before OSD composition.
module baseline_scene_color_stream #(
    parameter integer W=1280,H=720,RGB_SHADING_ENABLE=1,
    parameter integer POSITION_BIAS_ENABLE=0,SOURCE_ROTATE_180=0
)(
    input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,
    input wire [23:0] camera_rgb,mixed_rgb,
    output wire out_vs,out_hs,out_de,out_protect,
    output wire [23:0] display_rgb,roi_rgb,
    output wire roi_de,roi_sof,roi_last
);
    reg vs_d,armed;
    reg [11:0] x,y;
    reg [7:0] protect_pipe,armed_pipe,sof_pipe,last_pipe;
    reg [23:0] mixed_pipe[0:7];
    wire [23:0] corrected;
    wire corrected_de;
    assign out_de=corrected_de;
    assign out_protect=protect_pipe[7];
    assign display_rgb=!corrected_de?24'd0:
                       (protect_pipe[7]?mixed_pipe[7]:corrected);
    assign roi_rgb=corrected;
    assign roi_de=corrected_de && armed_pipe[7];
    assign roi_sof=sof_pipe[7];
    assign roi_last=last_pipe[7];
    generate if(POSITION_BIAS_ENABLE) begin: position_bias
    baseline_scene_position_color_bias #(.W(W),.H(H),.SOURCE_ROTATE_180(SOURCE_ROTATE_180)) corrector(
        .clk(clk),.rst_n(rst_n),.in_vs(in_vs),.in_hs(in_hs),.in_de(in_de),
        .x(x),.y(y),.in_rgb(camera_rgb),
        .out_vs(out_vs),.out_hs(out_hs),.out_de(corrected_de),.out_rgb(corrected)
    );
    end else begin: legacy_shading
    baseline_display_color_shading #(.ENABLE(RGB_SHADING_ENABLE)) corrector(
        .clk(clk),.rst_n(rst_n),.in_vs(in_vs),.in_hs(in_hs),.in_de(in_de),
        .in_protect(1'b0),.x(x),.y(y),.in_rgb(camera_rgb),
        .out_vs(out_vs),.out_hs(out_hs),.out_de(corrected_de),
        .out_protect(),.out_rgb(corrected)
    );
    end endgenerate
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;armed<=0;x<=0;y<=0;
            protect_pipe<=0;armed_pipe<=0;sof_pipe<=0;last_pipe<=0;
            for(i=0;i<8;i=i+1) mixed_pipe[i]<=0;
        end else begin
            vs_d<=in_vs;
            // VS begins in vertical blank; all active pixels follow it.
            if(in_vs && !vs_d) begin x<=0;y<=0;armed<=1;end
            else if(in_de && armed) begin
                if(x==W-1) begin x<=0;y<=(y==H-1)?12'd0:y+1'b1;end
                else x<=x+1'b1;
            end
            protect_pipe<={protect_pipe[6:0],in_protect};
            armed_pipe<={armed_pipe[6:0],armed};
            sof_pipe<={sof_pipe[6:0],in_de && armed && x==0 && y==0};
            last_pipe<={last_pipe[6:0],in_de && armed && x==W-1};
            mixed_pipe[0]<=mixed_rgb;
            for(i=1;i<8;i=i+1) mixed_pipe[i]<=mixed_pipe[i-1];
        end
    end
endmodule

// Eight clocks, reusing the formerly bypassed shared stage. No extra video delay.
// Existing sensor-coordinate residual gains are applied ONCE to both consumers.
// New residual offsets use UPRIGHT SCREEN coordinates, never rotated twice:
// top 256 rows: R -0..16; lower-right ramp: R -0..12, B -0..24.
// Only adds/shifts/comparisons are added; no new DSP, ERAM or frame buffer.
// Near-neutral inputs retain min(original channel,G) as a floor, preventing
// edge gains/offsets from manufacturing saturated green out of white/gray.
module baseline_scene_position_color_bias #(
    parameter integer W=1280,H=720,SOURCE_ROTATE_180=0
)(input wire clk,rst_n,in_vs,in_hs,in_de,
  input wire [11:0] x,y,input wire [23:0] in_rgb,
  output wire out_vs,out_hs,out_de,output reg [23:0] out_rgb);
    wire [23:0] edge_rgb;
    display_edge_color #(.W(W),.H(H),.SOURCE_ROTATE_180(SOURCE_ROTATE_180)) perimeter(
        .clk(clk),.rst_n(rst_n),.in_vs(in_vs),.in_hs(in_hs),.in_de(in_de),
        .in_protect(1'b0),.in_rgb(in_rgb),.out_vs(),.out_hs(),.out_de(),
        .out_protect(),.out_rgb(edge_rgb));
    wire [8:0] tw=(y<256)?(12'd256-y):9'd0;
    wire [8:0] xw=(x<=W/2)?9'd0:((x>=W/2+512)?9'd256:((x-W/2)>>1));
    wire [8:0] yw=(y<=H/2)?9'd0:((y>=H/2+256)?9'd256:(y-H/2));
    wire [8:0] cw=(xw<yw)?xw:yw;
    wire [10:0] triple={2'b0,cw}+{1'b0,cw,1'b0};
    wire [5:0] rbias=(tw>>4)+(triple>>6);
    wire [5:0] bbias=triple>>5;
    wire [7:0] rgmax=(in_rgb[23:16]>in_rgb[15:8])?in_rgb[23:16]:in_rgb[15:8];
    wire [7:0] rgmin=(in_rgb[23:16]<in_rgb[15:8])?in_rgb[23:16]:in_rgb[15:8];
    wire [7:0] maximum=(rgmax>in_rgb[7:0])?rgmax:in_rgb[7:0];
    wire [7:0] minimum=(rgmin<in_rgb[7:0])?rgmin:in_rgb[7:0];
    wire neutral=(maximum-minimum)<=(maximum>>2);
    reg [7:0] vp,hp,dp;
    reg [5:0] rp[0:5],bp[0:5];
    reg [7:0] rf[0:5],bf[0:5];
    reg [5:0] np;
    reg [23:0] rgb7;
    wire [7:0] rtrim,btrim;
    function [7:0] subtract_bias;
        input [7:0] value;input [5:0] bias;
        begin
            if(value<=14) subtract_bias=value;
            else if({1'b0,value}>(9'd14+{3'b0,bias})) subtract_bias=value-bias;
            else subtract_bias=14;
        end
    endfunction
    assign rtrim=subtract_bias(edge_rgb[23:16],rp[5]);
    assign btrim=subtract_bias(edge_rgb[7:0],bp[5]);
    assign out_vs=vp[7];assign out_hs=hp[7];assign out_de=dp[7];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vp<=0;hp<=0;dp<=0;np<=0;rgb7<=0;out_rgb<=0;
            for(i=0;i<6;i=i+1)begin rp[i]<=0;bp[i]<=0;rf[i]<=0;bf[i]<=0;end
        end else begin
            vp<={vp[6:0],in_vs};hp<={hp[6:0],in_hs};dp<={dp[6:0],in_de};
            rp[0]<=rbias;bp[0]<=bbias;np<={np[4:0],neutral};
            rf[0]<=(in_rgb[23:16]<in_rgb[15:8])?in_rgb[23:16]:in_rgb[15:8];
            bf[0]<=(in_rgb[7:0]<in_rgb[15:8])?in_rgb[7:0]:in_rgb[15:8];
            for(i=1;i<6;i=i+1)begin rp[i]<=rp[i-1];bp[i]<=bp[i-1];rf[i]<=rf[i-1];bf[i]<=bf[i-1];end
            rgb7<={(np[5] && rtrim<rf[5])?rf[5]:rtrim,edge_rgb[15:8],
                   (np[5] && btrim<bf[5])?bf[5]:btrim};
            out_rgb<=dp[6]?rgb7:24'd0;
        end
    end
endmodule

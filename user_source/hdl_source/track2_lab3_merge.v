// ================================================================
// track2_lab3_merge.v
// ---------------------------------------------------------------
// Track2 algorithm extension for the SC520 official Lab3 project.
// Responsibilities:
//   - ROI-based target detection
//   - centroid / bbox / area calculation
//   - self-check status
//   - bbox overlay on video output
// ================================================================

`timescale 1ns / 1ps

module track2_lab3_merge (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        video_vsync,
    input  wire        video_hsync,
    input  wire        video_de,
    input  wire [23:0] video_pixel,

    output reg         out_vsync,
    output reg         out_hsync,
    output reg         out_de,
    output reg  [23:0] out_pixel,

    output reg         track_valid,
    output reg [15:0] bbox_x0,
    output reg [15:0] bbox_y0,
    output reg [15:0] bbox_x1,
    output reg [15:0] bbox_y1,
    output reg [15:0] centroid_x,
    output reg [15:0] centroid_y,
    output reg [15:0] target_area,
    output reg         roi_valid,
    output reg         color_match_ok,
    output reg         bbox_drawn,
    output reg         selfcheck_ok,
    output reg [3:0]  selfcheck_status
);

    reg [15:0] x_cnt;
    reg [15:0] y_cnt;
    reg [31:0] sum_x;
    reg [31:0] sum_y;
    reg [31:0] pix_count;
    reg [15:0] min_x, min_y;
    reg [15:0] max_x, max_y;
    reg        roi_valid_i;
    reg        color_match_ok_i;

    wire [7:0] r = video_pixel[23:16];
    wire [7:0] g = video_pixel[15:8];
    wire [7:0] b = video_pixel[7:0];
    wire target_pixel = (r >= 8'd80) && (g <= 8'd160) && (b <= 8'd160);

    localparam ROI_X0 = 16'd160;
    localparam ROI_Y0 = 16'd120;
    localparam ROI_X1 = 16'd1120;
    localparam ROI_Y1 = 16'd520;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= 0; y_cnt <= 0;
            sum_x <= 0; sum_y <= 0; pix_count <= 0;
            min_x <= 16'hFFFF; min_y <= 16'hFFFF;
            max_x <= 0; max_y <= 0;
            roi_valid_i <= 1'b0;
            color_match_ok_i <= 1'b0;
            track_valid <= 1'b0;
            bbox_x0 <= 0; bbox_y0 <= 0; bbox_x1 <= 0; bbox_y1 <= 0;
            centroid_x <= 0; centroid_y <= 0; target_area <= 0;
            roi_valid <= 1'b0; color_match_ok <= 1'b0;
            bbox_drawn <= 1'b0; selfcheck_ok <= 1'b0; selfcheck_status <= 4'd0;
            out_vsync <= 0; out_hsync <= 0; out_de <= 0; out_pixel <= 24'd0;
        end else begin
            out_vsync <= video_vsync;
            out_hsync <= video_hsync;
            out_de <= video_de;

            if (video_vsync == 1'b0) begin
                x_cnt <= 0; y_cnt <= 0;
                sum_x <= 0; sum_y <= 0; pix_count <= 0;
                min_x <= 16'hFFFF; min_y <= 16'hFFFF;
                max_x <= 0; max_y <= 0;
                roi_valid_i <= 1'b0;
                color_match_ok_i <= 1'b0;
                track_valid <= 1'b0;
                bbox_x0 <= 0; bbox_y0 <= 0; bbox_x1 <= 0; bbox_y1 <= 0;
                centroid_x <= 0; centroid_y <= 0; target_area <= 0;
                roi_valid <= 1'b0; color_match_ok <= 1'b0;
                bbox_drawn <= 1'b0; selfcheck_ok <= 1'b0; selfcheck_status <= 4'd0;
            end else if (video_de) begin
                if (target_pixel && (x_cnt >= ROI_X0) && (x_cnt <= ROI_X1) &&
                    (y_cnt >= ROI_Y0) && (y_cnt <= ROI_Y1)) begin
                    sum_x <= sum_x + x_cnt;
                    sum_y <= sum_y + y_cnt;
                    pix_count <= pix_count + 32'd1;
                    if (x_cnt < min_x) min_x <= x_cnt;
                    if (y_cnt < min_y) min_y <= y_cnt;
                    if (x_cnt > max_x) max_x <= x_cnt;
                    if (y_cnt > max_y) max_y <= y_cnt;
                    roi_valid_i <= 1'b1;
                end else begin
                    roi_valid_i <= 1'b0;
                end

                color_match_ok_i <= target_pixel;

                if (x_cnt == 16'd1279) begin
                    x_cnt <= 0;
                    y_cnt <= y_cnt + 1;
                end else begin
                    x_cnt <= x_cnt + 1;
                end
            end

            if (pix_count >= 32'd64 && pix_count <= 32'd20000 && roi_valid_i) begin
                bbox_x0 <= min_x;
                bbox_y0 <= min_y;
                bbox_x1 <= max_x;
                bbox_y1 <= max_y;
                centroid_x <= sum_x / pix_count;
                centroid_y <= sum_y / pix_count;
                target_area <= pix_count[15:0];
                track_valid <= 1'b1;
            end else begin
                bbox_x0 <= 0; bbox_y0 <= 0; bbox_x1 <= 0; bbox_y1 <= 0;
                centroid_x <= 0; centroid_y <= 0; target_area <= 0;
                track_valid <= 1'b0;
            end

            roi_valid <= roi_valid_i;
            color_match_ok <= color_match_ok_i;

            if (track_valid && (bbox_x1 > bbox_x0) && (bbox_y1 > bbox_y0)) begin
                selfcheck_ok <= 1'b1;
                selfcheck_status <= 4'd1;
            end else begin
                selfcheck_ok <= 1'b0;
                selfcheck_status <= 4'd0;
            end

            if (video_de) begin
                if ((x_cnt >= bbox_x0 && x_cnt <= bbox_x1 && (y_cnt == bbox_y0 || y_cnt == bbox_y1)) ||
                    (y_cnt >= bbox_y0 && y_cnt <= bbox_y1 && (x_cnt == bbox_x0 || x_cnt == bbox_x1))) begin
                    out_pixel <= 24'hFF0000;
                    bbox_drawn <= 1'b1;
                end else begin
                    out_pixel <= video_pixel;
                    bbox_drawn <= 1'b0;
                end
            end else begin
                out_pixel <= 24'd0;
            end
        end
    end

endmodule

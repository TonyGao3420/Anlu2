// 单目标红色检测器：在显示像素时钟域统计红色区域的边界和质心。
// 输入直接旁路观察 DDR 读出的 RGB/DE，不对官方视频通路施加反压或修改像素。
// 红色判定允许有限的绿偏容差；每帧全屏搜索，边界随红色像素实际范围变化。
// 当前输出为轴对齐矩形外接框；本模块依赖画面中只有一个主要红色目标，不做连通域分割。
module roi_target_tracker #(
    parameter integer IMG_W = 1280,
    parameter integer IMG_H = 720,
    parameter integer ROI_HALF_W = 320,
    parameter integer ROI_HALF_H = 180,
    parameter integer ROI_MIN_HALF_W = 96,
    parameter integer ROI_MIN_HALF_H = 72,
    parameter integer ROI_MARGIN_X = 48,
    parameter integer ROI_MARGIN_Y = 32,
    parameter integer MIN_VALUE = 24,
    parameter integer MIN_AREA = 128,
    parameter integer MAX_AREA = 120000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_frame_start,
    input  wire        in_de,
    input  wire        in_line_last,
    input  wire [23:0] in_rgb,

    output reg         target_valid,
    output reg [15:0]  bbox_x0,
    output reg [15:0]  bbox_y0,
    output reg [15:0]  bbox_x1,
    output reg [15:0]  bbox_y1,
    output reg [15:0]  centroid_x,
    output reg [15:0]  centroid_y,
    output reg [19:0]  target_area,
    output reg         frame_done,
    // Pulses only after the valid centroid is ready (or a miss is confirmed).
    output reg         result_update,
    output wire        mask_valid,
    output wire        red_mask,
    output wire [11:0]  mask_x,
    output wire [11:0]  mask_y,
    output reg         dbg_roi_valid,
    output reg         dbg_color_match
);
    localparam [11:0] FRAME_CENTER_X = IMG_W / 2;
    localparam [11:0] FRAME_CENTER_Y = IMG_H / 2;

    reg [11:0] x_count, y_count;
    reg [11:0] roi_center_x, roi_center_y;
    reg [11:0] roi_half_w_live, roi_half_h_live;
    reg        full_frame_search;

    reg [11:0] x_pipe;
    reg [11:0] y_pipe;
    reg [11:0] x_match_pipe;
    reg [11:0] y_match_pipe;
    reg [23:0] rgb_pipe;
    reg        roi_pipe;
    reg        de_pipe;
    reg        match_pipe;

    reg [31:0] sum_x;
    reg [31:0] sum_y;
    reg [19:0] pixel_count;
    reg [11:0] min_x, min_y, max_x, max_y;

    // 3x3 majority filter for red-mask cleanup. Two one-bit line stores keep
    // the detector streaming at one pixel per clock with modest memory cost.
    reg [IMG_W-1:0] mask_line_1;
    reg [IMG_W-1:0] mask_line_2;
    reg mask_top_x1, mask_top_x2;
    reg mask_mid_x1, mask_mid_x2;
    reg mask_bot_x1, mask_bot_x2;

    // RGB-to-HSV red-sector approximation. The wider hue allowance and lower
    // chroma floor accept faded reds and center-shifted reds while 3x3 cleanup
    // plus the frame-level area/occupancy checks reject isolated color noise.
    wire [7:0] green_blue_min = (rgb_pipe[15:8] < rgb_pipe[7:0])
                                ? rgb_pipe[15:8] : rgb_pipe[7:0];
    wire [7:0] green_blue_diff = (rgb_pipe[15:8] < rgb_pipe[7:0])
                                 ? (rgb_pipe[7:0] - rgb_pipe[15:8])
                                 : (rgb_pipe[15:8] - rgb_pipe[7:0]);
    wire [7:0] red_chroma = (rgb_pipe[23:16] > green_blue_min)
                            ? (rgb_pipe[23:16] - green_blue_min) : 8'd0;
    // A small channel margin accommodates the observed green cast near screen
    // center without treating neutral gray as red (the chroma floor rejects it).
    wire [8:0] red_with_margin = {1'b0, rgb_pipe[23:16]} + 9'd20;
    wire [8:0] blue_with_margin = {1'b0, rgb_pipe[7:0]} + 9'd12;
    wire red_is_max = (red_with_margin >= {1'b0, rgb_pipe[15:8]}) &&
                      (red_with_margin >= {1'b0, rgb_pipe[7:0]}) &&
                      ({1'b0, rgb_pipe[23:16]} >= blue_with_margin);
    wire [8:0] red_hue_tolerance = {1'b0, red_chroma} -
                                   ({1'b0, red_chroma} >> 3) + 9'd32;
    wire red_hue_match = red_is_max &&
                         ({1'b0, green_blue_diff} <= red_hue_tolerance);
    // Lower floors recover dim and partially desaturated red regions.
    wire red_sat_match = (red_chroma >= 8'd8) &&
                         (red_chroma >= (rgb_pipe[23:16] >> 4));
    wire red_value_match = rgb_pipe[23:16] >= MIN_VALUE;
    wire hsv_red_match = red_hue_match && red_sat_match && red_value_match;

    wire [11:0] dx = (x_count >= roi_center_x)
                     ? (x_count - roi_center_x) : (roi_center_x - x_count);
    wire [11:0] dy = (y_count >= roi_center_y)
                     ? (y_count - roi_center_y) : (roi_center_y - y_count);
    // The pixel stream is already a one-pixel-per-clock hardware pipeline.
    // Search the complete frame every time to avoid losing a target after
    // sudden motion or a temporary color shift; the reported box remains tight.
    wire in_roi = 1'b1;

    // Tighten the following-frame search window around the measured object.
    // Its extent follows the detected red pixels, with a motion margin and
    // conservative limits so moderate inter-frame movement remains in view.
    wire [12:0] bbox_width = {1'b0, max_x} - {1'b0, min_x} + 13'd1;
    wire [12:0] bbox_height = {1'b0, max_y} - {1'b0, min_y} + 13'd1;
    wire [12:0] roi_half_w_candidate = (bbox_width >> 1) + ROI_MARGIN_X;
    wire [12:0] roi_half_h_candidate = (bbox_height >> 1) + ROI_MARGIN_Y;

    // Keep frame acceptance comparable to the first working rectangle-box
    // version: judge the filtered red-pixel count, not red-pixel density in
    // the bounding rectangle. Density is not the same as red coverage of the
    // physical object and rejected many legitimate hollow/irregular objects.
    wire frame_candidate_valid = (pixel_count >= MIN_AREA) &&
                                 (pixel_count <= MAX_AREA);

    // Iterative restoring divider; two coordinates share one 32-cycle datapath.
    reg        div_busy;
    reg        div_y_phase;
    reg [5:0]  div_iterations;
    reg [31:0] div_dividend;
    reg [19:0] div_divisor;
    reg [31:0] div_sum_y_hold;
    reg [19:0] div_count_hold;
    reg [31:0] div_quotient;
    reg [20:0] div_remainder;
    wire [20:0] div_remainder_shift = {div_remainder[19:0], div_dividend[31]};
    wire        div_subtract = div_remainder_shift >= {1'b0, div_divisor};
    wire [20:0] div_remainder_next = div_subtract
                                     ? div_remainder_shift - {1'b0, div_divisor}
                                     : div_remainder_shift;
    wire [31:0] div_quotient_next = {div_quotient[30:0], div_subtract};

    wire mask_top_now = (y_match_pipe >= 2) ? mask_line_2[x_match_pipe] : 1'b0;
    wire mask_mid_now = (y_match_pipe >= 1) ? mask_line_1[x_match_pipe] : 1'b0;
    wire [3:0] red_neighborhood_count =
        {3'd0, mask_top_x2} + {3'd0, mask_top_x1} + {3'd0, mask_top_now} +
        {3'd0, mask_mid_x2} + {3'd0, mask_mid_x1} + {3'd0, mask_mid_now} +
        {3'd0, mask_bot_x2} + {3'd0, mask_bot_x1} + {3'd0, match_pipe};
    wire filtered_pixel_valid = de_pipe && (x_match_pipe >= 1) && (y_match_pipe >= 1);
    wire filtered_red_pixel = filtered_pixel_valid && mask_mid_x1 &&
                              (red_neighborhood_count >= 3);
    wire [11:0] filtered_x = x_match_pipe - 12'd1;
    wire [11:0] filtered_y = y_match_pipe - 12'd1;

    // Expose the denoised one-pixel-per-clock mask to the silhouette stage.
    assign mask_valid = filtered_pixel_valid;
    assign red_mask   = filtered_red_pixel;
    assign mask_x     = filtered_x;
    assign mask_y     = filtered_y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_count            <= 12'd0;
            y_count            <= 12'd0;
            roi_center_x       <= FRAME_CENTER_X;
            roi_center_y       <= FRAME_CENTER_Y;
            roi_half_w_live    <= ROI_HALF_W;
            roi_half_h_live    <= ROI_HALF_H;
            // Acquire a target anywhere in the first frame after reset. Once a
            // candidate is confirmed, later frames use the adaptive tracking ROI.
            full_frame_search <= 1'b1;
            x_pipe             <= 12'd0;
            y_pipe             <= 12'd0;
            x_match_pipe       <= 12'd0;
            y_match_pipe       <= 12'd0;
            rgb_pipe           <= 24'd0;
            roi_pipe           <= 1'b0;
            de_pipe            <= 1'b0;
            match_pipe         <= 1'b0;
            sum_x              <= 32'd0;
            sum_y              <= 32'd0;
            pixel_count        <= 20'd0;
            min_x              <= 12'hfff;
            min_y              <= 12'hfff;
            max_x              <= 12'd0;
            max_y              <= 12'd0;
            mask_top_x1        <= 1'b0;
            mask_top_x2        <= 1'b0;
            mask_mid_x1        <= 1'b0;
            mask_mid_x2        <= 1'b0;
            mask_bot_x1        <= 1'b0;
            mask_bot_x2        <= 1'b0;
            target_valid       <= 1'b0;
            bbox_x0            <= 16'd0;
            bbox_y0            <= 16'd0;
            bbox_x1            <= 16'd0;
            bbox_y1            <= 16'd0;
            centroid_x         <= 16'd0;
            centroid_y         <= 16'd0;
            target_area        <= 20'd0;
            frame_done         <= 1'b0;
            result_update     <= 1'b0;
            dbg_roi_valid      <= 1'b0;
            dbg_color_match    <= 1'b0;
            div_busy           <= 1'b0;
            div_y_phase        <= 1'b0;
            div_iterations     <= 6'd0;
            div_dividend       <= 32'd0;
            div_divisor        <= 20'd1;
            div_sum_y_hold     <= 32'd0;
            div_count_hold     <= 20'd1;
            div_quotient       <= 32'd0;
            div_remainder      <= 21'd0;
        end else begin
            frame_done      <= 1'b0;
            result_update  <= 1'b0;
            dbg_roi_valid   <= in_de && in_roi;
            dbg_color_match <= filtered_red_pixel;

            // Keep the mask neighborhood aligned with the threshold pipeline.
            if (de_pipe) begin
                if (x_match_pipe == 0) begin
                    mask_top_x1 <= mask_top_now;
                    mask_top_x2 <= 1'b0;
                    mask_mid_x1 <= mask_mid_now;
                    mask_mid_x2 <= 1'b0;
                    mask_bot_x1 <= match_pipe;
                    mask_bot_x2 <= 1'b0;
                end else begin
                    mask_top_x2 <= mask_top_x1;
                    mask_top_x1 <= mask_top_now;
                    mask_mid_x2 <= mask_mid_x1;
                    mask_mid_x1 <= mask_mid_now;
                    mask_bot_x2 <= mask_bot_x1;
                    mask_bot_x1 <= match_pipe;
                end

                if (y_match_pipe == 0) begin
                    mask_line_2[x_match_pipe] <= 1'b0;
                    mask_line_1[x_match_pipe] <= match_pipe;
                end else begin
                    mask_line_2[x_match_pipe] <= mask_line_1[x_match_pipe];
                    mask_line_1[x_match_pipe] <= match_pipe;
                end
            end

            // Coordinates use the same frame-start, active-pixel and line-last
            // signals as hdmi_mixer, keeping the detection tap aligned to its RGB.
            if (in_frame_start) begin
                x_count <= 12'd0;
                y_count <= 12'd0;
            end else if (in_de) begin
                if (in_line_last) begin
                    x_count <= 12'd0;
                    if (y_count < IMG_H - 1) y_count <= y_count + 12'd1;
                end else if (x_count < IMG_W - 1) begin
                    x_count <= x_count + 12'd1;
                end
            end

            // Detection-only pipeline. It never stalls or alters display data.
            x_pipe     <= x_count;
            y_pipe     <= y_count;
            rgb_pipe   <= in_rgb;
            roi_pipe   <= in_roi;
            de_pipe    <= in_de;
            x_match_pipe <= x_pipe;
            y_match_pipe <= y_pipe;
            match_pipe <= de_pipe && roi_pipe && hsv_red_match;

            if (filtered_red_pixel) begin
                sum_x       <= sum_x + filtered_x;
                sum_y       <= sum_y + filtered_y;
                pixel_count <= pixel_count + 20'd1;
                if (filtered_x < min_x) min_x <= filtered_x;
                if (filtered_y < min_y) min_y <= filtered_y;
                if (filtered_x > max_x) max_x <= filtered_x;
                if (filtered_y > max_y) max_y <= filtered_y;
            end

            // At frame start, publish the completed frame and begin collecting
            // the next one. The long vertical blank leaves ample time for centroid.
            if (in_frame_start) begin
                frame_done <= 1'b1;
                target_valid <= frame_candidate_valid;
                if (frame_candidate_valid) begin
                    bbox_x0     <= {4'd0, min_x};
                    bbox_y0     <= {4'd0, min_y};
                    bbox_x1     <= {4'd0, max_x};
                    bbox_y1     <= {4'd0, max_y};
                    target_area <= pixel_count;
                    div_busy       <= 1'b1;
                    div_y_phase    <= 1'b0;
                    div_iterations <= 6'd32;
                    div_dividend   <= sum_x;
                    div_divisor    <= pixel_count;
                    div_sum_y_hold <= sum_y;
                    div_count_hold <= pixel_count;
                    div_quotient   <= 32'd0;
                    div_remainder  <= 21'd0;
                    full_frame_search <= 1'b0;
                    if (roi_half_w_candidate < ROI_MIN_HALF_W)
                        roi_half_w_live <= ROI_MIN_HALF_W;
                    else if (roi_half_w_candidate > ROI_HALF_W)
                        roi_half_w_live <= ROI_HALF_W;
                    else
                        roi_half_w_live <= roi_half_w_candidate[11:0];
                    if (roi_half_h_candidate < ROI_MIN_HALF_H)
                        roi_half_h_live <= ROI_MIN_HALF_H;
                    else if (roi_half_h_candidate > ROI_HALF_H)
                        roi_half_h_live <= ROI_HALF_H;
                    else
                        roi_half_h_live <= roi_half_h_candidate[11:0];
                end else begin
                    bbox_x0            <= 16'd0;
                    bbox_y0            <= 16'd0;
                    bbox_x1            <= 16'd0;
                    bbox_y1            <= 16'd0;
                    centroid_x         <= 16'd0;
                    centroid_y         <= 16'd0;
                    target_area        <= 20'd0;
                    div_busy           <= 1'b0;
                    full_frame_search <= 1'b1;
                    roi_half_w_live    <= ROI_HALF_W;
                    roi_half_h_live    <= ROI_HALF_H;
                    result_update     <= 1'b1;
                end
                sum_x       <= 32'd0;
                sum_y       <= 32'd0;
                pixel_count <= 20'd0;
                min_x       <= 12'hfff;
                min_y       <= 12'hfff;
                max_x       <= 12'd0;
                max_y       <= 12'd0;
            end

            if (div_busy) begin
                div_dividend  <= {div_dividend[30:0], 1'b0};
                div_remainder <= div_remainder_next;
                div_quotient  <= div_quotient_next;
                if (div_iterations == 6'd1) begin
                    if (!div_y_phase) begin
                        centroid_x     <= {4'd0, div_quotient_next[11:0]};
                        div_y_phase    <= 1'b1;
                        div_iterations <= 6'd32;
                        div_dividend   <= div_sum_y_hold;
                        div_divisor    <= div_count_hold;
                        div_quotient   <= 32'd0;
                        div_remainder  <= 21'd0;
                    end else begin
                        centroid_y    <= {4'd0, div_quotient_next[11:0]};
                        roi_center_x  <= centroid_x[11:0];
                        roi_center_y  <= div_quotient_next[11:0];
                        div_busy      <= 1'b0;
                        result_update <= 1'b1;
                    end
                end else begin
                    div_iterations <= div_iterations - 6'd1;
                end
            end
        end
    end
endmodule

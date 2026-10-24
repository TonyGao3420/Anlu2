// 3x3 二值掩码轮廓提取器。
// 两条1-bit行缓存提供上下邻域；每个有效像素每拍处理，不改变DDR/HDMI握手。
// 输出对应3x3窗口中心像素的轮廓标记：中心为红色且邻域不全为红色。
module red_mask_contour #(
    parameter integer IMG_W = 1280
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [11:0] in_x,
    input  wire [11:0] in_y,
    input  wire        in_mask,
    output wire        out_contour
);
    // No reset is applied to these line memories. The first image row clears
    // the older-row state as it is written, avoiding a large reset network.
    reg [IMG_W-1:0] line_1;
    reg [IMG_W-1:0] line_2;

    reg top_x1, top_x2;
    reg mid_x1, mid_x2;
    reg bot_x1, bot_x2;

    wire top_now = (in_y >= 2) ? line_2[in_x] : 1'b0;
    wire mid_now = (in_y >= 1) ? line_1[in_x] : 1'b0;
    wire bot_now = in_mask;

    wire center_pixel = mid_x1;
    wire all_window_pixels =
        top_x2 & top_x1 & top_now &
        mid_x2 & mid_x1 & mid_now &
        bot_x2 & bot_x1 & bot_now;
    wire window_ready = (in_x >= 1) && (in_y >= 1);
    // The stream has already advanced to the bottom-right sample needed by
    // this neighborhood. The pulse is combinational to avoid another cycle.
    assign out_contour = in_valid && window_ready &&
                         center_pixel && !all_window_pixels;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_x1     <= 1'b0;
            top_x2     <= 1'b0;
            mid_x1     <= 1'b0;
            mid_x2     <= 1'b0;
            bot_x1     <= 1'b0;
            bot_x2     <= 1'b0;
        end else begin
            if (in_valid) begin
                if (in_x == 0) begin
                    top_x1 <= top_now;
                    top_x2 <= 1'b0;
                    mid_x1 <= mid_now;
                    mid_x2 <= 1'b0;
                    bot_x1 <= bot_now;
                    bot_x2 <= 1'b0;
                end else begin
                    top_x2 <= top_x1;
                    top_x1 <= top_now;
                    mid_x2 <= mid_x1;
                    mid_x1 <= mid_now;
                    bot_x2 <= bot_x1;
                    bot_x1 <= bot_now;
                end

                if (in_y == 0) begin
                    line_2[in_x] <= 1'b0;
                    line_1[in_x] <= in_mask;
                end else begin
                    line_2[in_x] <= line_1[in_x];
                    line_1[in_x] <= in_mask;
                end

            end
        end
    end
endmodule

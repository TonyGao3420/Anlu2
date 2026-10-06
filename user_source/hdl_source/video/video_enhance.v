// Anlu2 源码说明：对显示RGB做黑白场扩展、饱和度调整、限幅水平锐化和gamma提亮。
// 接口与使用约定：六级流水；同步与RGB严格等延迟。DE边界复制邻居，OSD及测试图可保护。
// 工程状态：已列入TD编译清单。

// Anlu2 视频显示增强：六级流水，输入/输出均为每拍一个 RGB888 像素。
// clk=HDMI 像素时钟；rst_n=低有效复位。VS/HS/DE 与 RGB 一起延迟。
// 依次做黑白场伸展、限幅锐化、色度饱和度增强和全画面一致的gamma；不启用空间色偏补偿。
// protect 用于 OSD/测试图：原样输出并隔离邻接像素，避免文字边缘光晕。
// 左右边界复制中心像素；DE=0 清除邻域，绝不跨行取样。
// ENABLE=0 仍保持同样的流水延迟，可直接进行同场景 A/B 对比。
module video_enhance #(
    parameter integer ENABLE = 1,
    parameter integer GAMMA_ENABLE = 1,
    parameter integer SHARPEN_ENABLE = 1,
    parameter integer CONTRAST_ENABLE = 1,
    parameter integer SATURATION_ENABLE = 1,
    parameter integer BLACK_LEVEL = 12,
    parameter integer WHITE_LEVEL = 238,
    parameter integer SATURATION_Q8 = 320,
    parameter integer DETAIL_LIMIT = 12,
    parameter integer NOISE_THRESHOLD = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_vsync,
    input  wire        in_hsync,
    input  wire        in_de,
    input  wire        in_protect,
    input  wire [23:0] in_rgb,
    output reg         out_vsync,
    output reg         out_hsync,
    output reg         out_de,
    output reg  [23:0] out_rgb
);
    // 黑白场增益在 elaboration 阶段计算，像素路径只包含常量乘法与移位。
    localparam integer CONTRAST_GAIN_Q8 =
        (255 * 256 + ((WHITE_LEVEL - BLACK_LEVEL) / 2)) / (WHITE_LEVEL - BLACK_LEVEL);

    // 第一级保留原始像素及控制信号，避免复杂色彩运算直接落在输入路径。
    reg [23:0] center_raw, left_raw;
    reg center_de, center_vs, center_hs, center_protect;
    reg left_protect;
    // 后续分开执行对比度、饱和度、锐化和gamma，避免单拍堆叠长算术链。
    reg [23:0] contrast_left_rgb, contrast_center_rgb, contrast_right_rgb;
    reg contrast_de, contrast_vs, contrast_hs;
    reg contrast_left_protect, contrast_center_protect, contrast_right_protect;
    reg [23:0] prep_left_rgb, prep_center_rgb, prep_right_rgb;
    reg prep_de, prep_vs, prep_hs, prep_protect;
    reg [23:0] sharp_rgb, grade_rgb;
    reg sharp_de, sharp_vs, sharp_hs, sharp_protect;
    reg grade_de, grade_vs, grade_hs, grade_protect;

    // 有符号计算防止暗部减法下溢；最大修正幅度为 +/- DETAIL_LIMIT。
    // c + (2*c-l-r)/4 相当于轻量反锐化，不增加曝光时间或传感器噪声。
    // 黑白场扩展只在显示支路执行，降低发灰感；阈值参数可按实机光照调整。
    function [7:0] contrast_channel;
        input [7:0] value;
        integer scaled;
        begin
            if (value <= BLACK_LEVEL) contrast_channel = 8'd0;
            else if (value >= WHITE_LEVEL) contrast_channel = 8'd255;
            else begin
                scaled = ((value - BLACK_LEVEL) * CONTRAST_GAIN_Q8 + 128) >> 8;
                contrast_channel = scaled[7:0];
            end
        end
    endfunction

    // 在近似亮度Y周围放大色差，灰阶的Cb/Cr为零，因此中性灰不偏色。
    function [23:0] color_grade;
        input [23:0] rgb;
        reg [9:0] y_sum;
        reg [7:0] y;
        reg signed [9:0] cb;
        reg signed [9:0] cr;
        reg signed [9:0] cb_scaled;
        reg signed [9:0] cr_scaled;
        reg signed [10:0] green_sum;
        reg signed [9:0] green_delta;
        reg signed [10:0] red_value;
        reg signed [10:0] green_value;
        reg signed [10:0] blue_value;
        begin
            // Widen G before the shift: an 8-bit shift can wrap bright greens
            // and create a luminance-dependent red/green cast.
            y_sum = {2'b00, rgb[23:16]} + ({2'b00, rgb[15:8]} << 1) +
                    {2'b00, rgb[7:0]} + 10'd2;
            y = y_sum[9:2];
            cr = $signed({1'b0, rgb[23:16]}) - $signed({1'b0, y});
            cb = $signed({1'b0, rgb[7:0]}) - $signed({1'b0, y});
            // The default 1.25x saturation uses a shift/add, avoiding wide DSP chains in the pixel path.
            if (SATURATION_Q8 == 320) begin
                cb_scaled = cb + (cb >>> 2);
                cr_scaled = cr + (cr >>> 2);
            end else begin
                cb_scaled = (cb * SATURATION_Q8) >>> 8;
                cr_scaled = (cr * SATURATION_Q8) >>> 8;
            end
            green_sum = {cr_scaled[9], cr_scaled} + {cb_scaled[9], cb_scaled};
            green_delta = green_sum >>> 1;
            red_value = $signed({3'b000, y}) + $signed({cr_scaled[9], cr_scaled});
            green_value = $signed({3'b000, y}) - $signed({green_delta[9], green_delta});
            blue_value = $signed({3'b000, y}) + $signed({cb_scaled[9], cb_scaled});
            if (red_value < 0) red_value = 0;
            else if (red_value > 255) red_value = 255;
            if (green_value < 0) green_value = 0;
            else if (green_value > 255) green_value = 255;
            if (blue_value < 0) blue_value = 0;
            else if (blue_value > 255) blue_value = 255;
            color_grade = {red_value[7:0], green_value[7:0], blue_value[7:0]};
        end
    endfunction

    function [7:0] sharpen;
        input [7:0] l, c, r;
        reg signed [10:0] lap;
        reg signed [10:0] detail;
        reg signed [10:0] value;
        begin
            lap = $signed({2'b00, c, 1'b0}) - $signed({3'b000, l}) - $signed({3'b000, r});
            if ((lap > NOISE_THRESHOLD) || (lap < -NOISE_THRESHOLD)) detail = lap / 4;
            else detail = 0;
            if (detail > DETAIL_LIMIT) detail = DETAIL_LIMIT;
            if (detail < -DETAIL_LIMIT) detail = -DETAIL_LIMIT;
            value = $signed({3'b000, c}) + detail;
            if (value < 0) sharpen = 8'd0;
            else if (value > 255) sharpen = 8'd255;
            else sharpen = value[7:0];
        end
    endfunction

    // 9 个锚点构成分段线性近似，替代每通道 256 项 case LUT。
    // 斜率用常数乘法并右移 5 位，保持暗部提亮且黑白端点精确，显著节省组合逻辑。
    function [7:0] gamma_lut;
        input [7:0] value;
        integer base;
        integer slope;
        integer offset;
        begin
            if (value < 32) begin base=0; slope=80; offset=value; end
            else if (value < 64) begin base=80; slope=38; offset=value-32; end
            else if (value < 96) begin base=118; slope=30; offset=value-64; end
            else if (value < 128) begin base=148; slope=26; offset=value-96; end
            else if (value < 160) begin base=174; slope=23; offset=value-128; end
            else if (value < 192) begin base=197; slope=21; offset=value-160; end
            else if (value < 224) begin base=218; slope=19; offset=value-192; end
            else begin base=237; slope=18; offset=value-224; end
            gamma_lut = (base + ((slope * offset + 16) >> 5) > 255)
                      ? 8'd255 : (base + ((slope * offset + 16) >> 5));
        end
    endfunction

    function [23:0] finish_display_pixel;
        input [23:0] rgb;
        reg [23:0] gamma_rgb;
        begin
            if (GAMMA_ENABLE)
                gamma_rgb = {gamma_lut(rgb[23:16]), gamma_lut(rgb[15:8]), gamma_lut(rgb[7:0])};
            else
                gamma_rgb = rgb;
            finish_display_pixel = gamma_rgb;
        end
    endfunction

    wire [23:0] left_window_raw = left_protect ? center_raw : left_raw;
    wire left_window_protect = left_protect ? center_protect : left_protect;
    wire [23:0] right_window_raw = (in_de && !in_protect) ? in_rgb : center_raw;
    wire right_window_protect = (in_de && !in_protect) ? in_protect : center_protect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            center_raw <= 0;
            left_raw <= 0;
            center_de <= 0;
            center_vs <= 0;
            center_hs <= 0;
            center_protect <= 0;
            left_protect <= 0;
            contrast_left_rgb <= 0;
            contrast_center_rgb <= 0;
            contrast_right_rgb <= 0;
            contrast_de <= 0;
            contrast_vs <= 0;
            contrast_hs <= 0;
            contrast_left_protect <= 0;
            contrast_center_protect <= 0;
            contrast_right_protect <= 0;
            prep_left_rgb <= 0;
            prep_center_rgb <= 0;
            prep_right_rgb <= 0;
            prep_de <= 0;
            prep_vs <= 0;
            prep_hs <= 0;
            prep_protect <= 0;
            sharp_rgb <= 0;
            sharp_de <= 0;
            sharp_vs <= 0;
            sharp_hs <= 0;
            sharp_protect <= 0;
            grade_rgb <= 0;
            grade_de <= 0;
            grade_vs <= 0;
            grade_hs <= 0;
            grade_protect <= 0;
            out_rgb <= 0;
            out_de <= 0;
            out_vsync <= 0;
            out_hsync <= 0;
        end else begin
            // 第一级保存原始中心和左邻居；下一拍输入作为中心的右邻居。
            center_raw <= in_rgb;
            center_de <= in_de;
            center_vs <= in_vsync;
            center_hs <= in_hsync;
            center_protect <= in_protect;
            left_raw <= (in_de && center_de) ? center_raw : in_rgb;
            left_protect <= (in_de && center_de) ? center_protect : in_protect;

            // 第二级只做黑白场伸展；消隐期及受保护邻点用中心值补边。
            contrast_de <= center_de;
            contrast_vs <= center_vs;
            contrast_hs <= center_hs;
            contrast_left_protect <= left_protect ? center_protect : left_protect;
            contrast_center_protect <= center_protect;
            contrast_right_protect <= right_window_protect;
            contrast_left_rgb <= (ENABLE && CONTRAST_ENABLE && center_de && !left_window_protect)
                               ? {contrast_channel(left_window_raw[23:16]), contrast_channel(left_window_raw[15:8]), contrast_channel(left_window_raw[7:0])}
                               : left_window_raw;
            contrast_center_rgb <= (ENABLE && CONTRAST_ENABLE && center_de && !center_protect)
                                 ? {contrast_channel(center_raw[23:16]), contrast_channel(center_raw[15:8]), contrast_channel(center_raw[7:0])}
                                 : center_raw;
            contrast_right_rgb <= (ENABLE && CONTRAST_ENABLE && center_de && !right_window_protect)
                                ? {contrast_channel(right_window_raw[23:16]), contrast_channel(right_window_raw[15:8]), contrast_channel(right_window_raw[7:0])}
                                : right_window_raw;

            // 第三级把对比度后的三个水平邻点延迟对齐。
            // 饱和度只对最终中心输出像素计算一次，避免左右邻点重复实例化色彩矩阵。
            prep_de <= contrast_de;
            prep_vs <= contrast_vs;
            prep_hs <= contrast_hs;
            prep_protect <= contrast_center_protect;
            prep_left_rgb <= contrast_left_rgb;
            prep_center_rgb <= contrast_center_rgb;
            prep_right_rgb <= contrast_right_rgb;

            // 第四级只做限幅锐化，避免与饱和度矩阵挤在同一时钟周期。
            sharp_de <= prep_de;
            sharp_vs <= prep_vs;
            sharp_hs <= prep_hs;
            sharp_protect <= prep_protect;
            if (!prep_de) sharp_rgb <= 24'd0;
            else if (!ENABLE || prep_protect) sharp_rgb <= prep_center_rgb;
            else if (!SHARPEN_ENABLE)
                sharp_rgb <= prep_center_rgb;
            else
                sharp_rgb <= {
                    sharpen(prep_left_rgb[23:16], prep_center_rgb[23:16], prep_right_rgb[23:16]),
                    sharpen(prep_left_rgb[15:8], prep_center_rgb[15:8], prep_right_rgb[15:8]),
                    sharpen(prep_left_rgb[7:0], prep_center_rgb[7:0], prep_right_rgb[7:0])
                };

            // 第五级仅计算饱和度，独立于空间锐化的加减链。
            grade_de <= sharp_de;
            grade_vs <= sharp_vs;
            grade_hs <= sharp_hs;
            grade_protect <= sharp_protect;
            if (!sharp_de) grade_rgb <= 24'd0;
            else if (!ENABLE || sharp_protect || !SATURATION_ENABLE)
                grade_rgb <= sharp_rgb;
            else
                grade_rgb <= color_grade(sharp_rgb);

            // 第六级做全画面一致的Gamma；RGB与同步信号逐级对齐。
            out_de <= grade_de;
            out_vsync <= grade_vs;
            out_hsync <= grade_hs;
            if (!grade_de) out_rgb <= 24'd0;
            else if (!ENABLE || grade_protect) out_rgb <= grade_rgb;
            else out_rgb <= finish_display_pixel(grade_rgb);
        end
    end
endmodule

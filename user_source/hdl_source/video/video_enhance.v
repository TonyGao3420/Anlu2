// Anlu2 源码说明：对显示RGB做黑白场扩展、饱和度调整、限幅水平锐化和gamma提亮。
// 接口与使用约定：五级流水；同步与数据严格等延迟。DE边界复制邻居，OSD及测试图可保护。
// 工程状态：已列入TD编译清单。

// Anlu2 视频显示增强：五级流水，输入/输出均为每拍一个 RGB888 像素。
// clk=HDMI 像素时钟；rst_n=低有效复位。VS/HS/DE 与 RGB 一起延迟。
// 依次做黑白场伸展、色度饱和度增强、限幅水平锐化和gamma显示曲线。
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
    reg [23:0] sharp_rgb;
    reg sharp_de, sharp_vs, sharp_hs, sharp_protect;

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
        integer y;
        integer cb;
        integer cr;
        integer cb_scaled;
        integer cr_scaled;
        integer red_value;
        integer green_value;
        integer blue_value;
        integer green_delta;
        begin
            // Shift/add luminance approximation: exact for neutral greys, cheaper than three multipliers.
            y = (rgb[23:16] + (rgb[15:8] << 1) + rgb[7:0] + 2) >> 2;
            cb = $signed({1'b0, rgb[7:0]}) - y;
            cr = $signed({1'b0, rgb[23:16]}) - y;
            // The default 1.25x saturation uses a shift/add, avoiding wide DSP chains in the pixel path.
            if (SATURATION_Q8 == 320) begin
                cb_scaled = cb + (cb >>> 2);
                cr_scaled = cr + (cr >>> 2);
            end else begin
                cb_scaled = (cb * SATURATION_Q8) >>> 8;
                cr_scaled = (cr * SATURATION_Q8) >>> 8;
            end
            green_delta = (cr_scaled + cb_scaled) >>> 1;
            red_value = y + cr_scaled;
            green_value = y - green_delta;
            blue_value = y + cb_scaled;
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

    // 完整 256 项常量 LUT，round(255*(x/255)^(1/1.8))。
    // 黑=0、白=255，单调不减；避免原先乘 1.5 后从 170 开始的白色截断。
    function [7:0] gamma_lut;
        input [7:0] value;
        begin
            case (value)
                8'd0: gamma_lut = 8'd0;
                8'd1: gamma_lut = 8'd12;
                8'd2: gamma_lut = 8'd17;
                8'd3: gamma_lut = 8'd22;
                8'd4: gamma_lut = 8'd25;
                8'd5: gamma_lut = 8'd29;
                8'd6: gamma_lut = 8'd32;
                8'd7: gamma_lut = 8'd35;
                8'd8: gamma_lut = 8'd37;
                8'd9: gamma_lut = 8'd40;
                8'd10: gamma_lut = 8'd42;
                8'd11: gamma_lut = 8'd44;
                8'd12: gamma_lut = 8'd47;
                8'd13: gamma_lut = 8'd49;
                8'd14: gamma_lut = 8'd51;
                8'd15: gamma_lut = 8'd53;
                8'd16: gamma_lut = 8'd55;
                8'd17: gamma_lut = 8'd57;
                8'd18: gamma_lut = 8'd58;
                8'd19: gamma_lut = 8'd60;
                8'd20: gamma_lut = 8'd62;
                8'd21: gamma_lut = 8'd64;
                8'd22: gamma_lut = 8'd65;
                8'd23: gamma_lut = 8'd67;
                8'd24: gamma_lut = 8'd69;
                8'd25: gamma_lut = 8'd70;
                8'd26: gamma_lut = 8'd72;
                8'd27: gamma_lut = 8'd73;
                8'd28: gamma_lut = 8'd75;
                8'd29: gamma_lut = 8'd76;
                8'd30: gamma_lut = 8'd78;
                8'd31: gamma_lut = 8'd79;
                8'd32: gamma_lut = 8'd80;
                8'd33: gamma_lut = 8'd82;
                8'd34: gamma_lut = 8'd83;
                8'd35: gamma_lut = 8'd85;
                8'd36: gamma_lut = 8'd86;
                8'd37: gamma_lut = 8'd87;
                8'd38: gamma_lut = 8'd89;
                8'd39: gamma_lut = 8'd90;
                8'd40: gamma_lut = 8'd91;
                8'd41: gamma_lut = 8'd92;
                8'd42: gamma_lut = 8'd94;
                8'd43: gamma_lut = 8'd95;
                8'd44: gamma_lut = 8'd96;
                8'd45: gamma_lut = 8'd97;
                8'd46: gamma_lut = 8'd98;
                8'd47: gamma_lut = 8'd100;
                8'd48: gamma_lut = 8'd101;
                8'd49: gamma_lut = 8'd102;
                8'd50: gamma_lut = 8'd103;
                8'd51: gamma_lut = 8'd104;
                8'd52: gamma_lut = 8'd105;
                8'd53: gamma_lut = 8'd107;
                8'd54: gamma_lut = 8'd108;
                8'd55: gamma_lut = 8'd109;
                8'd56: gamma_lut = 8'd110;
                8'd57: gamma_lut = 8'd111;
                8'd58: gamma_lut = 8'd112;
                8'd59: gamma_lut = 8'd113;
                8'd60: gamma_lut = 8'd114;
                8'd61: gamma_lut = 8'd115;
                8'd62: gamma_lut = 8'd116;
                8'd63: gamma_lut = 8'd117;
                8'd64: gamma_lut = 8'd118;
                8'd65: gamma_lut = 8'd119;
                8'd66: gamma_lut = 8'd120;
                8'd67: gamma_lut = 8'd121;
                8'd68: gamma_lut = 8'd122;
                8'd69: gamma_lut = 8'd123;
                8'd70: gamma_lut = 8'd124;
                8'd71: gamma_lut = 8'd125;
                8'd72: gamma_lut = 8'd126;
                8'd73: gamma_lut = 8'd127;
                8'd74: gamma_lut = 8'd128;
                8'd75: gamma_lut = 8'd129;
                8'd76: gamma_lut = 8'd130;
                8'd77: gamma_lut = 8'd131;
                8'd78: gamma_lut = 8'd132;
                8'd79: gamma_lut = 8'd133;
                8'd80: gamma_lut = 8'd134;
                8'd81: gamma_lut = 8'd135;
                8'd82: gamma_lut = 8'd136;
                8'd83: gamma_lut = 8'd137;
                8'd84: gamma_lut = 8'd138;
                8'd85: gamma_lut = 8'd139;
                8'd86: gamma_lut = 8'd139;
                8'd87: gamma_lut = 8'd140;
                8'd88: gamma_lut = 8'd141;
                8'd89: gamma_lut = 8'd142;
                8'd90: gamma_lut = 8'd143;
                8'd91: gamma_lut = 8'd144;
                8'd92: gamma_lut = 8'd145;
                8'd93: gamma_lut = 8'd146;
                8'd94: gamma_lut = 8'd146;
                8'd95: gamma_lut = 8'd147;
                8'd96: gamma_lut = 8'd148;
                8'd97: gamma_lut = 8'd149;
                8'd98: gamma_lut = 8'd150;
                8'd99: gamma_lut = 8'd151;
                8'd100: gamma_lut = 8'd152;
                8'd101: gamma_lut = 8'd152;
                8'd102: gamma_lut = 8'd153;
                8'd103: gamma_lut = 8'd154;
                8'd104: gamma_lut = 8'd155;
                8'd105: gamma_lut = 8'd156;
                8'd106: gamma_lut = 8'd157;
                8'd107: gamma_lut = 8'd157;
                8'd108: gamma_lut = 8'd158;
                8'd109: gamma_lut = 8'd159;
                8'd110: gamma_lut = 8'd160;
                8'd111: gamma_lut = 8'd161;
                8'd112: gamma_lut = 8'd161;
                8'd113: gamma_lut = 8'd162;
                8'd114: gamma_lut = 8'd163;
                8'd115: gamma_lut = 8'd164;
                8'd116: gamma_lut = 8'd165;
                8'd117: gamma_lut = 8'd165;
                8'd118: gamma_lut = 8'd166;
                8'd119: gamma_lut = 8'd167;
                8'd120: gamma_lut = 8'd168;
                8'd121: gamma_lut = 8'd169;
                8'd122: gamma_lut = 8'd169;
                8'd123: gamma_lut = 8'd170;
                8'd124: gamma_lut = 8'd171;
                8'd125: gamma_lut = 8'd172;
                8'd126: gamma_lut = 8'd172;
                8'd127: gamma_lut = 8'd173;
                8'd128: gamma_lut = 8'd174;
                8'd129: gamma_lut = 8'd175;
                8'd130: gamma_lut = 8'd175;
                8'd131: gamma_lut = 8'd176;
                8'd132: gamma_lut = 8'd177;
                8'd133: gamma_lut = 8'd178;
                8'd134: gamma_lut = 8'd178;
                8'd135: gamma_lut = 8'd179;
                8'd136: gamma_lut = 8'd180;
                8'd137: gamma_lut = 8'd181;
                8'd138: gamma_lut = 8'd181;
                8'd139: gamma_lut = 8'd182;
                8'd140: gamma_lut = 8'd183;
                8'd141: gamma_lut = 8'd183;
                8'd142: gamma_lut = 8'd184;
                8'd143: gamma_lut = 8'd185;
                8'd144: gamma_lut = 8'd186;
                8'd145: gamma_lut = 8'd186;
                8'd146: gamma_lut = 8'd187;
                8'd147: gamma_lut = 8'd188;
                8'd148: gamma_lut = 8'd188;
                8'd149: gamma_lut = 8'd189;
                8'd150: gamma_lut = 8'd190;
                8'd151: gamma_lut = 8'd191;
                8'd152: gamma_lut = 8'd191;
                8'd153: gamma_lut = 8'd192;
                8'd154: gamma_lut = 8'd193;
                8'd155: gamma_lut = 8'd193;
                8'd156: gamma_lut = 8'd194;
                8'd157: gamma_lut = 8'd195;
                8'd158: gamma_lut = 8'd195;
                8'd159: gamma_lut = 8'd196;
                8'd160: gamma_lut = 8'd197;
                8'd161: gamma_lut = 8'd198;
                8'd162: gamma_lut = 8'd198;
                8'd163: gamma_lut = 8'd199;
                8'd164: gamma_lut = 8'd200;
                8'd165: gamma_lut = 8'd200;
                8'd166: gamma_lut = 8'd201;
                8'd167: gamma_lut = 8'd202;
                8'd168: gamma_lut = 8'd202;
                8'd169: gamma_lut = 8'd203;
                8'd170: gamma_lut = 8'd204;
                8'd171: gamma_lut = 8'd204;
                8'd172: gamma_lut = 8'd205;
                8'd173: gamma_lut = 8'd206;
                8'd174: gamma_lut = 8'd206;
                8'd175: gamma_lut = 8'd207;
                8'd176: gamma_lut = 8'd208;
                8'd177: gamma_lut = 8'd208;
                8'd178: gamma_lut = 8'd209;
                8'd179: gamma_lut = 8'd209;
                8'd180: gamma_lut = 8'd210;
                8'd181: gamma_lut = 8'd211;
                8'd182: gamma_lut = 8'd211;
                8'd183: gamma_lut = 8'd212;
                8'd184: gamma_lut = 8'd213;
                8'd185: gamma_lut = 8'd213;
                8'd186: gamma_lut = 8'd214;
                8'd187: gamma_lut = 8'd215;
                8'd188: gamma_lut = 8'd215;
                8'd189: gamma_lut = 8'd216;
                8'd190: gamma_lut = 8'd217;
                8'd191: gamma_lut = 8'd217;
                8'd192: gamma_lut = 8'd218;
                8'd193: gamma_lut = 8'd218;
                8'd194: gamma_lut = 8'd219;
                8'd195: gamma_lut = 8'd220;
                8'd196: gamma_lut = 8'd220;
                8'd197: gamma_lut = 8'd221;
                8'd198: gamma_lut = 8'd222;
                8'd199: gamma_lut = 8'd222;
                8'd200: gamma_lut = 8'd223;
                8'd201: gamma_lut = 8'd223;
                8'd202: gamma_lut = 8'd224;
                8'd203: gamma_lut = 8'd225;
                8'd204: gamma_lut = 8'd225;
                8'd205: gamma_lut = 8'd226;
                8'd206: gamma_lut = 8'd226;
                8'd207: gamma_lut = 8'd227;
                8'd208: gamma_lut = 8'd228;
                8'd209: gamma_lut = 8'd228;
                8'd210: gamma_lut = 8'd229;
                8'd211: gamma_lut = 8'd230;
                8'd212: gamma_lut = 8'd230;
                8'd213: gamma_lut = 8'd231;
                8'd214: gamma_lut = 8'd231;
                8'd215: gamma_lut = 8'd232;
                8'd216: gamma_lut = 8'd233;
                8'd217: gamma_lut = 8'd233;
                8'd218: gamma_lut = 8'd234;
                8'd219: gamma_lut = 8'd234;
                8'd220: gamma_lut = 8'd235;
                8'd221: gamma_lut = 8'd236;
                8'd222: gamma_lut = 8'd236;
                8'd223: gamma_lut = 8'd237;
                8'd224: gamma_lut = 8'd237;
                8'd225: gamma_lut = 8'd238;
                8'd226: gamma_lut = 8'd238;
                8'd227: gamma_lut = 8'd239;
                8'd228: gamma_lut = 8'd240;
                8'd229: gamma_lut = 8'd240;
                8'd230: gamma_lut = 8'd241;
                8'd231: gamma_lut = 8'd241;
                8'd232: gamma_lut = 8'd242;
                8'd233: gamma_lut = 8'd243;
                8'd234: gamma_lut = 8'd243;
                8'd235: gamma_lut = 8'd244;
                8'd236: gamma_lut = 8'd244;
                8'd237: gamma_lut = 8'd245;
                8'd238: gamma_lut = 8'd245;
                8'd239: gamma_lut = 8'd246;
                8'd240: gamma_lut = 8'd247;
                8'd241: gamma_lut = 8'd247;
                8'd242: gamma_lut = 8'd248;
                8'd243: gamma_lut = 8'd248;
                8'd244: gamma_lut = 8'd249;
                8'd245: gamma_lut = 8'd249;
                8'd246: gamma_lut = 8'd250;
                8'd247: gamma_lut = 8'd251;
                8'd248: gamma_lut = 8'd251;
                8'd249: gamma_lut = 8'd252;
                8'd250: gamma_lut = 8'd252;
                8'd251: gamma_lut = 8'd253;
                8'd252: gamma_lut = 8'd253;
                8'd253: gamma_lut = 8'd254;
                8'd254: gamma_lut = 8'd254;
                8'd255: gamma_lut = 8'd255;
                default: gamma_lut = 8'd0;
            endcase
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

            // 第三级只做饱和度处理，RGB 与保护标志仍严格对齐。
            prep_de <= contrast_de;
            prep_vs <= contrast_vs;
            prep_hs <= contrast_hs;
            prep_protect <= contrast_center_protect;
            prep_left_rgb <= (ENABLE && SATURATION_ENABLE && contrast_de && !contrast_left_protect)
                           ? color_grade(contrast_left_rgb) : contrast_left_rgb;
            prep_center_rgb <= (ENABLE && SATURATION_ENABLE && contrast_de && !contrast_center_protect)
                             ? color_grade(contrast_center_rgb) : contrast_center_rgb;
            prep_right_rgb <= (ENABLE && SATURATION_ENABLE && contrast_de && !contrast_right_protect)
                            ? color_grade(contrast_right_rgb) : contrast_right_rgb;

            // 第四级锐化已完成色彩预处理的窗口，控制信号使用同一流水级。
            sharp_de <= prep_de;
            sharp_vs <= prep_vs;
            sharp_hs <= prep_hs;
            sharp_protect <= prep_protect;
            if (!prep_de) sharp_rgb <= 24'd0;
            else if (!ENABLE || !SHARPEN_ENABLE || prep_protect) sharp_rgb <= prep_center_rgb;
            else
                sharp_rgb <= {
                    sharpen(prep_left_rgb[23:16], prep_center_rgb[23:16], prep_right_rgb[23:16]),
                    sharpen(prep_left_rgb[15:8], prep_center_rgb[15:8], prep_right_rgb[15:8]),
                    sharpen(prep_left_rgb[7:0], prep_center_rgb[7:0], prep_right_rgb[7:0])
                };

            // 第四级执行gamma曲线并输出，控制信号与像素严格同延迟。
            out_de <= sharp_de;
            out_vsync <= sharp_vs;
            out_hsync <= sharp_hs;
            if (!sharp_de) out_rgb <= 24'd0;
            else if (!ENABLE || !GAMMA_ENABLE || sharp_protect) out_rgb <= sharp_rgb;
            else
                out_rgb <= {
                    gamma_lut(sharp_rgb[23:16]),
                    gamma_lut(sharp_rgb[15:8]),
                    gamma_lut(sharp_rgb[7:0])
                };
        end
    end
endmodule

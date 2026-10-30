// Anlu2 源码说明：接收DDR输出像素，叠加Logo、中文字符、帧计数和检测目标框，或选择调试图案。
// 接口与使用约定：读使能直接取VTC的DE，目标框坐标来自同一像素时钟域；OSD_ENABLE控制静态OSD。
// 工程状态：已列入TD编译清单。

module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer OSD_ENABLE = 1,
    parameter integer CENTER_OSD_ENABLE = 1,
    parameter integer DEBUG_MODE = 0
) (
    input wire I_clk,
    input wire I_rst_n,

    input wire I_video_vsync,
    input wire I_video_hsync,
    input wire I_video_de,
    input wire I_video_user,
    input wire I_video_last,

    input wire [3:0] I_debug_status,

    // Frame-level target bounds from the single-green-object tracker.
    input wire        I_target_bbox_valid,
    input wire [15:0] I_target_bbox_x0,
    input wire [15:0] I_target_bbox_y0,
    input wire [15:0] I_target_bbox_x1,
    input wire [15:0] I_target_bbox_y1,

    output wire        O_video_rd_en,
    input  wire [23:0] I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg        O_hdmi_protect,  // OSD/测试图保护标记，与输出像素同拍
    output reg [23:0] O_hdmi_data,
    output reg [11:0] O_hdmi_x,
    output reg [11:0] O_hdmi_y
);

    reg         S_video_vsync_1d;
    reg         S_video_vsync_2d;
    reg         S_video_hsync_1d;
    reg         S_video_hsync_2d;
    reg         S_video_de_1d;
    reg         S_video_de_2d;
    reg  [11:0] S_x;
    reg  [11:0] S_y;
    reg  [11:0] S_x_1d;
    reg  [11:0] S_x_2d;
    reg  [11:0] S_y_1d;
    reg  [11:0] S_y_2d;

    // Add a small safety margin around the measured red-pixel bounds.
    wire [15:0] bbox_x0_padded = (I_target_bbox_x0 > 16'd4)
                                      ? I_target_bbox_x0 - 16'd4 : 16'd0;
    wire [15:0] bbox_y0_padded = (I_target_bbox_y0 > 16'd4)
                                      ? I_target_bbox_y0 - 16'd4 : 16'd0;
    wire [15:0] bbox_x1_padded = I_target_bbox_x1 + 16'd4;
    wire [15:0] bbox_y1_padded = I_target_bbox_y1 + 16'd4;
    wire [15:0] display_x = {4'd0, S_x_2d};
    wire [15:0] display_y = {4'd0, S_y_2d};
    wire target_rectangle_pixel = I_target_bbox_valid &&
        (display_x >= bbox_x0_padded) && (display_x <= bbox_x1_padded) &&
        (display_y >= bbox_y0_padded) && (display_y <= bbox_y1_padded) &&
        ((display_x < bbox_x0_padded + 16'd2) ||
         (display_x + 16'd2 > bbox_x1_padded) ||
         (display_y < bbox_y0_padded + 16'd2) ||
         (display_y + 16'd2 > bbox_y1_padded));

    reg         S_osd_hit;
    reg  [23:0] S_osd_color;
    reg  [11:0] S_logo_x;
    reg  [11:0] S_logo_y;
    reg  [ 3:0] S_char_idx;
    reg  [ 2:0] S_char_row;
    reg  [ 2:0] S_char_col;
    reg  [ 4:0] S_char_bits;
    reg         S_char_on;
    reg         S_logo_blue_on;
    reg         S_logo_red_on;
    reg  [11:0] S_logo_tmp_y;
    reg  [ 3:0] S_logo_red_band;
    reg  [11:0] S_logo_red_x_start;
    reg  [11:0] S_logo_red_x_end;
    reg  [16:0] S_logo_addr;
    wire [24:0] S_logo_pixel;
    reg  [31:0] S_frame_cnt;
    reg  [11:0] S_dyn_x;
    reg  [11:0] S_dyn_y;
    reg  [ 3:0] S_dyn_char;
    reg  [ 2:0] S_dyn_col;
    reg  [ 2:0] S_dyn_row;
    reg  [ 4:0] S_dyn_bits;
    reg         S_dyn_on;
    reg  [ 3:0] S_dyn_digit_idx;
    reg  [11:0] S_dyn_digit_x;
    reg  [ 6:0] S_dyn_seg;
    reg  [ 3:0] S_cnt_d0;
    reg  [ 3:0] S_cnt_d1;
    reg  [ 3:0] S_cnt_d2;
    reg  [ 3:0] S_cnt_d3;
    reg  [ 3:0] S_cnt_d4;
    reg  [ 3:0] S_cnt_d5;
    reg  [ 2:0] S_lbl_row;
    reg  [ 2:0] S_lbl_col;
    reg  [ 1:0] S_lbl_idx;
    reg  [ 4:0] S_lbl_bits;
    reg  [ 6:0] S_lbl_local_x;
    reg  [ 3:0] S_dyn_dec_digit;
    reg  [ 4:0] S_cn_local_x;
    reg  [ 4:0] S_cn_local_y;
    reg  [ 3:0] S_cn_col;
    reg  [ 3:0] S_cn_row;
    reg  [15:0] S_cn_row_bits;
    reg         S_cn_on;
    reg  [ 9:0] S_cn_scale_x;
    reg  [ 9:0] S_cn_scale_y;
    reg  [ 7:0] S_pf_char;
    reg  [ 4:0] S_pf_local_x;
    reg  [ 4:0] S_pf_local_y;
    reg  [ 3:0] S_pf_col;
    reg  [ 3:0] S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg         S_pf_on;
    reg  [ 9:0] S_pf_scale_x;
    reg  [ 9:0] S_pf_scale_y;

    localparam LOGO_X          = 12'd0;
    localparam LOGO_Y          = 12'd0;
    localparam LOGO_W          = 12'd160;
    localparam LOGO_H          = 12'd160;

    localparam COLOR_LOGO_BLUE = 24'h1f315c;
    localparam COLOR_LOGO_RED  = 24'hec1c2d;
    localparam COLOR_TEXT      = 24'h00e6ff;
    localparam DYN_OSD_X       = 12'd375;
    localparam DYN_OSD_Y       = 12'd120;
    localparam DYN_OSD_W       = 12'd200;
    localparam DYN_OSD_H       = 12'd24;
    localparam CN_Y_OFFSET     = 12'd2;
    localparam COLOR_DYN_TEXT  = 24'hfff200;
    localparam CHAR_AN         = 8'h80;
    localparam CHAR_LU         = 8'h81;
    localparam CHAR_C          = 8'h43;
    localparam CHAR_N          = 8'h4e;
    localparam CHAR_T          = 8'h54;
    localparam CHAR_0          = 8'h30;
    localparam CHAR_COLON      = 8'h3a;

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case (I_char)
                4'd0: begin
                    case (I_row)  // A
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case (I_row)  // N
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case (I_row)  // L
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case (I_row)  // O
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case (I_row)  // G
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case (I_row)  // I
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case (I_row)  // C
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    // 7-seg bit mapping: {a,b,c,d,e,f,g}
    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case (I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case (I_idx)
                2'd0: begin  // C
                    case (I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin  // N
                    case (I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin  // T
                    case (I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin  // ':'
                    case (I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".
    function [15:0] F_cn16_row;
        input I_char;  // 0: an, 1: lu
        input [3:0] I_row;
        begin
            if (!I_char) begin
                case (I_row)
                    4'd0: F_cn16_row = 16'h0200;
                    4'd1: F_cn16_row = 16'h7ff0;
                    4'd2: F_cn16_row = 16'h4410;
                    4'd3: F_cn16_row = 16'h0400;
                    4'd4: F_cn16_row = 16'h7ff0;
                    4'd5: F_cn16_row = 16'h0840;
                    4'd6: F_cn16_row = 16'h1040;
                    4'd7: F_cn16_row = 16'h1c80;
                    4'd8: F_cn16_row = 16'h0300;
                    4'd9: F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end else begin
                case (I_row)
                    4'd0: F_cn16_row = 16'h79e0;
                    4'd1: F_cn16_row = 16'h4a20;
                    4'd2: F_cn16_row = 16'h4d40;
                    4'd3: F_cn16_row = 16'h7880;
                    4'd4: F_cn16_row = 16'h1140;
                    4'd5: F_cn16_row = 16'h1630;
                    4'd6: F_cn16_row = 16'h5be0;
                    4'd7: F_cn16_row = 16'h5220;
                    4'd8: F_cn16_row = 16'h5220;
                    4'd9: F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case (I_char)
                4'h0: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10011;
                        3'd3: F_dyn_char_bits = 5'b10101;
                        3'd4: F_dyn_char_bits = 5'b11001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h1: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b00100;
                        3'd1: F_dyn_char_bits = 5'b01100;
                        3'd2: F_dyn_char_bits = 5'b00100;
                        3'd3: F_dyn_char_bits = 5'b00100;
                        3'd4: F_dyn_char_bits = 5'b00100;
                        3'd5: F_dyn_char_bits = 5'b00100;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h2: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b00001;
                        3'd3: F_dyn_char_bits = 5'b00110;
                        3'd4: F_dyn_char_bits = 5'b01000;
                        3'd5: F_dyn_char_bits = 5'b10000;
                        3'd6: F_dyn_char_bits = 5'b11111;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h3: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11110;
                        3'd1: F_dyn_char_bits = 5'b00001;
                        3'd2: F_dyn_char_bits = 5'b00001;
                        3'd3: F_dyn_char_bits = 5'b01110;
                        3'd4: F_dyn_char_bits = 5'b00001;
                        3'd5: F_dyn_char_bits = 5'b00001;
                        3'd6: F_dyn_char_bits = 5'b11110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h4: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b00010;
                        3'd1: F_dyn_char_bits = 5'b00110;
                        3'd2: F_dyn_char_bits = 5'b01010;
                        3'd3: F_dyn_char_bits = 5'b10010;
                        3'd4: F_dyn_char_bits = 5'b11111;
                        3'd5: F_dyn_char_bits = 5'b00010;
                        3'd6: F_dyn_char_bits = 5'b00010;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h5: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11111;
                        3'd1: F_dyn_char_bits = 5'b10000;
                        3'd2: F_dyn_char_bits = 5'b11110;
                        3'd3: F_dyn_char_bits = 5'b00001;
                        3'd4: F_dyn_char_bits = 5'b00001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h6: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b00110;
                        3'd1: F_dyn_char_bits = 5'b01000;
                        3'd2: F_dyn_char_bits = 5'b10000;
                        3'd3: F_dyn_char_bits = 5'b11110;
                        3'd4: F_dyn_char_bits = 5'b10001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h7: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11111;
                        3'd1: F_dyn_char_bits = 5'b00001;
                        3'd2: F_dyn_char_bits = 5'b00010;
                        3'd3: F_dyn_char_bits = 5'b00100;
                        3'd4: F_dyn_char_bits = 5'b01000;
                        3'd5: F_dyn_char_bits = 5'b01000;
                        3'd6: F_dyn_char_bits = 5'b01000;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h8: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10001;
                        3'd3: F_dyn_char_bits = 5'b01110;
                        3'd4: F_dyn_char_bits = 5'b10001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'h9: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10001;
                        3'd3: F_dyn_char_bits = 5'b01111;
                        3'd4: F_dyn_char_bits = 5'b00001;
                        3'd5: F_dyn_char_bits = 5'b00010;
                        3'd6: F_dyn_char_bits = 5'b11100;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'ha: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10001;
                        3'd3: F_dyn_char_bits = 5'b11111;
                        3'd4: F_dyn_char_bits = 5'b10001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b10001;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'hb: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10001;
                        3'd3: F_dyn_char_bits = 5'b11110;
                        3'd4: F_dyn_char_bits = 5'b10001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b11110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'hc: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b01110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10000;
                        3'd3: F_dyn_char_bits = 5'b10000;
                        3'd4: F_dyn_char_bits = 5'b10000;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b01110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'hd: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11110;
                        3'd1: F_dyn_char_bits = 5'b10001;
                        3'd2: F_dyn_char_bits = 5'b10001;
                        3'd3: F_dyn_char_bits = 5'b10001;
                        3'd4: F_dyn_char_bits = 5'b10001;
                        3'd5: F_dyn_char_bits = 5'b10001;
                        3'd6: F_dyn_char_bits = 5'b11110;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'he: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11111;
                        3'd1: F_dyn_char_bits = 5'b10000;
                        3'd2: F_dyn_char_bits = 5'b10000;
                        3'd3: F_dyn_char_bits = 5'b11110;
                        3'd4: F_dyn_char_bits = 5'b10000;
                        3'd5: F_dyn_char_bits = 5'b10000;
                        3'd6: F_dyn_char_bits = 5'b11111;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                4'hf: begin
                    case (I_row)
                        3'd0: F_dyn_char_bits = 5'b11111;
                        3'd1: F_dyn_char_bits = 5'b10000;
                        3'd2: F_dyn_char_bits = 5'b10000;
                        3'd3: F_dyn_char_bits = 5'b11110;
                        3'd4: F_dyn_char_bits = 5'b10000;
                        3'd5: F_dyn_char_bits = 5'b10000;
                        3'd6: F_dyn_char_bits = 5'b10000;
                        default: F_dyn_char_bits = 5'b00000;
                    endcase
                end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:
    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case (I_char)
                CHAR_AN: begin
                    case (I_row)
                        4'd0: F_osd_char16_row = 16'h0200;
                        4'd1: F_osd_char16_row = 16'h7ff0;
                        4'd2: F_osd_char16_row = 16'h4410;
                        4'd3: F_osd_char16_row = 16'h0400;
                        4'd4: F_osd_char16_row = 16'h7ff0;
                        4'd5: F_osd_char16_row = 16'h0840;
                        4'd6: F_osd_char16_row = 16'h1040;
                        4'd7: F_osd_char16_row = 16'h1c80;
                        4'd8: F_osd_char16_row = 16'h0300;
                        4'd9: F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case (I_row)
                        4'd0: F_osd_char16_row = 16'h79e0;
                        4'd1: F_osd_char16_row = 16'h4a20;
                        4'd2: F_osd_char16_row = 16'h4d40;
                        4'd3: F_osd_char16_row = 16'h7880;
                        4'd4: F_osd_char16_row = 16'h1140;
                        4'd5: F_osd_char16_row = 16'h1630;
                        4'd6: F_osd_char16_row = 16'h5be0;
                        4'd7: F_osd_char16_row = 16'h5220;
                        4'd8: F_osd_char16_row = 16'h5220;
                        4'd9: F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case (I_row)
                        4'd2: F_osd_char16_row = 16'h03f0;
                        4'd3: F_osd_char16_row = 16'h0c0c;
                        4'd4: F_osd_char16_row = 16'h1800;
                        4'd5: F_osd_char16_row = 16'h3000;
                        4'd6: F_osd_char16_row = 16'h3000;
                        4'd7: F_osd_char16_row = 16'h3000;
                        4'd8: F_osd_char16_row = 16'h3000;
                        4'd9: F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case (I_row)
                        4'd2: F_osd_char16_row = 16'h300c;
                        4'd3: F_osd_char16_row = 16'h380c;
                        4'd4: F_osd_char16_row = 16'h3c0c;
                        4'd5: F_osd_char16_row = 16'h360c;
                        4'd6: F_osd_char16_row = 16'h330c;
                        4'd7: F_osd_char16_row = 16'h318c;
                        4'd8: F_osd_char16_row = 16'h30cc;
                        4'd9: F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case (I_row)
                        4'd2: F_osd_char16_row = 16'h3ffc;
                        4'd3: F_osd_char16_row = 16'h03c0;
                        4'd4: F_osd_char16_row = 16'h03c0;
                        4'd5: F_osd_char16_row = 16'h03c0;
                        4'd6: F_osd_char16_row = 16'h03c0;
                        4'd7: F_osd_char16_row = 16'h03c0;
                        4'd8: F_osd_char16_row = 16'h03c0;
                        4'd9: F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case (I_row)
                        4'd6: F_osd_char16_row = 16'h0180;
                        4'd7: F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    // The tracker publishes at corrected-camera SOF, a few clocks after mixer SOF.
    // Capture on line 1 so both axes use that complete result, well before the HUD.
    wire S_center_hit;
    wire [23:0] S_center_rgb;
    wire S_center_valid;
    wire signed [15:0] S_center_x,S_center_y;
    generate if (OSD_ENABLE && CENTER_OSD_ENABLE) begin: center_hud
        roi_center_osd #(.IMG_W(IMG_WIDTH),.IMG_H(IMG_HEIGHT)) coordinates (
            .clk(I_clk),.rst_n(I_rst_n),
            .capture(I_video_de && S_x==12'd0 && S_y==12'd1),
            .bbox_valid(I_target_bbox_valid),
            .bbox_x0(I_target_bbox_x0),.bbox_y0(I_target_bbox_y0),
            .bbox_x1(I_target_bbox_x1),.bbox_y1(I_target_bbox_y1),
            .pixel_x(S_x_2d),.pixel_y(S_y_2d),
            .hit(S_center_hit),.rgb(S_center_rgb),
            .center_valid(S_center_valid),.center_x(S_center_x),.center_y(S_center_y));
    end else begin: no_center_hud
        assign S_center_hit=1'b0;assign S_center_rgb=24'd0;
        assign S_center_valid=1'b0;assign S_center_x=16'd0;assign S_center_y=16'd0;
    end endgenerate

    assign O_video_rd_en = I_video_de;

    // ERAM prefetch starts two existing coordinate stages ahead of the mixer.
    // The resulting pixel matches S_x_2d/S_y_2d without delaying any video IO.
    wire [16:0] S_logo_prefetch_addr =
        (S_x < LOGO_W && S_y < LOGO_H)
        ? ({S_y,7'b0}+{S_y,5'b0}+S_x) : 17'd0;
    anlogic_logo_eram u_anlogic_logo_rom (
        .I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_addr (S_logo_prefetch_addr),
        .O_pixel(S_logo_pixel)
    );

    osd_char_lib u_osd_char_lib (
        .I_char    (S_pf_char),
        .I_row     (S_pf_row),
        .O_row_bits(S_pf_row_bits)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end else if (I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end else if (I_video_de) begin
            if (I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end else if (I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if (S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if (S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if (S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if (S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if (S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if (S_cnt_d5 == 4'd9) S_cnt_d5 <= 4'd0;
                                else S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end else S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end else S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end else S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end else S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end else S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
        end else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
        end
    end

    always @(*) begin
        S_osd_hit = 1'b0;
        S_osd_color = 24'd0;
        S_logo_addr = 17'd0;

        S_logo_x = 12'd0;
        S_logo_y = 12'd0;
        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_on = 1'b0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;

        if (S_video_de_2d && OSD_ENABLE) begin
            if((S_x_2d >= LOGO_X) && (S_x_2d < (LOGO_X + LOGO_W)) &&
               (S_y_2d >= LOGO_Y) && (S_y_2d < (LOGO_Y + LOGO_H))) begin
                S_logo_x = S_x_2d - LOGO_X;
                S_logo_y = S_y_2d - LOGO_Y;
                // 160=128+32; preserve DSP resources.
                S_logo_addr = {S_logo_y,7'b0} + {S_logo_y,5'b0} + S_logo_x;
                if (S_logo_pixel[24]) begin
                    S_osd_hit   = 1'b1;
                    S_osd_color = S_logo_pixel[23:0];
                end
            end

            if((!S_osd_hit) &&
               (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d >= DYN_OSD_Y) && (S_y_2d < (DYN_OSD_Y + DYN_OSD_H))) begin
                S_dyn_x = S_x_2d - DYN_OSD_X;
                S_dyn_y = S_y_2d - DYN_OSD_Y;

                // Unified prefix render using one character library.
                // an:[0..23], lu:[24..47], C:[52..67], N:[68..83], T:[84..99], :[100..107]
                if ((S_dyn_x < 12'd108) && (S_dyn_y < 12'd24)) begin
                    if ((S_dyn_x < 12'd24) || ((S_dyn_x >= 12'd24) && (S_dyn_x < 12'd48))) begin
                        if (S_dyn_y >= CN_Y_OFFSET) S_pf_local_y = S_dyn_y - CN_Y_OFFSET;
                        else S_pf_local_y = 5'd31;

                        if (S_dyn_x < 12'd24) begin
                            S_pf_char = CHAR_AN;
                            S_pf_local_x = S_dyn_x;
                        end else begin
                            S_pf_char = CHAR_LU;
                            S_pf_local_x = S_dyn_x - 12'd24;
                        end

                        if ((S_pf_local_x < 5'd24) && (S_pf_local_y < 5'd24)) begin
                            S_pf_scale_x = S_pf_local_x * 10'd16;
                            S_pf_scale_y = S_pf_local_y * 10'd16;
                            S_pf_col = S_pf_scale_x / 10'd24;
                            S_pf_row = S_pf_scale_y / 10'd24;
                            case (S_pf_col)
                                4'd0: S_pf_on = S_pf_row_bits[15];
                                4'd1: S_pf_on = S_pf_row_bits[14];
                                4'd2: S_pf_on = S_pf_row_bits[13];
                                4'd3: S_pf_on = S_pf_row_bits[12];
                                4'd4: S_pf_on = S_pf_row_bits[11];
                                4'd5: S_pf_on = S_pf_row_bits[10];
                                4'd6: S_pf_on = S_pf_row_bits[9];
                                4'd7: S_pf_on = S_pf_row_bits[8];
                                4'd8: S_pf_on = S_pf_row_bits[7];
                                4'd9: S_pf_on = S_pf_row_bits[6];
                                4'd10: S_pf_on = S_pf_row_bits[5];
                                4'd11: S_pf_on = S_pf_row_bits[4];
                                4'd12: S_pf_on = S_pf_row_bits[3];
                                4'd13: S_pf_on = S_pf_row_bits[2];
                                4'd14: S_pf_on = S_pf_row_bits[1];
                                4'd15: S_pf_on = S_pf_row_bits[0];
                                default: S_pf_on = 1'b0;
                            endcase
                        end
                    end
                    else if((S_dyn_x >= 12'd52) && (S_dyn_x < 12'd100) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        if (S_dyn_x < 12'd68) begin
                            S_pf_char = CHAR_C;
                            S_pf_local_x = S_dyn_x - 12'd52;
                        end else if (S_dyn_x < 12'd84) begin
                            S_pf_char = CHAR_N;
                            S_pf_local_x = S_dyn_x - 12'd68;
                        end else begin
                            S_pf_char = CHAR_T;
                            S_pf_local_x = S_dyn_x - 12'd84;
                        end
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_col = S_pf_local_x[3:0];
                        S_pf_row = S_pf_local_y[3:0];
                        case (S_pf_col)
                            4'd0: S_pf_on = S_pf_row_bits[15];
                            4'd1: S_pf_on = S_pf_row_bits[14];
                            4'd2: S_pf_on = S_pf_row_bits[13];
                            4'd3: S_pf_on = S_pf_row_bits[12];
                            4'd4: S_pf_on = S_pf_row_bits[11];
                            4'd5: S_pf_on = S_pf_row_bits[10];
                            4'd6: S_pf_on = S_pf_row_bits[9];
                            4'd7: S_pf_on = S_pf_row_bits[8];
                            4'd8: S_pf_on = S_pf_row_bits[7];
                            4'd9: S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                    end
                    else if((S_dyn_x >= 12'd100) && (S_dyn_x < 12'd108) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        S_pf_char = CHAR_COLON;
                        S_pf_local_x = S_dyn_x - 12'd100;
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_col = S_pf_scale_x / 10'd8;
                        S_pf_row = S_pf_local_y[3:0];
                        case (S_pf_col)
                            4'd0: S_pf_on = S_pf_row_bits[15];
                            4'd1: S_pf_on = S_pf_row_bits[14];
                            4'd2: S_pf_on = S_pf_row_bits[13];
                            4'd3: S_pf_on = S_pf_row_bits[12];
                            4'd4: S_pf_on = S_pf_row_bits[11];
                            4'd5: S_pf_on = S_pf_row_bits[10];
                            4'd6: S_pf_on = S_pf_row_bits[9];
                            4'd7: S_pf_on = S_pf_row_bits[8];
                            4'd8: S_pf_on = S_pf_row_bits[7];
                            4'd9: S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                    end

                    if (S_pf_on) S_dyn_on = 1'b1;
                end

                // Decimal 6 digits starts at x=110. Each digit is 15x24.
                if ((S_dyn_x >= 12'd110) && (S_dyn_x < 12'd200)) begin
                    if (S_dyn_x < 12'd125) begin
                        S_dyn_digit_idx = 4'd0;
                        S_dyn_digit_x   = S_dyn_x - 12'd110;
                        S_dyn_dec_digit = S_cnt_d5;
                    end else if (S_dyn_x < 12'd140) begin
                        S_dyn_digit_idx = 4'd1;
                        S_dyn_digit_x   = S_dyn_x - 12'd125;
                        S_dyn_dec_digit = S_cnt_d4;
                    end else if (S_dyn_x < 12'd155) begin
                        S_dyn_digit_idx = 4'd2;
                        S_dyn_digit_x   = S_dyn_x - 12'd140;
                        S_dyn_dec_digit = S_cnt_d3;
                    end else if (S_dyn_x < 12'd170) begin
                        S_dyn_digit_idx = 4'd3;
                        S_dyn_digit_x   = S_dyn_x - 12'd155;
                        S_dyn_dec_digit = S_cnt_d2;
                    end else if (S_dyn_x < 12'd185) begin
                        S_dyn_digit_idx = 4'd4;
                        S_dyn_digit_x   = S_dyn_x - 12'd170;
                        S_dyn_dec_digit = S_cnt_d1;
                    end else begin
                        S_dyn_digit_idx = 4'd5;
                        S_dyn_digit_x   = S_dyn_x - 12'd185;
                        S_dyn_dec_digit = S_cnt_d0;
                    end

                    // Render decimal digits through unified 16x16 character library.
                    // Keep enlarged 15x24 box for readability.
                    if ((S_dyn_digit_x < 12'd15) && (S_dyn_y < 12'd24)) begin
                        S_pf_char = CHAR_0 + {4'd0, S_dyn_dec_digit};
                        S_pf_local_x = S_dyn_digit_x[4:0];
                        S_pf_local_y = S_dyn_y[4:0];
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_scale_y = S_pf_local_y * 10'd16;
                        S_pf_col = S_pf_scale_x / 10'd15;
                        S_pf_row = S_pf_scale_y / 10'd24;
                        case (S_pf_col)
                            4'd0: S_pf_on = S_pf_row_bits[15];
                            4'd1: S_pf_on = S_pf_row_bits[14];
                            4'd2: S_pf_on = S_pf_row_bits[13];
                            4'd3: S_pf_on = S_pf_row_bits[12];
                            4'd4: S_pf_on = S_pf_row_bits[11];
                            4'd5: S_pf_on = S_pf_row_bits[10];
                            4'd6: S_pf_on = S_pf_row_bits[9];
                            4'd7: S_pf_on = S_pf_row_bits[8];
                            4'd8: S_pf_on = S_pf_row_bits[7];
                            4'd9: S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                        if (S_pf_on) S_dyn_on = 1'b1;
                    end
                end

                if (S_dyn_on) begin
                    S_osd_hit   = 1'b1;
                    S_osd_color = COLOR_DYN_TEXT;
                end
            end
        end

        // Protect the complete coordinate HUD (glyph and black background) from ISP gains.
        if (S_video_de_2d && S_center_hit) begin
            S_osd_hit   = 1'b1;
            S_osd_color = S_center_rgb;
        end

        // Draw a clean two-pixel rectangular box instead of marking mask pixels.
        if (target_rectangle_pixel) begin
            S_osd_hit   = 1'b1;
            S_osd_color = 24'h00ffff;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
            O_hdmi_protect   <= 1'b0;
            O_hdmi_x         <= 12'd0;
            O_hdmi_y         <= 12'd0;
        end else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            O_hdmi_vsync     <= S_video_vsync_2d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            O_hdmi_hsync     <= S_video_hsync_2d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            O_hdmi_de        <= S_video_de_2d;

            // video_out 的两个寄存级已对齐 S_video_de_2d；RGB 不可再延迟两拍。
            O_hdmi_protect   <= (DEBUG_MODE != 0) || S_osd_hit;
            O_hdmi_x         <= S_x_2d;
            O_hdmi_y         <= S_y_2d;
            if (DEBUG_MODE == 1) begin
                if (S_video_de_2d) begin
                    if (S_x < 12'd128) O_hdmi_data <= 24'hff0000;
                    else if (S_x < 12'd256) O_hdmi_data <= 24'h00ff00;
                    else if (S_x < 12'd384) O_hdmi_data <= 24'h0000ff;
                    else if (S_x < 12'd512) O_hdmi_data <= 24'hffff00;
                    else if (S_x < 12'd640) O_hdmi_data <= 24'h00ffff;
                    else if (S_x < 12'd768) O_hdmi_data <= 24'hff00ff;
                    else if (S_x < 12'd896) O_hdmi_data <= 24'hffffff;
                    else O_hdmi_data <= 24'h202020;
                end else begin
                    O_hdmi_data <= 24'd0;
                end
            end else if (DEBUG_MODE == 2) begin
                if (S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end else begin
                    O_hdmi_data <= 24'd0;
                end
            end else if (DEBUG_MODE == 3) begin
                if (S_video_de_2d) begin
                    if (S_x < 12'd256) O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if (S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if (S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end else begin
                    O_hdmi_data <= 24'd0;
                end
            end else begin
                if (S_osd_hit) O_hdmi_data <= S_osd_color;
                else O_hdmi_data <= S_video_de_2d ? I_video_rd_data : 24'd0;
            end
        end
    end

endmodule

// Exact official lab_ex3 160x160 logo: two lossless 10-bit palette indices
// per 20-bit ERAM word. Index stage + palette stage reuse the existing latency.
module anlogic_logo_eram(input wire I_clk,I_rst_n,input wire [16:0] I_addr,output wire [24:0] O_pixel);
 wire [13:0] wa=I_addr[14:1];
 wire [19:0] q0,q1,q2;reg [1:0] bank;reg half;
 always @(posedge I_clk)begin bank<=(wa<8192)?0:((wa<12288)?1:2);half<=I_addr[0];end
 wire [19:0] word_q=(bank==0)?q0:((bank==1)?q1:q2);
 wire [9:0] index_q=half?word_q[19:10]:word_q[9:0];
 wire [24:0] palette_q;
 PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A(20),.ADDR_WIDTH_A(13),.DATA_DEPTH_A(8192),
  .DATA_WIDTH_B(20),.ADDR_WIDTH_B(13),.DATA_DEPTH_B(8192),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
  .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.INIT_FILE("official_logo_index0.mif"),.FILL_ALL("NONE")
 ) u_official_logo_index0 (
  .dia(20'd0),.addra(13'd0),.cea(1'b0),.ocea(1'b0),.clka(I_clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
  .dib(20'd0),.addrb(wa[12:0]),.ceb(1'b1),.oceb(1'b1),.clkb(I_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(q0),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
 );
 PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A(20),.ADDR_WIDTH_A(12),.DATA_DEPTH_A(4096),
  .DATA_WIDTH_B(20),.ADDR_WIDTH_B(12),.DATA_DEPTH_B(4096),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
  .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.INIT_FILE("official_logo_index1.mif"),.FILL_ALL("NONE")
 ) u_official_logo_index1 (
  .dia(20'd0),.addra(12'd0),.cea(1'b0),.ocea(1'b0),.clka(I_clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
  .dib(20'd0),.addrb(wa[11:0]),.ceb(1'b1),.oceb(1'b1),.clkb(I_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(q1),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
 );
 PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A(20),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
  .DATA_WIDTH_B(20),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
  .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.INIT_FILE("official_logo_index2.mif"),.FILL_ALL("NONE")
 ) u_official_logo_index2 (
  .dia(20'd0),.addra(9'd0),.cea(1'b0),.ocea(1'b0),.clka(I_clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
  .dib(20'd0),.addrb(wa[8:0]),.ceb(1'b1),.oceb(1'b1),.clkb(I_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(q2),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
 );
 PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A(25),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
  .DATA_WIDTH_B(25),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
  .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.INIT_FILE("official_logo_palette.mif"),.FILL_ALL("NONE")
 ) u_official_logo_palette (
  .dia(25'd0),.addra(10'd0),.cea(1'b0),.ocea(1'b0),.clka(I_clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
  .dib(25'd0),.addrb(index_q),.ceb(1'b1),.oceb(1'b1),.clkb(I_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(palette_q),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
 );
 reg [1:0] valid;
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)valid<=0;else valid<={valid[0],I_addr<17'd25600};
 assign O_pixel=valid[1]?palette_q:25'd0;
endmodule

// Three-clock display-only overlay. All metadata is sampled once per frame.
module multi_target_overlay #(parameter integer W=1280,H=720,N=8,COMBO_STATUS=0,FRAME_STABLE_BOXES=0)(
 input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,input wire [23:0] in_rgb,
 input wire style_active,input wire enable,input wire [N-1:0] valid,input wire [N*12-1:0] x0,y0,x1,y1,
 input wire [3:0] count,input wire [15:0] total,process_us,input wire overflow,late,
 input wire [23:0] age_us,input wire [15:0] frame_id,input wire latency_valid,
 output reg out_vs,out_hs,out_de,output reg [23:0] out_rgb);
 reg vs_d,armed;reg [11:0] x,y;wire first=in_de && armed && x==0 && y==0;
 reg mode,style_mode;reg [N-1:0] sv;reg [N*12-1:0] sx0,sy0,sx1,sy1;
 // The main detector already holds these boxes for the complete active frame.
 // Generic callers retain the original local snapshot unless explicitly enabled.
 wire [N-1:0] fv=FRAME_STABLE_BOXES?valid:sv;
 wire [N*12-1:0] fx0=FRAME_STABLE_BOXES?x0:sx0,fy0=FRAME_STABLE_BOXES?y0:sy0;
 wire [N*12-1:0] fx1=FRAME_STABLE_BOXES?x1:sx1,fy1=FRAME_STABLE_BOXES?y1:sy1;
 // synthesis translate_off
 generate if(FRAME_STABLE_BOXES)begin: check_frame_boxes
  reg [N*49-1:0] held;
  always @(posedge clk)if(first)held<={valid,x0,y0,x1,y1};
  else if(rst_n && in_de && armed && {valid,x0,y0,x1,y1}!==held)
   $fatal(1,"Overlay detector boxes changed during active frame");
 end endgenerate
 // synthesis translate_on
 reg [3:0] fc;reg [15:0] ft,fu,fid;reg fo,fl,lv,stale;
 reg [23:0] fa;reg stale_sticky;reg [15:0] last_id;
 // Three values share one 24-cycle binary-to-BCD engine. No divider or DSP.
 reg [4:0] job;reg [4:0] bitn;reg busy,load;
 reg [23:0] binary,bcd;
 reg [23:0] total_bcd,us_bcd,age_bcd;
 reg [23:0] adjusted;integer q,i;
 always @*begin adjusted=bcd;for(q=0;q<6;q=q+1)if(bcd[q*4+:4]>=5)adjusted[q*4+:4]=bcd[q*4+:4]+4'd3;end
 always @(posedge clk or negedge rst_n)if(!rst_n)begin
  vs_d<=0;armed<=0;x<=0;y<=0;mode<=0;style_mode<=0;sv<=0;sx0<=0;sy0<=0;sx1<=0;sy1<=0;
  fc<=0;ft<=0;fu<=0;fid<=0;fo<=0;fl<=0;lv<=0;stale<=0;fa<=0;last_id<=0;stale_sticky<=0;
  job<=0;bitn<=0;busy<=0;load<=0;binary<=0;bcd<=0;total_bcd<=0;us_bcd<=0;age_bcd<=0;

 end else begin
  vs_d<=in_vs;
  if(in_vs && !vs_d)begin armed<=1;x<=0;y<=0;end
  else if(in_de && armed)if(x==W-1)begin x<=0;y<=(y==H-1)?12'd0:y+1'b1;end else x<=x+1'b1;
  if(frame_id!=last_id)begin last_id<=frame_id;stale_sticky<=0;end
  else if(latency_valid && age_us>=24'd200000)stale_sticky<=1;
  if(first)begin
   mode<=enable;style_mode<=COMBO_STATUS?style_active:1'b0;sv<=valid;sx0<=x0;sy0<=y0;sx1<=x1;sy1<=y1;
   fc<=count;ft<=total;fu<=process_us;fid<=frame_id;fo<=overflow;fl<=late;
   lv<=latency_valid;stale<=stale_sticky || age_us>=24'd200000;fa<=age_us;
   job<=0;busy<=1;load<=1;
  end else if(busy)begin
   if(load)begin
    load<=0;bitn<=0;bcd<=0;
    case(job)0:binary<={8'd0,ft};1:binary<={8'd0,fu};default:binary<=fa;endcase
   end else begin
    bcd<={adjusted[22:0],binary[23]};binary<={binary[22:0],1'b0};
    if(bitn==23)begin
     case(job)0:total_bcd<={adjusted[22:0],binary[23]};1:us_bcd<={adjusted[22:0],binary[23]};default:age_bcd<={adjusted[22:0],binary[23]};endcase
     if(job==2)busy<=0;else begin job<=job+1'b1;load<=1;end
    end else bitn<=bitn+1'b1;
   end
  end
 end
 reg [11:0] px,py;reg [23:0] rgb1,rgb2;reg [3:0] c1,c2;reg md1,protect1;
 reg hit2;reg [23:0] paint2;reg hit;reg [23:0] paint;
 reg [7:0] ch;reg [34:0] bits;reg [4:0] row;reg ink,hud;reg [3:0] col,hr,idx;reg [3:0] dig;
 function [23:0] color;input integer n;begin case(n)
  0:color=24'h00ffff;1:color=24'hffb030;2:color=24'hffff30;3:color=24'h70a0ff;
  4:color=24'hff70dd;5:color=24'h70ff90;6:color=24'hffffff;default:color=24'hff8050;endcase end endfunction
 function [7:0] dec;input [3:0] d;begin dec="0"+d;end endfunction
 function [7:0] hexch;input [3:0] d;begin hexch=d<10?"0"+d:"A"+d-10;end endfunction
 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "G":glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
   "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
   "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
   "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   "Y":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
   "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
   "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "I":glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "N":glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
   "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "X":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
   "+":glyph={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
   default:glyph=35'd0;
  endcase end
 endfunction
 integer z;reg [12:0] bx,by;reg [11:0] ox,oy;reg tag;reg [3:0] tx,ty;
 always @*begin
  hit=0;paint=rgb1;ch=" ";col=0;hr=0;idx=0;dig=0;hud=0;tag=0;tx=0;ty=0;ox=0;oy=0;bx=0;by=0;
  if(md1 && c1[0])begin
   // Preserve existing Logo/OSD; each independent box has a fixed slot color.
   for(z=0;z<N;z=z+1)begin
    if(fv[z] && !protect1 && px>=fx0[z*12+:12] && px<=fx1[z*12+:12] && py>=fy0[z*12+:12] && py<=fy1[z*12+:12] &&
      (px==fx0[z*12+:12] || px==fx0[z*12+:12]+12'd1 || px==fx1[z*12+:12] || px+12'd1==fx1[z*12+:12] ||
       py==fy0[z*12+:12] || py==fy0[z*12+:12]+12'd1 || py==fy1[z*12+:12] || py+12'd1==fy1[z*12+:12]))begin hit=1;paint=color(z);end
   end
   // Replaces the previous right-side mode HUD only in mode 4.
   if(px>=1008 && px<1264 && py>=16 && py<112)begin
    hud=1;col=(px-1008)>>4;hr=(py-16)>>4;tx=px[3:0];ty=py[3:0];ch=" ";
    case(hr)
     0:case(col)0:ch="M";1:ch="O";2:ch="D";3:ch="E";4:ch=":";5:ch="M";6:ch="U";7:ch="L";8:ch="T";9:ch="I";10:ch=style_mode?"+":" ";11:ch=style_mode?"S":" ";12:ch=style_mode?"T":" ";13:ch=style_mode?"Y":" ";14:ch=style_mode?"L":" ";15:ch=style_mode?"E":" ";endcase
     1:case(col)0:ch="N";1:ch=":";2:ch=dec(fc);4:ch="T";5:ch="O";6:ch="T";7:ch=":";8,9,10,11,12:ch=dec(total_bcd[(12-col)*4+:4]);14:ch=fo?"+":" ";15:ch=fl?"L":" ";endcase
     2:case(col)0:ch="L";1:ch="A";2:ch="T";3:ch=":";
      4,5,6,7,8,9:ch=lv && !stale?dec(age_bcd[(9-col)*4+:4]):"-";
      10:ch="U";11:ch="S";13:ch=stale?"S":" ";endcase
     3:case(col)0:ch="D";1:ch="E";2:ch="T";3:ch=":";4,5,6,7,8,9:ch=dec(us_bcd[(9-col)*4+:4]);10:ch="U";11:ch="S";endcase
     4:case(col)0:ch="F";1:ch="I";2:ch="D";3:ch=":";4,5,6,7:ch=hexch(fid[(7-col)*4+:4]);endcase
     5:begin if(col<N*2 && !col[0])ch="1"+col[3:1];end
    endcase
    paint=hr==5?color(col[3:1]):24'h60ffff;
   end
  end
  bits=glyph(ch);row=0;
  case(ty[3:1])0:row=bits[34:30];1:row=bits[29:25];2:row=bits[24:20];3:row=bits[19:15];4:row=bits[14:10];5:row=bits[9:5];6:row=bits[4:0];endcase
  ink=tx[3:1]<5 && row[4-tx[3:1]];
  if(hud)begin hit=1;if(!ink)paint=24'h101820;end
  else if(tag)begin if(ink)hit=1;else if(!hit)paint=rgb1;end
 end
 always @(posedge clk or negedge rst_n)if(!rst_n)begin
  px<=0;py<=0;rgb1<=0;rgb2<=0;c1<=0;c2<=0;md1<=0;protect1<=0;hit2<=0;paint2<=0;
  out_vs<=0;out_hs<=0;out_de<=0;out_rgb<=0;
 end else begin
  px<=x;py<=y;rgb1<=in_rgb;c1<={in_vs,in_hs,in_protect,in_de};md1<=first?enable:mode;protect1<=in_protect;
  rgb2<=rgb1;c2<=c1;hit2<=hit;paint2<=paint;
  out_vs<=c2[3];out_hs<=c2[2];out_de<=c2[0];out_rgb<=hit2?paint2:rgb2;
 end
endmodule

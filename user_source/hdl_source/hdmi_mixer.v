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
    reg  [14:0] S_logo_addr;
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
    wire [14:0] S_logo_prefetch_addr =
        (S_x < LOGO_W && S_y < LOGO_H)
        ? (({S_y,7'b0}+{S_y,5'b0})+S_x) : 15'd0;
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
        S_logo_addr = 15'd0;

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
                // LOGO_W=160=128+32：显式移位相加，避免地址路径映射为DSP乘法器。
                S_logo_addr = {S_logo_y, 7'b0} + {S_logo_y, 5'b0} + S_logo_x;
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

// Integrated ERAM logo definition: keep the mixer self-contained for TD source lists.
// Lossless logo ERAM. Generated from anlogic_logo_rom.v; do not hand-edit pixels.
// 10-bit cropped indices + all 25-bit palette colors, including transparency.
// Two synchronous reads reuse the mixer's existing x/y pipeline stages.
// Packed constant initialization is self-contained: no runtime file paths.
module anlogic_logo_eram(input wire I_clk,I_rst_n,input wire [14:0] I_addr,
 output wire [24:0] O_pixel);
 localparam [163839:0] INDEX_BITS={
  512'h00000000000000000000000000000000000000000000000000000001048f00401004010040100401004010040100401004010040108842000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000701bf06c1b06c1b06c1b06c1b06c1b06c1b06c1b06c1b06c1b06c1b06c1b06c1b6f9bd000000005709401004010040100401004010040100401004010040,
  512'h1004256f0000000000000000000000000000000000000000000000000000000000000006ec260040100401004010040100401004010040100401004012383500,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000006e9b90741d0741d0741d0741d0741d0741d0741d0741d0741d0741d0741d0741d6e1b7000000003109c0100401004010040100401004,
  512'h01004010040100401004011a1b60000000000000000000000000000000000000000000000000000000001b56d001004010040100401004010040100401004010,
  512'h0401004226cc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000124220040100,
  512'h401004010040100401004010040100401004016c9b10000000000000000000000000000000000000000000000000000000001b00980100401004010040100401,
  512'h004010040100401004010048e0d40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000dc4c0040100401004010040100401004010040100401004010045f6bc000000000000000000000000000000000000000000000000000023483004010040,
  512'h1004010040100401004010040100401004016b9ad000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000001ac0940100401004010040100401004010040100401004010041c6ac00000000000000000000000000000000000000000000000000,
  512'h006a8260040100401004010040100401004010040100401004016a48c00000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000001a869c010040100401004010040100401004010040100401004011848b00000000000000000000000000000000,
  512'h0000000000000001a61fc0100401004010040100401004010040100401004010041c694000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000069028004010040100401004010040100401004010040100401069a31a80000000000000,
  512'h000000000000000000000000000000007d098010040100401004010040100401004010040100401005a217800000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a168019064190641906,
  512'h41906419064190641906419064190641906419064190641906419064190659f67800000006759c00401004010040100401004010040100401004010040100432,
  512'h66c00000000000000000000000000000000000000000066999004010040100401004010040100401004010040100401071980000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000065d966,
  512'h54180601806018060180601806018060180601806018060180601806018060180601806018060181b46e00000001940e00100401004010040100401004010040,
  512'h100401004010040964c8a00000000000000000000000000000000000000006482600401004010040100401004010040100401004010040164590000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000063c2f008020080200802008020080200802008020080200802008020080200802008020080200802008020218e000000018d224010040100401004,
  512'h010040100401004010040100401004011298c000000000000000000000000000000000000018b6281a00401004010040100401004010040100401004010041c6,
  512'h24000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000018861c050080200802008020080200802008020080200802008020080200802008020080200802008020080200986614000000061,
  512'h05000401004010040100401004010040100401004010040100474204000000000000000000000000000000000018309801004010040100401004010040100401,
  512'h00401004010045d22000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000018260416058160581605816058160581605816058160581605816058160581605816058160581605816058160,
  512'h59805fc00000005f88700401004010040100401004010040100401004010040100486214000000000000000000000000000000005f57c0040100401004010040,
  512'h10040100401004010040100401070840000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000017b5e81705c1705c1705c1705c1705c1705c1705c1705c1705c1705c1705c1705c1705c17,
  512'h05c1705c1705c1705c175e40000000001780d80100401004010040100401004010040100401004010040120d770000000000000000000000000000005d975004,
  512'h0100401004010040100401004010040100401004010b83f000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000825d0090040100401004010040100401004010040100401004010d9730000000000000000000000,
  512'h000001725c40100401004010040100401004010040100401004010041c1000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000012c80004010040100401004010040100401004010040100401005705bc000,
  512'h00000000000000000000007a0ac0100401004010040100401004010040100401004010042e5b8000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000001056d0040100401004010040100401004010040100401,
  512'h00401004255b000000000000000000000002056b0240100401004010040100401004010040100401004010884000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000016a200010040100401004010040,
  512'h100401004010040100401004015a5680000000000000000000059c2b0040100401004010040100401004010040100401004010b8330000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001661fc01004,
  512'h010040100401004010040100401004010040100401071650000000000000000016458c0100401004010040100401004010040100401004010042258800000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000001611f81505415054150541505415054150541505415054150541505415054150541505415054150541505415054150541505415054150547e58,
  512'h000000001f55f0040100401004010040100401004010040100401004010055e5740000000000000007c570010040100401004010040100401004010040100401,
  512'h0042e0fc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000015b568050140501405014050140501405014050140501405014050140501405014050140501405014050140501405014050,
  512'h1405014050142f56400000001ed580040100401004010040100401004010040100401004010041c55c0000000000005595500401004010040100401004010040,
  512'h10040100401004010884000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000005515300802008020080200802008020080200802008020080200802008020080200802008020080200802,
  512'h00802008020080200802008020080254951000000007a540010040100401004010040100401004010040100401004011e54f00000000005382b0040100401004,
  512'h010040100401004010040100401004011d4330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000534130080200802008020080200802008020080200802008020080200802008020080,
  512'h20080200802008020080200802008020080200802008025314b000000014a5241a00401004010040100401004010040100401004010040106878520000007751,
  512'hc7600401004010040100401004010040100401004010042251800000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000001455101304c1304c1304c1304c1304c1304c1304c1304c1304c1304c,
  512'h1304c1304c1304c1304c1304c1304c1304c1304c1304c1304c1304c1304c1304d4350800000005042b0040100401004010040100401004010040100401004010,
  512'h05404fc00000720ac010040100401004010040100401004010040100401004750fc0000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013e4f41405014050140501405014050140501405,
  512'h0140501405014050140501405014050140501405014050140501405014050140501405014050140513c4ec00000004e874068010040100401004010040100401,
  512'h004010040100401005394e0731c5370680100401004010040100401004010040100401004010703e000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000720d001004010040,
  512'h1004010040100401004010040100401004010d1364d42b0040100401004010040100401004010040100401004014d03300000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h714cc1a004010040100401004010040100401004010040100401005324c41a00401004010040100401004010040100401004010041c0f0000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000004c12f0040100401004010040100401004010040100401004010041a068010040100401004010040100401004010040100401004701bc00,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000004b92d06801004010040100401004010040100401004010040100401004010040100401004010040100401004010040,
  512'h1004014b12b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000012a4a40100401004010040100401004010040100401004010040100401004010040100401004,
  512'h01004010040100401004011c06500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000004a12704812048120481204812048120481204812048120481204812048120481204812048120481,
  512'h2048120481204812048120481204812048120481204812048120481249925000000012448c1a0040100401004010040100401004010040100401004010040100,
  512'h4010040100401004010040100401004010042a0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000001224840b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c,
  512'h0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b02c0b4811f478000000047432004010040100401004010040100401004010,
  512'h04010040100401004010040100401004010040100401004010051c1bc00000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000011b02002008020080200802008020080200802008020080200,
  512'h80200802008020080200802008020080200802008020080200802008020080200802008020080200802008020091a46400000004611706801004010040100401,
  512'h00401004010040100401004010040100401004010040100401004010040100401095160000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b86d0080200802008020080200802008020,
  512'h080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080545514000000006c44c0,
  512'h10040100401004010040100401004010040100401004010040100401004010040100401004010040144831000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001ad11044110441104411,
  512'h04411044110441104411044110441104411044110441104411044110441104411044110441104411044110441104411044110441104411044110441104411441,
  512'h0f000000006a11869004010040100401004010040100401004010040100401004010040100401004010040100401004290f80000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004381,
  512'h00401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004,
  512'h01004010040104350c000000000042c3d004010040100401004010040100401004010040100401004010040100401004010040100401004680c4000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000019d0a0680100401004010040100401004010040100401004010040100401004010040100401004010943,
  512'hc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000109420010040100401004010040100401004010040100401004010040100401004,
  512'h0100401004010b431000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000041c1a004010040100401004010040100401004010040100,
  512'h40100401004010040100401004224180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004146600401004010040100401004010,
  512'h0401004010040100401004010040100401004010042d194000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001040680100401,
  512'h00401004010040100401004010040100401004010040100401004010883000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000040d0203c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f0,
  512'h3c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f405000000,
  512'h0000ff190010040100401004010040100401004010040100401004010040100401004010b4fe0000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003f42f00c0300c0300c0300c0300c03,
  512'h00c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c,
  512'h0300c0306cfc00000000003ec1c00401004010040100401004010040100401004010040100401004010042a0c000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fa3e402008020080,
  512'h20080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200,
  512'h80200802008020080200802014f83dc000000018cf60040100401004010040100401004010040100401004010040100401004f51800000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'hf4020020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020,
  512'h0802008020080200802008020080200802008020083b3cc0000000000f207001004010040100401004010040100401004010040100401004010a856000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000188f101004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004,
  512'h0100401004010040100401004010040100401004010040100401004010f03bcee00000000ed18401004010040100401004010040100401004010040100401004,
  512'h010b4ec0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000003acea0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380,
  512'he0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e0380e3a4e8000000000039c1c00401004010040100401004010040100,
  512'h40100401004010042939800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000394e40040100401004010,
  512'h040100401004010040100401004010042d1800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e3,
  512'h0700100401004010040100401004010040100401004010a030000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000e217c0100401004010040100401004010040100401004010e83900000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000003841c00401004010040100401004010040100401004280c0000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000001785d004010040100401004010040100401004010043a16400000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e037c0d034,
  512'h0d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0340d0,
  512'h340d0340d0340d0340d0340d0340d0340d0340d0340d0340d034de1700000000000dd070010040100401004010040100401004010a0530000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000370db014050140501405014050140501405014050140501405014050140501405014050140501405014050140501405014050140501405014050140501405,
  512'h014050140501405014050140501405014050140501405014050140501405014050141816c5a00000000da364010040100401004010040100401004010e859000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000003601800802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080,
  512'h20080200802008020080200802008020080200802008020080200802008020080200802008020080200802160d7000000000015c220040100401004010040100,
  512'h40100429158000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000055358020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008,
  512'h020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802134d5350000000034c54004010,
  512'h04010040100401004010042734800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000d10bc08020080200802008020080200802008020080200802008020080200802008020080200802,
  512'h0080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020d033c00,
  512'h00000000530a401004010040100401004010a44f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000148ce0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0,
  512'h280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280,
  512'ha0280a028cd33000000000003909c010040100401004010040109ccb000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000032828004010040100401004223240000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000320c700401004010040100427114000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000510e0010040100401094c600000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c531001004010040109cc30000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030850004010042813,
  512'hc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000c13000701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c,
  512'h0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701c0701cbf00000000002,
  512'hf8bd00401004270dc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000bc058040100401004010040100401004010040100401004010040100401004010040100401004010040100401,
  512'h00401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004,
  512'h010bb2e80000000000b90d801138b800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000002dcb600802008020080200802008020080200802008020080200802008020080200802008020,
  512'h08020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080,
  512'h20080200802008020084d2d40000000000b42cc01130b20000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000002c40b0080200802008020080200802008020080200802008020080200802,
  512'h00802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008020080200802008,
  512'h02008020080200802008020080200802008022c0af000000000012c4a12400000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000ae120ad00c0300c0300c0300c0300c0300c0300c0300c0,
  512'h300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300,
  512'hc0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0311cac00000000002ac461140000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa2a40601806018060180601806018,
  512'h06018060180601806018060180601806018060180601806018060180601806018060180601806018060180601806018060180601806018060180601806018060,
  512'h180601806018060180601806018060180601806018060180601806018060180601806018a829c0000000000a6000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00002439080000000906400300c0300c0300c0300c0300c0300c0300c0300c0323f8f8000000000000000000000000000000a58f40c0300c0300c0300c0300c0,
  512'h300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0300c0323c2940,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000023b8e800000008e4950240902409024090240902409024090240902409024098e23700000000000000000000000000000026c2202409,
  512'h02409024090240902409024090240902409024090240902409024090240902409024090240902409024090240902409024090240902409024090240902409024,
  512'h0902409264a100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000001685b8da350000025e340680100401004010040100401004010040100401004010689c000000000000000000000000,
  512'h0000008cc2e004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100,
  512'h4010040100401004010040128e320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000008c45802e30000000022f288010040100401004010040100401004010040100401004668b800000,
  512'h00000000000000000000000003e09401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010,
  512'h0401004010040100401004010040100401004968b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000022c8ac478a8488a400000a48a01a0040100401004010040100401004010040100,
  512'h4010040989ca40000000000000000000000000000398980100401004010040100401004010040100401004010040100401004010040100401004010040100401,
  512'h00401004010040100401004010040100401004010040100401004a32680000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000225890441104488c000000088832004010040100401004010,
  512'h04010040100401004010040128a21000000000000000000000000000000144910040100401004010040100401004010040100401004010040100401004010040,
  512'h10040100401004010040100401004010040100401004010040100401004010040107220000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000087e1e06801,
  512'h004010040100401004010040100401004010040106a1d1cc00000000000000000000000000087087004010040100401004010040100401004010040100401004,
  512'h01004010040100401004010040100401004010040100401004010040100401004010040100401004012809f00000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000021b0f4010040100401004010040100401004010040100401004348680000000000000000000000000000009310c01004010040100401004010040100,
  512'h4010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010041c864000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000678601a00401004010040100401004010040100401004010047685e160000000000000000000000000000418540100401004010,
  512'h04010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010042c85000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000084e1200401004010040100401004010040100401004010040109a11000000000000000000000000000000,
  512'h214260040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010a8,
  512'ha1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000002100680100401004010040100401004010040100401004010060f83800000000000,
  512'h00000000000000001ee0d00401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100401004010040100,
  512'h40100401004012809f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000008320b090240902409024090240920a0000000209820010040100401004010040100401004010040100401004,
  512'h2881c0000000000000000000000000000007c2180100401004010040100401004010040100401004010040100401004010040100401004010040100401004010,
  512'h0401004010040100401004010049e818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000005281405014050140501405014050149d810000000080c69004010040100401004010040100,
  512'h401004010040100401808370000000000000000000000000000778041a0040100401004010040100401004010040100401004010040100401004010040100401,
  512'h0040100401004010040100401004010040100401006007fc00000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000001fe0ec0200802008020080200802008187f4000000022c6400401004010,
  512'h0401004010040100401004010040100401089fc00000000000000000000000000000025034004010040100401004010040100401004010040100401004010040,
  512'h10040100401004010040100401004010040100401004010040100401279fb0000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000007e9f90140200802008020080200802008022745500000,
  512'h0009c068010040100401004010040100401004010040100401005f87dc000000000000000000000000000229f606801004010040100401004010040100401004,
  512'h0100401004010040100401004010040100401004010040100401004010040100401004010b098000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d5f408c2308c2308c2308c2308c2,
  512'h308c230edf300000000631e40100401004010040100401004010040100401004010041c7c80000000000000000000000000000006c0c80100401004010040100,
  512'h401004010040100401004010040100401004010040100401004010040100401004010040100401004010041c26c0000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001702108421084,
  512'h2108421084210842108421085f100000000007c01c0040100401004010040100401004010040100401004017bdee0000000000000000000000000001ed1e1ec0,
  512'h781e0781e0781e0781e0781e0781e0781e0781e0781e0781e079eb0040100401004010040100401004010040100401004010042c268000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000007a9e9004010040100401004010040100401004010040100401069e800000000000000000000,
  512'h0000000000221e708020080200802008020080200802008020080200802008020799e50040100401004010040100401004010040100401004012644200000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000001e40700100401004010040100401004010040100401004010043d78c0,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000007884e004010040100401004010040100401004010040100,
  512'h4010b098000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e178001004010040100401004010040100401004,
  512'h01004010040977c97000000000000000000000000000000000000000000000000000000000000000000000000000001de7740100401004010040100401004010,
  512'h04010040100401004962480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007702a00401004010040100,
  512'h401004010040100401004010040125494000000000000000000000000000000000000000000000000000000000000000000000000000000930e0010040100401,
  512'h0040100401004010040100401004010042c0d4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076dda0,
  512'h04010040100401004010040100401004010040100401025d976000000000000000000000000000000000000000000000000000000000000000000000000075dd,
  512'h60040100401004010040100401004010040100401004010709200000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000007546b07c1f07c1f07c1f07c1f07c1f07c1f07c1f07c1f07c1f07c1f,
  512'h751d300000001d20a8010040100401004010040100401004010040100401005d1740000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000240910040100401004010040100401004010040100401004010b0350000000000000000000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000073dce02c0b02c0b02c0b02c0b02c0b02c0b02c0,
  512'hb02c0b02c0b02c0b00dcd000000008c7300100401004010040100401004010040100401004010040172c8d000000000000000000000000000000000000000000,
  512'h000000000000000000000000008223c0100401004010040100401004010040100401004010041c10800000000000000000000000000000000000000000000000,
  512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001ca72405008020080200802008,
  512'h02008020080200802008020080200802009c818800000002102900401004010040100401004010040100401004010040110dc700000000000000000000000000,
  512'h0000000000000000000000000000000000000000009010c010040100401004010040100401004010040100401005c67140000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c470c0200,
  512'h8020080200802008020080200802008020080200802008020080870800000000cc54004010040100401004010040100401004010040100401004897040000000
 };
 localparam [25599:0] PALETTE_BITS={
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
  512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fef070fef0f17131d395c657aadb2bd62e427edce,
  512'hd0f6e7688fccc4dfe181974d596f32405edddfe37cca4c7f3515758637be2e4e7f03132ff13135f65a5fd557dcebed2fae4f71dfddcddfca6297c47c9ff55559,
  512'h5a667cadb3becf12597fbb5b7fc9ea0fe5fe06b6c6f34d576d727b8ff57576d719dfaa8beefd2d5d9d759dee6e86b6e0f51b5f6a80a5ac38f73778690a8ddc2c,
  512'h5ccd85adfcaced6b212d4b616c82a0a7b574f5b6e98b0e5fa9c9ffb27aafe9d5e7676f832c3c5bc1c5ce5bde637ea8a99fab0b2b237c24e92196a0b8eb324260,
  512'he0e2e67e23a4beebcc77b8395b8bd477f36367ea8895364462e1e3e6d5985e7f51f27f3282ffcb2b4dc1e633f53b3f6a7488989faeee6f717d3d5db2131518e9,
  512'h6a76f703226280bb646e84c3464e59dbe0a4868a56c768ad658dde2a468381879532415eac323e7575f6e84a0d5717a8de1e3664d50d82a2bcede1e2e6eb6c6e,
  512'h50d41aff9b1b5fa676dfde0615cdf23e4a6cad999eabfcc5c77c884a7ecccd7374561a4aab7ff3535bea828ff22e35c74a51cd10983878d9df98a8ef890947dd,
  512'h9db3a5a9b3fcd4d5fba2a5fd8d4f3f57b7f80889ac7cb527ef4747f13337f9979afce1e2727374fb3b7bf46536db8bdc747cbd42f101279097a5e0e265c7cbd4,
  512'h6e6f921828a9ab6bb4564e669e6a86c3cfd1d79ea5b3f6f7786e8fd23858d9cb136414d10d87f5353bf6676bfb33357e6424ba3a9b33e4c67d4d75cf737b8a92,
  512'hacdf757f91fe6868fd4f513e03a4b878e9eab313d6627aae6888c3c4c8cefc41437ddd1dfa7adb5a0a6b2eeeff15295dc6ed0123fccfcffa1e21fccd4f3f5858,
  512'h98991a0cc4f567e60617e84253f32028fcb93b75b5f73bdbfc74b5872fe51d37ee3643f735398a92a1eced6fe667eb6486aa943516cc5c8d0f7b838e9ab2e53f,
  512'h4d68e8696bf17274288a4db7d8597a6ad39e3e5a966e8ac5c7cad1cdd0d776f7382e8fd21e0e1e5a72db9dd5fa47f99fa1fbcfd09199aa4cd097f7f879525365,
  512'h5fc3dbffc0809ff0f9014a5670b5ba447878f9a9cb6e9fbc8caf99ca07d0e907f79799243454dadce0e7a92c3eef2fbf01f27fbbfc1f7f838e9cb4e7e8e9eca7,
  512'hadbadde064ff79193f43b41fb1f227ef33373b475f2a3958d3d65bfeaff03ed0d13f68487fde1e27878b963a5a9f546078a7ae3ae6a7eb7414f67364561a9af3,
  512'hb4f12592869ed1a3a8b3939babf979ba2aac2f11e3050bd41cae96aad65072b1f99093fd36387e9b1c7f73d43e6e7e9acb23dfef0b13e86877f01c24fa9fa37f,
  512'h34b4f515b71374662fbb9bbfc484a7f10b13e7e8ebadb33ede60a4fea808dfcd3d4951dacce1198be64253f5252cfd45c77ea5a67f1151bfba2a4d7da5ed85ae,
  512'h07656d812c3b5ab1b741dee1257697385636e84fde4e57ddddeff30109fcdddedb5d62727334fecd2ddf88e91b33842feaeaf3e45c6df54349fe6bec4b8f5727,
  512'h290c9f6676cfc46c859dca1fea5e6df11c25fb22a5ff36363757f8fcbced3fd5adc7ee0617f70d13facdceb5bac4df6125b7b839131415eb7bc467030f2eeafb,
  512'h1ffa898dfb32357dd99b2f10125fab3b5fa169a71f2742708ac5f76167fc4dcf7ccb0cfea9ca7fcdfe0e566697333b4ff0c2cdf2272efccf507ddfe0beaeaf3f,
  512'h89b9de667ea6062262ff0f33cfd1d69ea5336062667a1a7b13f4c68e6e86ae1a3677f77f83fb7a7ffdc647f4f576a829cd5f75d63f99397fe68e971321417f87,
  512'h97fd57587cca8cbecacb7d5d7dca1a8b5f3b435beebac5f2282ffcd354feaaebbe23c4df8575deb6ceefeea6aff0fd05f88688fe6aeaf4f5363b1b3bbe8e9eb9,
  512'h920b04a4e562e0f51d32425fe162e6c78bd47e65665677186b8bdc7f0713323a5ea1c2c6cdf373f5474b9425070b1a3a9b5c649d15cdf6424464a78e95a3a2a9,
  512'h364cd0d83b5b9c1c5c8cfdb5d61f979ba6809cd3c6c9cfa127b5490d5572b3953778092a3aa3775b6377bfc3c9223354a42ab7fe19db32b37539ba2aeeeef716,
  512'h667eb25e7cb9606a80f171f3474b93a6c8ac54f5b74f17273e7e96c7c7c9cf374663e465e8feb070fe86875abb0bafd38bb7a7abb2385c9f384663f575f6cb0f,
  512'h16b9397a52d3d5bdcdee37eae2ea5e7ebbcacdd39a21b07131f3a6c88c3faacaefaa5a8ff37b7f979da9f1242cbdc1ca5fa1a5ff56569394763bec2cb7f3676b,
  512'h071737213253c0444c484c54bdc3a4b3c4a65c6ca51c98dd5eff0f31f62c34f90f93d7da5ff999fabfb9a9d9199a9dc9f23fb1b5bd767f91e364e85e6064e567,
  512'h6b3798294f891154e92193999da9213252e6e7eac88cd4f878f9d263656e3e5684a8e9679399a57c8596f890144d51186728ec9334260929aaac7cc1424060a3,
  512'h2031529da4b2c8cd1524062a3f54e55f79094c7cc147ed2327838999fcb032c80c143f12d311e2f50f91115474b93feaccd5ef1d25fdc6487c47497eab2bff58,
  512'h386f79013fe5adc3e2404ff78a8cfab93b7ea0213eac8d55b6579f78e127d1d5e6385a9fef1e26fd3cbefddfa07dc3849f01c25f80f137b47092385a9c000000
 };
 reg [9:0] index_mem[0:16383];
 reg [24:0] palette_mem[0:1023];
 integer init_i;
 initial begin
  for(init_i=0;init_i<16384;init_i=init_i+1)index_mem[init_i]=INDEX_BITS[init_i*10+:10];
  for(init_i=0;init_i<1024;init_i=init_i+1)palette_mem[init_i]=PALETTE_BITS[init_i*25+:25];
 end
 reg [9:0] index_q;
 reg range_q;
 reg [24:0] pixel_q;
 reg [1:0] valid_q;
 always @(posedge I_clk)begin
  index_q<=index_mem[I_addr[13:0]];
  if(I_addr>=15'd5494 && I_addr<=15'd20426)range_q<=1'b1;else range_q<=1'b0;
  pixel_q<=palette_mem[range_q?index_q:10'd0];
 end
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)valid_q<=0;else valid_q<={valid_q[0],1'b1};
 end
 assign O_pixel=valid_q[1]?pixel_q:25'd0;
endmodule

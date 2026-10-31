// White-field calibration helper.
// Samples nine 128x128 patches, one patch per frame. After nine frames all
// nine averages are held and shown together. Only glyph pixels and rectangle
// borders are overlaid; the background is transparent. Sampling happens before
// this overlay, so the labels never affect the measured values.
module white_field_rgb_osd #(
    parameter integer W = 1280,
    parameter integer H = 720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_vs,
    input  wire        in_hs,
    input  wire        in_de,
    input  wire [23:0] in_rgb,
    output wire        out_vs,
    output wire        out_hs,
    output wire        out_de,
    output reg  [23:0] out_rgb
);

    reg        vs_d;
    reg        armed;
    reg [11:0] x;
    reg [11:0] y;

    wire frame_start = in_vs && !vs_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d <= 1'b0;
            armed <= 1'b0;
            x <= 12'd0;
            y <= 12'd0;
        end else begin
            vs_d <= in_vs;
            if (in_vs && !vs_d) begin
                x <= 12'd0;
                y <= 12'd0;
                armed <= 1'b1;
            end else if (in_de && armed) begin
                if (x == W - 1) begin
                    x <= 12'd0;
                    y <= (y == H - 1) ? 12'd0 : y + 1'b1;
                end else begin
                    x <= x + 1'b1;
                end
            end
        end
    end

    // Edge patches: the outer 128x128 strips include the real screen border.
    // Left/center/right x = 0/576/1152; top/middle/bottom y = 0/296/592.
    function [11:0] patch_x;
        input [3:0] b;
        begin
            case (b)
                4'd0,4'd3,4'd6: patch_x = 12'd0;
                4'd1,4'd4,4'd7: patch_x = 12'd576;
                default:        patch_x = 12'd1152;
            endcase
        end
    endfunction

    function [11:0] patch_y;
        input [3:0] b;
        begin
            case (b)
                4'd0,4'd1,4'd2: patch_y = 12'd0;
                4'd3,4'd4,4'd5: patch_y = 12'd296;
                default:        patch_y = 12'd592;
            endcase
        end
    endfunction

    reg [3:0]  sample_block;
    reg [21:0] sum_r, sum_g, sum_b;

    wire [11:0] sample_x = patch_x(sample_block);
    wire [11:0] sample_y = patch_y(sample_block);
    wire sample = in_de && armed &&
                  (x >= sample_x) && (x < (sample_x + 12'd128)) &&
                  (y >= sample_y) && (y < (sample_y + 12'd128));

    wire [7:0] sample_r = sum_r[21:14];
    wire [7:0] sample_g = sum_g[21:14];
    wire [7:0] sample_b = sum_b[21:14];

    // Stored decimal digits for all nine patches, so every value can be shown
    // at the same time without a per-pixel divider.
    reg [3:0] r_h [0:8];
    reg [3:0] r_t [0:8];
    reg [3:0] r_o [0:8];
    reg [3:0] g_h [0:8];
    reg [3:0] g_t [0:8];
    reg [3:0] g_o [0:8];
    reg [3:0] b_h [0:8];
    reg [3:0] b_t [0:8];
    reg [3:0] b_o [0:8];

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_block <= 4'd0;
            sum_r <= 22'd0;
            sum_g <= 22'd0;
            sum_b <= 22'd0;
            for (k = 0; k < 9; k = k + 1) begin
                r_h[k] <= 4'd0; r_t[k] <= 4'd0; r_o[k] <= 4'd0;
                g_h[k] <= 4'd0; g_t[k] <= 4'd0; g_o[k] <= 4'd0;
                b_h[k] <= 4'd0; b_t[k] <= 4'd0; b_o[k] <= 4'd0;
            end
        end else if (frame_start) begin
            // One 128x128 patch per frame. 128*128 = 16384 samples.
            r_h[sample_block] <= sample_r / 8'd100;
            r_t[sample_block] <= (sample_r % 8'd100) / 8'd10;
            r_o[sample_block] <= sample_r % 8'd10;
            g_h[sample_block] <= sample_g / 8'd100;
            g_t[sample_block] <= (sample_g % 8'd100) / 8'd10;
            g_o[sample_block] <= sample_g % 8'd10;
            b_h[sample_block] <= sample_b / 8'd100;
            b_t[sample_block] <= (sample_b % 8'd100) / 8'd10;
            b_o[sample_block] <= sample_b % 8'd10;

            sum_r <= 22'd0;
            sum_g <= 22'd0;
            sum_b <= 22'd0;
            sample_block <= (sample_block == 4'd8) ? 4'd0 : sample_block + 1'b1;
        end else if (sample) begin
            sum_r <= sum_r + {14'd0, in_rgb[23:16]};
            sum_g <= sum_g + {14'd0, in_rgb[15:8]};
            sum_b <= sum_b + {14'd0, in_rgb[7:0]};
        end
    end

    // One-stage pixel alignment for the overlay.
    reg [11:0] px, py;
    reg [23:0] rgb1;
    reg        vs1, hs1, de1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px <= 12'd0;
            py <= 12'd0;
            rgb1 <= 24'd0;
            vs1 <= 1'b0;
            hs1 <= 1'b0;
            de1 <= 1'b0;
        end else begin
            px <= x;
            py <= y;
            rgb1 <= in_rgb;
            vs1 <= in_vs;
            hs1 <= in_hs;
            de1 <= in_de;
        end
    end

    // Nine fixed label cells, one per patch. The labels are transparent:
    // only the 16x16 font pixels and the patch borders are drawn.
    wire [1:0] label_col = (px < 12'd426) ? 2'd0 : (px < 12'd852) ? 2'd1 : 2'd2;
    wire [1:0] label_row = (py < 12'd240) ? 2'd0 : (py < 12'd480) ? 2'd1 : 2'd2;
    wire [3:0] label_block = {2'b0, label_row} * 3 + {2'b0, label_col};

    wire [11:0] label_x = {4'b0, label_col} * 12'd426 + 12'd12;
    wire [11:0] label_y = {4'b0, label_row} * 12'd240 + 12'd12;
    wire [11:0] lx = px - label_x;
    wire [11:0] ly = py - label_y;

    wire label_area = de1 &&
                      (px >= label_x) && (px < (label_x + 12'd112)) &&
                      (py >= label_y) && (py < (label_y + 12'd48));

    wire [1:0] line = ly[5:4];
    wire [3:0] row  = ly[3:0];
    wire [3:0] col  = lx[6:4];
    wire [3:0] gcol = lx[3:0];

    wire [3:0] lr_h = r_h[label_block];
    wire [3:0] lr_t = r_t[label_block];
    wire [3:0] lr_o = r_o[label_block];
    wire [3:0] lg_h = g_h[label_block];
    wire [3:0] lg_t = g_t[label_block];
    wire [3:0] lg_o = g_o[label_block];
    wire [3:0] lb_h = b_h[label_block];
    wire [3:0] lb_t = b_t[label_block];
    wire [3:0] lb_o = b_o[label_block];

    wire [7:0] block_digit = 8'h31 + {4'd0, label_block};

    function [7:0] digit_char;
        input [3:0] d;
        begin
            digit_char = 8'h30 + {4'd0, d};
        end
    endfunction

    reg [7:0] ch;
    always @(*) begin
        ch = 8'h20;
        case (line)
            2'd0: begin
                case (col)
                    4'd0: ch = block_digit;
                    4'd1: ch = 8'h20;
                    4'd2: ch = "R";
                    4'd3: ch = ":";
                    4'd4: ch = digit_char(lr_h);
                    4'd5: ch = digit_char(lr_t);
                    4'd6: ch = digit_char(lr_o);
                    default: ch = 8'h20;
                endcase
            end
            2'd1: begin
                case (col)
                    4'd2: ch = "G";
                    4'd3: ch = ":";
                    4'd4: ch = digit_char(lg_h);
                    4'd5: ch = digit_char(lg_t);
                    4'd6: ch = digit_char(lg_o);
                    default: ch = 8'h20;
                endcase
            end
            2'd2: begin
                case (col)
                    4'd2: ch = "B";
                    4'd3: ch = ":";
                    4'd4: ch = digit_char(lb_h);
                    4'd5: ch = digit_char(lb_t);
                    4'd6: ch = digit_char(lb_o);
                    default: ch = 8'h20;
                endcase
            end
            default: ch = 8'h20;
        endcase
    end

    wire [15:0] row_bits;
    osd_char_lib u_font (
        .I_char    (ch),
        .I_row     (row),
        .O_row_bits(row_bits)
    );

    wire ink = label_area && row_bits[15 - gcol];

    // Draw a 2-pixel border around every 128x128 sampling patch.
    reg box_hit;
    integer b;
    always @(*) begin
        box_hit = 1'b0;
        if (de1) begin
            for (b = 0; b < 9; b = b + 1) begin
                if ((px >= patch_x(b)) && (px < (patch_x(b) + 12'd128)) &&
                    (py >= patch_y(b)) && (py < (patch_y(b) + 12'd128)) &&
                    ((px < (patch_x(b) + 12'd2)) ||
                     (px >= (patch_x(b) + 12'd126)) ||
                     (py < (patch_y(b) + 12'd2)) ||
                     (py >= (patch_y(b) + 12'd126)))) begin
                    box_hit = 1'b1;
                end
            end
        end
    end

    assign out_vs = vs1;
    assign out_hs = hs1;
    assign out_de = de1;

    always @(*) begin
        if (ink) begin
            out_rgb = 24'h000000;
        end else if (box_hit) begin
            out_rgb = 24'h00FF00;
        end else begin
            out_rgb = rgb1;
        end
    end

endmodule

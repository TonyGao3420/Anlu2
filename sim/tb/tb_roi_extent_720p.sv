`timescale 1ns/1ps

// Frame-level regression for the streamed red detector. The small raster keeps
// simulation fast while exercising the same detector pipeline and thresholds.
module tb_roi_extent_720p;
    localparam integer IMG_W = 1280;
    localparam integer IMG_H = 720;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg in_frame_start = 1'b0;
    reg in_de = 1'b0;
    reg in_line_last = 1'b0;
    reg [23:0] in_rgb = 24'd0;

    wire target_valid;
    wire [15:0] bbox_x0, bbox_y0, bbox_x1, bbox_y1;
    wire [15:0] centroid_x, centroid_y;
    wire [19:0] target_area;
    wire frame_done, result_update;
    wire mask_valid, red_mask;
    wire [11:0] mask_x, mask_y;
    wire dbg_roi_valid, dbg_color_match;

    roi_target_tracker #(
        .IMG_W(IMG_W), .IMG_H(IMG_H),
        .ROI_HALF_W(320), .ROI_HALF_H(180),
        .ROI_MIN_HALF_W(96), .ROI_MIN_HALF_H(72),
        .ROI_MARGIN_X(48), .ROI_MARGIN_Y(32),
        .MIN_VALUE(24), .MIN_AREA(64), .MAX_AREA(120000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_frame_start(in_frame_start), .in_de(in_de),
        .in_line_last(in_line_last), .in_rgb(in_rgb),
        .target_valid(target_valid), .bbox_x0(bbox_x0), .bbox_y0(bbox_y0),
        .bbox_x1(bbox_x1), .bbox_y1(bbox_y1),
        .centroid_x(centroid_x), .centroid_y(centroid_y),
        .target_area(target_area), .frame_done(frame_done),
        .result_update(result_update), .mask_valid(mask_valid),
        .red_mask(red_mask), .mask_x(mask_x), .mask_y(mask_y),
        .dbg_roi_valid(dbg_roi_valid), .dbg_color_match(dbg_color_match)
    );

    task automatic send_frame_start;
        begin
            @(negedge clk);
            in_de = 1'b0;
            in_line_last = 1'b0;
            in_frame_start = 1'b1;
            @(negedge clk);
            in_frame_start = 1'b0;
        end
    endtask

    task automatic send_pixel(input [23:0] pixel, input bit last_pixel);
        begin
            @(negedge clk);
            in_de = 1'b1;
            in_line_last = last_pixel;
            in_rgb = pixel;
        end
    endtask

    task automatic send_rect_frame(
        input integer x0, input integer y0,
        input integer x1, input integer y1,
        input [23:0] rect_color
    );
        integer x, y;
        reg [23:0] pixel;
        begin
            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    pixel = ((x >= x0) && (x <= x1) &&
                             (y >= y0) && (y <= y1)) ? rect_color : 24'h303030;
                    send_pixel(pixel, x == IMG_W - 1);
                end
                @(negedge clk);
                in_de = 1'b0;
                in_line_last = 1'b0;
                in_rgb = 24'd0;
                repeat (2) @(negedge clk);
            end
            in_de = 1'b0;
            in_line_last = 1'b0;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic send_h_frame;
        integer x, y;
        reg in_h;
        begin
            // A sparse, hollow red object exercises the case rejected by the
            // former >=50% red-pixel-to-bounding-box occupancy gate.
            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    in_h = (((x >= 16) && (x <= 18)) ||
                            ((x >= 33) && (x <= 35)) ||
                            ((y >= 14) && (y <= 16))) &&
                           (x >= 16) && (x <= 35) &&
                           (y >= 3) && (y <= 27);
                    send_pixel(in_h ? 24'hA04840 : 24'h303030,
                               x == IMG_W - 1);
                end
                @(negedge clk);
                in_de = 1'b0;
                in_line_last = 1'b0;
                in_rgb = 24'd0;
                repeat (2) @(negedge clk);
            end
            in_de = 1'b0;
            in_line_last = 1'b0;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic check_color_frame(
        input [23:0] test_color,
        input bit expected_detection
    );
        begin
            send_rect_frame(20, 8, 39, 23, test_color);
            send_frame_start();
            #1;
            if (frame_done !== 1'b1 || target_valid !== expected_detection)
                $fatal(1, "Color classifier mismatch for RGB=%06h: expected detect=%b got=%b",
                       test_color, expected_detection, target_valid);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // Repeated locked frames must retain objects larger than seed windows.
        send_frame_start();
        repeat (4) begin
            send_rect_frame(550, 60, 729, 659, 24'hA04840);
            send_frame_start();
            #1;
            if (!target_valid || bbox_y0 != 60 || bbox_y1 != 659)
                $fatal(1, "Tall object clipped after lock: y=%0d..%0d", bbox_y0, bbox_y1);
            repeat (70) @(negedge clk);
        end
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        send_frame_start();
        repeat (4) begin
            send_rect_frame(140, 320, 1139, 399, 24'hA04840);
            send_frame_start();
            #1;
            if (!target_valid || bbox_x0 != 140 || bbox_x1 != 1139)
                $fatal(1, "Wide object clipped after lock: x=%0d..%0d", bbox_x0, bbox_x1);
            repeat (70) @(negedge clk);
        end
        $display("PASS ROI tall/wide: complete bounds retained across four locked frames");
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;

        $finish;
    end
    initial begin
        #100_000_000; $fatal(1, "720p timeout");
    end
endmodule

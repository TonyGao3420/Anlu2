`timescale 1ns/1ps

// Frame-level regression for the streamed red detector. The small raster keeps
// simulation fast while exercising the same detector pipeline and thresholds.
module tb_roi_target_tracker;
    localparam integer IMG_W = 64;
    localparam integer IMG_H = 32;

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
        .ROI_HALF_W(24), .ROI_HALF_H(12),
        .ROI_MIN_HALF_W(8), .ROI_MIN_HALF_H(6),
        .ROI_MARGIN_X(4), .ROI_MARGIN_Y(3),
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

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // Muted red tests tolerance; the gray background must not be detected.
        send_frame_start();
        send_rect_frame(20, 8, 39, 23, 24'hA04840);
        send_frame_start();
        #1;
        if (!frame_done || !target_valid)
            $fatal(1, "ROI miss: expected the muted-red rectangle to be detected");
        if (bbox_x0 < 20 || bbox_x1 > 39 || bbox_y0 < 8 || bbox_y1 > 23 ||
            bbox_x1 <= bbox_x0 || bbox_y1 <= bbox_y0)
            $fatal(1, "ROI bounds invalid: (%0d,%0d)-(%0d,%0d)",
                   bbox_x0, bbox_y0, bbox_x1, bbox_y1);
        if (target_area < 128 || target_area > 320)
            $fatal(1, "ROI area outside expected denoised rectangle: %0d", target_area);
        wait (result_update === 1'b1);
        #1;
        if (centroid_x != 29 || centroid_y != 15)
            $fatal(1, "Centroid divider mismatch: (%0d,%0d)", centroid_x, centroid_y);
        $display("PASS ROI acquire: bounds=(%0d,%0d)-(%0d,%0d) area=%0d centroid=(%0d,%0d)",
                 bbox_x0, bbox_y0, bbox_x1, bbox_y1, target_area, centroid_x, centroid_y);

        send_h_frame();
        send_frame_start();
        #1;
        if (!frame_done || !target_valid)
            $fatal(1, "ROI miss: sparse red H-shaped object was rejected");
        if (bbox_x0 < 16 || bbox_x1 > 35 || bbox_y0 < 3 || bbox_y1 > 27 ||
            bbox_x1 <= bbox_x0 || bbox_y1 <= bbox_y0)
            $fatal(1, "Sparse ROI bounds invalid: (%0d,%0d)-(%0d,%0d)",
                   bbox_x0, bbox_y0, bbox_x1, bbox_y1);
        $display("PASS ROI sparse-object box: bounds=(%0d,%0d)-(%0d,%0d) area=%0d",
                 bbox_x0, bbox_y0, bbox_x1, bbox_y1, target_area);

        // Once locked, a target far outside the adaptive window is ignored.
        // The miss restores full-frame search, so the same target is acquired
        // on the next frame without requiring a reset.
        send_rect_frame(48, 4, 57, 27, 24'hA04840);
        send_frame_start();
        #1;
        if (!frame_done || target_valid)
            $fatal(1, "ROI gate did not reject a target outside the locked window");
        send_rect_frame(48, 4, 57, 27, 24'hA04840);
        send_frame_start();
        #1;
        if (!frame_done || !target_valid || bbox_x0 < 48 || bbox_x1 > 57)
            $fatal(1, "Full-frame reacquisition failed after ROI miss");
        $display("PASS ROI reacquire: bounds=(%0d,%0d)-(%0d,%0d)",
                 bbox_x0, bbox_y0, bbox_x1, bbox_y1);

        // An all-gray frame must release the ROI rather than keep a stale box.
        send_rect_frame(-1, -1, -1, -1, 24'hFF0000);
        send_frame_start();
        #1;
        if (!frame_done || target_valid || bbox_x0 != 0 || bbox_y0 != 0 ||
            bbox_x1 != 0 || bbox_y1 != 0)
            $fatal(1, "ROI stale/false positive after target removal");
        $display("PASS ROI release: no box on neutral frame");
        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "ROI simulation timeout");
    end
endmodule

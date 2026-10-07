`timescale 1ns/1ps

module tb_camera_link_replay;
    localparam integer IMG_HEIGHT = 8;
    localparam integer IMG_WIDTH  = 1280;

    reg clk = 0;
    reg rst_n = 0;
    reg tlast = 0;
    reg tuser = 0;
    reg tvalid = 0;
    reg [95:0] in_data = 0;
    reg o_tready = 1;

    wire o_tlast;
    wire o_tuser;
    wire o_tvalid;
    wire [95:0] o_data;

    awb #(
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_WIDTH(IMG_WIDTH),
        .AUTO_GAIN_ENABLE(0)
    ) dut (
        .I_clk(clk),
        .I_rst_n(rst_n),
        .I_tlast(tlast),
        .I_tuser(tuser),
        .I_tdata(in_data),
        .I_tvalid(tvalid),
        .I_tready(),
        .O_tlast(o_tlast),
        .O_tuser(o_tuser),
        .O_tdata(o_data),
        .O_tvalid(o_tvalid),
        .O_tready(o_tready)
    );

    always #5 clk = ~clk;

    function automatic [23:0] make_pixel;
        input integer row;
        input integer col;
        input bit green_bias;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            r = (col * 9 + row * 5) % 8'd200 + 8'd30;
            g = (row * 11 + col * 7) % 8'd180 + 8'd60 + (green_bias ? 8'd35 : 8'd0);
            b = ((row + col) * 13) % 8'd160 + 8'd40;
            make_pixel = {r, g, b};
        end
    endfunction

    task automatic drive_frame;
        input integer rows;
        input integer cols;
        input bit green_bias;
        integer row;
        integer col;
        reg [23:0] p0, p1, p2, p3;
        begin
            for (row = 0; row < rows; row = row + 1) begin
                // Real camera streams emit a row-start marker before the first valid payload.
                tuser = 1'b1;
                tvalid = 1'b1;
                p0 = make_pixel(row, 0, green_bias);
                p1 = make_pixel(row, 1, green_bias);
                p2 = make_pixel(row, 2, green_bias);
                p3 = make_pixel(row, 3, green_bias);
                in_data = {p3, p2, p1, p0};
                tlast = 1'b0;
                @(posedge clk);

                tuser = 1'b0;
                for (col = 0; col < cols; col = col + 4) begin
                    // Use a practical burst length that crosses the AWB delay threshold.
                    if (col + 4 <= cols) begin
                        p0 = make_pixel(row, col + 0, green_bias);
                        p1 = make_pixel(row, col + 1, green_bias);
                        p2 = make_pixel(row, col + 2, green_bias);
                        p3 = make_pixel(row, col + 3, green_bias);
                        in_data = {p3, p2, p1, p0};
                    end
                    tvalid = 1'b1;
                    tlast = (row == rows - 1 && col + 4 >= cols) ? 1'b1 : 1'b0;
                    @(posedge clk);
                end
            end

            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            repeat (12) @(posedge clk);
        end
    endtask

    initial begin
        $display("Starting camera-like replay regression");
        repeat (4) @(posedge clk);
        rst_n = 1;

        // First frame: camera sees a neutral gray scene with a mild green shift.
        drive_frame(IMG_HEIGHT, IMG_WIDTH, 1'b1);

        // Second frame: close to a neutral reference, verifying the pipeline remains stable.
        drive_frame(IMG_HEIGHT, IMG_WIDTH, 1'b0);

        // Wait for the end-to-end frame delay to flush before deciding whether the pipeline is alive.
        repeat (8000) begin
            if (o_tvalid) begin
                $display("PASS: camera-like replay produced valid output: %h", o_data[23:0]);
                $finish;
            end
            @(posedge clk);
        end

        $display("FAIL: camera-like replay produced no valid output");
        $fatal(1);
    end
endmodule

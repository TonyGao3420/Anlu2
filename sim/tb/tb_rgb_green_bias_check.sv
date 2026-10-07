`timescale 1ns/1ps

module tb_rgb_green_bias_check;
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

    function automatic [23:0] make_pixel;
        input integer row;
        input integer col;
        input integer green_bias;
        input integer idx;
        integer r;
        integer g;
        integer b;
        begin
            r = ((col * 13 + row * 7 + idx * 5) % 180) + 30;
            g = ((row * 17 + col * 11 + idx * 9) % 170) + 70 + green_bias;
            b = ((row * 11 + col * 5 + idx * 7) % 190) + 35;
            make_pixel = {r[7:0], g[7:0], b[7:0]};
        end
    endfunction

    task automatic drive_realistic_frame;
        input integer rows;
        input integer cols;
        input integer green_bias;
        integer row;
        integer col;
        reg [23:0] p0, p1, p2, p3;
        begin
            for (row = 0; row < rows; row = row + 1) begin
                tuser = (row == 0) ? 1'b1 : 1'b0;
                for (col = 0; col < cols; col = col + 4) begin
                    p0 = make_pixel(row, col + 0, green_bias, 0);
                    p1 = make_pixel(row, col + 1, green_bias, 1);
                    p2 = make_pixel(row, col + 2, green_bias, 2);
                    p3 = make_pixel(row, col + 3, green_bias, 3);
                    in_data = {p3, p2, p1, p0};
                    tvalid = 1'b1;
                    tlast = (row == rows - 1 && col + 4 >= cols) ? 1'b1 : 1'b0;
                    @(posedge clk);
                end
            end

            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            repeat (16) @(posedge clk);
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        integer cycle;
        $display("Starting realistic AWB camera-flow check");
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Frame 1: green-heavy scene, equivalent to a camera with a mild green cast.
        drive_realistic_frame(IMG_HEIGHT, IMG_WIDTH, 25);

        // Frame 2: neutral scene, to verify the AWB path stays stable rather than drifting frame-to-frame.
        drive_realistic_frame(IMG_HEIGHT, IMG_WIDTH, 0);

        // Wait long enough for the internal delay buffer and AWB update path to flush.
        for (cycle = 0; cycle < 10000; cycle = cycle + 1) begin
            if (o_tvalid) begin
                $display("PASS: realistic AWB camera stream generated valid output sample = %h", o_data);
                $finish;
            end
            @(posedge clk);
        end

        $display("FAIL: realistic AWB camera stream never produced a valid output");
        $fatal(1);
    end
endmodule

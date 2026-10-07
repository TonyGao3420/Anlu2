`timescale 1ns/1ps

module tb_basic_video_enhance;
    reg clk = 0;
    reg rst_n = 0;
    reg [23:0] in_rgb = 24'd0;
    reg in_vsync = 0;
    reg in_hsync = 0;
    reg in_de = 0;
    reg in_protect = 0;

    wire out_vsync;
    wire out_hsync;
    wire out_de;
    wire [23:0] out_rgb;

    video_enhance #(
        .ENABLE(0),
        .GAMMA_ENABLE(0),
        .SHARPEN_ENABLE(0),
        .CONTRAST_ENABLE(0),
        .SATURATION_ENABLE(0),
        .BRIGHTNESS_OFFSET(6),
        .BLACK_LEVEL(12),
        .WHITE_LEVEL(238),
        .SATURATION_Q8(320),
        .DETAIL_LIMIT(12),
        .NOISE_THRESHOLD(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_vsync(in_vsync),
        .in_hsync(in_hsync),
        .in_de(in_de),
        .in_protect(in_protect),
        .in_rgb(in_rgb),
        .out_vsync(out_vsync),
        .out_hsync(out_hsync),
        .out_de(out_de),
        .out_rgb(out_rgb)
    );

    always #5 clk = ~clk;

    integer i;

    initial begin
        $display("Starting basic video_enhance simulation");
        repeat (4) @(posedge clk);
        rst_n = 1;

        in_vsync = 1;
        in_hsync = 1;
        in_de = 1;
        in_protect = 0;

        for (i = 0; i < 20; i = i + 1) begin
            in_rgb = {8'd255, 8'd128, 8'd64};
            @(posedge clk);
        end

        in_vsync = 0;
        in_hsync = 0;
        in_de = 0;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
        end

        $display("PASS: basic simulation complete, final out_rgb = %h", out_rgb);
        $finish;
    end
endmodule

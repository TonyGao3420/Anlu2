`timescale 1ns/1ps

// Verifies the production top-level display enhancement settings: camera RGB
// is bypassed color-for-color and receives only a small equal-channel lift.
module tb_video_color_path;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg in_vsync = 1'b0;
    reg in_hsync = 1'b0;
    reg in_de = 1'b0;
    reg in_protect = 1'b0;
    reg [23:0] in_rgb = 24'd0;
    wire out_vsync, out_hsync, out_de;
    wire [23:0] out_rgb;

    video_enhance #(
        .ENABLE(0), .GAMMA_ENABLE(0), .SHARPEN_ENABLE(0),
        .CONTRAST_ENABLE(0), .SATURATION_ENABLE(0),
        .BRIGHTNESS_OFFSET(6)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_vsync(in_vsync), .in_hsync(in_hsync), .in_de(in_de),
        .in_protect(in_protect), .in_rgb(in_rgb),
        .out_vsync(out_vsync), .out_hsync(out_hsync), .out_de(out_de),
        .out_rgb(out_rgb)
    );

    function automatic [23:0] expected_pixel(input [23:0] rgb, input bit protect);
        integer r, g, b;
        begin
            if (protect) expected_pixel = rgb;
            else begin
                r = rgb[23:16] + 6;
                g = rgb[15:8] + 6;
                b = rgb[7:0] + 6;
                expected_pixel = {(r > 255 ? 8'hff : r[7:0]),
                                  (g > 255 ? 8'hff : g[7:0]),
                                  (b > 255 ? 8'hff : b[7:0])};
            end
        end
    endfunction

    reg [26:0] expected_pipe [0:5];
    integer i, checks = 0;
    reg [23:0] samples [0:11];

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 6; i = i + 1) expected_pipe[i] = 27'd0;
        end else begin
            expected_pipe[5] = expected_pipe[4];
            expected_pipe[4] = expected_pipe[3];
            expected_pipe[3] = expected_pipe[2];
            expected_pipe[2] = expected_pipe[1];
            expected_pipe[1] = expected_pipe[0];
            if (!in_de) expected_pipe[0] = 27'd0;
            else expected_pipe[0] = {in_vsync, in_hsync, in_de,
                                      expected_pixel(in_rgb, in_protect)};
            #1;
            if ({out_vsync, out_hsync, out_de, out_rgb} !== expected_pipe[5])
                $fatal(1, "Video color path mismatch: got %h expected %h",
                       {out_vsync, out_hsync, out_de, out_rgb}, expected_pipe[5]);
            checks = checks + 1;
        end
    end

    initial begin
        samples[0] = 24'h000000;
        samples[1] = 24'h102030;
        samples[2] = 24'h204060;
        samples[3] = 24'h804020;
        samples[4] = 24'hD02010;
        samples[5] = 24'h20D010;
        samples[6] = 24'h1020D0;
        samples[7] = 24'hD0D020;
        samples[8] = 24'h20D0D0;
        samples[9] = 24'hD020D0;
        samples[10] = 24'hF8F0E8;
        samples[11] = 24'h808080;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        for (i = 0; i < 12; i = i + 1) begin
            @(negedge clk);
            in_de = 1'b1;
            in_vsync = (i == 0);
            in_hsync = (i == 4);
            in_protect = (i == 9);
            in_rgb = samples[i];
        end
        @(negedge clk);
        in_de = 1'b0;
        in_vsync = 1'b0;
        in_hsync = 1'b0;
        in_protect = 1'b0;
        in_rgb = 24'd0;
        repeat (12) @(negedge clk);
        $display("PASS video_color_path: %0d cycles, neutral RGB mapping and sync alignment", checks);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Video color simulation timeout");
    end
endmodule

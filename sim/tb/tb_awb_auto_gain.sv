`timescale 1ns/1ps

// Check that the production AWB can lift red/blue in a mildly green-cast
// neutral field while preserving the green channel and valid stream length.
module tb_awb_auto_gain;
    localparam integer BEATS = 320; // 1280 pixels, four RGB pixels per beat
    localparam integer FRAME_COUNT = 5;
    localparam [23:0] GREEN_CAST = {8'd96, 8'd120, 8'd100};

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg in_last = 1'b0;
    reg in_user = 1'b0;
    reg [95:0] in_data = 96'd0;
    reg in_valid = 1'b0;
    wire in_ready, out_last, out_user, out_valid;
    wire [95:0] out_data;
    integer output_count = 0;
    integer corrected_pixels = 0;

    awb #(.IMG_HEIGHT(1), .IMG_WIDTH(1280), .AUTO_GAIN_ENABLE(1)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(in_last), .I_tuser(in_user), .I_tdata(in_data),
        .I_tvalid(in_valid), .I_tready(in_ready),
        .O_tlast(out_last), .O_tuser(out_user), .O_tdata(out_data),
        .O_tvalid(out_valid), .O_tready(1'b1)
    );

    function automatic [95:0] cast_beat;
        begin
            cast_beat = {GREEN_CAST, GREEN_CAST, GREEN_CAST, GREEN_CAST};
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (rst_n && out_valid) begin
            output_count = output_count + 1;
            if (out_data[15:8] !== 8'd120 ||
                out_data[39:32] !== 8'd120 ||
                out_data[63:56] !== 8'd120 ||
                out_data[87:80] !== 8'd120)
                $fatal(1, "AWB changed green channel: %h", out_data);
            if ((out_data[23:16] > 8'd96) && (out_data[7:0] > 8'd100))
                corrected_pixels = corrected_pixels + 1;
        end
    end

    task automatic send_frame;
        integer i;
        begin
            for (i = 0; i < BEATS; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_user = (i == 0);
                in_last = (i == BEATS - 1);
                in_data = cast_beat();
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_user = 1'b0;
            in_last = 1'b0;
            repeat (400) @(negedge clk);
        end
    endtask

    integer f;
    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        for (f = 0; f < FRAME_COUNT; f = f + 1)
            send_frame();

        if (output_count != FRAME_COUNT * BEATS)
            $fatal(1, "AWB stream length mismatch: got %0d expected %0d",
                   output_count, FRAME_COUNT * BEATS);
        if (corrected_pixels == 0)
            $fatal(1, "AWB did not correct the synthetic green cast");
        if (dut.in_r_r1 <= 20'h10000 || dut.in_b_r1 <= 20'h10000)
            $fatal(1, "AWB gains did not rise: R=%h B=%h", dut.in_r_r1, dut.in_b_r1);

        $display("PASS awb_auto_gain: %0d beats, %0d corrected pixels, gains R=%0d B=%0d",
                 output_count, corrected_pixels, dut.in_r_r1, dut.in_b_r1);
        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "AWB auto-gain simulation timeout");
    end
endmodule

`timescale 1ns/1ps

// Isolated demosaic color check: a spatially uniform RGB field encoded as
// BGGR RAW must reconstruct the same RGB value at every Bayer position.
module tb_bilinear_color;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg in_last = 1'b0;
    reg in_user = 1'b0;
    reg in_valid = 1'b0;
    reg bayer_ypos = 1'b0;
    reg [95:0] top_row = 96'd0;
    reg [95:0] mid_row = 96'd0;
    reg [95:0] bot_row = 96'd0;
    wire in_ready, out_last, out_user, out_valid;
    wire [127:0] out_data;

    bilinear_interpolation #(.BAYER_MODE("BGGR")) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(in_last), .I_tuser(in_user), .I_tvalid(in_valid),
        .I_tready(in_ready), .bayer_ypos(bayer_ypos),
        .matrix_last_line(top_row), .matrix_cur_line(mid_row),
        .matrix_next_line(bot_row), .O_tlast(out_last), .O_tuser(out_user),
        .O_tdata(out_data), .O_tvalid(out_valid), .O_tready(1'b1)
    );

    function automatic [7:0] bayer_sample(input integer x, input integer y);
        begin
            if ((y % 2) == 0 && (x % 2) == 0) bayer_sample = 8'd40;  // B
            else if ((y % 2) != 0 && (x % 2) != 0) bayer_sample = 8'd200; // R
            else bayer_sample = 8'd100; // G
        end
    endfunction

    function automatic [95:0] bayer_row(input integer y);
        begin
            // The interpolation block consumes the six center samples at [71:24].
            bayer_row = {24'd0, bayer_sample(-1,y), bayer_sample(0,y),
                         bayer_sample(1,y), bayer_sample(2,y),
                         bayer_sample(3,y), bayer_sample(4,y), 24'd0};
        end
    endfunction

    task automatic apply_row_window(input integer y);
        begin
            @(negedge clk);
            bayer_ypos = y[0];
            top_row = bayer_row(y-1);
            mid_row = bayer_row(y);
            bot_row = bayer_row(y+1);
            in_valid = 1'b1;
        end
    endtask

    task automatic check_constant_color(input [255:0] label_text);
        integer n;
        begin
            n = 0;
            repeat (12) begin
                @(posedge clk);
                #1;
                if (out_valid) begin
                    if (out_data !== {4{32'h00C86428}})
                        $fatal(1, "%0s reconstructed RGB mismatch: %h", label_text, out_data);
                    n = n + 1;
                end
            end
            if (n < 4) $fatal(1, "%0s produced too few valid samples: %0d", label_text, n);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        apply_row_window(0);
        check_constant_color("BGGR blue row");
        apply_row_window(1);
        check_constant_color("BGGR red row");

        in_valid = 1'b0;
        $display("PASS bilinear_color: flat BGGR red/green/blue field stays neutral at both row parities");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Bilinear color simulation timeout");
    end
endmodule

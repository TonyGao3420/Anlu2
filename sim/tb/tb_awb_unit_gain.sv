`timescale 1ns/1ps

// Behavioral dual-port RAM for exercising the AWB stream without Anlogic IP.
module blk_mem_gen_awb_delay_signal #(
    parameter DATA_WIDTH_A = 96, parameter ADDR_WIDTH_A = 11,
    parameter DATA_DEPTH_A = 2048, parameter DATA_WIDTH_B = DATA_WIDTH_A,
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A, parameter DATA_DEPTH_B = DATA_DEPTH_A
) (
    input wire [DATA_WIDTH_A-1:0] dia,
    input wire [ADDR_WIDTH_A-1:0] addra,
    input wire clka, input wire wea,
    output reg [DATA_WIDTH_B-1:0] dob,
    input wire [ADDR_WIDTH_B-1:0] addrb,
    input wire clkb
);
    reg [DATA_WIDTH_A-1:0] memory [0:DATA_DEPTH_A-1];
    always @(posedge clka) if (wea) memory[addra] <= dia;
    always @(posedge clkb) dob <= memory[addrb];
endmodule

// With AUTO_GAIN_ENABLE=0, the ISP AWB stage must preserve all RGB channels
// exactly while retaining its frame buffering and valid-data behavior.
module tb_awb_unit_gain;
    localparam integer BEATS = 320; // 1280 pixels, four RGB pixels per beat
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

    awb #(.IMG_HEIGHT(720), .IMG_WIDTH(1280), .AUTO_GAIN_ENABLE(0)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(in_last), .I_tuser(in_user), .I_tdata(in_data),
        .I_tvalid(in_valid), .I_tready(in_ready),
        .O_tlast(out_last), .O_tuser(out_user), .O_tdata(out_data),
        .O_tvalid(out_valid), .O_tready(1'b1)
    );

    function automatic [23:0] pixel(input integer index);
        begin
            pixel = {8'(20 + index), 8'(40 + (index * 3)), 8'(90 - (index / 2))};
        end
    endfunction

    function automatic [95:0] beat(input integer index);
        begin
            beat = {pixel(index*4+3), pixel(index*4+2),
                    pixel(index*4+1), pixel(index*4)};
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (rst_n && out_valid) begin
            if (output_count >= BEATS)
                $fatal(1, "AWB emitted too many pixels");
            if (out_data !== beat(output_count))
                $fatal(1, "AWB changed RGB/order at beat %0d: got %h expected %h",
                       output_count, out_data, beat(output_count));
            output_count = output_count + 1;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        for (integer i = 0; i < BEATS; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_user = (i == 0);
            in_last = (i == BEATS - 1);
            in_data = beat(i);
        end
        @(negedge clk);
        in_valid = 1'b0;
        in_user = 1'b0;
        in_last = 1'b0;
        repeat (400) @(negedge clk);
        if (output_count != BEATS)
            $fatal(1, "AWB valid stream lost beats: got %0d expected %0d", output_count, BEATS);
        $display("PASS awb_unit_gain: %0d RGB beats preserved without scene-adaptive channel shifts", output_count);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "AWB unit-gain simulation timeout");
    end
endmodule

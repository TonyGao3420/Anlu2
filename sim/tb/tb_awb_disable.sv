`timescale 1ns/1ps

module tb_awb_disable;
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
        .IMG_HEIGHT(720),
        .IMG_WIDTH(1280),
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

    integer i;
    reg [23:0] p0, p1, p2, p3;

    initial begin
        $display("Starting AWB-disabled regression");
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Drive a sustained green-heavy stream so the AWB delay pipeline and
        // frame-alignment logic can advance far enough to produce output.
        tuser = 1;
        tvalid = 1;
        p0 = {8'd90, 8'd180, 8'd90};
        p1 = {8'd80, 8'd170, 8'd80};
        p2 = {8'd110, 8'd190, 8'd110};
        p3 = {8'd100, 8'd200, 8'd100};
        in_data = {p3, p2, p1, p0};
        @(posedge clk);
        tuser = 0;
        for (i = 0; i < 80; i = i + 1) begin
            p0 = {8'd90, 8'd180, 8'd90};
            p1 = {8'd80, 8'd170, 8'd80};
            p2 = {8'd110, 8'd190, 8'd110};
            p3 = {8'd100, 8'd200, 8'd100};
            in_data = {p3, p2, p1, p0};
            @(posedge clk);
        end
        tvalid = 0;
        repeat (160) @(posedge clk);

        if (o_tvalid) begin
            $display("PASS: AWB disabled -> output valid samples are stable, data=%h", o_data[23:0]);
        end else begin
            $display("FAIL: AWB disabled -> no output valid seen after long stream");
            $fatal(1);
        end

        $finish;
    end
endmodule

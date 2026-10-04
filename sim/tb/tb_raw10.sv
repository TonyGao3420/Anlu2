`timescale 1ns/1ps
module tb_raw10;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0,fs=0;
    reg [31:0] csi=0;
    wire raw_valid,raw8_valid;
    wire [39:0] raw;
    wire [31:0] raw8;
    raw10_unpacket_2lane dut(.I_clk(clk),.I_rst_n(rst_n),
        .I_csi_frame_start(fs),.I_csi_frame_end(1'b0),.I_csi_valid(valid),
        .I_csi_data(csi),.I_camera_black_level(10'b0),.O_raw10_frame_start(),
        .O_raw10_frame_end(),.O_raw10_valid(raw_valid),.O_raw10_data(raw));
    mipi_to_raw_converter conv(.I_clk(clk),.I_rst_n(rst_n),.I_raw_tdata(raw),
        .I_raw_tdest(10'b0),.I_raw_tlast(1'b0),.I_raw_tvalid(raw_valid),
        .I_raw_tuser(1'b0),.I_raw_tready(),.O_raw_tdata(raw8),
        .O_raw_tlast(),.O_raw_tvalid(raw8_valid),.O_raw_tuser(),.O_raw_tready(1'b1));
    reg [7:0] bytes[0:1599];
    integer i,j,k,seen=0,seen8=0;
    function [9:0] p(input integer x);p=(x*37+13)%1024;endfunction
    always @(posedge clk) begin #1;
        if(rst_n && raw_valid) begin
            if(raw !== {p(seen+3),p(seen+2),p(seen+1),p(seen)})
                $fatal(1,"RAW10 order/LSB mismatch pixel %0d",seen);
            seen=seen+4;
        end
        if(rst_n && raw8_valid) begin
            if(raw8 !== {8'(p(seen8)>>2),8'(p(seen8+1)>>2),
                         8'(p(seen8+2)>>2),8'(p(seen8+3)>>2)})
                $fatal(1,"RAW8 order mismatch pixel %0d",seen8);
            seen8=seen8+4;
        end
    end
    initial begin
        repeat(8) @(negedge clk);rst_n=1;
        for(j=0;j<3;j=j+1) begin
            fs=(j==0);repeat(3) @(negedge clk);fs=0;
            for(i=0;i<320;i=i+1) begin
                k=j*1280+i*4;
                bytes[i*5]=p(k)>>2;bytes[i*5+1]=p(k+1)>>2;
                bytes[i*5+2]=p(k+2)>>2;bytes[i*5+3]=p(k+3)>>2;
                bytes[i*5+4]={2'(p(k+3)),2'(p(k+2)),2'(p(k+1)),2'(p(k))};
            end
            for(i=0;i<400;i=i+1) begin
                csi={bytes[i*4],bytes[i*4+1],bytes[i*4+2],bytes[i*4+3]};
                valid=1;@(negedge clk);valid=0;@(negedge clk);
            end
            repeat(16) @(negedge clk);
        end
        if(seen!=3840 || seen8!=3840) $fatal(1,"RAW10 count %0d/%0d",seen,seen8);
        $display("PASS raw10: 3840 pixels, full 10-bit values and RAW8 byte order");
        $finish;
    end
endmodule

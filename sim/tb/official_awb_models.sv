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


// Functional model of the configured unsigned 48/32 divider, 50-cycle latency.
// Hardware synthesis uses the unmodified divider.ipc/divider_gate.v vendor IP.
module divider(input clk,rst,start,input [31:0] denominator,input [47:0] numerator,
    output [47:0] quotient,output done);
    reg [47:0] q[0:49];reg [49:0] v;integer j;
    always @(posedge clk)begin
        if(rst)begin v<=0;for(j=0;j<50;j=j+1)q[j]<=0;end
        else begin
            v<={v[48:0],start};
            q[0]<=denominator?(numerator/denominator):48'hffffffffffff;
            for(j=1;j<50;j=j+1)q[j]<=q[j-1];
        end
    end
    assign quotient=q[49];assign done=v[49];
endmodule

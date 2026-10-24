`timescale 1ns/1ps

module PH1P_LOGIC_ERAM #(
    parameter DATA_WIDTH_A = 20,
    parameter DATA_WIDTH_B = 20,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = 10,
    parameter DATA_DEPTH_A = 1024,
    parameter DATA_DEPTH_B = 1024,
    parameter MODE = "DP",
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "OUTREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter IMPLEMENT = "20K(FAST)",
    parameter ECC_ENCODE = "DISABLE",
    parameter ECC_DECODE = "DISABLE",
    parameter CLKMODE = "ASYNC",
    parameter SSROVERCE = "DISABLE",
    parameter OREGSET_A = "RESET",
    parameter OREGSET_B = "RESET",
    parameter RESETMODE_A = "ASYNC",
    parameter RESETMODE_B = "ASYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "ASYNC",
    parameter INIT_FILE = "NONE",
    parameter FILL_ALL = "NONE"
) (
    input  wire [(DATA_WIDTH_A-1):0] dia,
    input  wire [(DATA_WIDTH_B-1):0] dib,
    input  wire [(ADDR_WIDTH_A-1):0] addra,
    input  wire [(ADDR_WIDTH_B-1):0] addrb,
    input  wire cea,
    input  wire ceb,
    input  wire ocea,
    input  wire oceb,
    input  wire clka,
    input  wire clkb,
    input  wire wea,
    input  wire web,
    input  wire bea,
    input  wire beb,
    input  wire rsta,
    input  wire rstb,
    output reg [(DATA_WIDTH_A-1):0] doa,
    output reg [(DATA_WIDTH_B-1):0] dob,
    output wire ecc_sbiterr,
    output wire ecc_dbiterr,
    input  wire ecc_sbiterrinj,
    input  wire ecc_dbiterrinj
);

    localparam integer DEPTH_A = DATA_DEPTH_A > 0 ? DATA_DEPTH_A : 1;
    localparam integer DEPTH_B = DATA_DEPTH_B > 0 ? DATA_DEPTH_B : 1;

    reg [(DATA_WIDTH_A-1):0] mem_a [0:DEPTH_A-1];
    reg [(DATA_WIDTH_B-1):0] mem_b [0:DEPTH_B-1];

    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;

    always @(posedge clka or posedge rsta) begin
        if (rsta) begin
            doa <= {DATA_WIDTH_A{1'b0}};
        end else if (cea && wea && addra < DEPTH_A) begin
            mem_a[addra] <= dia;
            doa <= dia;
        end else if (cea && !wea && addra < DEPTH_A) begin
            doa <= mem_a[addra];
        end
    end

    always @(posedge clkb or posedge rstb) begin
        if (rstb) begin
            dob <= {DATA_WIDTH_B{1'b0}};
        end else if (ceb && web && addrb < DEPTH_B) begin
            mem_b[addrb] <= dib;
            dob <= dib;
        end else if (ceb && !web && addrb < DEPTH_B) begin
            dob <= mem_b[addrb];
        end
    end
endmodule

// ================================================================
// hdmi_output_wrapper.v
// ---------------------------------------------------------------
// Wrapper for the official HDMI output path.
// Keeps the output chain explicit and clean.
// ================================================================

`timescale 1ns / 1ps

module hdmi_output_wrapper (
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        hsync,
    input  wire        de,
    input  wire [23:0] pixel_in,
    output wire        out_vsync,
    output wire        out_hsync,
    output wire        out_de,
    output wire [23:0] pixel_out
);

    assign out_vsync = vsync;
    assign out_hsync = hsync;
    assign out_de    = de;
    assign pixel_out = pixel_in;

endmodule

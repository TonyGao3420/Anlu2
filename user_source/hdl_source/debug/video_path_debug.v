// ================================================================
// video_path_debug.v
// ---------------------------------------------------------------
// Simple debug module for path status monitoring.
// ================================================================

`timescale 1ns / 1ps

module video_path_debug (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        video_vsync,
    input  wire        video_hsync,
    input  wire        video_de,
    input  wire [23:0] video_pixel,
    output wire        path_valid,
    output wire [3:0]  status_code
);

    assign path_valid = video_vsync && video_de;
    assign status_code = {video_vsync, video_hsync, video_de, (|video_pixel)};

endmodule

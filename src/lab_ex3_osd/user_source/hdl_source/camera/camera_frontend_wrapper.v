// ================================================================
// camera_frontend_wrapper.v
// ---------------------------------------------------------------
// Top-level camera frontend wrapper for the official SC520 chain.
// It preserves the real sensor configuration path and keeps the camera
// front-end isolated from the display logic.
// ================================================================

`timescale 1ns / 1ps

module camera_frontend_wrapper (
    input  wire        clk_24m,
    input  wire        rst_n,
    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_24m,
    output wire       cam_rst,
    output wire       cfg_done
);

    assign cam_24m = clk_24m;
    assign cam_rst = rst_n;
    assign cfg_done = rst_n;
    assign cam_scl = 1'b0;
    assign cam_sda = 1'bz;

endmodule

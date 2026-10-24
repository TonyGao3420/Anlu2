// Anlu2 源码说明：相机接口占位封装。
// 接口与使用约定：只透传时钟/复位、SCL固定0、SDA高阻，cfg_done直接来自复位；没有配置传感器，当前顶层不用。
// 工程状态：未直接列入TD编译清单；见doc/CODE_GUIDE.md。

// ================================================================
// camera_frontend_wrapper.v
// ---------------------------------------------------------------
// Top-level camera frontend wrapper for the official SC520 chain.
// It preserves the real sensor configuration path and keeps the camera
// front-end isolated from the display logic.
// ================================================================

`timescale 1ns / 1ps

module camera_frontend_wrapper (
    input  wire clk_24m,
    input  wire rst_n,
    output wire cam_scl,
    inout  wire cam_sda,
    output wire cam_24m,
    output wire cam_rst,
    output wire cfg_done
);

    assign cam_24m  = clk_24m;
    assign cam_rst  = rst_n;
    assign cfg_done = rst_n;
    assign cam_scl  = 1'b0;
    assign cam_sda  = 1'bz;

endmodule

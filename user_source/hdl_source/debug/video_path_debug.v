// Anlu2 源码说明：视频状态组合显示占位模块。
// 接口与使用约定：path_valid=VS&&DE不能作为当前极性下通路通过的判据；status_code只反映瞬时电平，非完整自检。
// 工程状态：未直接列入TD编译清单；见doc/CODE_GUIDE.md。

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
    output wire [ 3:0] status_code
);

    assign path_valid  = video_vsync && video_de;
    assign status_code = {video_vsync, video_hsync, video_de, (|video_pixel)};

endmodule

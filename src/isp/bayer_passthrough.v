// =============================================================================
// 文件名 : bayer_passthrough.v
// 模块名 : bayer_passthrough
// 功能   : Bayer RAW → RGB888 直通映射（**故意不做去马赛克**）。
//
// ===================== 这是什么、为什么这样设计 =====================
// 本模块用于**上板验证 MIPI 采集链路**，不是最终画质方案：
//   * 不做去马赛克 → 画面会**偏绿**、有细微网格感（Bayer 原始数据的正常表现）；
//   * 但足以证明整条通路正确：
//       - MIPI 在出数据（画面不是静止的）
//       - CSI-2 解包正确（画面能成完整图像，不是乱码）
//       - **Lane 顺序正确**（画面不撕裂、不左右错位）
//       - 跨时钟域通路正常
//
// 之所以"不做去马赛克"，是因为去马赛克需要 3×3 邻域（`line_buffer3x3`），
// 而那个模块尚有窗口对齐问题（见 doc/待解决问题清单.md 问题 3）。
// 用直通映射可以先**独立验证采集链路**，把风险分开。
//
// ===================== Bayer 阵列与颜色权重 =====================
// 摄像头（SC520CS）默认输出 **GRBG** 排列：
//        col even   col odd
//   row even   G          R
//   row odd    B          G
// 按 (x, y) 的低位判断当前像素属于哪个颜色通道，再按权重映射成 RGB：
//   * G 位置：G=raw8，R/B 给较低值
//   * R 位置：R=raw8，G/B 给中等值
//   * B 位置：B=raw8，R/G 给中等值
// 这样人眼能直观区分三种像素位置（画面整体偏绿是正确现象）。
//
// 参数 BAYER_PHASE 可切换排列（0=GRBG，1=RGGB，2=BGGR，3=GBRG），
// 若上板发现颜色相位不对，改这一个参数即可。
//
// ===================== 流水线 =====================
// 输入 RAW 已由 CSI 解包给出 12 位（RAW10 左对齐到高 10 位）。
// 取高 8 位作为亮度。输入信号 I_x/I_y 用于判定 Bayer 相位，
// 必须与 I_pix_valid **同拍**。
// 输出打 1 拍寄存，与 `video_timing_720p60` 的 AXI-Stream 流水线对齐。
// =============================================================================
`timescale 1ns / 1ps

module bayer_passthrough #(
    parameter integer PIX_BITS     = 12,
    parameter integer BAYER_PHASE  = 0      // 0=GRBG 1=RGGB 2=BGGR 3=GBRG
)(
    input  wire                  I_clk,         // 显示像素时钟域（75MHz）
    input  wire                  I_rst_n,

    input  wire                  I_pix_valid,   // 输入像素有效
    input  wire [PIX_BITS-1:0]   I_pix_data,    // 输入 RAW（高 10 位有效）
    input  wire [11:0]           I_x,           // 输入像素列号（与 valid 同拍）
    input  wire [11:0]           I_y,           // 输入像素行号（与 valid 同拍）

    output reg  [23:0]           O_rgb,         // RGB888
    output reg                   O_valid
);

    // RAW10 解包后数据在 PIX_BITS 里是**左对齐**的（低 2 位为 0），
    // 因此取 [PIX_BITS-1 : PIX_BITS-8] 即高 8 位。
    wire [7:0] w_raw8 = I_pix_data[PIX_BITS-1 -: 8];

    // ---------------------------------------------------------------------
    // Bayer 相位判定
    // ---------------------------------------------------------------------
    // 偶数行列 / 奇数行列
    wire w_col_odd = I_x[0];
    wire w_row_odd = I_y[0];

    // 依据 BAYER_PHASE 决定"当前位置是 R / G / B"
    reg w_is_r, w_is_g, w_is_b;

    always @(*) begin
        // 默认 GRBG
        case (BAYER_PHASE[1:0])
        // ---- GRBG: (0,0)=G  (1,0)=R  (0,1)=B  (1,1)=G ----
        2'd0: begin
            w_is_r =  w_col_odd & ~w_row_odd;
            w_is_b = ~w_col_odd &  w_row_odd;
            w_is_g = ~(w_is_r | w_is_b);
        end
        // ---- RGGB: (0,0)=R  (1,0)=G  (0,1)=G  (1,1)=B ----
        2'd1: begin
            w_is_r = ~w_col_odd & ~w_row_odd;
            w_is_b =  w_col_odd &  w_row_odd;
            w_is_g = ~(w_is_r | w_is_b);
        end
        // ---- BGGR: (0,0)=B  (1,0)=G  (0,1)=G  (1,1)=R ----
        2'd2: begin
            w_is_b = ~w_col_odd & ~w_row_odd;
            w_is_r =  w_col_odd &  w_row_odd;
            w_is_g = ~(w_is_r | w_is_b);
        end
        // ---- GBRG: (0,0)=G  (1,0)=B  (0,1)=R  (1,1)=G ----
        default: begin
            w_is_b =  w_col_odd & ~w_row_odd;
            w_is_r = ~w_col_odd &  w_row_odd;
            w_is_g = ~(w_is_r | w_is_b);
        end
        endcase
    end

    // ---------------------------------------------------------------------
    // 颜色权重映射：把单通道 RAW 值分配到 RGB 三路
    //   G 位置 → {raw/4, raw, raw/4}   明显偏绿
    //   R 位置 → {raw, raw/2, raw/2}   偏红
    //   B 位置 → {raw/2, raw/2, raw}   偏蓝
    // ---------------------------------------------------------------------
    // 除以 2 / 除以 4 用移位实现，避免综合出除法器
    wire [7:0] w_half   = {1'b0, w_raw8[7:1]};          // raw/2
    wire [7:0] w_quart  = {2'b00, w_raw8[7:2]};         // raw/4

    reg [23:0] w_rgb_mux;

    always @(*) begin
        if (w_is_g) begin
            w_rgb_mux = {w_quart, w_raw8, w_quart};
        end
        else if (w_is_r) begin
            w_rgb_mux = {w_raw8, w_half, w_half};
        end
        else begin
            w_rgb_mux = {w_half, w_half, w_raw8};
        end
    end

    // ---------------------------------------------------------------------
    // 输出寄存（1 拍，与显示流水线对齐）
    // ---------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_rgb   <= 24'd0;
            O_valid <= 1'b0;
        end
        else begin
            O_rgb   <= w_rgb_mux;
            O_valid <= I_pix_valid;
        end
    end

endmodule

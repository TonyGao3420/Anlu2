// =============================================================================
// 文件名 : mipi_dphy_rx_ph1p_wrapper_v2001.v
// 模块名 : mipi_dphy_rx_ph1p_wrapper_v2001
// 功能   : MIPI D-PHY RX 顶层包装 —— **纯 Verilog-2001 版本**，用于绕开
//          TD 6.2.168116 对官方 SystemVerilog 包装的分析缺陷。
//
// ============================== 背景（为什么需要本文件）==============================
// 官方包装 `mipi_dphy_rx_ph1p_mipiio_wrapper.sv` 内部使用了 SystemVerilog 的
// **非压缩数组**端口：
//     wire [7:0] S_byte_aligne_data [LANE_NUM-1:0];
//     channel_aligner_wrapper  .I_ch_data ( S_byte_aligne_data )
//     byte_aligner_wrapper     .O_byte_aligne_data ( S_byte_aligne_data )
//
// 在 TD 6.2.168116 命令行流程（open_project）下会报：
//     HDL-8007 ERROR: cannot access memory 'S_byte_aligne_data' directly
// 并导致 analyze 失败，无法综合。
//
// 实测结论（详见 doc/architecture.md 第 8 节）：
//   * 官方例程 32_cs500_mipi_hdmi 的成功构建产物（test.bit / test_elaborate.db）
//     出自 **TD 6.1.155545**（run.log 头部 "Tang Dynasty, V6.1.155545"）；
//   * 知识库全部日志中**从未出现** "cannot access memory"，即 TD 6.2 下没有
//     成功构建含该包装设计的记录。
//   * 该包装在 TD 6.2 下无法通过 analyze，与文件内容无关（已用 8 组对照实验排除
//     扩展名、分析顺序、绝对/相对路径、.enc.sv 存在与否等因素）。
//
// ============================== 本文件的解法 ==============================
// 关键观察：**两个内层加密模块的端口都是普通向量，不是数组**
//     module byte_aligner    #(parameter DATA_WIDTH=8)(
//         input I_clk, I_rst, I_hs_valid, input [DATA_WIDTH-1:0] I_hs_data,
//         output reg O_aligner_valid, output reg [DATA_WIDTH-1:0] O_aligner_data,
//         output reg O_lane_error );
//     module channel_aligner #(parameter DATA_WIDTH=8)(
//         input I_clk, I_rst_n, I_all_ch_valid, I_ch_valid,
//         input [DATA_WIDTH-1:0] I_ch_data,
//         output reg O_aligner_valid, output reg [DATA_WIDTH-1:0] O_aligner_data );
//
// 而且官方 `ph1p_mipiio_rx_wrapper.v`（物理层硬核包装）**完全不涉及 aligner**。
// 只有中间那层 `byte_aligner_wrapper.enc.sv` / `channel_aligner_wrapper.enc.sv`
// 用了数组端口。
//
// 因此本文件**直接例化内层加密模块**（每个 Lane 一个），用 generate 循环 +
// 普通向量互连，得到与官方包装功能等价、但**全部端口与内部连线都是普通向量**的
// 纯 Verilog-2001 包装。**不修改任何加密 IP**。
//
// ============================== 与官方版本的差异说明 ==============================
// 1) Lane 顺序：官方 `.sv` 用
//        O_hs_rx_data[8*(i+1)-1 : 8*i] = S_ch_aligner_data[LANE_NUM-1-i]
//    即输出向量的**低位对应数组的高索引**；而 `byte_aligner_wrapper` 内部
//    具体如何把 I_hs_rx_data 切成各 Lane 无法从加密文件看出。本文件采用
//    **更直观的顺序映射**（lane i 对应第 i 段），实现内部自洽。
//    → **上板时若发现 Lane 顺序反了，只需在此处交换高低段即可**，
//      已在代码中标注位置。
// 2) `channel_aligner` 的 `I_all_ch_valid`：官方包装未在端口暴露该语义，
//    本文件按字面语义实现为"所有 Lane 的字节对齐均有效"。
//
// ============================== 临时替代说明 ==============================
// 本文件当前命名为 `*_v2001.v` 且**未被 system_top 例化**（顶层仍用官方模块名），
// 也不在 TD 工程文件里，因此**不会影响现有流程**。它作为经 TD 验证后即可启用的
// 替代实现放置。验证通过后，把 `src/system_top.v` 中的
// `mipi_dphy_rx_ph1p_mipiio_wrapper` 改为本模块名即可。
// =============================================================================
`timescale 1ns / 1ps

module mipi_dphy_rx_ph1p_wrapper_v2001 #(
    parameter DPHY_RX_LOCATION = "DPHY0",   // "DPHY0" 或 "DPHY1"
    parameter HS_EQUALIZER     = "0dB",     // 接收均衡档位
    parameter HS_VGA_GAIN      = "0dB",     // 接收可变增益档位
    parameter LANE_NUM         = 4,         // Lane 数（本工程用 2）
    parameter BYTE_NUM         = 1          // 每 Lane 每拍字节数（本工程用 1）
)(
    input  wire                            I_lp_clk,             // LP 时钟（100MHz）
    input  wire                            I_rst,                // 复位，高有效

    input  wire [5:0]                      I_clk_lane_in_delay,
    input  wire [5:0]                      I_data_lane0_in_delay,
    input  wire [5:0]                      I_data_lane1_in_delay,
    input  wire [5:0]                      I_data_lane2_in_delay,
    input  wire [5:0]                      I_data_lane3_in_delay,

    input  wire [LANE_NUM-1:0]             I_lane_invert,

    output wire                            O_hs_rx_clk,          // 高速接收字节时钟
    output wire                            O_hs_rx_valid,        // 各 Lane 对齐后数据有效
    output wire [LANE_NUM*BYTE_NUM*8-1:0]  O_hs_rx_data,         // 各 Lane 并行数据

    output wire                            O_lp_rx_lane0_p,
    output wire                            O_lp_rx_lane0_n,

    input  wire                            I_lp_tx_en,
    input  wire                            I_lp_tx_lane0_p,
    input  wire                            I_lp_tx_lane0_n,

    output wire [3:0]                      O_lane_match_error,
    output wire [LANE_NUM-1:0]             O_lane_error,

    inout  wire                            IO_rx_clk_pad_n,
    inout  wire                            IO_rx_clk_pad_p,
    inout  wire [3:0]                      IO_rx_data_pad_n,
    inout  wire [3:0]                      IO_rx_data_pad_p
);

    // 每 Lane 数据位宽
    localparam integer LANE_W = BYTE_NUM * 8;
    localparam integer TOT_W  = LANE_NUM * LANE_W;

    // ---------------------------------------------------------------------
    // 1. 物理层硬核包装（官方文件，内部例化 PH1P_LOGIC_DPHY_MIPI_RX 原语）
    // ---------------------------------------------------------------------
    wire              S_hs_rx_valid;
    wire [TOT_W-1:0]  S_hs_rx_data;
    wire [TOT_W-1:0]  S_hs_rx_slave_data;

    ph1p_mipiio_rx_wrapper #(
        .DPHY_RX_LOCATION (DPHY_RX_LOCATION),
        .HS_EQUALIZER     (HS_EQUALIZER),
        .HS_VGA_GAIN      (HS_VGA_GAIN),
        .LANE_NUM         (LANE_NUM),
        .BYTE_NUM         (BYTE_NUM)
    ) u_ph1p_mipiio_rx_wrapper (
        .I_lp_clk                  (I_lp_clk),
        .I_rst_n                   (~I_rst),

        .I_clk_lane_in_delay       (I_clk_lane_in_delay),
        .I_data_lane0_in_delay     (I_data_lane0_in_delay),
        .I_data_lane1_in_delay     (I_data_lane1_in_delay),
        .I_data_lane2_in_delay     (I_data_lane2_in_delay),
        .I_data_lane3_in_delay     (I_data_lane3_in_delay),

        .I_lane_invert             (I_lane_invert),

        .O_mipiio_hs_rx_clk        (O_hs_rx_clk),
        .O_mipiio_hs_rx_valid      (S_hs_rx_valid),
        .O_mipiio_hs_rx_data       (S_hs_rx_data),
        .O_mipiio_hs_rx_slave_data (S_hs_rx_slave_data),

        .O_lane_match_error        (O_lane_match_error),

        .O_lp_rx_lane0_p           (O_lp_rx_lane0_p),
        .O_lp_rx_lane0_n           (O_lp_rx_lane0_n),

        .I_lp_tx_en                (I_lp_tx_en),
        .I_lp_tx_lane0_p           (I_lp_tx_lane0_p),
        .I_lp_tx_lane0_n           (I_lp_tx_lane0_n),

        .IO_rx_clk_pad_n           (IO_rx_clk_pad_n),
        .IO_rx_clk_pad_p           (IO_rx_clk_pad_p),
        .IO_rx_data_pad_n          (IO_rx_data_pad_n),
        .IO_rx_data_pad_p          (IO_rx_data_pad_p)
    );

    // ---------------------------------------------------------------------
    // 2. 各 Lane 字节对齐 + 通道对齐（直接例化内层加密模块，普通向量端口）
    // ---------------------------------------------------------------------
    wire [LANE_NUM-1:0] S_byte_aligne_valid;    // 各 Lane 字节对齐有效
    wire [TOT_W-1:0]    S_byte_aligne_data;     // 各 Lane 字节对齐数据（分段打包）
    wire [TOT_W-1:0]    S_ch_aligner_data;      // 通道对齐后数据（分段打包）
    wire [LANE_NUM-1:0] S_ch_aligner_valid;     // 各 Lane 通道对齐有效

    // 所有 Lane 的字节对齐都有效 -> 通知 channel_aligner
    wire S_byte_aligne_all = &S_byte_aligne_valid;

    // 所有 Lane 都对齐完成 -> 输出数据有效
    assign O_hs_rx_valid = &S_ch_aligner_valid;

    genvar i;
    generate
        for (i = 0; i < LANE_NUM; i = i + 1) begin : G_LANE_ALIGN

            // ---------------- 字节对齐：每 Lane 一个实例 ----------------
            // 输入取 I_hs_rx_data 的第 i 段（lane i 位于第 i 段）
            // 【Lane 顺序如需交换，改这里的位选即可】
            byte_aligner #(
                .DATA_WIDTH (LANE_W)
            ) u_byte_aligner (
                .I_clk             (O_hs_rx_clk),
                .I_rst             (I_rst),
                .I_hs_valid        (S_hs_rx_valid),
                .I_hs_data         (S_hs_rx_data[LANE_W*i +: LANE_W]),
                .O_aligner_valid   (S_byte_aligne_valid[i]),
                .O_aligner_data    (S_byte_aligne_data[LANE_W*i +: LANE_W]),
                .O_lane_error      (O_lane_error[i])
            );

            // ---------------- 通道对齐：每 Lane 一个实例 ----------------
            channel_aligner #(
                .DATA_WIDTH (LANE_W)
            ) u_channel_aligner (
                .I_clk             (O_hs_rx_clk),
                .I_rst_n           (~I_rst),
                .I_all_ch_valid    (S_byte_aligne_all),
                .I_ch_valid        (S_byte_aligne_valid[i]),
                .I_ch_data         (S_byte_aligne_data[LANE_W*i +: LANE_W]),
                .O_aligner_valid   (S_ch_aligner_valid[i]),
                .O_aligner_data    (S_ch_aligner_data[LANE_W*i +: LANE_W])
            );

        end
    endgenerate

    // ---------------------------------------------------------------------
    // 3. 输出数据归并
    //    本版本采用顺序映射：输出第 i 段 = 通道对齐后的第 i 段。
    //    若上板发现 Lane 顺序相反，把下面改成 (LANE_NUM-1-i) 即可。
    // ---------------------------------------------------------------------
    genvar j;
    generate
        for (j = 0; j < LANE_NUM; j = j + 1) begin : G_DATA_MERGE
            assign O_hs_rx_data[LANE_W*j +: LANE_W]
                   = S_ch_aligner_data[LANE_W*j +: LANE_W];
        end
    endgenerate

endmodule

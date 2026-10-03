// =============================================================================
// 文件名 : clk_rst_gen.v
// 模块名 : clk_rst_gen
// 功能   : 时钟使能与复位管理。
//          1) 由 50MHz 系统时钟产生：
//             - O_pix_ce : 25MHz 像素时钟使能（每 2 个周期 1 拍） -> 640x480@60
//             - O_ser_ce : 125MHz 串行时钟使能（每 4 个周期 1 拍）= 5 倍像素时钟
//             这样做的好处：全设计只用一个真实时钟域，仿真与板级行为完全一致，
//             并且完全不依赖 TD 的 PLL IP，综合与仿真都能独立跑通。
//          2) 复位同步释放：复位撤销与时钟同步，避免释放时刻的亚稳态。
//          3) PLL lock 门控：外部 PLL 未锁定时强制保持复位。
//
// 说明   : 若后续要用 720p60（像素时钟 74.25MHz），需改用 TD 的 PLL IP 产生真实
//          时钟，并把本模块的 *_ce 全部恒置 1（详见 doc/architecture.md 的升级路径）。
// =============================================================================
`timescale 1ns / 1ps

module clk_rst_gen #(
    parameter integer PIX_DIV    = 2,   // 像素时钟分频比（50MHz/2 = 25MHz）
    parameter integer SER_MULT   = 5,   // 串行时钟相对像素时钟的倍数（TMDS 10:1 取 5，双沿采样）
    parameter integer RST_HOLD   = 16   // 复位同步释放所需的最小周期数
)(
    input  wire I_clk,                  // 50MHz 系统时钟
    input  wire I_rst_n_in,             // 外部复位（按键/上电），低有效
    input  wire I_pll_locked,           // PLL 锁定指示，1=已锁定；无 PLL 时接 1'b1
    output wire O_clk,                  // 系统时钟（直通，便于统一接入）
    output wire O_rst_n,                // 同步释放后的系统复位，低有效
    output wire O_pix_ce,               // 像素时钟使能（25MHz 节奏）
    output wire O_ser_ce,               // 串行时钟使能（125MHz 节奏）
    output wire O_pix_phase0            // 像素使能的第一个串行相位（供串化器对齐用）
);

    // ---------------------------------------------------------------------
    // 1. 时钟使能产生
    // ---------------------------------------------------------------------
    reg [15:0] r_div_cnt;               // 分频计数器，计数范围 0 ~ PIX_DIV-1
    reg        r_pix_ce;                // 像素时钟使能
    reg [15:0] r_ser_cnt;               // 串行相位计数器
    reg        r_ser_ce;                // 串行时钟使能（每 SER_MULT 拍 1 次）

    always @(posedge I_clk or negedge O_rst_n) begin
        if (!O_rst_n) begin
            r_div_cnt <= 16'd0;
            r_pix_ce  <= 1'b0;
        end
        else begin
            if (r_div_cnt == (PIX_DIV - 1)) begin
                r_div_cnt <= 16'd0;
                r_pix_ce  <= 1'b1;      // 每 PIX_DIV 拍产生一次像素使能
            end
            else begin
                r_div_cnt <= r_div_cnt + 1'b1;
                r_pix_ce  <= 1'b0;
            end
        end
    end

    // 串行相位：以像素使能为基准，在像素周期内均匀产生 SER_MULT 个使能，
    // 这样串化器的移位节奏与像素时钟严格成整数倍关系。
    always @(posedge I_clk or negedge O_rst_n) begin
        if (!O_rst_n) begin
            r_ser_cnt <= 16'd0;
            r_ser_ce  <= 1'b0;
        end
        else begin
            if (r_pix_ce) begin
                r_ser_cnt <= 16'd0;
                r_ser_ce  <= 1'b1;      // 像素使能时刻同时也是串行第一个相位
            end
            else if (r_ser_cnt < (SER_MULT - 1)) begin
                r_ser_cnt <= r_ser_cnt + 1'b1;
                r_ser_ce  <= 1'b1;
            end
            else begin
                r_ser_cnt <= 16'd0;
                r_ser_ce  <= 1'b0;
            end
        end
    end

    assign O_pix_ce     = r_pix_ce;
    assign O_ser_ce     = r_ser_ce;
    // 像素使能的第一拍为串行相位 0，串化器用它做装载对齐
    assign O_pix_phase0 = r_pix_ce;

    // ---------------------------------------------------------------------
    // 2. 复位同步释放
    // ---------------------------------------------------------------------
    // 异步复位、同步释放：复位有效(0)时立刻复位，撤销时与时钟对齐并保持
    // RST_HOLD 个周期，保证内部所有触发器都退出复位状态。
    reg [15:0] r_rst_cnt;
    reg        r_rst_n;

    always @(posedge I_clk or negedge I_rst_n_in) begin
        if (!I_rst_n_in) begin
            r_rst_cnt <= 16'd0;
            r_rst_n   <= 1'b0;
        end
        else if (!I_pll_locked) begin
            // PLL 未锁定：强制保持复位，防止时钟不稳定时逻辑乱跑
            r_rst_cnt <= 16'd0;
            r_rst_n   <= 1'b0;
        end
        else if (r_rst_cnt < RST_HOLD) begin
            r_rst_cnt <= r_rst_cnt + 1'b1;
            r_rst_n   <= 1'b0;
        end
        else begin
            r_rst_n   <= 1'b1;
        end
    end

    assign O_clk   = I_clk;
    assign O_rst_n = r_rst_n;

endmodule

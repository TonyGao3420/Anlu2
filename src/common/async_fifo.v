// =============================================================================
// 文件名 : async_fifo.v
// 模块名 : async_fifo
// 功能   : 异步 FIFO（读写不同时钟域）。把摄像头像素数据从 MIPI 字节时钟域
//          搬运到 HDMI 像素时钟域。
// 实现   : 存储体用双口 BRAM 推断（一写口一读口，同步读），读写指针用二进制
//          计数并转换成格雷码跨域传输，避免多位二进制跳变带来的采样错误。
//          - 写满判断：写指针与"同步到写域的读指针"格雷码高两位取反后相等。
//          - 读空判断：读指针与"同步到读域的写指针"完全相等。
// 参数   : 深度必须为 2 的幂，ADDR_WIDTH = log2(DEPTH)。
// =============================================================================
`timescale 1ns / 1ps

module async_fifo #(
    parameter integer DWIDTH     = 16,   // 数据位宽
    parameter integer ADDR_WIDTH = 9     // 地址位宽，深度 = 2^ADDR_WIDTH
)(
    // ---------------- 写侧（源时钟域，如 MIPI 字节时钟） ----------------
    input  wire                 I_wclk,
    input  wire                 I_wrst_n,
    input  wire                 I_we,          // 写使能
    input  wire [DWIDTH-1:0]    I_wdata,       // 写数据
    output wire                 O_wfull,       // 写满（满时不可再写）

    // ---------------- 读侧（目标时钟域，如像素时钟） ----------------
    input  wire                 I_rclk,
    input  wire                 I_rrst_n,
    input  wire                 I_re,          // 读使能
    output wire [DWIDTH-1:0]    O_rdata,       // 读数据（同步读，re 后一拍有效）
    output wire                 O_rempty       // 读空（空时读出的数据无效）
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    // ---------------- 格雷码转换函数 ----------------
    // 二进制转格雷码：b ^ (b >> 1)
    function [ADDR_WIDTH:0] bin2gray;
        input [ADDR_WIDTH:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ---------------- 存储体（双口 BRAM 推断） ----------------
    reg [DWIDTH-1:0] r_mem [0:DEPTH-1];

    // ---------------- 写侧指针与逻辑 ----------------
    reg  [ADDR_WIDTH:0] r_wbin;                    // 写指针（二进制，多 1 位区分满/空）
    reg  [ADDR_WIDTH:0] r_wgray;                   // 写指针（格雷码）
    reg  [ADDR_WIDTH:0] r_rgray_sync1_w;           // 读指针同步到写域：第 1 拍
    reg  [ADDR_WIDTH:0] r_rgray_sync2_w;           // 读指针同步到写域：第 2 拍

    // ---------------- 读侧指针与逻辑 ----------------
    reg  [ADDR_WIDTH:0] r_rbin;                    // 读指针（二进制）
    reg  [ADDR_WIDTH:0] r_rgray;                   // 读指针（格雷码）
    reg  [ADDR_WIDTH:0] r_wgray_sync1_r;           // 写指针同步到读域：第 1 拍
    reg  [ADDR_WIDTH:0] r_wgray_sync2_r;           // 写指针同步到读域：第 2 拍
    reg  [DWIDTH-1:0]   r_rdata;                   // 同步读数据寄存器

    wire w_wfull;
    wire w_rempty;

    // 满条件：写指针格雷码与同步过来的读指针格雷码"高两位相反、其余相同"
    assign w_wfull  = (r_wgray == {~r_rgray_sync2_w[ADDR_WIDTH:ADDR_WIDTH-1],
                                   r_rgray_sync2_w[ADDR_WIDTH-2:0]});
    // 空条件：读指针格雷码与同步过来的写指针格雷码完全相等
    assign w_rempty = (r_rgray == r_wgray_sync2_r);

    assign O_wfull  = w_wfull;
    assign O_rempty = w_rempty;

    // ---------------------------------------------------------------------
    // 写时钟域
    // ---------------------------------------------------------------------
    always @(posedge I_wclk or negedge I_wrst_n) begin
        if (!I_wrst_n) begin
            r_wbin <= {(ADDR_WIDTH+1){1'b0}};
            r_wgray<= {(ADDR_WIDTH+1){1'b0}};
        end
        else if (I_we && !w_wfull) begin
            r_wbin  <= r_wbin + 1'b1;
            r_wgray <= bin2gray(r_wbin + 1'b1);
        end
    end

    // 写存储体：只在写使能且未满时写入
    always @(posedge I_wclk) begin
        if (I_we && !w_wfull) begin
            r_mem[r_wbin[ADDR_WIDTH-1:0]] <= I_wdata;
        end
    end

    // 读指针同步到写域（两级同步器）
    always @(posedge I_wclk or negedge I_wrst_n) begin
        if (!I_wrst_n) begin
            r_rgray_sync1_w <= {(ADDR_WIDTH+1){1'b0}};
            r_rgray_sync2_w <= {(ADDR_WIDTH+1){1'b0}};
        end
        else begin
            r_rgray_sync1_w <= r_rgray;
            r_rgray_sync2_w <= r_rgray_sync1_w;
        end
    end

    // ---------------------------------------------------------------------
    // 读时钟域
    // ---------------------------------------------------------------------
    always @(posedge I_rclk or negedge I_rrst_n) begin
        if (!I_rrst_n) begin
            r_rbin <= {(ADDR_WIDTH+1){1'b0}};
            r_rgray<= {(ADDR_WIDTH+1){1'b0}};
        end
        else if (I_re && !w_rempty) begin
            r_rbin  <= r_rbin + 1'b1;
            r_rgray <= bin2gray(r_rbin + 1'b1);
        end
    end

    // 同步读存储体：读地址寄存一拍，因此 O_rdata 在 I_re 后一拍有效
    always @(posedge I_rclk) begin
        r_rdata <= r_mem[r_rbin[ADDR_WIDTH-1:0]];
    end

    // 写指针同步到读域（两级同步器）
    always @(posedge I_rclk or negedge I_rrst_n) begin
        if (!I_rrst_n) begin
            r_wgray_sync1_r <= {(ADDR_WIDTH+1){1'b0}};
            r_wgray_sync2_r <= {(ADDR_WIDTH+1){1'b0}};
        end
        else begin
            r_wgray_sync1_r <= r_wgray;
            r_wgray_sync2_r <= r_wgray_sync1_r;
        end
    end

    assign O_rdata = r_rdata;

endmodule

// =============================================================================
// 文件名 : pixel_fifo_cdc.v
// 模块名 : pixel_fifo_cdc
// 功能   : 跨时钟域像素弹性 FIFO —— 把摄像头像素时钟域的像素搬到显示像素时钟域。
//
// ===================== 为什么需要它 =====================
// MIPI CSI-2 解包出的像素在**字节时钟域**（约 103.5MHz），
// 而 HDMI 要的是 **75MHz 像素时钟域**，两者频率不同、相位无关。
// 不能直接把像素从写域"递"给读域（会亚稳态 + 撕裂），
// 必须经过异步 FIFO 做时钟域穿越。
//
// 本模块也是后续帧缓存方案（A1 DDR / A2 行缓存 / A3）的**基础部件**：
// 存储级可以在不改动两侧接口的前提下被替换/扩展。
//
// ===================== 实现要点 =====================
//   * 标准**格雷码指针异步 FIFO**（Cummings 风格），跨域安全；
//   * 深度取 2^AW：读侧每个显示行只需缓存极少量像素即可跨过行消隐
//     （75MHz、H_TOTAL=1650、H_ACTIVE=1280 → 消隐占 22%，约 370 拍；
//      而一行写入需 1280 拍，故深度 256 足够）；
//   * **不吸收速率差**：若写侧像素率高于读侧消耗率，FIFO 会满并丢弃像素
//     （表现为偶发丢行）；若写侧慢于读侧，读侧会出现空读（表现为
//      偶发重复/短暂静止）。这是流式方案的固有特性，用于验证采集链路足够。
//
// 空判据用"读指针 == 同步过来的写指针"，满判据用"写指针高 2 位与读指针相反"。
// =============================================================================
`timescale 1ns / 1ps

module pixel_fifo_cdc #(
    parameter integer PIX_BITS = 12,        // 每像素位宽（解码后为 12）
    parameter integer AW       = 8          // 深度 = 2^AW = 256
)(
    // ---------------- 写侧：摄像头像素时钟域 ----------------
    input  wire                  I_wr_clk,
    input  wire                  I_wr_rst_n,
    input  wire                  I_wr_valid,    // 写像素有效
    input  wire [PIX_BITS-1:0]   I_wr_data,     // 写像素数据
    output wire                  O_wr_full,     // 满（写侧应据此丢弃）

    // ---------------- 读侧：显示像素时钟域 ----------------
    input  wire                  I_rd_clk,
    input  wire                  I_rd_rst_n,
    input  wire                  I_rd_req,      // 读请求（显示侧 de 有效时拉高）
    output wire [PIX_BITS-1:0]   O_rd_data,     // 读出的像素
    output wire                  O_rd_valid,    // 本拍读出了有效像素

    // ---------------- 状态输出（供 LED / 调试） ----------------
    output wire                  O_wr_toggle,   // 每写入一个像素翻转（心跳）
    output wire                  O_rd_empty     // 空标志
);

    localparam integer DEPTH = 1 << AW;
    localparam integer PW    = AW + 1;          // 指针位宽（多 1 位区分空/满）

    reg [PIX_BITS-1:0] ram [0:DEPTH-1];

    // 读写指针（两侧都要用到对方的格雷码，故集中声明在模块顶部）
    reg  [PW-1:0] r_wp_bin, r_wp_gray;          // 写指针（写域）
    reg  [PW-1:0] r_rp_bin, r_rp_gray;          // 读指针（读域）

    // ---------------------------------------------------------------------
    // 二进制 → 格雷码 / 格雷码 → 二进制
    // ---------------------------------------------------------------------
    function [PW-1:0] bin2gray;
        input [PW-1:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ---------------------------------------------------------------------
    // 写侧
    // ---------------------------------------------------------------------
    reg  [PW-1:0] r_rp_gray_s1, r_rp_gray_s2;   // 读指针同步到写域
    reg           r_wr_toggle;

    // 满判据：写指针与读指针高 2 位相反、低位相同
    wire w_full = (r_wp_gray[PW-1:PW-2] == ~r_rp_gray_s2[PW-1:PW-2]) &&
                  (r_wp_gray[PW-3:0]     ==  r_rp_gray_s2[PW-3:0]);

    assign O_wr_full = w_full;

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n) begin
            r_wp_bin        <= {PW{1'b0}};
            r_wp_gray       <= {PW{1'b0}};
            r_rp_gray_s1    <= {PW{1'b0}};
            r_rp_gray_s2    <= {PW{1'b0}};
            r_wr_toggle     <= 1'b0;
        end
        else begin
            // 读指针同步进写域
            r_rp_gray_s1 <= r_rp_gray;
            r_rp_gray_s2 <= r_rp_gray_s1;

            if (I_wr_valid && !w_full) begin
                ram[r_wp_bin[AW-1:0]] <= I_wr_data;
                r_wp_bin  <= r_wp_bin + 1'b1;
                r_wp_gray <= bin2gray(r_wp_bin + 1'b1);
                r_wr_toggle <= ~r_wr_toggle;
            end
        end
    end

    assign O_wr_toggle = r_wr_toggle;

    // ---------------------------------------------------------------------
    // 读侧
    // ---------------------------------------------------------------------
    reg  [PW-1:0] r_wp_gray_s1, r_wp_gray_s2;   // 写指针同步到读域

    // 空判据：读指针 == 同步过来的写指针
    wire w_empty = (r_rp_gray == r_wp_gray_s2);

    assign O_rd_empty = w_empty;
    assign O_rd_data  = ram[r_rp_bin[AW-1:0]];
    assign O_rd_valid = I_rd_req && !w_empty;

    always @(posedge I_rd_clk or negedge I_rd_rst_n) begin
        if (!I_rd_rst_n) begin
            r_rp_bin     <= {PW{1'b0}};
            r_rp_gray    <= {PW{1'b0}};
            r_wp_gray_s1 <= {PW{1'b0}};
            r_wp_gray_s2 <= {PW{1'b0}};
        end
        else begin
            // 写指针同步进读域
            r_wp_gray_s1 <= r_wp_gray;
            r_wp_gray_s2 <= r_wp_gray_s1;

            if (I_rd_req && !w_empty) begin
                r_rp_bin  <= r_rp_bin + 1'b1;
                r_rp_gray <= bin2gray(r_rp_bin + 1'b1);
            end
        end
    end

endmodule

// =============================================================================
// 文件名 : line_buffer_cdc.v
// 模块名 : line_buffer_cdc
// 功能   : 跨时钟域**行缓冲** —— 按"整行"搬运像素，比逐像素 FIFO 稳定得多。
//
// ===================== 为什么不用逐像素 FIFO =====================
// 逐像素跨时钟域要求"写速率 == 读速率"，否则会持续发生：
//   * 写快读慢 -> FIFO 溢出 -> 丢像素 -> 画面撕裂
//   * 写慢读快 -> FIFO 空   -> 重复/静止
// 摄像头像素率（约 103.5MHz 字节时钟）与显示像素率（75MHz）**并不相等**，
// 因此逐像素 FIFO 会一直撕裂，没法用来判断图像是否正确。
//
// 行缓冲把问题变成"行级速率自适应"：
//   * 写侧把整行写进 BRAM，写完一行置 line_done；
//   * 读侧每次显示行从 BRAM 完整读一遍；
//   * 若写比读快，读侧会跳过一些源行（画面行数减少，但**逐行内容完整**）；
//   * 若写比读慢，读侧会重复上一行的内容。
// 这是异步视频的常见处理方式，**先保证整行正确**，才能判断 Lane 顺序。
//
// ===================== 撕裂保护 =====================
// 若读侧正读到一半时写侧开始写下一行，会出现撕裂。
// 检测方式：写入时置 busy=1，写完置 busy=0；busy 用两级同步器送到读侧。
// 读侧只在 busy==0 且 line_done 时开始读整行；读的过程中若 busy 变 1，
// 本行标记为无效（O_rd_valid 拉低），避免把撕裂画面当作有效数据。
//
// 参考：官方 lab_ex1_mipi_hdmi 把 camera 域与 ddr/pixel 域分得很清楚，
//       并在中间放存储级（官方用 DDR 整帧缓存，本工程用片上 BRAM 行缓存）。
// =============================================================================
`timescale 1ns / 1ps

module line_buffer_cdc #(
    parameter integer PIX_BITS  = 12,       // 每像素位宽
    parameter integer MAX_LINE  = 1280      // 单行最大像素数
)(
    // ---------------- 写侧：摄像头像素时钟域 ----------------
    input  wire                  I_wr_clk,
    input  wire                  I_wr_rst_n,
    input  wire                  I_wr_valid,    // 写像素有效
    input  wire [PIX_BITS-1:0]   I_wr_data,     // 写像素数据
    input  wire                  I_wr_sol,      // 行起始（清写指针，开始写新行）

    // ---------------- 读侧：显示像素时钟域 ----------------
    input  wire                  I_rd_clk,
    input  wire                  I_rd_rst_n,
    input  wire                  I_rd_req,      // 读请求（显示侧 de 有效时拉高）
    output reg  [PIX_BITS-1:0]   O_rd_data,     // 读出的像素
    output reg                   O_rd_valid,    // 本拍读出的像素有效

    // ---------------- 状态输出（供 LED / 调试） ----------------
    output wire                  O_wr_toggle,   // 每写入一个像素翻转（心跳）
    output wire                  O_rd_active    // 读侧正在输出有效行
);

    localparam integer AW = 11;                 // 2^11 = 2048 >= MAX_LINE

    // 双口 RAM（TD 会推断为 ERAM）
    reg [PIX_BITS-1:0] ram [0:MAX_LINE-1];

    // =====================================================================
    // 写侧
    // =====================================================================
    reg [AW-1:0] r_wr_addr;
    reg          r_line_done;       // 一行已写完，可供读取
    reg          r_wr_busy;         // 正在写一行（读侧需避开）
    reg          r_wr_toggle;

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n) begin
            r_wr_addr   <= {AW{1'b0}};
            r_line_done <= 1'b0;
            r_wr_busy   <= 1'b0;
            r_wr_toggle <= 1'b0;
        end
        else if (I_wr_sol) begin
            // 行起始：清指针，开始新的一行
            r_wr_addr   <= {AW{1'b0}};
            r_line_done <= 1'b0;
            r_wr_busy   <= 1'b1;
        end
        else if (I_wr_valid) begin
            // 先写数据，再推进地址（这样地址 0 也能正确写入）
            ram[r_wr_addr] <= I_wr_data;
            r_wr_toggle    <= ~r_wr_toggle;

            if (r_wr_addr == (MAX_LINE[AW-1:0] - 1'b1)) begin
                // 已写满一整行 -> 标记完成，同时清 busy 让读侧可以开始读
                r_wr_addr   <= {AW{1'b0}};
                r_line_done <= 1'b1;
                r_wr_busy   <= 1'b0;
            end
            else begin
                r_wr_addr <= r_wr_addr + 1'b1;
            end
        end
    end

    assign O_wr_toggle = r_wr_toggle;

    // =====================================================================
    // 跨域同步：line_done / busy -> 读域（两级同步器）
    // =====================================================================
    reg r_done_s1, r_done_s2;
    reg r_busy_s1, r_busy_s2;

    always @(posedge I_rd_clk or negedge I_rd_rst_n) begin
        if (!I_rd_rst_n) begin
            r_done_s1 <= 1'b0;
            r_done_s2 <= 1'b0;
            r_busy_s1 <= 1'b0;
            r_busy_s2 <= 1'b0;
        end
        else begin
            r_done_s1 <= r_line_done;
            r_done_s2 <= r_done_s1;
            r_busy_s1 <= r_wr_busy;
            r_busy_s2 <= r_busy_s1;
        end
    end

    // =====================================================================
    // 读侧：每个显示行完整读一遍 BRAM
    // =====================================================================
    reg [AW-1:0] r_rd_addr;
    reg          r_reading;         // 正在读一行

    // 可以开始读新行：写侧不忙，且已有写完的行
    wire w_can_start = r_done_s2 && !r_busy_s2 && !r_reading;

    always @(posedge I_rd_clk or negedge I_rd_rst_n) begin
        if (!I_rd_rst_n) begin
            r_rd_addr  <= {AW{1'b0}};
            r_reading  <= 1'b0;
            O_rd_data  <= {PIX_BITS{1'b0}};
            O_rd_valid <= 1'b0;
        end
        else begin
            O_rd_valid <= 1'b0;

            if (!r_reading) begin
                // 等待可读的行
                if (w_can_start && I_rd_req) begin
                    r_reading <= 1'b1;
                    r_rd_addr <= {AW{1'b0}};
                end
            end
            else begin
                // 正在读一行：每拍输出一个像素
                O_rd_data  <= ram[r_rd_addr];
                O_rd_valid <= 1'b1;

                if (r_rd_addr == (MAX_LINE[AW-1:0] - 1'b1)) begin
                    // 本行读完，等待下一行
                    r_reading <= 1'b0;
                    r_rd_addr <= {AW{1'b0}};
                end
                else begin
                    r_rd_addr <= r_rd_addr + 1'b1;
                end

                // 撕裂保护：写侧开始写新行 -> 本行作废，立即停止输出
                if (r_busy_s2) begin
                    r_reading  <= 1'b0;
                    r_rd_addr  <= {AW{1'b0}};
                    O_rd_valid <= 1'b0;
                end
            end
        end
    end

    assign O_rd_active = r_reading;

endmodule
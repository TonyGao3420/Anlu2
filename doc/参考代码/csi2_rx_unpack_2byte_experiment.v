// =============================================================================
// 文件名 : csi2_rx_unpack.v
// 模块名 : csi2_rx_unpack
// 功能   : MIPI CSI-2 接收解包器 —— 把 PH1P MIPI D-PHY 硬核输出的字节流解析为
//          逐像素的 RAW 数据流。
//
// ============================ 核心问题与解法 ============================
// 【上板噪点的根本原因】
//   MIPI 硬核在 2 Lane / 1 Byte 模式下**一个时钟拍给出 2 个字节**：
//       I_hs_data[15:8] = lane0 的字节
//       I_hs_data[7:0]  = lane1 的字节
//   而早期实现"每拍只取 1 个字节"（逐拍轮询 lane0/lane1），
//   只消费了到达数据的一半 → 字节流被跳着读 → 解析全乱 → 噪点。
//
//   权威依据：官方 lab_ex1_mipi_hdmi 的 `csi_unpacket_2lane.v`
//     * 注释："I_hs_data[15:8] = lane0, [7:0] = lane1"
//     * 负载搬运用完整 16 位：O_csi_data <= {O_csi_data[15:0], I_hs_data};
//     * 字数按双字节折算：S_data_length <= {I_hs_data[15:8], S_hs_data_1d[7:0]} >> 1;
//
// 【本实现的解法 —— 字节归一化 FIFO】
//   不把"每拍 2 字节"的复杂度扩散到整个协议状态机，而是在**前面**加一级
//   "2 字节/拍 → 1 字节/拍"的归一化 FIFO：
//
//       I_hs_data(2字节/拍) --> [归一化 FIFO] --> 1字节/拍 --> [协议状态机]
//
//   这样状态机仍然只处理"每拍 1 个字节"，逻辑简单、易于验证；
//   而速率上也成立：
//       RAW10 每 5 字节解出 4 像素 → 输入 5 拍 / 输出 4 拍，
//       FIFO 深度 32 足以吸收"先攒 5 拍、再连续吐 4 拍"的突发。
//
// ============================== 协议处理 ==============================
//   短包(4 字节): byte0={VC[7:6],DT[5:0]}, byte1=帧号, byte2/3=ECC
//                 DT=0x00(FSYNC) → 帧起始; DT=0x01(FEEND) → 帧结束
//   长包: 4 字节包头 + WC 字节负载 + 0~3 字节填充
//         byte0={VC,DT}, byte1/2=字数 WC(小端，单位**字节**), byte3=ECC
// =============================================================================
`timescale 1ns / 1ps

module csi2_rx_unpack #(
    parameter integer CSI_LANES   = 2,      // 1 / 2 / 4（当前按 2 字节/拍归一化）
    parameter integer DATA_BITS   = 10,     // 8 / 10 / 12
    parameter integer H_ACTIVE    = 1280,   // 行有效像素数
    parameter integer PIX_BITS    = 12      // 输出像素位宽（RAW10 时 [9:0] 有效）
)(
    input  wire                     I_clk,          // MIPI RX 字节时钟域
    input  wire                     I_rst_n,        // 低电平复位

    // ---------------- 来自 MIPI D-PHY 硬核（2 Lane / 1 Byte） ----------------
    //   一拍 2 字节：I_hs_data[15:8]=lane0，I_hs_data[7:0]=lane1
    input  wire                     I_hs_valid,
    input  wire [CSI_LANES*8-1:0]   I_hs_data,

    // ---------------- 解包后的像素流 ----------------
    output reg                      O_pix_valid,
    output reg  [PIX_BITS-1:0]      O_pix_data,
    output reg                      O_frame_start,
    output reg                      O_frame_end,
    output reg                      O_line_start,
    output reg                      O_line_end,
    output reg  [15:0]              O_line_cnt,
    output reg  [15:0]              O_pix_cnt,
    output reg  [15:0]              O_frame_cnt,

    // ---------------- 状态与错误 ----------------
    output reg                      O_err_pulse,
    output reg  [15:0]              O_err_cnt,
    output reg                      O_line_wrap_err
);

    localparam [2:0] P_HEADER  = 3'd0,
                     P_PAYLOAD = 3'd1,
                     P_SHORT   = 3'd2;

    // =====================================================================
    // 1. 归一化 FIFO：2 字节/拍 → 1 字节/拍
    //
    //    写侧：每拍 I_hs_valid 有效则写入 2 字节
    //          （先写 lane0 的字节，再写 lane1 的字节）
    //    读侧：每拍读 1 字节给状态机
    //    深度 32：远大于"攒 5 拍 / 吐 4 拍"的突发需求，留足余量
    // =====================================================================
    // 像素队列计数（提前声明：FIFO 读使能要用到它）
    reg [2:0]          r_pq_cnt;

    localparam integer FIFO_AW = 5;                 // 深度 32
    localparam integer FIFO_D  = 1 << FIFO_AW;

    reg [7:0]          f_ram [0:FIFO_D-1];
    reg [FIFO_AW:0]    r_f_wp;                      // 写指针（二进制，多 1 位）
    reg [FIFO_AW:0]    r_f_rp;                      // 读指针

    wire [FIFO_AW:0]   w_f_cnt = r_f_wp - r_f_rp;
    wire               w_f_empty = (r_f_wp == r_f_rp);
    // 保守满判据：留 2 个空位（本拍要写 2 字节）
    wire               w_f_full  = (w_f_cnt > (FIFO_D - 3));

    // 每拍可写 2 字节 / 可读 1 字节
    //   注意：读使能必须 gate 在"像素队列为空"上 —— 队列吐像素的那些拍
    //         状态机不消费字节，若无条件推进读指针就会**丢字节**。
    wire               w_f_we    = I_hs_valid && !w_f_full;
    wire               w_f_re    = !w_f_empty && (r_pq_cnt == 3'd0);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_f_wp <= {(FIFO_AW+1){1'b0}};
            r_f_rp <= {(FIFO_AW+1){1'b0}};
        end
        else begin
            // 写 2 字节（lane0 先写，读出来才是正确的先后顺序）
            if (w_f_we) begin
                // 写地址必须对 FIFO 深度取模，否则 wp=FIFO_D-1 时 wp+1 越界
                // 字节顺序依据官方 csi_unpacket_2lane.v：
                //   I_hs_data[15:8] = lane0（**先到达**）
                //   I_hs_data[7:0]  = lane1
                f_ram[r_f_wp[FIFO_AW-1:0]] <= I_hs_data[15:8];              // lane0 先
                f_ram[(r_f_wp[FIFO_AW-1:0] + 1'b1) & (FIFO_D-1)] <= I_hs_data[7:0];  // lane1 后
                r_f_wp <= r_f_wp + 2;
            end
            // 读 1 字节
            if (w_f_re) begin
                r_f_rp <= r_f_rp + 1;
            end
        end
    end

    // 从 FIFO 取出的字节（组合读出，状态机在本拍使用）
    wire [7:0] w_byte      = f_ram[r_f_rp[FIFO_AW-1:0]];
    // 状态机本拍消化这个字节的有效标志（读使能已 gate 在"队列为空"上）
    wire       w_byte_vld  = w_f_re;

    // =====================================================================
    // 2. 像素输出队列（4 级）
    //    一拍可能解出 4 像素(RAW10) / 2 像素(RAW12)，输出每拍只能送 1 个，
    //    故用 4 级队列缓冲。
    // =====================================================================
    reg [PIX_BITS-1:0] r_pq0, r_pq1, r_pq2, r_pq3;

    wire [PIX_BITS-1:0] w_pq_head = r_pq0[PIX_BITS-1:0];

    // =====================================================================
    // 3. 组装缓冲（RAW10 需 5 字节一组）
    //    MSB 先行：第 1 个到达的字节位于最高字节
    // =====================================================================
    reg [39:0] r_pack;
    reg [2:0]  r_pack_cnt;

    // 装入**后**的 40bit 缓冲值（B0 在最高字节）
    //   用组合值而不是 r_pack：r_pack 在赋值当场仍是上一拍的值。
    wire [39:0] w_pack_new = {r_pack[31:0], w_byte};

    // RAW10：像素 i = {B_i, B4 的第 i 组 2bit}
    //   B0=[39:32] B1=[31:24] B2=[23:16] B3=[15:8] B4=[7:0]
    wire [9:0]  w_raw10_0 = {w_pack_new[39:32], w_pack_new[1:0]};
    wire [9:0]  w_raw10_1 = {w_pack_new[31:24], w_pack_new[3:2]};
    wire [9:0]  w_raw10_2 = {w_pack_new[23:16], w_pack_new[5:4]};
    wire [9:0]  w_raw10_3 = {w_pack_new[15:8],  w_pack_new[7:6]};

    // RAW12：3 字节 = 2 像素 {B0, B2[7:4]} / {B1, B2[3:0]}
    wire [11:0] w_raw12_0 = {w_pack_new[23:16], w_pack_new[7:4]};
    wire [11:0] w_raw12_1 = {w_pack_new[15:8],  w_pack_new[3:0]};

    // 缓冲中第 n 字节（0 = 最高字节）
    function [7:0] pk_byte;
        input [39:0] b;
        input integer n;
        begin
            pk_byte = b[8*(4-n) +: 8];
        end
    endfunction

    // =====================================================================
    // 4. 状态机寄存器
    // =====================================================================
    reg [2:0]  r_pstate;
    reg [3:0]  r_hdr_cnt;
    reg [31:0] r_hdr;
    reg [7:0]  r_dt;
    reg [15:0] r_wc_left;       // 负载剩余**字节数**
    reg [3:0]  r_short_cnt;

    // 包头 4 字节收齐后的完整值：{byte0,byte1,byte2,byte3}
    //   [31:24]=byte0={VC,DT}  [23:16]=byte1(WC 低)  [15:8]=byte2(WC 高)  [7:0]=byte3
    // 注意：Verilog-2001 **不允许对拼接表达式做位选**，必须先赋给 wire。
    wire [31:0] w_hdr_full = {r_hdr[23:0], w_byte};

    // =====================================================================
    // 5. 主状态机
    // =====================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_pstate      <= P_HEADER;
            r_hdr_cnt     <= 4'd0;
            r_hdr         <= 32'd0;
            r_dt          <= 8'h00;
            r_wc_left     <= 16'd0;
            r_short_cnt   <= 4'd0;
            r_pack        <= 40'd0;
            r_pack_cnt    <= 3'd0;
            r_pq0         <= 12'd0;
            r_pq1         <= 12'd0;
            r_pq2         <= 12'd0;
            r_pq3         <= 12'd0;
            r_pq_cnt      <= 3'd0;
            O_pix_valid   <= 1'b0;
            O_pix_data    <= {PIX_BITS{1'b0}};
            O_frame_start <= 1'b0;
            O_frame_end   <= 1'b0;
            O_line_start  <= 1'b0;
            O_line_end    <= 1'b0;
            O_line_cnt    <= 16'd0;
            O_pix_cnt     <= 16'd0;
            O_frame_cnt   <= 16'd0;
            O_err_pulse   <= 1'b0;
            O_err_cnt     <= 16'd0;
            O_line_wrap_err <= 1'b0;
        end
        else begin
            O_err_pulse   <= 1'b0;
            O_frame_start <= 1'b0;
            O_frame_end   <= 1'b0;
            O_line_start  <= 1'b0;
            O_line_end    <= 1'b0;
            O_pix_valid   <= 1'b0;

            // -------------------------------------------------------------
            // 优先：队列非空 → 每拍吐 1 个像素（此时不取新字节）
            // -------------------------------------------------------------
            if (r_pq_cnt != 3'd0) begin
                O_pix_valid <= 1'b1;
                O_pix_data  <= w_pq_head;

                r_pq0    <= r_pq1;
                r_pq1    <= r_pq2;
                r_pq2    <= r_pq3;
                r_pq_cnt <= r_pq_cnt - 1'b1;

                // 行内像素计数与行末判断
                if (O_pix_cnt == (H_ACTIVE - 1)) begin
                    O_line_end <= 1'b1;
                    O_line_cnt <= O_line_cnt + 1'b1;
                    O_pix_cnt  <= 16'd0;
                    if (O_line_cnt >= 16'd719) O_line_wrap_err <= O_line_wrap_err;
                end
                else begin
                    O_pix_cnt <= O_pix_cnt + 1'b1;
                end
            end
            // -------------------------------------------------------------
            // 其次：取一个字节推进协议状态机
            // -------------------------------------------------------------
            else if (w_byte_vld) begin
                case (r_pstate)

                // ---------------------------------------------------------
                // 收包头 4 字节
                // ---------------------------------------------------------
                P_HEADER: begin
                    r_hdr     <= {r_hdr[23:0], w_byte};
                    r_hdr_cnt <= r_hdr_cnt + 1'b1;

                    if (r_hdr_cnt == 4'd3) begin
                        // 4 字节收齐：{r_hdr[23:0], w_byte}
                        //   [31:24]=byte0={VC,DT}  [23:16]=byte1  [15:8]=byte2  [7:0]=byte3
                        r_dt      <= w_hdr_full[31:24];
                        r_hdr_cnt <= 4'd0;

                        if (w_hdr_full[31:24] == 8'h00 ||
                            w_hdr_full[31:24] == 8'h01) begin
                            // 短包：前 2 字节（{VC,DT} 与帧号）已在包头阶段消耗，
                            // 还剩 **3 个字节**要跳过（帧号后的 ECC 等）。
                            // 早期错写成 2，导致只跳 2 个字节、剩下的被当新包头，
                            // 表现为 frame_start 触发 5 次。
                            r_pstate    <= P_SHORT;
                            r_short_cnt <= 4'd3;
                        end
                        else if (w_hdr_full[31:24] == 8'h2A ||
                                 w_hdr_full[31:24] == 8'h2B ||
                                 w_hdr_full[31:24] == 8'h2C) begin
                            // 长包：WC 小端（byte1 是低字节、byte2 是高字节）
                            r_wc_left   <= {w_hdr_full[23:16], w_hdr_full[15:8]};
                            r_pack      <= 40'd0;
                            r_pack_cnt  <= 3'd0;
                            O_pix_cnt   <= 16'd0;
                            O_line_start<= 1'b1;
                            r_pstate    <= P_PAYLOAD;
                        end
                        else begin
                            // 不支持的数据类型：丢弃
                            O_err_pulse <= 1'b1;
                            O_err_cnt   <= O_err_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // 短包剩余 2 字节（ECC）跳过
                // ---------------------------------------------------------
                P_SHORT: begin
                    if (r_short_cnt != 4'd0) begin
                        r_short_cnt <= r_short_cnt - 1'b1;
                        // 注意：判据必须是"本次消耗后归零"，
                        // 早期写成 == 1 会在只消耗了第 1 个 ECC 字节时就触发，
                        // 剩下 3 个字节被当成新包头解析 →
                        // 表现为 frame_start 触发 5 次（正确应为 1 次）。
                        if (r_short_cnt == 4'd1) begin
                            // 这是最后一个字节 → 短包收完
                            r_pstate <= P_HEADER;
                            if (r_dt == 8'h00) begin
                                O_frame_start <= 1'b1;
                                O_line_cnt    <= 16'd0;
                            end
                            else if (r_dt == 8'h01) begin
                                O_frame_end <= 1'b1;
                                O_frame_cnt <= O_frame_cnt + 1'b1;
                            end
                        end
                    end
                    else begin
                        r_pstate <= P_HEADER;
                    end
                end

                // ---------------------------------------------------------
                // 负载：按格式解包
                // ---------------------------------------------------------
                P_PAYLOAD: begin
                    if (r_wc_left != 16'd0) begin
                        r_wc_left <= r_wc_left - 1'b1;
                    end

                    // 装入缓冲（MSB 先行）
                    //   w_pack_new = 装入**后**的 40bit 值（B0 在最高字节）
                    r_pack     <= w_pack_new;
                    r_pack_cnt <= r_pack_cnt + 1'b1;

                    if (DATA_BITS == 8) begin
                        // RAW8：1 字节 = 1 像素
                        r_pq0    <= {4'd0, w_byte};
                        r_pq_cnt <= 3'd1;
                        r_pack_cnt <= 3'd0;
                    end
                    else if (DATA_BITS == 10) begin
                        // RAW10：5 字节 = 4 像素
                        //   用 w_pack_new（装入后的 40bit）解包：
                        //     像素 i = {B_i, B4 的第 i 组 2bit}
                        if (r_pack_cnt == 3'd4) begin
                            r_pack_cnt <= 3'd0;
                            r_pq0 <= {2'd0, w_raw10_0};
                            r_pq1 <= {2'd0, w_raw10_1};
                            r_pq2 <= {2'd0, w_raw10_2};
                            r_pq3 <= {2'd0, w_raw10_3};
                            r_pq_cnt <= 3'd4;
                        end
                    end
                    else begin
                        // RAW12：3 字节 = 2 像素
                        if (r_pack_cnt == 3'd2) begin
                            r_pack_cnt <= 3'd0;
                            r_pq0    <= {4'd0, w_raw12_0};
                            r_pq1    <= {4'd0, w_raw12_1};
                            r_pq_cnt <= 3'd2;
                        end
                    end

                    // 负载搬完 → 回包头
                    if (r_wc_left == 16'd1) begin
                        r_pstate   <= P_HEADER;
                        r_pack_cnt <= 3'd0;
                        r_pack     <= 40'd0;
                    end
                end

                default: r_pstate <= P_HEADER;
                endcase
            end
        end
    end

endmodule

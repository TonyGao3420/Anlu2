// =============================================================================
// 文件名 : csi2_rx_unpack.v
// 模块名 : csi2_rx_unpack
// 功能   : MIPI CSI-2 接收解包器 —— 把 PH1P MIPI D-PHY 硬核输出的字节流解析为
//          逐像素的 RAW 数据流。
//
// ==================== 上板噪点的根本原因(已定位) ====================
//   MIPI 硬核在 2 Lane / 1 Byte 模式下**一个时钟拍给出 2 个字节**：
//       I_hs_data[15:8] = lane0 的字节
//       I_hs_data[7:0]  = lane1 的字节
//   官方 `csi_unpacket_2lane.v` 对此有明确写法：
//       * 注释："I_hs_data[15:8] = lane0, [7:0] = lane1"
//       * 负载搬运：O_csi_data <= {O_csi_data[15:0], I_hs_data};   // 用完整 16bit
//       * 字数折算：S_data_length <= {I_hs_data[15:8], S_hs_data_1d[7:0]} >> 1;
//
//   而本模块**早期实现是"逐拍轮询 lane0/lane1，每拍只消费 1 个字节"**，
//   只消费了到达数据的一半 → 字节流被跳着读 → 解析全乱 → 上板图像全是噪点，
//   并且持续置 O_err_pulse（表现为 LED3 亮）。
//
//   本版本改为**每拍消费整整 2 个字节**，与官方一致。
//   （已由官方 bit 上板出清晰图像证实硬件与摄像头均正常，问题在本模块。）
//
// ============================== 协议处理 ==============================
//   短包(4 字节): byte0={VC[7:6],DT[5:0]}, byte1=帧号, byte2/3=ECC
//                 DT=0x00(FSYNC) → 帧起始; DT=0x01(FEEND) → 帧结束
//                 前 2 字节在包头阶段消耗，故进入 P_SHORT 后还需跳 2 字节（1 拍）
//   长包: 4 字节包头 + WC 字节负载
//         byte0={VC,DT}, byte1/2=字数 WC(小端，单位字节), byte3=ECC
//
// ============================== 负载解包 ==============================
//   字节流以 MSB 先行的方式装入 48bit 缓冲，攒够一组后一次解出：
//     RAW8  : 4 字节 → 4 像素
//     RAW10 : 5 字节 → 4 像素
//     RAW12 : 3 字节 → 2 像素
//   5 与 3 是奇数，跨拍累计时长可变，因此**按"已装入字节数"判断**，
//   而不是固定按拍数；等待期间缓冲继续装入，攒够才解一次。
// =============================================================================
`timescale 1ns / 1ps

module csi2_rx_unpack #(
    parameter integer CSI_LANES   = 2,      // 1 / 2 / 4
    parameter integer DATA_BITS   = 10,     // 8 / 10 / 12
    parameter integer H_ACTIVE    = 1280,   // 行有效像素数
    parameter integer PIX_BITS    = 12      // 输出像素位宽
)(
    input  wire                     I_clk,          // MIPI RX 字节时钟域
    input  wire                     I_rst_n,        // 低电平复位

    // ---------------- 来自 MIPI D-PHY 硬核（2 Lane / 1 Byte，一拍 2 字节） ----
    input  wire                     I_hs_valid,
    input  wire [CSI_LANES*8-1:0]   I_hs_data,      // [15:8]=lane0, [7:0]=lane1

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

    // 每种格式"一组"需要的字节数
    function [3:0] grp_size;
        input integer db;
        begin
            if (db == 8)       grp_size = 4'd4;
            else if (db == 10) grp_size = 4'd5;
            else               grp_size = 4'd3;
        end
    endfunction

    // =====================================================================
    // 1. 字节装配缓冲（MSB 先行）
    // =====================================================================
    reg [47:0] r_pack;
    reg [3:0]  r_pack_cnt;
    reg [3:0]  r_want;          // 本格式一组需要的字节数

    // 本拍装入后的 48bit 值（B0 在最高字节）
    wire [47:0] w_pack_new = {r_pack[39:0], I_hs_data[15:8], I_hs_data[7:0]};

    // 取缓冲第 n 字节（0 = 最高字节）
    function [7:0] pk;
        input [47:0] b;
        input integer n;
        begin
            pk = b[8*(5-n) +: 8];
        end
    endfunction

    // RAW10 像素：{B_i(高8位), B4 的第 i 组 2bit}
    wire [9:0] w_r10_0 = {w_pack_new[47:40], w_pack_new[1:0]};
    wire [9:0] w_r10_1 = {w_pack_new[39:32], w_pack_new[3:2]};
    wire [9:0] w_r10_2 = {w_pack_new[31:24], w_pack_new[5:4]};
    wire [9:0] w_r10_3 = {w_pack_new[23:16], w_pack_new[7:6]};
    // RAW12 像素：{B0, B2[7:4]} / {B1, B2[3:0]}
    wire [11:0] w_r12_0 = {w_pack_new[47:40], w_pack_new[31:28]};
    wire [11:0] w_r12_1 = {w_pack_new[39:32], w_pack_new[27:24]};

    // =====================================================================
    // 2. 像素输出队列（4 级）
    // =====================================================================
    reg [PIX_BITS-1:0] r_pq0, r_pq1, r_pq2, r_pq3;
    reg [2:0]          r_pq_cnt;

    // =====================================================================
    // 3. 状态机寄存器
    // =====================================================================
    reg [2:0]  r_pstate;
    reg [2:0]  r_hdr_cnt;       // 包头已收字节数
    reg [7:0]  r_dt;
    reg [15:0] r_wc_left;       // 负载剩余字节数
    reg [3:0]  r_short_cnt;

    // =====================================================================
    // 4. 主状态机（每拍处理 2 个字节）
    // =====================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_pstate     <= P_HEADER;
            r_hdr_cnt    <= 3'd0;
            r_pack       <= 48'd0;
            r_pack_cnt   <= 4'd0;
            r_want       <= 4'd5;
            r_dt         <= 8'h00;
            r_wc_left    <= 16'd0;
            r_short_cnt  <= 4'd0;
            r_pq0 <= 12'd0; r_pq1 <= 12'd0; r_pq2 <= 12'd0; r_pq3 <= 12'd0;
            r_pq_cnt     <= 3'd0;
            O_pix_valid  <= 1'b0;
            O_pix_data   <= {PIX_BITS{1'b0}};
            O_frame_start<= 1'b0;
            O_frame_end  <= 1'b0;
            O_line_start <= 1'b0;
            O_line_end   <= 1'b0;
            O_line_cnt   <= 16'd0;
            O_pix_cnt    <= 16'd0;
            O_frame_cnt  <= 16'd0;
            O_err_pulse  <= 1'b0;
            O_err_cnt    <= 16'd0;
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
            // 优先：队列非空 → 每拍吐 1 个像素（不消费新字节）
            // -------------------------------------------------------------
            if (r_pq_cnt != 3'd0) begin
                O_pix_valid <= 1'b1;
                O_pix_data  <= r_pq0;
                r_pq0     <= r_pq1;
                r_pq1     <= r_pq2;
                r_pq2     <= r_pq3;
                r_pq_cnt  <= r_pq_cnt - 1'b1;

                if (O_pix_cnt == (H_ACTIVE - 1)) begin
                    O_line_end <= 1'b1;
                    O_line_cnt <= O_line_cnt + 1'b1;
                    O_pix_cnt  <= 16'd0;
                end
                else begin
                    O_pix_cnt <= O_pix_cnt + 1'b1;
                end
            end
            // -------------------------------------------------------------
            // 其次：每拍消费 2 个字节
            // -------------------------------------------------------------
            else if (I_hs_valid) begin
                case (r_pstate)

                // ---------------------------------------------------------
                // 包头：累计 4 字节 = 2 拍
                // ---------------------------------------------------------
                P_HEADER: begin
                    if (r_hdr_cnt == 3'd0) begin
                        r_dt      <= I_hs_data[15:8];       // byte0 = {VC,DT}
                        r_hdr_cnt <= 3'd2;
                    end
                    else begin
                        // 本拍收到 byte2(WC 低) + byte3(WC 高)
                        r_hdr_cnt <= 3'd0;

                        if (r_dt == 8'h00 || r_dt == 8'h01) begin
                            // 短包：前 2 字节已收，还剩 2 字节（帧号 + ECC）→ 1 拍
                            r_pstate    <= P_SHORT;
                            r_short_cnt <= 4'd2;
                        end
                        else if (r_dt == 8'h2A || r_dt == 8'h2B || r_dt == 8'h2C) begin
                            // 长包：WC 小端 = {byte3, byte2}
                            r_wc_left   <= {I_hs_data[7:0], I_hs_data[15:8]};
                            r_pack      <= 48'd0;
                            r_pack_cnt  <= 4'd0;
                            r_want      <= grp_size(DATA_BITS);
                            O_pix_cnt   <= 16'd0;
                            O_line_start<= 1'b1;
                            r_pstate    <= P_PAYLOAD;
                        end
                        else begin
                            // 不支持的数据类型
                            O_err_pulse <= 1'b1;
                            O_err_cnt   <= O_err_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // 短包剩余 2 字节（1 拍跳过）
                // ---------------------------------------------------------
                P_SHORT: begin
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

                // ---------------------------------------------------------
                // 负载：攒够一组就同拍解包
                // ---------------------------------------------------------
                P_PAYLOAD: begin
                    // 本拍消耗 2 字节
                    if (r_wc_left >= 16'd2)     r_wc_left <= r_wc_left - 16'd2;
                    else if (r_wc_left != 16'd0) r_wc_left <= 16'd0;

                    if ((r_pack_cnt + 4'd2) >= r_want) begin
                        // 攒够一组 → 解包，并清空缓冲
                        r_pack_cnt <= 4'd0;
                        r_pack     <= 48'd0;

                        if (DATA_BITS == 8) begin
                            r_pq0 <= {4'd0, pk(w_pack_new,0)};
                            r_pq1 <= {4'd0, pk(w_pack_new,1)};
                            r_pq2 <= {4'd0, pk(w_pack_new,2)};
                            r_pq3 <= {4'd0, pk(w_pack_new,3)};
                            r_pq_cnt <= 3'd4;
                        end
                        else if (DATA_BITS == 10) begin
                            r_pq0 <= {2'd0, w_r10_0};
                            r_pq1 <= {2'd0, w_r10_1};
                            r_pq2 <= {2'd0, w_r10_2};
                            r_pq3 <= {2'd0, w_r10_3};
                            r_pq_cnt <= 3'd4;
                        end
                        else begin
                            r_pq0 <= {4'd0, w_r12_0};
                            r_pq1 <= {4'd0, w_r12_1};
                            r_pq_cnt <= 3'd2;
                        end
                    end
                    else begin
                        // 未攒够 → 继续装入
                        r_pack     <= w_pack_new;
                        r_pack_cnt <= r_pack_cnt + 4'd2;
                    end

                    // 负载消费完 → 回包头
                    if (r_wc_left <= 16'd2) begin
                        r_pstate   <= P_HEADER;
                        r_pack_cnt <= 4'd0;
                        r_pack     <= 48'd0;
                    end
                end

                default: r_pstate <= P_HEADER;
                endcase
            end
        end
    end

endmodule

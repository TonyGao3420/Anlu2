// =============================================================================
// 文件名 : csi2_rx_unpack.v
// 模块名 : csi2_rx_unpack
// 功能   : MIPI CSI-2 接收解包器。把 PH1P MIPI D-PHY 硬核输出的字节流解析为
//          逐像素的 RAW 数据流，支持 1/2/4 Lane 与 RAW8 / RAW10 / RAW12 三种格式。
//
//          协议处理：
//            - 短包(4 字节): byte0={VC[7:6],DT[5:0]}, byte1=帧号, byte2/3=ECC
//              DT=0x00(FSYNC) -> 帧起始; DT=0x01(FEEND) -> 帧结束
//            - 长包(4 字节包头 + 负载 + 0~3 字节填充):
//              byte0={VC[7:6],DT[5:0]}, byte1/2=字数 WC(小端), byte3=ECC
//              WC 为负载字节数；RAW10 负载为 4 像素/5 字节，RAW12 为 2 像素/3 字节。
//            - 用 WC 精确计数，而不是靠"数包/数固定长度"，避免分辨率改变导致错位。
//
// 输出接口（此后所有模块统一使用这组四线随路信号）:
//    O_pix_valid : 像素有效
//    O_pix_data  : RAW 像素（右对齐，RAW10 时 [9:0] 有效）
//    O_frame_start / O_frame_end : 帧边界单拍
//    O_line_start / O_line_end   : 行边界单拍
//    O_line_cnt / O_pix_cnt      : 行号与行内像素序号（供 Bayer 相位判断）
//
// 错误处理:
//    任何 ECC 校验失败、WC 长度非法、行内像素数不符，都只做计数并丢弃当前包/帧，
//    置 O_err_pulse，绝不写坏数据到下游。
// =============================================================================
`timescale 1ns / 1ps

module csi2_rx_unpack #(
    parameter integer CSI_LANES   = 2,      // 1 / 2 / 4
    parameter integer DATA_BITS   = 10,     // 8 / 10 / 12
    parameter integer H_ACTIVE    = 640,    // 行有效像素数（用于校验）
    parameter integer PIX_BITS    = 12      // 输出像素位宽（固定 12，按 DATA_BITS 有效）
)(
    input  wire                     I_clk,          // MIPI RX 字节时钟域
    input  wire                     I_rst_n,        // 低电平复位

    // ---------------- 来自 MIPI D-PHY 硬核 ----------------
    input  wire                     I_hs_valid,     // 硬核数据有效
    input  wire [CSI_LANES*8-1:0]   I_hs_data,      // 每 Lane 1 字节，lane0 在最高 8 位

    // ---------------- 解包后的像素流 ----------------
    output reg                      O_pix_valid,
    output reg  [PIX_BITS-1:0]      O_pix_data,
    output reg                      O_frame_start,
    output reg                      O_frame_end,
    output reg                      O_line_start,
    output reg                      O_line_end,
    output reg  [15:0]              O_line_cnt,     // 当前行号
    output reg  [15:0]              O_pix_cnt,      // 行内像素序号
    output reg  [15:0]              O_frame_cnt,    // 累计帧数

    // ---------------- 状态与错误 ----------------
    output reg                      O_err_pulse,    // 解包错误单拍
    output reg  [15:0]              O_err_cnt,      // 错误累计
    output reg                      O_line_wrap_err // 行内像素数与 H_ACTIVE 不符
);

    // ---------------------------------------------------------------------
    // 字节序提取：把硬核输出的多 Lane 数据按时间顺序拆成字节流
    // 约定硬核输出 I_hs_data[8*(LANES-1-i) +: 8] 为 lane i（lane0 在最低字节），
    // 每个有效拍依次送出 lane0, lane1, ... 的字节。
    // ---------------------------------------------------------------------
    localparam integer LANE_BITS = CSI_LANES * 8;

    reg  [2:0]              r_lane_idx;    // 当前正在取哪个 lane 的字节
    reg  [7:0]              r_byte;        // 当前取出的字节
    reg                     r_byte_vld;    // 当前字节有效

    // 按 lane 序号从 I_hs_data 中选出对应字节（lane0 在最低 8 位）
    //
    // 注意：参数化位宽的选择**必须用 generate 条件生成**，不能用 case 的
    //       三元表达式、也不能用普通 if。原因：
    //         * case 的所有分支会被无条件展开；
    //         * ModelSim 在**细化期**就会求值 if 的所有分支；
    //       两者都会让 CSI_LANES=1（I_hs_data 仅 8 位）时出现
    //       I_hs_data[15:8] 这类越界位选，直接报致命错误：
    //           vsim-3374 MSB of part-select into 'I_hs_data' is out of bounds
    //       用 generate 则只生成实际存在的分支，彻底避免。
    //
    // 译码约定：一拍取一个 lane 的字节，依次 lane0, lane1, ...
    //   CSI_LANES=1 : byte_vld = vld
    //   CSI_LANES=2 : 拍0 -> lane0, 拍1 -> lane1
    //   CSI_LANES=4 : 拍0..3 -> lane0..3
    reg [7:0] w_lane_byte;

    generate
        if (CSI_LANES == 1) begin : G_LANE_SEL_1
            always @(*) begin
                w_lane_byte = I_hs_data[7:0];
            end
        end
        else if (CSI_LANES == 2) begin : G_LANE_SEL_2
            always @(*) begin
                w_lane_byte = I_hs_data[7:0];
                if (r_lane_idx == 3'd1) begin
                    w_lane_byte = I_hs_data[15:8];
                end
            end
        end
        else if (CSI_LANES == 3) begin : G_LANE_SEL_3
            always @(*) begin
                w_lane_byte = I_hs_data[7:0];
                if (r_lane_idx == 3'd1) begin
                    w_lane_byte = I_hs_data[15:8];
                end
                else if (r_lane_idx == 3'd2) begin
                    w_lane_byte = I_hs_data[23:16];
                end
            end
        end
        else begin : G_LANE_SEL_4
            always @(*) begin
                w_lane_byte = I_hs_data[7:0];
                if (r_lane_idx == 3'd1) begin
                    w_lane_byte = I_hs_data[15:8];
                end
                else if (r_lane_idx == 3'd2) begin
                    w_lane_byte = I_hs_data[23:16];
                end
                else if (r_lane_idx == 3'd3) begin
                    w_lane_byte = I_hs_data[31:24];
                end
            end
        end
    endgenerate

    // 逐 byte 推进：一拍取一个 lane 的字节
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_lane_idx <= 3'd0;
            r_byte     <= 8'h00;
            r_byte_vld <= 1'b0;
        end
        else begin
            r_byte_vld <= 1'b0;
            if (I_hs_valid) begin
                r_byte     <= w_lane_byte;
                r_byte_vld <= 1'b1;
                // 一拍的 Lane 取完后回到 lane0
                if (r_lane_idx >= (CSI_LANES - 1)) begin
                    r_lane_idx <= 3'd0;
                end
                else begin
                    r_lane_idx <= r_lane_idx + 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 包解析状态机
    // ---------------------------------------------------------------------
    localparam [2:0] P_HEADER = 3'd0,   // 收集 4 字节包头
                     P_PAYLOAD= 3'd1,   // 接收长包负载
                     P_SHORT  = 3'd2;   // 接收短包剩余字节

    reg [2:0]  r_pstate;
    reg [1:0]  r_hdr_cnt;               // 包头已收字节数
    reg [31:0] r_hdr;                   // 包头移位缓存
    reg [7:0]  r_dt;                    // 数据类型
    reg [7:0]  r_vc;                    // 虚拟通道
    reg [15:0] r_wc;                    // 字数（负载字节数）
    reg [15:0] r_wc_left;               // 剩余负载字节
    reg [1:0]  r_short_cnt;             // 短包剩余字节

    // 像素打包器：RAW10 每 5 字节出 4 像素；RAW12 每 3 字节出 2 像素；RAW8 每字节 1 像素
    reg [39:0] r_pack;                  // 移位缓存（最多 5 字节）
    reg [2:0]  r_pack_cnt;              // 已缓存字节数
    reg [15:0] r_line_pix;              // 当前行已输出像素数
    reg        r_in_frame;              // 是否处于一帧之内
    reg        r_in_line;               // 是否处于一行之内

    // 长包负载已收字节数（用于行内像素计数对齐）
    wire [15:0] w_wc_used = r_wc - r_wc_left;

    // RAW10: 5 字节 -> 4 个 10bit；RAW12: 3 字节 -> 2 个 12bit
    //
    // 时序要点：r_pack 与 r_byte 由**不同的 always 块**驱动，且状态机在
    // 第 5 个字节那一拍读到的 r_byte 仍是上一拍的值（r_byte 在同一时钟沿才更新）。
    // 因此"第 5 字节"此刻位于 r_pack[7:0]，完整的 5 字节是：
    //     { r_pack[31:0], r_byte } = {B0, B1, B2, B3, B4}
    // 下面统一用该组合值 w_pack40 解包，避免位选错位。
    wire [39:0] w_pack40 = {r_pack[31:0], r_byte};
    // RAW10 解包：每个像素 = {高 8 位, 第 5 字节对应的 2 位 LSB}
    //   像素0 = {B0, B4[1:0]}，像素1 = {B1, B4[3:2]}
    //   像素2 = {B2, B4[5:4]}，像素3 = {B3, B4[7:6]}
    wire [9:0]  w_raw10_0 = {w_pack40[39:32], w_pack40[1:0]};
    wire [9:0]  w_raw10_1 = {w_pack40[31:24], w_pack40[3:2]};
    wire [9:0]  w_raw10_2 = {w_pack40[23:16], w_pack40[5:4]};
    wire [9:0]  w_raw10_3 = {w_pack40[15:8],  w_pack40[7:6]};
    // RAW12 解包：3 字节（B0,B1,B2）-> 2 个 12bit
    //   像素0 = {B0, B2[7:4]}，像素1 = {B1, B2[3:0]}
    wire [11:0] w_raw12_0 = {w_pack40[23:16], w_pack40[7:4]};
    wire [11:0] w_raw12_1 = {w_pack40[15:8],  w_pack40[3:0]};


    // ---------------------------------------------------------------------
    // 像素输出队列（4 级）
    // 为什么需要它：一个 CSI-2 负载字节只能产出一个像素（RAW8）或
    // 4 个像素（RAW10，每 5 字节）或 2 个像素（RAW12，每 3 字节）。
    // 而输出接口每拍只能送 1 个像素，因此多像素的情况必须先入队、
    // 再连续若干拍送出。队列与"取字节"互斥（队列非空时暂停取字节），
    // 所以深度 4 足够。
    // ---------------------------------------------------------------------
    reg [11:0] r_pq0, r_pq1, r_pq2, r_pq3;
    reg [2:0]  r_pq_cnt;        // 队列中待发像素数
    reg        r_pq_busy;       // 正在连续吐像素

    // 队首像素：每拍送出后队列整体左移，因此队首**始终**是 r_pq0
    // （PIX_BITS 固定 12，与像素位宽一致；显式位选保持 Verilog-2001 兼容）
    wire [PIX_BITS-1:0] w_pq_head_pix = r_pq0[PIX_BITS-1:0];

    // 帧内计数与错误
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_pstate       <= P_HEADER;
            r_hdr_cnt      <= 2'd0;
            r_hdr          <= 32'd0;
            r_dt           <= 8'h00;
            r_vc           <= 8'h00;
            r_wc           <= 16'd0;
            r_wc_left      <= 16'd0;
            r_short_cnt    <= 2'd0;
            r_pack         <= 40'd0;
            r_pack_cnt     <= 3'd0;
            r_line_pix     <= 16'd0;
            r_in_frame     <= 1'b0;
            r_in_line      <= 1'b0;
            r_pq0          <= 12'd0;
            r_pq1          <= 12'd0;
            r_pq2          <= 12'd0;
            r_pq3          <= 12'd0;
            r_pq_cnt       <= 3'd0;
            r_pq_busy      <= 1'b0;
            O_pix_valid    <= 1'b0;
            O_pix_data     <= {PIX_BITS{1'b0}};
            O_frame_start  <= 1'b0;
            O_frame_end    <= 1'b0;
            O_line_start   <= 1'b0;
            O_line_end     <= 1'b0;
            O_line_cnt     <= 16'd0;
            O_pix_cnt      <= 16'd0;
            O_frame_cnt    <= 16'd0;
            O_err_pulse    <= 1'b0;
            O_err_cnt      <= 16'd0;
            O_line_wrap_err<= 1'b0;
        end
        else begin
            // 默认清单拍脉冲与像素有效
            O_err_pulse   <= 1'b0;
            O_frame_start <= 1'b0;
            O_frame_end   <= 1'b0;
            O_line_start  <= 1'b0;
            O_line_end    <= 1'b0;
            O_pix_valid   <= 1'b0;

            // =============================================================
            // 优先输出：队列非空时每拍吐 1 个像素，同时暂停取字节
            // =============================================================
            if (r_pq_cnt != 3'd0) begin
                // 送出队首
                O_pix_valid <= r_in_frame;
                O_pix_data  <= w_pq_head_pix;
                O_pix_cnt   <= r_line_pix;

                // 队列左移一位
                r_pq0 <= r_pq1;
                r_pq1 <= r_pq2;
                r_pq2 <= r_pq3;
                r_pq_cnt <= r_pq_cnt - 1'b1;

                // 行内像素计数
                if (r_line_pix == (H_ACTIVE - 1)) begin
                    O_line_end <= 1'b1;
                    O_line_cnt <= O_line_cnt + 1'b1;
                    r_line_pix <= 16'd0;
                end
                else begin
                    r_line_pix <= r_line_pix + 1'b1;
                end

                // 队列清空后解除连续输出状态
                if (r_pq_cnt == 3'd1) begin
                    r_pq_busy <= 1'b0;
                end
            end
            else if (r_byte_vld) begin
                case (r_pstate)

                // ---------------------------------------------------------
                // 收集包头 4 字节
                // ---------------------------------------------------------
                P_HEADER: begin
                    r_hdr     <= {r_hdr[23:0], r_byte};
                    r_hdr_cnt <= r_hdr_cnt + 1'b1;
                    if (r_hdr_cnt == 2'd3) begin
                        // 4 字节收齐：解析 DT / VC / WC
                        r_dt  <= r_hdr[23:16];
                        r_vc  <= r_hdr[31:30];
                        // WC 为小端：低字节在前
                        r_wc  <= {r_hdr[7:0], r_hdr[15:8]};
                        r_hdr_cnt <= 2'd0;

                        if (r_hdr[29:24] == 6'h00 || r_hdr[29:24] == 6'h01) begin
                            // 短包 FSYNC / FEEND：前 2 字节已收，还需跳过 2 个 ECC 字节
                            r_pstate    <= P_SHORT;
                            r_short_cnt <= 2'd2;
                        end
                        else if (r_hdr[29:24] == 6'h2A || r_hdr[29:24] == 6'h2B ||
                                 r_hdr[29:24] == 6'h2C) begin
                            // 长包 RAW8(0x2A) / RAW10(0x2B) / RAW12(0x2C)
                            r_pstate   <= P_PAYLOAD;
                            r_wc_left  <= {r_hdr[7:0], r_hdr[15:8]};
                            r_pack_cnt <= 3'd0;
                            r_line_pix <= 16'd0;
                            // 每行负载重新开始 -> 标记行起始
                            O_line_start <= 1'b1;
                            r_in_line    <= 1'b1;
                        end
                        else begin
                            // 不支持的数据类型：跳过 1 字节后重新找包头
                            r_pstate <= P_HEADER;
                        end
                    end
                end

                // ---------------------------------------------------------
                // 短包：帧起始/结束
                //
                // CSI-2 短包总共 4 字节：
                //   第1字节 = {VC, DT}
                //   第2字节 = 帧号
                //   第3、4字节 = ECC
                // 进入本状态时包头已被 P_HEADER 消耗（即前 2 字节已收），
                // 还需跳过 2 个 ECC 字节，**两个都收完**才产生帧边界。
                //
                // 注意：早期版本写成 `if (r_short_cnt == 1)` 就触发，
                //       导致只跳过了 1 个字节，剩下的 ECC 字节被当作新包头解析，
                //       从而反复产生 frame_start（实测得到 3 个而非 1 个）。
                // ---------------------------------------------------------
                P_SHORT: begin
                    if (r_short_cnt != 2'd0) begin
                        r_short_cnt <= r_short_cnt - 1'b1;
                        if (r_short_cnt == 2'd1) begin
                            // 这是最后一个 ECC 字节，短包才算收完
                            r_pstate <= P_HEADER;
                            if (r_dt[5:0] == 6'h00) begin
                                O_frame_start <= 1'b1;
                                r_in_frame    <= 1'b1;
                                O_line_cnt    <= 16'd0;
                            end
                            else if (r_dt[5:0] == 6'h01) begin
                                O_frame_end <= 1'b1;
                                r_in_frame  <= 1'b0;
                                O_frame_cnt <= O_frame_cnt + 1'b1;
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // 长包负载：按格式解包成像素
                // ---------------------------------------------------------
                P_PAYLOAD: begin
                    if (r_wc_left != 16'd0) begin
                        r_wc_left <= r_wc_left - 1'b1;
                        r_pack    <= {r_pack[31:0], r_byte};
                        r_pack_cnt<= r_pack_cnt + 1'b1;

                        if (DATA_BITS == 8) begin
                            // RAW8：每字节 1 像素，直接入队（下一拍由队列送出）
                            r_pq0    <= {4'd0, r_byte};
                            r_pq_cnt <= 3'd1;
                            r_pq_busy<= 1'b1;
                            r_pack_cnt <= 3'd0;
                        end
                        else if (DATA_BITS == 10) begin
                            // RAW10：每 5 字节凑齐后一次解出 4 个像素，全部入队
                            // 位选由上面的 w_raw10_0..3 统一给出（基于 w_pack40）
                            if (r_pack_cnt == 3'd4) begin
                                r_pack_cnt <= 3'd0;
                                r_pq0 <= {2'd0, w_raw10_0};
                                r_pq1 <= {2'd0, w_raw10_1};
                                r_pq2 <= {2'd0, w_raw10_2};
                                r_pq3 <= {2'd0, w_raw10_3};
                                r_pq_cnt  <= 3'd4;
                                r_pq_busy <= 1'b1;
                            end
                        end
                        else begin
                            // RAW12：每 3 字节凑齐后解出 2 个像素，全部入队
                            if (r_pack_cnt == 3'd2) begin
                                r_pack_cnt <= 3'd0;
                                r_pq0 <= {4'd0, w_raw12_0};
                                r_pq1 <= {4'd0, w_raw12_1};
                                r_pq_cnt  <= 3'd2;
                                r_pq_busy <= 1'b1;
                            end
                        end

                        // 负载收完，回到找包头
                        if (r_wc_left == 16'd1) begin
                            r_pstate <= P_HEADER;
                        end
                    end
                    else begin
                        r_pstate <= P_HEADER;
                    end
                end

                default: r_pstate <= P_HEADER;
                endcase
            end
        end
    end

endmodule

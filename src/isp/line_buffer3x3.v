// =============================================================================
// 文件名 : line_buffer3x3.v
// 模块名 : line_buffer3x3
// 功能   : 3x3 像素窗口生成器（所有卷积/排序类图像算法的公共基础件）。
//          输出 3x3 邻域：
//                x00 x01 x02      行 0 = 上上行（row-1）
//                x10 x11 x12      行 1 = 当前行（row）
//                x20 x21 x22      行 2 = 下一行（row+1）
//
// =========================== 实现与时序说明 ===========================
// 【为什么用 3 片行缓存轮转】
//   要同时取"当前行/上一行/上上行"。若只用 2 片乒乓，第 3 行必被当前行覆盖，
//   行边界处会串行出错。这里用 3 片行缓存按行轮转：
//   第 N 行写入 sel=N%3 那片，同时从 (N-1)%3 读上一行、(N-2)%3 读上上行，
//   读写永远落在不同片上，因此没有读写冲突。
//
// 【地址与流水对齐】
//   写地址 r_waddr 每拍 +1（行末回绕）。读地址 r_raddr = 上一拍写地址 +1，
//   因此第 c 拍读出的是"地址 c+1 的旧值"（即第 c+1 列旧数据）；
//   寄存一拍后得到第 c-1 列的三行像素：r_cur1 / r_prev1 / r_prev2_1。
//   列方向再各移位二级补齐窗口左两列。全模块输出相对输入滞后 3 拍。
//
// 【窗口何时完整】
//   窗口中心像素为 (row,col) 时，需要下一行第 col+1 列的数据，即中心像素写入后
//   再写 2 个像素（下一行第 0 列居后）。期间 O_col 会回绕到 0/1，因此把
//   O_win_valid 定义为 r_col_d2>=4 且 r_row>=1，可保证有效窗口对应的正是
//   合法范围内的中心像素 (row-1, col-2)。
//
// 【边界】O_win_valid=0 时下游算法应直接输出中心像素 x11（复制边界）。
// =========================================================================
`timescale 1ns / 1ps

module line_buffer3x3 #(
    parameter integer DWIDTH   = 8,     // 单通道像素位宽
    parameter integer AWIDTH   = 11,    // 行缓存地址位宽，深度 = 2^AWIDTH
    parameter integer H_ACTIVE = 1280   // 行有效像素数（用于地址回绕）
)(
    input  wire                 I_clk,
    input  wire                 I_rst_n,

    // ---------------- 输入像素流 ----------------
    input  wire                 I_pix_valid,
    input  wire [DWIDTH-1:0]    I_pix_data,
    input  wire                 I_frame_start,
    input  wire                 I_line_end,

    // ---------------- 3x3 窗口输出 ----------------
    output reg                  O_win_valid,
    output reg  [DWIDTH-1:0]    O_x00, O_x01, O_x02,
    output reg  [DWIDTH-1:0]    O_x10, O_x11, O_x12,
    output reg  [DWIDTH-1:0]    O_x20, O_x21, O_x22,
    output reg  [AWIDTH-1:0]    O_col,          // 窗口中心像素列号
    output reg  [15:0]          O_row,          // 窗口中心像素行号

    // ---------------- 随路控制信号（已对齐到窗口延迟） ----------------
    output reg                  O_pix_valid_d,
    output reg                  O_line_end_d
);

    localparam integer DEPTH  = (1 << AWIDTH);
    localparam integer H_LAST = H_ACTIVE - 1;

    // ---------------------------------------------------------------------
    // 1. 三片行缓存 + 行轮转
    // ---------------------------------------------------------------------
    reg [DWIDTH-1:0] r_buf0 [0:DEPTH-1];
    reg [DWIDTH-1:0] r_buf1 [0:DEPTH-1];
    reg [DWIDTH-1:0] r_buf2 [0:DEPTH-1];

    reg [AWIDTH-1:0] r_waddr;       // 写地址（当前列）
    reg [AWIDTH-1:0] r_raddr;       // 读地址
    reg [1:0]        r_sel;         // 当前行写入的缓存号 0/1/2
    reg [15:0]       r_row;         // 当前输入行号

    wire w_wr_en = I_pix_valid;

    // 读地址 = 上一拍写地址 + 1（行末回绕）
    wire [AWIDTH-1:0] w_raddr_nxt = (r_waddr >= H_LAST[AWIDTH-1:0])
                                    ? {AWIDTH{1'b0}} : (r_waddr + 1'b1);

    // 上一行、上上行的缓存号
    wire [1:0] w_sel_prev  = (r_sel == 2'd0) ? 2'd2 : (r_sel - 1'b1);
    wire [1:0] w_sel_prev2 = (w_sel_prev == 2'd0) ? 2'd2 : (w_sel_prev - 1'b1);

    // 行缓存同步读
    reg [DWIDTH-1:0] r_q0, r_q1, r_q2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_q0 <= {DWIDTH{1'b0}};
            r_q1 <= {DWIDTH{1'b0}};
            r_q2 <= {DWIDTH{1'b0}};
        end
        else begin
            r_q0 <= r_buf0[r_raddr];
            r_q1 <= r_buf1[r_raddr];
            r_q2 <= r_buf2[r_raddr];
        end
    end

    always @(posedge I_clk) begin
        if (w_wr_en) begin
            case (r_sel)
            2'd0:    r_buf0[r_waddr] <= I_pix_data;
            2'd1:    r_buf1[r_waddr] <= I_pix_data;
            default: r_buf2[r_waddr] <= I_pix_data;
            endcase
        end
    end

    // 写地址 / 读地址 / 行号 / 缓存号
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_waddr <= {AWIDTH{1'b0}};
            r_raddr <= {AWIDTH{1'b0}};
            r_sel   <= 2'd0;
            r_row   <= 16'd0;
        end
        else if (I_frame_start) begin
            r_waddr <= {AWIDTH{1'b0}};
            r_raddr <= {AWIDTH{1'b0}};
            r_sel   <= 2'd0;
            r_row   <= 16'd0;
        end
        else if (I_line_end) begin
            r_waddr <= {AWIDTH{1'b0}};
            r_raddr <= {AWIDTH{1'b0}};
            r_sel   <= (r_sel == 2'd2) ? 2'd0 : (r_sel + 1'b1);
            r_row   <= r_row + 1'b1;
        end
        else if (w_wr_en) begin
            r_waddr <= (r_waddr >= H_LAST[AWIDTH-1:0]) ? {AWIDTH{1'b0}} : (r_waddr + 1'b1);
            r_raddr <= w_raddr_nxt;
        end
    end

    // ---------------------------------------------------------------------
    // 2. 按轮转选择三行数据，寄存一拍对齐到"第 c-1 列"
    // ---------------------------------------------------------------------
    reg [DWIDTH-1:0] w_cur_q, w_prev_q, w_prev2_q;
    always @(*) begin
        case (r_sel)
        2'd0:    w_cur_q   = r_q0;
        2'd1:    w_cur_q   = r_q1;
        default: w_cur_q   = r_q2;
        endcase

        case (w_sel_prev)
        2'd0:    w_prev_q  = r_q0;
        2'd1:    w_prev_q  = r_q1;
        default: w_prev_q  = r_q2;
        endcase

        case (w_sel_prev2)
        2'd0:    w_prev2_q = r_q0;
        2'd1:    w_prev2_q = r_q1;
        default: w_prev2_q = r_q2;
        endcase
    end

    reg [DWIDTH-1:0] r_cur1, r_prev1, r_prev2_1;
    reg [DWIDTH-1:0] r_in_d1, r_in_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cur1    <= {DWIDTH{1'b0}};
            r_prev1   <= {DWIDTH{1'b0}};
            r_prev2_1 <= {DWIDTH{1'b0}};
            r_in_d1   <= {DWIDTH{1'b0}};
            r_in_d2   <= {DWIDTH{1'b0}};
        end
        else begin
            r_cur1    <= w_cur_q;
            r_prev1   <= w_prev_q;
            r_prev2_1 <= w_prev2_q;
            r_in_d1   <= w_wr_en ? I_pix_data : r_in_d1;
            r_in_d2   <= r_in_d1;
        end
    end

    // ---------------------------------------------------------------------
    // 3. 列号 / 有效 / 行末 对齐（tap 1 拍 + 列移位 1 拍 = 2 拍）
    // ---------------------------------------------------------------------
    reg [AWIDTH-1:0] r_col_d1, r_col_d2;
    reg              r_pv1, r_pv2;
    reg              r_le_d1, r_le_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_col_d1 <= {AWIDTH{1'b0}};
            r_col_d2 <= {AWIDTH{1'b0}};
            r_pv1    <= 1'b0;
            r_pv2    <= 1'b0;
            r_le_d1  <= 1'b0;
            r_le_d2  <= 1'b0;
        end
        else begin
            r_pv1    <= w_wr_en;
            r_pv2    <= r_pv1;
            r_col_d1 <= r_waddr;
            r_col_d2 <= r_col_d1;
            r_le_d1  <= I_line_end;
            r_le_d2  <= r_le_d1;
        end
    end

    // ---------------------------------------------------------------------
    // 4. 列方向移位：补齐窗口左两列
    // ---------------------------------------------------------------------
    reg [DWIDTH-1:0] r_a0, r_a1;    // 上上行左两列
    reg [DWIDTH-1:0] r_b0, r_b1;    // 上一行左两列
    reg [DWIDTH-1:0] r_c0, r_c1;    // 当前行左两列

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_a0 <= {DWIDTH{1'b0}}; r_a1 <= {DWIDTH{1'b0}};
            r_b0 <= {DWIDTH{1'b0}}; r_b1 <= {DWIDTH{1'b0}};
            r_c0 <= {DWIDTH{1'b0}}; r_c1 <= {DWIDTH{1'b0}};
        end
        else if (w_wr_en) begin
            // 注意：这里**不**在行末清零。窗口需要跨行读取（上一行末尾+下一行开头），
            // 清零会把每行最后两个窗口的左侧数据抹掉；行首前几列由 O_win_valid
            // 门控判定为无效，因此残留数据不会影响输出。
            r_a0 <= r_a1; r_a1 <= r_prev2_1;
            r_b0 <= r_b1; r_b1 <= r_prev1;
            r_c0 <= r_c1; r_c1 <= r_cur1;
        end
    end

    // ---------------------------------------------------------------------
    // 5. 输出级
    // ---------------------------------------------------------------------
    // 窗口中心列 = 当前列 - 2；中心行 = 当前行 - 1
    wire [AWIDTH-1:0] w_center_col = (r_col_d2 >= 2) ? (r_col_d2 - 2'd2) : {AWIDTH{1'b0}};
    wire [15:0]       w_center_row = (r_row >= 1) ? (r_row - 1'b1) : 16'd0;
    // 有效条件：中心列 >= 2（左边有两列）且中心行 >= 1（上面有一行）
    wire w_win_ok = r_pv2 && (r_col_d2 >= 4) && (r_row >= 1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_x00 <= {DWIDTH{1'b0}}; O_x01 <= {DWIDTH{1'b0}}; O_x02 <= {DWIDTH{1'b0}};
            O_x10 <= {DWIDTH{1'b0}}; O_x11 <= {DWIDTH{1'b0}}; O_x12 <= {DWIDTH{1'b0}};
            O_x20 <= {DWIDTH{1'b0}}; O_x21 <= {DWIDTH{1'b0}}; O_x22 <= {DWIDTH{1'b0}};
            O_win_valid   <= 1'b0;
            O_col         <= {AWIDTH{1'b0}};
            O_row         <= 16'd0;
            O_pix_valid_d <= 1'b0;
            O_line_end_d  <= 1'b0;
        end
        else begin
            O_x00 <= r_a0; O_x01 <= r_a1; O_x02 <= r_prev2_1;
            O_x10 <= r_b0; O_x11 <= r_b1; O_x12 <= r_prev1;
            O_x20 <= r_c0; O_x21 <= r_c1; O_x22 <= r_cur1;

            O_win_valid   <= w_win_ok;
            O_col         <= w_center_col;
            O_row         <= w_center_row;
            O_pix_valid_d <= r_pv2;
            O_line_end_d  <= r_le_d2;
        end
    end

endmodule

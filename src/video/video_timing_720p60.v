// =============================================================================
// 文件名 : video_timing_720p60.v
// 模块名 : video_timing_720p60
// 功能   : 720p60 视频时序发生器 + 内置测试图案，直接输出 HDMI 发送核所需的
//          AXI-Stream 视频时序（user / valid / last / data / ready）。
//
//          为什么自己产生时序而不是用 uivtc：
//          HDMI 发送核（hdmi_1_4b_transmitter_core_wrapper）内部按 HTOTAL/VTOTAL
//          等参数自行生成同步，只消费 AXI-Stream 像素流，因此这里只需按标准
//          720p60 时序给出"有效像素 + 帧首 user + 行末 last"即可。
//
// ============================ 720p60 时序参数 ============================
//  像素时钟 75MHz（PLL 的 C4）
//  行: H_ACTIVE=1280  H_FRONT=110  H_SYNC=40   H_BACK=220   H_TOTAL=1650
//      顺序 = 有效像素 -> 前肩 -> 同步脉冲 -> 后肩
//  场: V_ACTIVE=720   V_FRONT=5    V_SYNC=5    V_BACK=20    V_TOTAL=750
//  行同步 / 场同步均为负极性（低电平有效），与 VESA 720p60 一致
//
// 说明   : 该模块内部自带测试图案（彩条 / 渐变 / 棋盘），因此**不接摄像头也能出图**，
//          可先验证 HDMI 链路，再接入 MIPI 采集数据。
// =============================================================================
`timescale 1ns / 1ps

module video_timing_720p60 #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FRONT  = 110,
    parameter integer H_SYNC   = 40,
    parameter integer H_BACK   = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FRONT  = 5,
    parameter integer V_SYNC   = 5,
    parameter integer V_BACK   = 20
)(
    input  wire        I_pix_clk,       // 像素时钟 75MHz
    input  wire        I_rst_n,         // 低电平复位
    input  wire [1:0]  I_pattern_sel,   // 0=彩条 1=灰度渐变 2=棋盘格 3=摄像头RAW

    // ---------------- 摄像头数据源（I_pattern_sel==3 时使用） ----------------
    // 数据由跨时钟域 FIFO 提供，本模块只负责在正确的时刻请求像素。
    input  wire [23:0] I_cam_rgb,       // 已转成 RGB888 的摄像头像素
    input  wire        I_cam_active,    // 摄像头当前行已就绪（读侧可请求像素）
    output wire        O_cam_req,       // 像素读取请求（本拍需要 I_cam_rgb 的下一拍数据）
    output wire [11:0] O_cam_col,       // 与 I_cam_rgb **同拍**的列号（供 Bayer 列相位使用）

    // ---------------- AXI-Stream 视频输出（接 HDMI 发送核） ----------------
    output reg         O_axis_user,     // 帧首像素标志
    output reg         O_axis_valid,    // 像素有效
    output reg         O_axis_last,     // 行末像素标志
    output reg  [23:0] O_axis_data,     // RGB888
    input  wire        I_axis_ready,    // 下游准备好

    // ---------------- 供调试/叠加使用的计数与同步 ----------------
    output wire        O_hs,            // 行同步（负极性）
    output wire        O_vs,            // 场同步（负极性）
    output wire        O_de,            // 数据有效
    output wire [11:0] O_x,             // 当前像素列号（0 ~ H_ACTIVE-1，仅 de 有效）
    output wire [11:0] O_y,             // 当前像素行号（0 ~ V_ACTIVE-1，仅 de 有效）
    output reg         O_frame_toggle   // 每帧翻转一次，可用于指示帧率
);

    localparam integer H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;  // 1650
    localparam integer V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;  // 750

    reg [11:0] r_hcnt;      // 行计数 0 ~ H_TOTAL-1
    reg [11:0] r_vcnt;      // 场计数 0 ~ V_TOTAL-1
    reg [11:0] r_x_align;   // 与 AXI-Stream 控制信号同拍的列号
    reg [11:0] r_y_align;   // 与 AXI-Stream 控制信号同拍的行号

    // ---------------------------------------------------------------------
    // 行列计数
    // 行阶段顺序： [0, H_ACTIVE)              = 有效像素
    //              [H_ACTIVE, +H_FRONT)       = 行前肩
    //              [+H_FRONT, +H_SYNC)        = 行同步
    //              [.., H_TOTAL)              = 行后肩
    // ---------------------------------------------------------------------
    // 时序边界常量（用 localparam 明确位宽，避免隐式 wire 推断带来的问题）
    localparam integer HSP = H_ACTIVE + H_FRONT;            // 行同步起点 = 1390
    localparam integer HEP = H_ACTIVE + H_FRONT + H_SYNC;   // 行同步终点 = 1430
    localparam integer VSP = V_ACTIVE + V_FRONT;            // 场同步起点 = 725
    localparam integer VEP = V_ACTIVE + V_FRONT + V_SYNC;   // 场同步终点 = 730

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_hcnt <= 12'd0;
            r_vcnt <= 12'd0;
        end
        else begin
            if (r_hcnt == (H_TOTAL - 1)) begin
                r_hcnt <= 12'd0;
                // 一行结束，场计数推进
                r_vcnt <= (r_vcnt == (V_TOTAL - 1)) ? 12'd0 : (r_vcnt + 1'b1);
            end
            else begin
                r_hcnt <= r_hcnt + 1'b1;
            end
        end
    end

    // 有效区域
    wire w_h_active = (r_hcnt < H_ACTIVE);
    wire w_v_active = (r_vcnt < V_ACTIVE);
    wire w_de       = w_h_active && w_v_active;

    // 同步信号（负极性：在同步区间内为 0）
    // 用整数比较写成显式范围，避免位宽推断差异
    wire w_hs = ~((r_hcnt >= HSP[11:0]) && (r_hcnt < HEP[11:0]));
    wire w_vs = ~((r_vcnt >= VSP[11:0]) && (r_vcnt < VEP[11:0]));

    // 注意：O_de / O_hs / O_vs 与 O_x / O_y 全部打 1 拍输出，
    // 与寄存的 AXI-Stream 控制信号（user/valid/last）严格同拍对齐。
    reg r_de, r_hs, r_vs;
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_de <= 1'b0;
            r_hs <= 1'b1;       // 负极性，空闲为高
            r_vs <= 1'b1;
        end
        else begin
            r_de <= w_de;
            r_hs <= w_hs;
            r_vs <= w_vs;
        end
    end

    // === 临时调试结束 ===

    assign O_hs = r_hs;
    assign O_vs = r_vs;
    assign O_de = r_de;
    assign O_x  = r_x_align;
    assign O_y  = r_y_align;

    // ---------------------------------------------------------------------
    // 测试图案生成
    // ---------------------------------------------------------------------
    // 8 段彩条（白 黄 青 绿 品红 红 蓝 黑），每段宽 H_ACTIVE/8 = 160 像素
    reg [23:0] r_bar_color;
    wire [2:0] w_bar_idx = r_hcnt[10:8];    // 1280/8 = 160 = 2^7，用高 3 位正好 8 段

    always @(*) begin
        case (w_bar_idx)
        3'd0:    r_bar_color = 24'hFFFFFF;  // 白
        3'd1:    r_bar_color = 24'hFFFF00;  // 黄
        3'd2:    r_bar_color = 24'h00FFFF;  // 青
        3'd3:    r_bar_color = 24'h00FF00;  // 绿
        3'd4:    r_bar_color = 24'hFF00FF;  // 品红
        3'd5:    r_bar_color = 24'hFF0000;  // 红
        3'd6:    r_bar_color = 24'h0000FF;  // 蓝
        default: r_bar_color = 24'h000000;  // 黑
        endcase
    end

    // 棋盘格：8x8 像素交替
    wire w_chk = r_hcnt[3] ^ r_vcnt[3];

    // 移动色块：一个 160x120 的方块在画面内水平移动，用于直观确认画面在刷新
    reg [11:0] r_move_x;
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_move_x <= 12'd0;
        end
        else if (r_hcnt == (H_TOTAL - 1) && r_vcnt == (V_TOTAL - 1)) begin
            // 每帧移动 8 个像素，移出右边界后回到左边
            r_move_x <= (r_move_x >= (H_ACTIVE - 160)) ? 12'd0 : (r_move_x + 12'd8);
        end
    end

    wire w_in_block = (r_hcnt >= r_move_x) && (r_hcnt < (r_move_x + 12'd160)) &&
                      (r_vcnt >= 12'd300)   && (r_vcnt < 12'd420);

    // 灰度渐变：横向渐变 + 纵向条纹
    wire [7:0] w_gray = r_hcnt[9:2];        // 0~255 横向渐变
    wire [7:0] w_gray_v = r_vcnt[8:1];

    // ---------------------------------------------------------------------
    // 摄像头像素读取请求
    //   w_de（未打拍）与 r_hcnt 同拍，表示"本拍正在画第 r_hcnt 列"。
    //   摄像头像素在**下一拍**到达（FIFO 读延迟 1 拍）。
    //   只在 I_cam_active 时请求，避免在摄像头行未就绪时把 FIFO 读空。
    // ---------------------------------------------------------------------
    assign O_cam_req = w_de && (I_pattern_sel == 2'd3) && I_cam_active;

    // 与 I_cam_rgb **同拍**的列号：I_cam_rgb 相对 O_cam_req 晚 1 拍，
    // 因此这里把 r_hcnt 打 1 拍输出，正好与 I_cam_rgb 对齐。
    // （Bayer 列相位必须与实际像素数据同拍，否则颜色相位会错位。）
    reg [11:0] r_cam_col;

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cam_col <= 12'd0;
        end
        else if (O_cam_req) begin
            r_cam_col <= r_hcnt;
        end
    end

    assign O_cam_col = r_cam_col;

    // 摄像头像素第 1 级寄存：FIFO 在 c+1 拍给出第 x 列像素，这里存下来
    reg [23:0] r_cam_d1;

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cam_d1 <= 24'd0;
        end
        else begin
            r_cam_d1 <= I_cam_rgb;
        end
    end

    // ---------------------------------------------------------------------
    // 数据源选择（第 1 级寄存）
    //   图案在 c+1 拍得到第 x 列数据；摄像头 r_cam_d1 同样在 c+1 拍得到第 x 列。
    //   两条路径**延迟一致**，都进入数据源寄存器。
    // ---------------------------------------------------------------------
    reg [23:0] r_axis_data_src;

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_axis_data_src <= 24'd0;
        end
        else begin
            case (I_pattern_sel)
            2'd0: r_axis_data_src <= r_bar_color;                       // 彩条
            2'd1: r_axis_data_src <= {w_gray, w_gray, w_gray};          // 横向灰度渐变
            2'd2: r_axis_data_src <= w_chk ? 24'hFFFFFF : 24'h404040;   // 棋盘格
            2'd3: r_axis_data_src <= r_cam_d1;                          // 摄像头 RAW 直通
            default: begin                                              // 渐变 + 移动块
                if (w_in_block) begin
                    r_axis_data_src <= 24'hFF8000;                      // 橙色方块
                end
                else begin
                    r_axis_data_src <= {w_gray, w_gray_v, w_gray};
                end
            end
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // 控制信号第 1 级寄存（与 r_axis_data_src 同拍）
    //
    // 为什么加 I_cam_active 门控：
    //   摄像头行缓存可能尚未就绪（还没有完整的一行）。此时若仍然拉高
    //   O_axis_valid，HDMI 会收到"有效但无数据"的像素，画面出现杂色/撕裂。
    //   因此**图案模式与摄像头模式统一**在 valid 上叠加 I_cam_active：
    //     I_pattern_sel != 3 时 I_cam_active 由顶层恒置 1 → 图案不受影响；
    //     I_pattern_sel == 3 时只有摄像头行就绪才输出有效像素。
    // ---------------------------------------------------------------------
    wire w_cam_gate = (I_pattern_sel == 2'd3) ? I_cam_active : 1'b1;

    reg r_valid_d1, r_user_d1, r_last_d1;

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_valid_d1 <= 1'b0;
            r_user_d1  <= 1'b0;
            r_last_d1  <= 1'b0;
        end
        else begin
            r_valid_d1 <= w_de && w_cam_gate;
            r_user_d1  <= w_de && w_cam_gate && (r_vcnt == 12'd0) && (r_hcnt == 12'd0);
            r_last_d1  <= w_de && w_cam_gate && (r_hcnt == (H_ACTIVE - 1));
        end
    end

    // ---------------------------------------------------------------------
    // 第 2 级寄存：数据与控制**同拍**输出，保证严格对齐
    // ---------------------------------------------------------------------
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_axis_data  <= 24'd0;
            O_axis_valid <= 1'b0;
            O_axis_user  <= 1'b0;
            O_axis_last  <= 1'b0;
        end
        else begin
            O_axis_data  <= r_axis_data_src;
            O_axis_valid <= r_valid_d1;
            O_axis_user  <= r_user_d1;
            O_axis_last  <= r_last_d1;
        end
    end

    // 与 AXI-Stream 控制信号同拍的行列号（打 2 拍对齐，与数据/控制流水一致），
    // 供下游做坐标相关处理。
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_x_align <= 12'd0;
            r_y_align <= 12'd0;
        end
        else begin
            r_x_align <= r_hcnt;
            r_y_align <= r_vcnt;
        end
    end

    // 帧指示：每帧结束翻转
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_frame_toggle <= 1'b0;
        end
        else if (r_hcnt == (H_TOTAL - 1) && r_vcnt == (V_TOTAL - 1)) begin
            O_frame_toggle <= ~O_frame_toggle;
        end
    end

endmodule

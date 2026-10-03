// =============================================================================
// 文件名 : system_top.v
// 模块名 : system_top
// 功能   : Anlu2 工程顶层 —— SC520CS 摄像头 MIPI 采集 + HDMI 720p60 视频输出。
//
// ============================== 硬件与配置 ==============================
//   开发板   : 安路 PH1P35A（器件 PH1P35MDG324，speed -3）
//   系统时钟 : 50MHz @ C4
//   复位     : R10（低电平有效）
//   摄像头   : SC520CS，MIPI CSI-2，2 Lane，RAW10，828Mbps/Lane，
//              I2C 地址 0x6C，芯片 ID 0xEE4B / 0x9E4B（寄存器 0x3107/0x3108）
//              24MHz MCLK 输出，上电需 PWDNB 先拉低 >=1ms 再释放并等待 >=5ms
//   显示     : HDMI（TMDS）720p60，像素时钟 75MHz，串行时钟 375MHz
//
// ================================ 时钟树 ================================
//   PLL（50MHz 输入）:
//     clk0_out = 100MHz  -> MIPI D-PHY 的 LP 时钟 I_lp_clk
//     clk1_out = 23.81MHz-> 摄像头 24MHz MCLK、I2C 配置、AE/AG 控制
//     clk4_out = 75MHz   -> HDMI 像素时钟
//     clk5_out = 375MHz  -> HDMI 串行时钟（5 倍像素时钟）
//
// ============================== 数据流 ==================================
//   SC520CS --MIPI 2Lane--> [mipi_dphy_rx] --+--> csi2_rx_unpack --> raw10
//        ^                                    |
//        | I2C 配置(165 条寄存器表)             +--> (留待接入 demosaic/RAW->RGB)
//        |                                         |
//   [uicfgcs520]                                  v
//                                          [视频选择：测试图案 / 摄像头]
//                                                 |
//                                                 v
//                                   [video_timing_720p60] --> AXI-Stream
//                                                 |
//                                                 v
//                          [hdmi_1_4b_transmitter_core] --> [hdmi_phy] --> TMDS
//
// ============================== 设计说明 ================================
//   1) 视频源由 I_use_pattern 选择：默认输出内置测试图案（彩条/渐变/棋盘），
//      即使摄像头未接、I2C 配置失败也能出图，便于先验证 HDMI 链路。
//   2) 摄像头初始化失败（ID 不符/I2C 无应答）不会阻塞系统：uicfgcs520 会给出
//      O_iic_error / O_sensor_id_ok，本模块把它们引到 LED 与调试口。
//   3) MIPI 接收硬核（PH1P_LOGIC_DPHY_MIPI_RX）与 HDMI 发送核均为厂商加密 IP，
//      只能在 TangDynasty 中综合；ModelSim 侧用行为模型替代（见 sim/models）。
// =============================================================================
`timescale 1ns / 1ps

module system_top #(
    // 视频图案：0=彩条 1=灰度渐变 2=棋盘格 3=渐变+移动块
    parameter [1:0] PATTERN_SEL_DEFAULT = 2'd0,
    // 摄像头上电时序（单位：23.81MHz 时钟拍数）
    parameter integer CAM_PWDNB_LOW_CYCLES  = 23810,    // >= 1ms
    parameter integer CAM_I2C_START_CYCLES  = 142857    // 释放后 >= 5ms 再启动 I2C
)(
    // ---------------- 系统 ----------------
    input  wire        I_sys_clk,       // 50MHz 系统时钟 @ C4
    input  wire        I_rst_n,         // 复位，低有效 @ R10

    // ---------------- 按键 ----------------
    input  wire [1:0]  I_button,        // 按键，低有效（N2 / J14）

    // ---------------- 摄像头 ----------------
    output wire        O_cam_scl,       // 摄像头 I2C SCL @ K3
    inout  wire        IO_cam_sda,      // 摄像头 I2C SDA @ J3
    output wire        O_cam_24m,       // 摄像头 24MHz MCLK @ L3
    output wire        O_cam_rst,       // 摄像头 PWDNB/XSHUTDN @ L2

    // ---------------- MIPI CSI 差分对（DPHY0） ----------------
    inout  wire        IO_rx_clk_pad_p, // MIPI 时钟 Lane P @ V15
    inout  wire        IO_rx_clk_pad_n, // MIPI 时钟 Lane N @ U16
    inout  wire [3:0]  IO_rx_data_pad_p,// MIPI 数据 Lane P[3:0] @ V13/V14/V16/V17
    inout  wire [3:0]  IO_rx_data_pad_n,// MIPI 数据 Lane N[3:0] @ U14/U15/U17/U18

    // ---------------- HDMI 输出（TMDS） ----------------
    output wire        O_tmds_ch0_p,    // 数据通道 0（蓝）@ G16
    output wire        O_tmds_ch1_p,    // 数据通道 1（绿）@ F17
    output wire        O_tmds_ch2_p,    // 数据通道 2（红）@ H14
    output wire        O_tmds_clk_p,    // 时钟通道     @ C17

    // ---------------- 调试/指示 ----------------
    output wire [3:0]  O_led            // LED 指示：PLL 锁定/摄像头 ID/配置完成/错误
    // 已移除的端口及原因：
    //   O_uart_txd   —— 串口功能未实装，且知识库未给出 UART 引脚定义，
    //                    保留未约束端口会使 bitgen 因 unconstr_io 中止。
    //   I_use_pattern—— 曾尝试与 I_button[0] 共用引脚 N2，TD 报
    //                    USR-8055 "Pin I_use_pattern is set to the same pad
    //                    with I_button[0]"，不允许两个端口占同一 PAD。
    //                    改为由参数 PATTERN_SEL_DEFAULT 决定图案，
    //                    后续如需按键切换，可改用 I_button 在 RTL 内译码。
);

    // ---------------------------------------------------------------------
    // 1. PLL：产生各路时钟
    // ---------------------------------------------------------------------
    wire w_clk_100m;        // MIPI LP 时钟
    wire w_clk_24m;         // 摄像头 24MHz / I2C / AE
    wire w_clk_pixel;       // HDMI 像素时钟 75MHz
    wire w_clk_serial;      // HDMI 串行时钟 375MHz
    wire w_pll_lock;

    PLL u_pll (
        .refclk   (I_sys_clk),
        .reset    (~I_rst_n),
        .clk0_out (w_clk_100m),
        .clk1_out (w_clk_24m),
        .clk4_out (w_clk_pixel),
        .clk5_out (w_clk_serial),
        .lock     (w_pll_lock)
    );

    // =====================================================================
    // 系统复位策略（上板调试后修正 —— 这是黑屏的根因）
    // =====================================================================
    // 【原先的错误写法】
    //     wire w_rst_n = w_pll_lock;      // 直接用 PLL lock 当全局复位
    //   问题：真实板子上 PLL 锁定瞬间 lock 会有短暂抖动。lock 每掉一次，
    //   就会把 uicfgcs520 / CSI 解包 / 视频时序**全部复位一次**，
    //   表现为：
    //     - LED1(w_sensor_id_ok)反复闪烁（配置状态机被反复清零）
    //     - HDMI 无法稳定输出 → 显示器无信号（黑屏）
    //   注意：PLL 参数、HDMI 核参数与官方工作版本**逐行一致**，
    //   所以问题一直在复位策略，不在参数。
    //
    // 【修正后】把 lock 当作"启动许可"，产生一个**一次性、上电后不再回退**
    //   的复位：
    //     1) lock 必须稳定保持 RST_HOLD 拍（去抖，滤掉锁定瞬间的毛刺）；
    //     2) 满足后 w_rst_n 锁存为 1，**此后无论 lock 再抖都不再复位**。
    //   这样既保证"PLL 未锁定时不放行"，又避免 lock 抖动打断整个设计。
    //   该策略已在诊断工程 sim/diag/video_min_top.v 上板验证通过（出彩条）。
    // =====================================================================
    reg [15:0] r_rst_cnt;
    reg        w_rst_n;

    always @(posedge w_clk_24m or negedge I_rst_n) begin
        if (!I_rst_n) begin
            // 外部复位：立即回到复位态（允许重新初始化）
            r_rst_cnt <= 16'd0;
            w_rst_n   <= 1'b0;
        end
        else if (!w_rst_n) begin
            // 尚未放行：等 lock 稳定保持足够长时间
            if (w_pll_lock) begin
                if (r_rst_cnt == 16'hFFFF) begin
                    w_rst_n <= 1'b1;        // 锁定稳定 → 一次性放行（锁存）
                end
                else begin
                    r_rst_cnt <= r_rst_cnt + 1'b1;
                end
            end
            else begin
                r_rst_cnt <= 16'd0;         // lock 掉了 → 去抖计数重来
            end
        end
        // else: w_rst_n 已为 1 → 保持放行，不再受 lock 抖动影响
    end

    // ---------------------------------------------------------------------
    // 2. 摄像头上电时序与 I2C 配置
    //    官方要求：PWDNB 先拉低 >=1ms，释放后等待 >=5ms 再启动 I2C，
    //    否则 PLL 刚锁定就写寄存器会出现偶发写入失败。
    // ---------------------------------------------------------------------
    reg  [17:0] r_cam_pwr_cnt;
    reg         r_cam_pwdnb;
    reg         r_cam_i2c_ready;

    // 注意：这里原来用 negedge w_pll_lock 作为异步复位，同样会被 lock 抖动打断，
    //       导致 I2C 上电时序反复重来。已改为跟随同步复位 w_rst_n。
    always @(posedge w_clk_24m or negedge w_rst_n) begin
        if (!w_rst_n) begin
            r_cam_pwr_cnt   <= 18'd0;
            r_cam_pwdnb     <= 1'b0;
            r_cam_i2c_ready <= 1'b0;
        end
        else begin
            if (r_cam_pwr_cnt < CAM_I2C_START_CYCLES[17:0]) begin
                r_cam_pwr_cnt <= r_cam_pwr_cnt + 1'b1;
            end
            if (r_cam_pwr_cnt >= CAM_PWDNB_LOW_CYCLES[17:0]) begin
                r_cam_pwdnb <= 1'b1;
            end
            if (r_cam_pwr_cnt >= (CAM_I2C_START_CYCLES[17:0] - 1'b1)) begin
                r_cam_i2c_ready <= 1'b1;
            end
        end
    end

    assign O_cam_rst = r_cam_pwdnb;
    assign O_cam_24m = w_clk_24m;

    // AE/AG：当前使用固定曝光/增益（自动曝光属于图像处理范畴，后续接入）
    wire [15:0] w_ae = 16'd1200;
    wire [15:0] w_ag = 16'd176;      // 176 = 最大模拟增益档（见 SC520GainTbl）

    wire        w_cam_cfg_done;
    wire        w_ae_cfg_done;
    wire [15:0] w_sensor_id;
    wire        w_sensor_id_ok;
    wire        w_iic_error;

    uicfgcs520 #(
        .CLK_DIV (23809524 / 100000 - 1)      // I2C 约 100kHz
    ) u_cam_cfg (
        .I_clk          (w_clk_24m),
        .I_rst_n        (r_cam_i2c_ready),
        .I_ae_req       (1'b0),               // 暂不动态调 AE
        .I_ae           (w_ae),
        .I_ag           (w_ag),
        .O_cam_scl      (O_cam_scl),
        .IO_cam_sda     (IO_cam_sda),
        .O_cfg_done     (w_cam_cfg_done),
        .O_ae_cfg_done  (w_ae_cfg_done),
        .O_sensor_id    (w_sensor_id),
        .O_sensor_id_ok (w_sensor_id_ok),
        .O_iic_error    (w_iic_error)
    );

    // ---------------------------------------------------------------------
    // 3. MIPI D-PHY 接收（2 Lane，828Mbps/Lane）
    // ---------------------------------------------------------------------
    wire        w_csi_rx_clk;
    wire        w_hs_rx_valid;
    wire [15:0] w_hs_rx_data;       // LANE_NUM(2) * BYTE_NUM(1) * 8 = 16 位
    wire [1:0]  w_lane_error;
    wire [3:0]  w_lane_match_error;

    // 说明：这里使用**纯 Verilog-2001 版本**的 MIPI 包装
    // （mipi_dphy_rx_ph1p_wrapper_v2001），而不是官方的
    // mipi_dphy_rx_ph1p_mipiio_wrapper.sv。
    // 原因：官方 .sv 包装使用 SystemVerilog 非压缩数组端口，在 TD 6.2.168116 的
    // open_project 分析阶段会报 HDL-8007 并导致 analyze 失败（已用对照实验确认）。
    // 本工程的 v2001 包装直接例化内层加密模块 byte_aligner / channel_aligner
    // （它们都是普通向量端口），功能等价且可被 TD 6.2 接受。
    // 详见 doc/architecture.md 第 8 节。
    mipi_dphy_rx_ph1p_wrapper_v2001 #(
        .DPHY_RX_LOCATION ("DPHY0"),
        .HS_EQUALIZER     ("3dB"),         // 828Mbps 接收均衡
        .HS_VGA_GAIN      ("8dB"),
        .LANE_NUM         (2),
        .BYTE_NUM         (1)
    ) u_mipi_rx (
        .I_lp_clk              (w_clk_100m),
        .I_rst                 (~w_rst_n),
        .I_clk_lane_in_delay   (6'd0),
        .I_data_lane0_in_delay (6'd0),
        .I_data_lane1_in_delay (6'd0),
        .I_data_lane2_in_delay (6'd0),
        .I_data_lane3_in_delay (6'd0),
        .I_lane_invert         (4'b0000),
        .O_hs_rx_clk           (w_csi_rx_clk),
        .O_hs_rx_valid         (w_hs_rx_valid),
        .O_hs_rx_data          (w_hs_rx_data),
        .O_lp_rx_lane0_p       (),
        .O_lp_rx_lane0_n       (),
        .I_lp_tx_en            (1'b0),
        .I_lp_tx_lane0_p       (1'b0),
        .I_lp_tx_lane0_n       (1'b0),
        .O_lane_match_error    (w_lane_match_error),
        .O_lane_error          (w_lane_error),
        .IO_rx_clk_pad_n       (IO_rx_clk_pad_n),
        .IO_rx_clk_pad_p       (IO_rx_clk_pad_p),
        .IO_rx_data_pad_n      (IO_rx_data_pad_n),
        .IO_rx_data_pad_p      (IO_rx_data_pad_p)
    );

    // ---------------------------------------------------------------------
    // 4. CSI-2 解包（把字节流还原为逐像素 RAW 数据）
    // ---------------------------------------------------------------------
    wire        w_pix_valid;
    wire [11:0] w_pix_data;
    wire        w_frame_start, w_frame_end, w_line_start, w_line_end;
    wire [15:0] w_line_cnt, w_pix_cnt, w_frame_cnt;
    wire        w_csi_err;
    wire [15:0] w_csi_err_cnt;
    wire        w_line_wrap_err;

    csi2_rx_unpack #(
        .CSI_LANES (2),
        .DATA_BITS (10),
        .H_ACTIVE  (1280),
        .PIX_BITS  (12)
    ) u_csi_unpack (
        .I_clk          (w_csi_rx_clk),
        .I_rst_n        (w_rst_n),
        .I_hs_valid     (w_hs_rx_valid),
        .I_hs_data      (w_hs_rx_data),
        .O_pix_valid    (w_pix_valid),
        .O_pix_data     (w_pix_data),
        .O_frame_start  (w_frame_start),
        .O_frame_end    (w_frame_end),
        .O_line_start   (w_line_start),
        .O_line_end     (w_line_end),
        .O_line_cnt     (w_line_cnt),
        .O_pix_cnt      (w_pix_cnt),
        .O_frame_cnt    (w_frame_cnt),
        .O_err_pulse    (w_csi_err),
        .O_err_cnt      (w_csi_err_cnt),
        .O_line_wrap_err(w_line_wrap_err)
    );

    // ---------------------------------------------------------------------
    // 5. 视频时序与图案（75MHz 像素时钟域）-> HDMI 发送核
    // ---------------------------------------------------------------------
    wire        w_axis_user, w_axis_valid, w_axis_last, w_axis_ready;
    wire [23:0] w_axis_data;
    wire        w_frame_toggle;     // 每帧翻转一次，用于 LED 帧心跳指示

    // 视频图案选择：当前由参数 PATTERN_SEL_DEFAULT 固定决定（默认彩条）。
    // 摄像头 RAW 通路接入后，这里改为二选一：
    //   图案源 = 按键译码 / 摄像头数据
    // 见 doc/architecture.md 的数据流说明。
    // 说明：原 I_use_pattern 端口已移除（会与 I_button[0] 争同一 PAD，
    //       TD 报 USR-8055）。如需按键切换图案，用下面的 w_btn_deb 在 RTL 内译码。
    wire [1:0] w_pattern_sel = PATTERN_SEL_DEFAULT;

    // 按键消抖（供后续图案切换 / 调试使用，当前悬空不影响功能）
    wire w_btn_press_unused;
    wire w_btn_level_unused;
    debounce #(
        .CNT_BITS (18)
    ) u_btn0_deb (
        .I_clk         (w_clk_24m),
        .I_rst_n       (w_rst_n),
        .I_key_n       (I_button[0]),
        .O_press_pulse (w_btn_press_unused),
        .O_key_level   (w_btn_level_unused)
    );

    video_timing_720p60 #(
        .H_ACTIVE(1280), .H_FRONT(110), .H_SYNC(40), .H_BACK(220),
        .V_ACTIVE(720),  .V_FRONT(5),   .V_SYNC(5),  .V_BACK(20)
    ) u_video_timing (
        .I_pix_clk      (w_clk_pixel),
        .I_rst_n        (w_rst_n),
        .I_pattern_sel  (w_pattern_sel),
        .O_axis_user    (w_axis_user),
        .O_axis_valid   (w_axis_valid),
        .O_axis_last    (w_axis_last),
        .O_axis_data    (w_axis_data),
        .I_axis_ready   (w_axis_ready),
        .O_hs           (),
        .O_vs           (),
        .O_de           (),
        .O_x            (),
        .O_y            (),
        .O_frame_toggle (w_frame_toggle)
    );

    // HDMI 发送核：内部含 TMDS 编码与 HDMI 1.4b 协议栈（厂商加密 IP）
    wire [9:0] w_ch0_tmds, w_ch1_tmds, w_ch2_tmds, w_clk_tmds;

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("PH1P"),
        // 720p60 VESA 时序参数
        .HTOTAL            (1650),
        .HSA               (40),
        .HFP               (110),
        .HBP               (220),
        .HACTIVE           (1280),
        .VTOTAL            (750),
        .VSA               (5),
        .VFP               (5),
        .VBP               (20),
        .VACTIVE           (720),
        .VIDEO_VIC         (4),
        .VIDEO_TPG         ("Disable"),   // 关内部测试图案，用我们自己的视频源
        .VIDEO_FORMAT      ("RGB"),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (125)
    ) u_hdmi_core (
        .I_pixel_clk        (w_clk_pixel),
        .I_rst              (~w_rst_n),
        .I_edid_read_trig   (1'b0),        // EDID 读取暂不使用
        .O_edid_read_valid  (),
        .O_edid_read_data   (),
        // AXI-Stream 视频输入（帧首 user / 有效 valid / 行末 last）
        .I_axis_s_user      (w_axis_user),
        .I_axis_s_valid     (w_axis_valid),
        .I_axis_s_last      (w_axis_last),
        .I_axis_s_data      (w_axis_data),
        .O_axis_s_ready     (w_axis_ready),
        // 音频（本工程未使用，接常量）
        .I_audio_valid      (1'b0),
        .I_audio_left_data  (24'd0),
        .I_audio_right_data (24'd0),
        .I_acr_valid        (1'b0),
        .I_acr_cts          (20'd0),
        .I_acr_n            (20'd0),
        .O_video_locked     (),
        .O_ddc_scl          (),
        .IO_ddc_sda         (),
        // TMDS 10bit 输出 -> 物理层串化
        .O_ch0_tmds_data    (w_ch0_tmds),
        .O_ch1_tmds_data    (w_ch1_tmds),
        .O_ch2_tmds_data    (w_ch2_tmds),
        .O_clk_tmds_data    (w_clk_tmds)
    );

    hdmi_phy_wrapper #(
        .DEVICE ("PH1P")
    ) u_hdmi_phy (
        .I_pixel_clk        (w_clk_pixel),
        .I_serial_clk       (w_clk_serial),
        .I_rst              (~w_rst_n),
        .I_tmds_channel_0   (w_ch0_tmds),
        .I_tmds_channel_1   (w_ch1_tmds),
        .I_tmds_channel_2   (w_ch2_tmds),
        .I_tmds_channel_clk (w_clk_tmds),
        .O_tmds_ch0_p       (O_tmds_ch0_p),
        .O_tmds_ch1_p       (O_tmds_ch1_p),
        .O_tmds_ch2_p       (O_tmds_ch2_p),
        .O_tmds_clk_p       (O_tmds_clk_p)
    );

    // ---------------------------------------------------------------------
    // 6. 状态指示（LED 高电平点亮）
    //
    // 上板可读性设计（经诊断工程验证的判读方式）：
    //   LED0 = PLL 锁定            → 期望**常亮**
    //   LED1 = 视频帧心跳          → 期望**闪烁**（约 0.7~1Hz，证明视频在跑）
    //   LED2 = 摄像头 ID 识别通过  → 接了摄像头后期望常亮
    //   LED3 = 配置完成 / 错误     → 见下方说明
    //
    // 【为什么 LED1 从"ID 识别"改成"帧心跳"】
    //   原来 LED1 接 w_sensor_id_ok，但它被复位策略影响会闪烁，难以判读。
    //   改成帧心跳后：
    //     * LED1 闪 + LED0 常亮 = PLL 与视频链路都正常（即使没接摄像头）
    //     * 这样"黑屏"就有明确的二分判据：心跳正常则问题在显示侧，
    //       心跳不动则问题在视频时钟/复位。
    // ---------------------------------------------------------------------
    assign O_led[0] = w_pll_lock;       // PLL 锁定（期望常亮）
    assign O_led[1] = w_frame_toggle;   // 视频帧心跳（期望闪烁）
    assign O_led[2] = w_sensor_id_ok;   // 摄像头 ID 识别通过
    // LED3 = 配置完成 或 任一错误（两者用"常亮"表示有进展/有异常）
    assign O_led[3] = w_cam_cfg_done | w_iic_error |
                      (|w_lane_error) | (|w_lane_match_error) | w_csi_err;

endmodule

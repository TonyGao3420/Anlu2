// =============================================================================
// 文件名 : video_min_top.v
// 模块名 : video_min_top
// 功能   : **上板诊断用**最小视频顶层 —— 只含 PLL + 彩条 + HDMI。
//
// ===================== 为什么需要它 =====================
// 上板现象：显示器无信号，且 LED1(摄像头 ID)闪烁 → 推断 uicfgcs520 被反复复位
// → 推断 PLL 锁定信号 w_pll_lock 不稳定。但主设计里同时有 MIPI 硬核与
// 摄像头 I2C 配置，无法区分"是 PLL 本身不稳"还是"被这些模块拖累"。
//
// 本顶层把变量降到最少：
//   * **不含** MIPI D-PHY 硬核（避免 VCCDPHY / 布局布线的干扰）
//   * **不含** 摄像头 I2C 配置（uicfgcs520）
//   * **不含** CSI-2 解包
//   * 保留 PLL + video_timing_720p60(彩条) + HDMI 发送核 + HDMI PHY
//
// ===================== 稳健复位（与主设计的关键差异） =====================
// 主设计：w_rst_n = w_pll_lock 直接做复位 → 一旦 lock 抖动，整个设计反复复位，
//         HDMI 无法稳定输出，且 LED 会乱闪。
// 本设计：I_rst_n 只做**上电复位**（同步释放），PLL 的 lock 仅用于：
//   * LED0 指示（可直接观察 PLL 到底稳不稳）
//   * 与复位做"或"，但不反复拉低（加最小保持时间）
//
// LED 指示（便于逐位判断硬件）：
//   LED0 = PLL lock           （常亮 = 锁定稳定）
//   LED1 = ~lock（反相）      （与 LED0 互补，便于确认不是接线问题）
//   LED2 = 帧心跳             （约 1.1Hz 翻转 = 视频在跑）
//   LED3 = 50MHz 计数高位     （约 1.5Hz 翻转 = 系统时钟在跑）
// =============================================================================
`timescale 1ns / 1ps

module video_min_top #(
    parameter [1:0] PATTERN_SEL = 2'd0     // 0=彩条
)(
    input  wire        I_sys_clk,       // 50MHz @ C4
    input  wire        I_rst_n,         // 复位 @ R10（低有效）
    output wire [3:0]  O_led,           // LED0..3 @ D10/E10/C6/D6

    output wire        O_tmds_ch0_p,    // @ G16
    output wire        O_tmds_ch1_p,    // @ F17
    output wire        O_tmds_ch2_p,    // @ H14
    output wire        O_tmds_clk_p     // @ C17
);

    // ---------------------------------------------------------------------
    // 1. PLL（与主设计完全相同的配置：50M → 100M/23.81M/75M/375M）
    // ---------------------------------------------------------------------
    wire w_clk_100m, w_clk_24m, w_clk_pixel, w_clk_serial, w_pll_lock;

    PLL u_pll (
        .refclk   (I_sys_clk),
        .reset    (~I_rst_n),
        .clk0_out (w_clk_100m),
        .clk1_out (w_clk_24m),
        .clk4_out (w_clk_pixel),
        .clk5_out (w_clk_serial),
        .lock     (w_pll_lock)
    );

    // ---------------------------------------------------------------------
    // 2. 稳健复位：只用外部复位做上电复位，同步释放；不依赖 PLL lock
    //    （这样即使 PLL 有问题，HDMI 链路也能独立工作，便于分离问题）
    // ---------------------------------------------------------------------
    reg [7:0] r_rst_cnt;
    reg       r_rst_n;

    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_rst_cnt <= 8'd0;
            r_rst_n   <= 1'b0;
        end
        else if (r_rst_cnt != 8'hFF) begin
            r_rst_cnt <= r_rst_cnt + 1'b1;
            r_rst_n   <= 1'b0;
        end
        else begin
            r_rst_n <= 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // 3. 视频时序 + 内置彩条 → AXI-Stream
    // ---------------------------------------------------------------------
    wire        w_axis_user, w_axis_valid, w_axis_last, w_axis_ready;
    wire [23:0] w_axis_data;
    wire        w_frame_toggle;

    video_timing_720p60 #(
        .H_ACTIVE(1280), .H_FRONT(110), .H_SYNC(40), .H_BACK(220),
        .V_ACTIVE(720),  .V_FRONT(5),   .V_SYNC(5),  .V_BACK(20)
    ) u_video_timing (
        .I_pix_clk      (w_clk_pixel),
        .I_rst_n        (r_rst_n),
        .I_pattern_sel  (PATTERN_SEL),
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

    // ---------------------------------------------------------------------
    // 4. HDMI 发送核（参数与官方工作版本完全一致）
    //    注意：AXI-Stream 信号按官方做法再打 2 拍后送入
    // ---------------------------------------------------------------------
    reg        r_user_d1, r_user_d2;
    reg        r_valid_d1, r_valid_d2;
    reg        r_last_d1, r_last_d2;
    reg [23:0] r_data_d1, r_data_d2;

    always @(posedge w_clk_pixel or negedge r_rst_n) begin
        if (!r_rst_n) begin
            r_user_d1  <= 1'b0; r_user_d2  <= 1'b0;
            r_valid_d1 <= 1'b0; r_valid_d2 <= 1'b0;
            r_last_d1  <= 1'b0; r_last_d2  <= 1'b0;
            r_data_d1  <= 24'd0; r_data_d2 <= 24'd0;
        end
        else begin
            r_user_d1  <= w_axis_user;  r_user_d2  <= r_user_d1;
            r_valid_d1 <= w_axis_valid; r_valid_d2 <= r_valid_d1;
            r_last_d1  <= w_axis_last;  r_last_d2  <= r_last_d1;
            r_data_d1  <= w_axis_data;  r_data_d2  <= r_data_d1;
        end
    end

    wire [9:0] w_ch0_tmds, w_ch1_tmds, w_ch2_tmds, w_clk_tmds;

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("PH1P"),
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
        .VIDEO_TPG         ("Disable"),
        .VIDEO_FORMAT      ("RGB"),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (125)
    ) u_hdmi_core (
        .I_pixel_clk        (w_clk_pixel),
        .I_rst              (~r_rst_n),
        .I_edid_read_trig   (1'b0),
        .O_edid_read_valid  (),
        .O_edid_read_data   (),
        .I_axis_s_user      (r_user_d2),
        .I_axis_s_valid     (r_valid_d2),
        .I_axis_s_last      (r_last_d2),
        .I_axis_s_data      (r_data_d2),
        .O_axis_s_ready     (w_axis_ready),
        .I_audio_valid      (1'b0),
        .I_audio_left_data  (24'd0),
        .I_audio_right_data (24'd0),
        .I_acr_valid        (1'b0),
        .I_acr_cts          (20'd0),
        .I_acr_n            (20'd0),
        .O_video_locked     (),
        .O_ddc_scl          (),
        .IO_ddc_sda         (),
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
        .I_rst              (~r_rst_n),
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
    // 5. LED 指示（4 个位各自独立，便于逐位判断）
    // ---------------------------------------------------------------------
    reg [23:0] r_heartbeat;

    always @(posedge w_clk_pixel or negedge r_rst_n) begin
        if (!r_rst_n) begin
            r_heartbeat <= 24'd0;
        end
        else begin
            r_heartbeat <= r_heartbeat + 1'b1;
        end
    end

    assign O_led[0] = w_pll_lock;               // PLL 锁定（期望常亮）
    assign O_led[1] = ~w_pll_lock;              // 与 LED0 互补（便于确认接线/极性）
    assign O_led[2] = r_heartbeat[23];          // 视频时钟域心跳
    assign O_led[3] = r_rst_cnt[6];             // 系统时钟在跑（复位后即翻转）

endmodule

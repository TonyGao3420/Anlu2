// Anlu2 源码说明：板级顶层：连接 SC520 配置、两路 MIPI 接收、ISP、DDR2 四帧缓存、OSD 和 HDMI 输出。
// 接口与使用约定：50 MHz板钟输入；显示端沿用官方mixer通路，ROI检测器只读观察DDR输出RGB并提供框坐标。
// 工程状态：已列入TD编译清单。

// ================================================================
// design_top_wrapper.v
// ---------------------------------------------------------------
// Official SC520 Lab3 video-chain top module.
// Layer 1: camera + MIPI + ISP + DDR + HDMI main path
// Layer 2: Track2 extension for target detection and bbox overlay
// ================================================================

module design_top_wrapper #(parameter integer CAMERA_ROTATE_180=1) (
    input wire I_sys_clk,
    input wire I_rst_n,
    input wire I_sw2,          // SW2: 1=style + one-second trail; SW1 still controls servo.
    input wire I_sw1,          // SW1：视觉伺服使能，1=开启，0=保持当前位置

    output wire O_cam_scl,
    inout  wire IO_cam_sda,
    output wire O_cam_24m,
    output wire O_cam_rst,

    inout wire [1:0] I_button,

    output wire O_screen_pwm,
    output wire O_servo_pan,
    output wire O_servo_tilt,
    output wire O_tmds_ch0_p,
    output wire O_tmds_ch1_p,
    output wire O_tmds_ch2_p,
    output wire O_tmds_clk_p,

    inout wire       IO_rx_clk_pad_n,
    inout wire       IO_rx_clk_pad_p,
    inout wire [3:0] IO_rx_data_pad_n,
    inout wire [3:0] IO_rx_data_pad_p,

    output wire [12:0] ddr_addr,
    output wire [ 1:0] ddr_ba,
    output wire [ 0:0] ddr_cke,
    output wire [ 0:0] ddr_odt,
    output wire [ 0:0] ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [ 0:0] ddr_ck_p,
    output wire [ 0:0] ddr_ck_n,
    inout  wire [ 1:0] ddr_dm,
    inout  wire [15:0] ddr_dq,
    inout  wire [ 1:0] ddr_dqs_p,
    inout  wire [ 1:0] ddr_dqs_n
);


    wire        S_100m_clk;
    wire        S_24m_clk;
    wire        S_aux_50m_clk;
    wire        S_10m_clk;

    wire        S_pll_lock;
    wire        S_rst_n;
    reg  [17:0] S_cam_power_cnt;
    reg         S_cam_pwdnb;
    reg         S_cam_i2c_ready;
    (* keep = "true" *)wire [15:0] S_cam_sensor_id;
    (* keep = "true" *)wire        S_cam_sensor_id_ok;
    (* keep = "true" *)wire        S_cam_i2c_error;
    localparam integer CAM_PWDNB_LOW_CYCLES = 23810;   // >= 1 ms at 23.809524 MHz
    localparam integer CAM_I2C_START_CYCLES = 142857;  // release + >= 5 ms

    wire [ 15:0] S_ae;
    wire [ 15:0] S_ag;
    wire         S_cam_cfg_done;
    wire         S_ae_cfg_done;
    wire         S_ae_req;

    wire         S_csi_rx_clk;
    wire         S_hs_rx_valid;
    wire [ 15:0] S_hs_rx_data;
    wire [  1:0] S_lane_error;

    wire         S_csi_frame_start;
    wire         S_csi_frame_end;
    wire         S_csi_valid;
    wire [ 31:0] S_csi_data;

    wire         S_raw10_frame_start;
    wire         S_raw10_frame_end;
    wire         S_raw10_valid;
    wire [ 39:0] S_raw10_data;

    wire         S_axis_tlast;
    wire         S_axis_tuser;
    wire [ 39:0] S_axis_tdata;
    wire         S_axis_tvalid;

    wire [ 39:0] S_raw_tdata;
    wire         S_raw_tlast;
    wire         S_raw_tvalid;
    wire         S_raw_tuser;

    wire         S_ISP_O_tready;
    wire [127:0] S_ISP_O_tdata;
    wire         S_ISP_O_tlast;
    wire         S_ISP_O_tuser;
    wire         S_ISP_O_tvalid;


    wire         S_ddr_clk;
    wire         S_hdmi_pixel_clk;
    wire         S_hdmi_serial_clk;
    wire         S_hdmi_rst_n;
    wire         S_video_out_rst_n;


    wire         S_vi_128b_frame_start;
    wire         S_vi_128b_valid;
    wire [127:0] S_vi_128b_data;

    wire         S_video_out_rd_busy;
    wire         S_video_in_wr_busy;
    wire [  1:0] S_video_out_rp;

    wire         S_ddr_user_wr_en;
    wire         S_ddr_user_rd_en;
    wire [ 24:0] S_ddr_user_addr;
    wire [127:0] S_ddr_user_wr_data;
    wire         S_ddr_user_ready;
    wire         S_ddr_user_rd_valid;
    wire [127:0] S_ddr_user_rd_data;

    wire         S_vi_ddr_wr_en;
    wire [ 24:0] S_vi_ddr_wr_addr;
    wire [127:0] S_vi_ddr_wr_data;
    wire         S_vi_ddr_wr_ready;

    wire         S_vo_ddr_rd_en;
    wire [ 24:0] S_vo_ddr_rd_addr;
    wire         S_vo_ddr_rd_ready;
    wire         S_vo_dbg_fifo_rst;
    wire         S_vo_dbg_ddr_rd_valid;
    wire         S_vo_dbg_fifo_rd_en;
    wire         S_vo_dbg_fifo_empty;

    wire         S_init_calib_complete;
    wire [ 24:0] S_mc_app_addr;
    wire [  2:0] S_mc_app_cmd;
    wire         S_mc_app_en;
    wire [127:0] S_mc_app_wdf_data;
    wire         S_mc_app_wdf_end;
    wire [ 15:0] S_mc_app_wdf_mask;
    wire         S_mc_app_wdf_wren;
    wire [127:0] S_mc_app_rd_data;
    wire         S_mc_app_rd_data_end;
    wire         S_mc_app_rd_data_valid;
    wire         S_mc_app_rdy;
    wire         S_mc_app_wdf_rdy;
    wire         S_mc_dbg_fifo_afull;
    wire         S_mc_dbg_app_rdy;
    wire         S_mc_dbg_wdf_rdy;
    wire         S_mc_dbg_cmd_pop;

    wire         S_hdmi_vsync;
    wire         S_hdmi_hsync;
    wire         S_hdmi_de;
    wire         S_hdmi_user;
    wire         S_hdmi_last;
    wire         S_video_out_vsync;
    wire         S_hdmi_window_rd_en;
    wire         S_hdmi_out_vsync;
    wire         S_hdmi_out_hsync;
    wire         S_hdmi_out_de;
    wire [ 23:0] S_hdmi_out_data;
    wire [ 11:0] S_hdmi_out_x;
    wire [ 11:0] S_hdmi_out_y;
    wire         S_hdmi_out_protect;
    wire         S_hdmi_enhanced_vsync;
    wire         S_hdmi_enhanced_hsync;
    wire         S_hdmi_enhanced_de;
    wire [ 23:0] S_hdmi_enhanced_data;

    wire [ 23:0] S_video_rd_data;
    wire         S_track2_valid;
    wire [ 15:0] S_track2_cx;
    wire [ 15:0] S_track2_cy;
    wire [ 19:0] S_track2_area;
    wire         S_track2_frame_done;
    wire         S_track2_result_update;
    wire [15:0]   S_track2_bbox_x0;
    wire [15:0]   S_track2_bbox_y0;
    wire [15:0]   S_track2_bbox_x1;
    wire [15:0]   S_track2_bbox_y1;
    wire         S_track2_dbg_roi_valid;
    wire         S_track2_dbg_color_match;
    reg          S_track2_result_toggle;

    // SW1 使能：异步开关在 HDMI 像素时钟域做 2 级同步
    reg  [1:0]   S_sw1_sync;
    reg          S_sw1_seen;
    wire         S_sw1_enable = S_sw1_sync[1];
    wire         S_sw1_change = S_sw1_sync[1] ^ S_sw1_seen;
    wire         S_servo_valid = S_track2_valid & S_sw1_enable;

    reg          S_dbg_raw_seen;
    reg          S_dbg_isp_seen;
    reg          S_dbg_ddr_wr_seen;
    reg          S_dbg_ddr_rd_seen;
    reg          S_dbg_cam_cfg_seen;
    reg          S_dbg_hs_seen;
    reg          S_dbg_csi_seen;
    reg          S_dbg_raw10_seen;
    reg          S_dbg_isp_fs_seen;
    reg          S_dbg_isp_valid_seen;
    reg          S_dbg_ddr_req_seen;
    reg          S_dbg_ddr_ready_seen;
    reg  [  1:0] S_dbg_raw_seen_sync;
    reg  [  1:0] S_dbg_isp_seen_sync;
    reg  [  1:0] S_dbg_ddr_wr_seen_sync;
    reg  [  1:0] S_dbg_ddr_rd_seen_sync;
    reg  [  1:0] S_dbg_cam_cfg_seen_sync;
    reg  [  1:0] S_dbg_hs_seen_sync;
    reg  [  1:0] S_dbg_csi_seen_sync;
    reg  [  1:0] S_dbg_raw10_seen_sync;
    reg  [  1:0] S_dbg_isp_fs_seen_sync;
    reg  [  1:0] S_dbg_isp_valid_seen_sync;
    reg  [  1:0] S_dbg_ddr_req_seen_sync;
    reg  [  1:0] S_dbg_ddr_ready_seen_sync;
    reg          S_dbg_video_nonzero_seen;
    reg          S_dbg_rd_req_seen;
    reg          S_dbg_rd_valid_seen;
    reg          S_dbg_rd_nonzero_seen;
    reg  [  1:0] S_dbg_rd_req_seen_sync;
    reg  [  1:0] S_dbg_rd_valid_seen_sync;
    reg  [  1:0] S_dbg_rd_nonzero_seen_sync;
    reg          S_dbg_mc_init_seen;
    reg          S_dbg_mc_app_rdy_seen;
    reg          S_dbg_mc_wdf_rdy_seen;
    reg          S_dbg_mc_cmd_pop_seen;
    reg  [  1:0] S_dbg_mc_init_seen_sync;
    reg  [  1:0] S_dbg_mc_app_rdy_seen_sync;
    reg  [  1:0] S_dbg_mc_wdf_rdy_seen_sync;
    reg  [  1:0] S_dbg_mc_cmd_pop_seen_sync;
    wire [  3:0] S_hdmi_debug_status;
    wire         S_lane_error_any;


    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;


    assign S_rst_n = S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_raw_seen <= 1'b0;
        else if (S_raw10_frame_start | S_axis_tvalid) S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_isp_seen <= 1'b0;
        else if (S_ISP_O_tuser | S_ISP_O_tvalid) S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_ddr_wr_seen <= 1'b0;
        else if (S_vi_ddr_wr_en) S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_ddr_rd_seen <= 1'b0;
        else if (S_ddr_user_rd_valid) S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_cam_cfg_seen <= 1'b0;
        else if (S_cam_cfg_done) S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_hs_seen <= 1'b0;
        else if (S_hs_rx_valid) S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_csi_seen <= 1'b0;
        else if (S_csi_frame_start | S_csi_valid) S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_raw10_seen <= 1'b0;
        else if (S_raw10_frame_start | S_raw10_valid) S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_isp_fs_seen <= 1'b0;
        else if (S_ISP_O_tuser) S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_isp_valid_seen <= 1'b0;
        else if (S_ISP_O_tvalid) S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_ddr_req_seen <= 1'b0;
        else if (S_vi_ddr_wr_en) S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_ddr_ready_seen <= 1'b0;
        else if (S_ddr_user_ready) S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if (!S_video_out_rst_n) S_dbg_rd_req_seen <= 1'b0;
        else if (S_video_out_vsync) S_dbg_rd_req_seen <= 1'b0;
        else if (S_vo_ddr_rd_en) S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if (!S_video_out_rst_n) S_dbg_rd_valid_seen <= 1'b0;
        else if (S_video_out_vsync) S_dbg_rd_valid_seen <= 1'b0;
        else if (S_ddr_user_rd_valid) S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if (!S_video_out_rst_n) S_dbg_rd_nonzero_seen <= 1'b0;
        else if (S_video_out_vsync) S_dbg_rd_nonzero_seen <= 1'b0;
        else if (S_hdmi_window_rd_en && (S_video_rd_data != 24'd0)) S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_mc_init_seen <= 1'b0;
        else if (S_init_calib_complete) S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_mc_app_rdy_seen <= 1'b0;
        else if (S_mc_dbg_app_rdy) S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if (S_mc_dbg_wdf_rdy) S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if (S_mc_dbg_cmd_pop) S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync    <= 2'b00;
            S_dbg_hs_seen_sync         <= 2'b00;
            S_dbg_csi_seen_sync        <= 2'b00;
            S_dbg_raw10_seen_sync      <= 2'b00;
            S_dbg_raw_seen_sync        <= 2'b00;
            S_dbg_isp_seen_sync        <= 2'b00;
            S_dbg_ddr_wr_seen_sync     <= 2'b00;
            S_dbg_ddr_rd_seen_sync     <= 2'b00;
            S_dbg_isp_fs_seen_sync     <= 2'b00;
            S_dbg_isp_valid_seen_sync  <= 2'b00;
            S_dbg_ddr_req_seen_sync    <= 2'b00;
            S_dbg_ddr_ready_seen_sync  <= 2'b00;
            S_dbg_video_nonzero_seen   <= 1'b0;
            S_dbg_rd_req_seen_sync     <= 2'b00;
            S_dbg_rd_valid_seen_sync   <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync    <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end else begin
            S_dbg_cam_cfg_seen_sync    <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync         <= {S_dbg_hs_seen_sync[0], S_dbg_hs_seen};
            S_dbg_csi_seen_sync        <= {S_dbg_csi_seen_sync[0], S_dbg_csi_seen};
            S_dbg_raw10_seen_sync      <= {S_dbg_raw10_seen_sync[0], S_dbg_raw10_seen};
            S_dbg_raw_seen_sync        <= {S_dbg_raw_seen_sync[0], S_dbg_raw_seen};
            S_dbg_isp_seen_sync        <= {S_dbg_isp_seen_sync[0], S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync     <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync     <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync     <= {S_dbg_isp_fs_seen_sync[0], S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync  <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync    <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync  <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync     <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync   <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync    <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if (S_hdmi_window_rd_en && (S_video_rd_data != 24'd0)) S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data), S_ddr_user_rd_valid, S_vo_ddr_rd_en, S_vi_ddr_wr_en
    };

    // SC520CS上电后先保持PWDNB/XSHUTDN为低，再释放并等待内部上电完成，
    // 避免PLL刚锁定就开始I2C初始化而造成寄存器偶发写入失败。
    always @(posedge S_24m_clk or negedge S_pll_lock) begin
        if (!S_pll_lock) begin
            S_cam_power_cnt <= 18'd0;
            S_cam_pwdnb <= 1'b0;
            S_cam_i2c_ready <= 1'b0;
        end else begin
            if (S_cam_power_cnt < CAM_I2C_START_CYCLES) S_cam_power_cnt <= S_cam_power_cnt + 1'b1;
            if (S_cam_power_cnt >= CAM_PWDNB_LOW_CYCLES) S_cam_pwdnb <= 1'b1;
            if (S_cam_power_cnt >= CAM_I2C_START_CYCLES - 1) S_cam_i2c_ready <= 1'b1;
        end
    end

    assign O_cam_rst = S_cam_pwdnb;
    assign O_cam_24m = S_24m_clk;




    PLL u_PLL (
        .refclk(I_sys_clk),
        .reset (~I_rst_n),

        .clk0_out(S_100m_clk),
        .clk1_out(S_24m_clk),

        .clk4_out(S_hdmi_pixel_clk),
        .clk5_out(S_hdmi_serial_clk),

        .lock(S_pll_lock)

    );





    ae_set u_ae_set (
        .I_clk(S_24m_clk),
        .I_rst(~S_rst_n),
        .I_btn({I_button, 2'b11}),
        .I_cam_cfg_done(S_cam_cfg_done),
        .I_ae_cfg_done(S_ae_cfg_done),
        .O_ae_req(S_ae_req),
        .O_ae(S_ae),
        .O_ag(S_ag)
    );

    // SC520CS原厂真实HD模式：1280x720@60、RAW10、2-Lane、828 Mbps/Lane。
    // 当前寄存器表已关闭Slave/FSIN等待，Sensor以free-run方式连续输出。
    uicfgcs520 #(
        .CLK_DIV(23809524 / 100000 - 1)
    ) u_uicfgcs520 (
        .I_clk(S_24m_clk),  //系统时钟输入
        .I_rst_n(S_cam_i2c_ready),  // SC520CS power-up delay completed
        .I_ae_req(S_ae_req),
        .I_ae(S_ae),
        .I_ag(S_ag),
        .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
        .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
        .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
        .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
        .O_sensor_id(S_cam_sensor_id),
        .O_sensor_id_ok(S_cam_sensor_id_ok),
        .O_iic_error(S_cam_i2c_error)
    );

    mipi_dphy_rx_ph1p_mipiio_wrapper #(
        .DPHY_RX_LOCATION("DPHY0"),
        .HS_EQUALIZER    ("3dB"),    // 828 Mbps/Lane接收均衡
        .HS_VGA_GAIN     ("8dB"),    //"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM        (2),
        .BYTE_NUM        (1)
    ) u_mipi_dphy_rx_ph1p_mipiio_wrapper (
        .I_lp_clk(S_100m_clk),
        .I_rst   (~S_rst_n),

        .I_clk_lane_in_delay  (6'd0),
        .I_data_lane0_in_delay(6'd0),
        .I_data_lane1_in_delay(6'd0),
        .I_data_lane2_in_delay(6'd0),
        .I_data_lane3_in_delay(6'd0),

        .I_lane_invert(4'b0000),

        .O_hs_rx_clk  (S_csi_rx_clk),
        .O_hs_rx_valid(S_hs_rx_valid),
        .O_hs_rx_data (S_hs_rx_data),

        .O_lp_rx_lane0_p(),
        .O_lp_rx_lane0_n(),

        .I_lp_tx_en     (1'b0),
        .I_lp_tx_lane0_p(1'b1),
        .I_lp_tx_lane0_n(1'b1),

        .O_lane_match_error(),
        .O_lane_error      (S_lane_error),

        .IO_rx_clk_pad_n (IO_rx_clk_pad_n),
        .IO_rx_clk_pad_p (IO_rx_clk_pad_p),
        .IO_rx_data_pad_n(IO_rx_data_pad_n),
        .IO_rx_data_pad_p(IO_rx_data_pad_p)
    );


    //  cwc cwc_inst
    //(
    //    .probe0(S_hs_rx_valid),
    //    .probe1(S_hs_rx_data),
    //    .probe2(S_lane_error),
    //    .clk(S_csi_rx_clk)
    //);

    //csi 解码为RAW数据
    csi_unpacket_2lane u_csi_unpacket (
        .I_clk     (S_csi_rx_clk),
        .I_rst_n   (S_rst_n),
        .I_hs_valid(S_hs_rx_valid),
        .I_hs_data (S_hs_rx_data),

        .O_csi_frame_start(S_csi_frame_start),
        .O_csi_frame_end  (S_csi_frame_end),
        .O_csi_valid      (S_csi_valid),
        .O_csi_data       (S_csi_data)
    );


    //解码为RAW8
    raw10_unpacket_2lane u_raw10_unpacket (
        .I_clk  (S_csi_rx_clk),
        .I_rst_n(S_rst_n),

        .I_csi_frame_start(S_csi_frame_start),
        .I_csi_frame_end  (S_csi_frame_end),
        .I_csi_valid      (S_csi_valid),
        .I_csi_data       (S_csi_data),

        .O_raw10_frame_start(S_raw10_frame_start),
        .O_raw10_frame_end  (S_raw10_frame_end),
        .O_raw10_valid      (S_raw10_valid),
        .O_raw10_data       (S_raw10_data)
    );


    //将数据转为stream流
    uial2axis #(
        .IMG_WIDTH(1280),
        .IMG_HEIGHT(720),
        .INPUT_DATA_WIDTH(40)
    ) u_uial2axis (
        .I_native_clk(S_csi_rx_clk),
        .I_rst_n     (S_rst_n),
        .I_data      (S_raw10_data),
        .I_data_valid(S_raw10_valid),
        .I_data_start(S_raw10_frame_start),
        .I_data_end  (S_raw10_frame_end),
        .axis_tvalid (S_axis_tvalid),
        .axis_tdata  (S_axis_tdata),
        .axis_tuser  (S_axis_tuser),
        .axis_tlast  (S_axis_tlast)
    );


    // 原厂HD模式直接输出1280x720 RAW10，不再进行FPGA固定窗口裁剪。
    assign S_raw_tdata  = S_axis_tdata;
    assign S_raw_tlast  = S_axis_tlast;
    assign S_raw_tvalid = S_axis_tvalid;
    assign S_raw_tuser  = S_axis_tuser;


    //cwc1 cwc1_Inst
    //  (
    //      .probe0(S_axis_tuser),
    //      .probe1(S_axis_tvalid),
    //      .probe2(S_axis_tlast),
    //      .probe3(S_axis_tdata),
    //      .probe4(S_ISP_O_tuser),
    //      .probe5(S_ISP_O_tvalid),
    //      .probe6(S_ISP_O_tlast),
    //      .probe7(S_ISP_O_tdata),
    //      .probe8 (S_raw_tdata ),
    //      .probe9 (S_raw_tlast ),
    //      .probe10(S_raw_tvalid),
    //      .probe11(S_raw_tuser ),
    //      .clk(S_csi_rx_clk)
    //  );


    //ISP算法顶层模块
    isp_top u_isp_top (
        .axi4s_video_aclk(S_csi_rx_clk),
        .I_rst_n         (S_rst_n),
        .I_tlast         (S_raw_tlast),
        .I_tuser         (S_raw_tuser),
        .I_tdata         (S_raw_tdata),
        .I_tvalid        (S_raw_tvalid),
        .I_tdest         (10'd0),
        .O_tready        (1'b1),            // 摄像头连续流，ISP不支持反压
        .O_tdata         (S_ISP_O_tdata),
        .O_tlast         (S_ISP_O_tlast),
        .O_tuser         (S_ISP_O_tuser),
        .O_tvalid        (S_ISP_O_tvalid),
        .I_tready        ()
    );


    video_in u_video_in (
        .I_rst_n(S_rst_n),

        .I_camera_clk        (S_csi_rx_clk),
        .I_camera_frame_start(S_ISP_O_tuser),
        .I_camera_valid      (S_ISP_O_tvalid),
        .I_camera_data       (S_ISP_O_tdata),
        .I_mipi_rx_error     (1'b0),

        .I_ddr_clk          (S_ddr_clk),
        .I_display_pause    (1'b0),
        .I_video_out_rd_busy(S_video_out_rd_busy),
        .O_video_in_wr_busy (S_video_in_wr_busy),
        .O_video_out_rp     (S_video_out_rp),

        .O_ddr_user_wr_en  (S_vi_ddr_wr_en),
        .O_ddr_user_addr   (S_vi_ddr_wr_addr),
        .O_ddr_user_wr_data(S_vi_ddr_wr_data),
        .I_ddr_user_ready  (S_ddr_user_ready)
    );



    assign S_ddr_user_wr_en = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out #(.ROTATE_180(CAMERA_ROTATE_180)) u_video_out (
        .I_rst_n  (S_video_out_rst_n),
        .I_ddr_clk(S_ddr_clk),

        .O_video_out_rd_busy(S_video_out_rd_busy),
        .I_video_in_wr_busy (S_video_in_wr_busy),
        .I_video_out_rp     (S_video_out_rp),

        .O_ddr_user_rd_en   (S_vo_ddr_rd_en),
        .O_ddr_user_addr    (S_vo_ddr_rd_addr),
        .I_ddr_user_ready   (S_ddr_user_ready),
        .I_ddr_user_rd_valid(S_ddr_user_rd_valid),
        .I_ddr_user_rd_data (S_ddr_user_rd_data),

        .I_dsi_clk    (S_hdmi_pixel_clk),
        .I_video_vsync(S_video_out_vsync),
        .I_video_rd_en(S_hdmi_window_rd_en),
        .O_vdieo_data (S_video_rd_data)
    );



    mc_to_user_interface u_mc_to_user_interface (
        .I_clk  (S_ddr_clk),
        .I_rst_n(S_rst_n),

        .I_ddr_user_wr_en   (S_ddr_user_wr_en),
        .I_ddr_user_rd_en   (S_ddr_user_rd_en),
        .I_ddr_user_addr    (S_ddr_user_addr),
        .I_ddr_user_wr_data (S_ddr_user_wr_data),
        .O_ddr_user_ready   (S_ddr_user_ready),
        .O_ddr_user_rd_valid(S_ddr_user_rd_valid),
        .O_ddr_user_rd_data (S_ddr_user_rd_data),

        .O_mc_app_en           (S_mc_app_en),
        .O_mc_app_addr         (S_mc_app_addr),
        .O_mc_app_cmd          (S_mc_app_cmd),
        .I_mc_app_rdy          (S_mc_app_rdy),
        .O_mc_app_wdf_wren     (S_mc_app_wdf_wren),
        .O_mc_app_wdf_data     (S_mc_app_wdf_data),
        .O_mc_app_wdf_end      (S_mc_app_wdf_end),
        .O_mc_app_wdf_mask     (S_mc_app_wdf_mask),
        .I_mc_app_wdf_rdy      (S_mc_app_wdf_rdy),
        .I_mc_app_rd_data      (S_mc_app_rd_data),
        .I_mc_app_rd_data_end  (S_mc_app_rd_data_end),
        .I_mc_app_rd_data_valid(S_mc_app_rd_data_valid)
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper (
        .I_sys_clk  (I_sys_clk),
        .I_sys_rst_n(S_rst_n),

        .O_ddr_clk             (S_ddr_clk),
        .O_init_calib_complete (S_init_calib_complete),
        .I_mc_app_addr         (S_mc_app_addr),
        .I_mc_app_cmd          (S_mc_app_cmd),
        .I_mc_app_en           (S_mc_app_en),
        .I_mc_app_wdf_data     (S_mc_app_wdf_data),
        .I_mc_app_wdf_end      (S_mc_app_wdf_end),
        .I_mc_app_wdf_mask     (S_mc_app_wdf_mask),
        .I_mc_app_wdf_wren     (S_mc_app_wdf_wren),
        .O_mc_app_rd_data      (S_mc_app_rd_data),
        .O_mc_app_rd_data_end  (S_mc_app_rd_data_end),
        .O_mc_app_rd_data_valid(S_mc_app_rd_data_valid),
        .O_mc_app_rdy          (S_mc_app_rdy),
        .O_mc_app_wdf_rdy      (S_mc_app_wdf_rdy),

        .ddr_addr (ddr_addr),
        .ddr_ba   (ddr_ba),
        .ddr_cke  (ddr_cke),
        .ddr_odt  (ddr_odt),
        .ddr_cs_n (ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),
        .ddr_cas_n(ddr_cas_n),
        .ddr_we_n (ddr_we_n),
        .ddr_ck_p (ddr_ck_p),
        .ddr_ck_n (ddr_ck_n),
        .ddr_dm   (ddr_dm),
        .ddr_dq   (ddr_dq),
        .ddr_dqs_p(ddr_dqs_p),
        .ddr_dqs_n(ddr_dqs_n)
    );



    uivtc #(
        .H_ActiveSize(1280),
        .H_FrameSize (1650),
        .H_SyncStart (1390),
        .H_SyncEnd   (1430),
        .V_ActiveSize(720),
        .V_FrameSize (750),
        .V_SyncStart (725),
        .V_SyncEnd   (730)
    ) u_hdmi_vtc (
        .I_vtc_rstn    (S_hdmi_rst_n),
        .I_vtc_clk     (S_hdmi_pixel_clk),
        .O_vtc_vs      (S_hdmi_vsync),
        .O_vtc_hs      (S_hdmi_hsync),
        .O_vtc_de_valid(S_hdmi_de),
        .O_vtc_user    (S_hdmi_user),
        .O_vtc_last    (S_hdmi_last)
    );

    // One calibrated camera stream for ROI and display; overlays stay separate.
    // Register pre-OSD camera RGB on the same edge as hdmi_mixer's output.
    reg [23:0] S_camera_rgb_aligned;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) S_camera_rgb_aligned<=0;
        else S_camera_rgb_aligned<=S_video_rd_data;
    wire S_color_vs,S_color_hs,S_color_de,S_color_protect;
    wire S_color_roi_de,S_color_roi_sof,S_color_roi_last;
    wire [23:0] S_color_display_rgb,S_color_roi_rgb;
    scene_color_stream #(.RGB_SHADING_ENABLE(0)) u_scene_color_stream(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_out_vsync),.in_hs(S_hdmi_out_hsync),.in_de(S_hdmi_out_de),
        .in_protect (S_hdmi_out_protect),.camera_rgb(S_camera_rgb_aligned),
        .mixed_rgb(S_hdmi_out_data),
        .out_vs(S_color_vs),.out_hs(S_color_hs),.out_de(S_color_de),
        .out_protect(S_color_protect),.display_rgb(S_color_display_rgb),
        .roi_rgb(S_color_roi_rgb),.roi_de(S_color_roi_de),
        .roi_sof(S_color_roi_sof),.roi_last(S_color_roi_last)
    );

    // Read-only ROI tap on corrected camera pixels, before OSD and brightness.
    roi_target_tracker #(
        .IMG_W       (1280),
        .IMG_H       (720),
        .ROI_HALF_W  (320),
        .ROI_HALF_H  (180),
        .MIN_VALUE   (24),
        .MIN_AREA    (64),
        .MAX_AREA    (120000)
    ) u_roi_target_tracker (
        .clk             (S_hdmi_pixel_clk),
        .rst_n           (S_hdmi_rst_n),
        .in_frame_start  (S_color_roi_sof),
        .in_de           (S_color_roi_de),
        .in_line_last    (S_color_roi_last),
        .in_rgb          (S_color_roi_rgb),
        .target_valid    (S_track2_valid),
        .bbox_x0         (S_track2_bbox_x0),
        .bbox_y0         (S_track2_bbox_y0),
        .bbox_x1         (S_track2_bbox_x1),
        .bbox_y1         (S_track2_bbox_y1),
        .centroid_x      (S_track2_cx),
        .centroid_y      (S_track2_cy),
        .target_area     (S_track2_area),
        .frame_done      (S_track2_frame_done),
        .result_update   (S_track2_result_update),
        .mask_valid      (),
        .green_mask      (),
        .mask_x          (),
        .mask_y          (),
        .dbg_roi_valid   (S_track2_dbg_roi_valid),
        .dbg_color_match (S_track2_dbg_color_match)
    );

    // SW1 异步输入同步到 HDMI 像素时钟域；变化时产生一次更新事件。
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_sw1_sync <= 2'b00;
            S_sw1_seen <= 1'b0;
        end else begin
            S_sw1_sync <= {S_sw1_sync[0], I_sw1};
            S_sw1_seen <= S_sw1_sync[1];
        end
    end

    // The tracker publishes only complete frame results. Toggle-based bundled
    // data crosses safely to the independent 50 MHz servo timing domain.
    // SW1 关闭时也翻转一次 toggle，让舵机锁存 valid=0 并保持当前位置。
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n)
            S_track2_result_toggle <= 1'b0;
        else if (S_track2_result_update || S_sw1_change)
            S_track2_result_toggle <= ~S_track2_result_toggle;
    end

    visual_servo_pwm #(
        .IMG_W(1280),
        .IMG_H(720)
    ) u_visual_servo_pwm (
        .clk_50m          (I_sys_clk),
        .rst_n            (I_rst_n),
        .source_toggle    (S_track2_result_toggle),
        .target_valid_async(S_servo_valid),
        // Detection already uses the upright RGB raster. Do not rotate twice.
        .target_x_async   (S_track2_cx),
        .target_y_async   (S_track2_cy),
        .servo_pan        (O_servo_pan),
        .servo_tilt       (O_servo_tilt)
    );

    hdmi_mixer #(
        .H_OFFSET  (0),
        .V_OFFSET  (0),
        .IMG_WIDTH (1280),
        .IMG_HEIGHT(720),
        .DEBUG_MODE(0)
    ) u_hdmi_mixer (
        .I_clk          (S_hdmi_pixel_clk),
        .I_rst_n        (S_hdmi_rst_n),
        .I_video_vsync  (S_hdmi_vsync),
        .I_video_hsync  (S_hdmi_hsync),
        .I_video_de     (S_hdmi_de),
        .I_video_user   (S_hdmi_user),
        .I_video_last   (S_hdmi_last),
        .I_debug_status (S_hdmi_debug_status),
        .I_target_bbox_valid   (S_track2_valid),
        .I_target_bbox_x0      (S_track2_bbox_x0),
        .I_target_bbox_y0      (S_track2_bbox_y0),
        .I_target_bbox_x1      (S_track2_bbox_x1),
        .I_target_bbox_y1      (S_track2_bbox_y1),
        .O_video_rd_en  (S_hdmi_window_rd_en),
        .I_video_rd_data(S_video_rd_data),
        .O_hdmi_vsync   (S_hdmi_out_vsync),
        .O_hdmi_hsync   (S_hdmi_out_hsync),
        .O_hdmi_de      (S_hdmi_out_de),
        .O_hdmi_protect (S_hdmi_out_protect),
        .O_hdmi_data    (S_hdmi_out_data),
        .O_hdmi_x       (S_hdmi_out_x),
        .O_hdmi_y       (S_hdmi_out_y)
    );

    // Additional perimeter correction is display-only; ROI above is unchanged.
    wire S_edge_vs,S_edge_hs,S_edge_de,S_edge_protect;
    wire [23:0] S_edge_rgb;
    display_edge_color #(.SOURCE_ROTATE_180(CAMERA_ROTATE_180)) u_display_edge_color(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_color_vs),.in_hs(S_color_hs),.in_de(S_color_de),
        .in_protect(S_color_protect),.in_rgb(S_color_display_rgb),
        .out_vs(S_edge_vs),.out_hs(S_edge_hs),.out_de(S_edge_de),
        .out_protect(S_edge_protect),.out_rgb(S_edge_rgb));

    // RAW correction is upstream. Keep this existing six-cycle stage at unity,
    // then apply a display-only common RGB tone curve.
    // Keep the validated DDR pixel alignment and protect OSD/ROI colors.
    video_enhance #(
        .ENABLE(0),
        .GAMMA_ENABLE(0),
        .SHARPEN_ENABLE(0),
        .CONTRAST_ENABLE(0),
        .SATURATION_ENABLE(0),
        .BRIGHTNESS_OFFSET(0),
        .RGB_GAIN_Q8(256),
        .BLACK_LEVEL(12),
        .WHITE_LEVEL(238),
        .SATURATION_Q8(320),
        .DETAIL_LIMIT(12),
        .NOISE_THRESHOLD(8)
    ) u_video_enhance (
        .clk       (S_hdmi_pixel_clk),
        .rst_n     (S_hdmi_rst_n),
        .in_vsync  (S_edge_vs),
        .in_hsync  (S_edge_hs),
        .in_de     (S_edge_de),
        .in_protect(S_edge_protect),
        .in_rgb    (S_edge_rgb),
        .out_vsync (S_hdmi_enhanced_vsync),
        .out_hsync (S_hdmi_enhanced_hsync),
        .out_de    (S_hdmi_enhanced_de),
        .out_rgb   (S_hdmi_enhanced_data)
    );

    reg [5:0] S_tone_protect;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) S_tone_protect<=0;
        else S_tone_protect<={S_tone_protect[4:0],S_edge_protect};
    wire S_tone_vs,S_tone_hs,S_tone_de;wire [23:0] S_tone_rgb;
    display_common_tone u_display_common_tone(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_enhanced_vsync),.in_hs(S_hdmi_enhanced_hsync),
        .in_de(S_hdmi_enhanced_de),.in_protect(S_tone_protect[5]),.in_rgb(S_hdmi_enhanced_data),
        .out_vs(S_tone_vs),.out_hs(S_tone_hs),.out_de(S_tone_de),.out_rgb(S_tone_rgb));

    // MERGED STYLE MODE BEGIN: display-only, no detector feedback.
    // Match scene_color_stream's un-overlaid camera luma and protect metadata
    // to the existing edge(6) + enhance(6) + common tone(3) pipeline.
    wire [9:0] S_style_luma_sum={2'd0,S_color_roi_rgb[23:16]}+
                              {1'd0,S_color_roi_rgb[15:8],1'b0}+{2'd0,S_color_roi_rgb[7:0]};
    reg [7:0] S_style_luma_delay[0:14];
    reg [14:0] S_style_protect_delay;
    integer style_i;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
        if(!S_hdmi_rst_n)begin
            S_style_protect_delay<=0;
            for(style_i=0;style_i<15;style_i=style_i+1)S_style_luma_delay[style_i]<=0;
        end else begin
            S_style_protect_delay<={S_style_protect_delay[13:0],S_color_protect};
            S_style_luma_delay[0]<=S_style_luma_sum[9:2];
            for(style_i=1;style_i<15;style_i=style_i+1)
                S_style_luma_delay[style_i]<=S_style_luma_delay[style_i-1];
        end
    end
    wire S_style_request;
    style_switch_control u_style_switch(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .sw2_async(I_sw2),.style_request(S_style_request));
    wire S_style_vs,S_style_hs,S_style_de,S_style_protect,S_style_roi,S_style_enable;
    wire [23:0] S_style_rgb;
    roi_background_stylize #(.IMG_W(1280),.IMG_H(720),.LINE_TOTAL(1650),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1),.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32)) u_background_stylize(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_tone_vs),.in_hs(S_tone_hs),.in_de(S_tone_de),
        .in_protect(S_style_protect_delay[14]),.in_enable(S_style_request),
        .in_rgb(S_tone_rgb),.in_gray(S_style_luma_delay[14]),
        .bbox_valid(S_track2_valid),.bbox_x0(S_track2_bbox_x0),.bbox_y0(S_track2_bbox_y0),
        .bbox_x1(S_track2_bbox_x1),.bbox_y1(S_track2_bbox_y1),
        .out_vs(S_style_vs),.out_hs(S_style_hs),.out_de(S_style_de),
        .out_protect(S_style_protect),.out_rgb(S_style_rgb),.out_roi(S_style_roi),.out_enable(S_style_enable));

    // One-second smoothed trail: no feedback into the detector or servo.
    wire [15:0] S_trail_ms;
    video_ms_clock #(.CLK_HZ(75000000)) u_trail_time(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.ms_now(S_trail_ms));
    wire S_trail_vs,S_trail_hs,S_trail_de,S_trail_protect,S_trail_hit;
    wire [23:0] S_trail_rgb;
    roi_motion_trail #(.TTL_MS(1000),.SMOOTH_ENABLE(1),.SAMPLE_INTERVAL_MS(50),.JITTER_PIXELS(4)) u_motion_trail(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_style_vs),.in_hs(S_style_hs),.in_de(S_style_de),
        .in_protect(S_style_protect),.in_roi(S_style_roi),.in_enable(S_style_enable),.in_clear(1'b0),
        .in_rgb(S_style_rgb),.ms_now(S_trail_ms),
        .point_valid(S_track2_valid),.point_x(S_track2_cx),.point_y(S_track2_cy),
        .out_vs(S_trail_vs),.out_hs(S_trail_hs),.out_de(S_trail_de),
        .out_protect(S_trail_protect),.out_hit(S_trail_hit),.out_rgb(S_trail_rgb),
        .render_busy(),.point_count(),.bank_valid());

    // MERGED STYLE MODE END

    hdmi_tx u_hdmi_tx (
        .I_pixel_clk       (S_hdmi_pixel_clk),
        .I_serial_clk      (S_hdmi_serial_clk),
        .I_rst             (~S_hdmi_rst_n),
        .I_key_in          (1'b0),
        .I_edid_read_trig  (1'b0),
        .O_edid_read_valid (),
        .O_edid_read_data  (),
        .I_video_rgb_enable(1'b1),
        .I_video_in_vs     (S_trail_vs),
        .I_video_in_de     (S_trail_de),
        .I_video_in_user   (1'b0),
        .I_video_in_valid  (1'b0),
        .I_video_in_last   (1'b0),
        .O_video_in_ready  (),
        .I_video_in_data   (S_trail_rgb),
        .I_audio_valid     (1'b0),
        .I_audio_left_data (24'd0),
        .I_audio_right_data(24'd0),
        .I_i2s_BCLK        (1'b0),
        .I_i2s_LRCK        (1'b0),
        .I_i2s_DOUT        (1'b0),
        .O_ddc_scl         (),
        .O_hdmi_clk_p      (),
        .O_hdmi_tx_p       (),
        .O_tmds_ch0_p      (O_tmds_ch0_p),
        .O_tmds_ch1_p      (O_tmds_ch1_p),
        .O_tmds_ch2_p      (O_tmds_ch2_p),
        .O_tmds_clk_p      (O_tmds_clk_p)
    );



endmodule

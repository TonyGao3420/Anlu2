module baseline_current_path(input clk,rst,vs,hs,de,user,last,input [23:0] camera,
input sw1,sw2,output ov,oh,od,output [23:0] rgb);
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


wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
wire I_sw1=sw1,I_sw2=sw2;wire O_servo_pan,O_servo_tilt;
wire [3:0] S_hdmi_debug_status=0;
assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
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
        .IMG_H(720),
        .PAN_REVERSE(0),
        .TILT_REVERSE(0)
    ) u_visual_servo_pwm (
        .clk_50m          (I_sys_clk),
        .rst_n            (I_rst_n),
        .source_toggle    (S_track2_result_toggle),
        .target_valid_async(S_servo_valid),
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
    display_edge_color u_display_edge_color(
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
    roi_background_stylize_baseline #(.IMG_W(1280),.IMG_H(720),.LINE_TOTAL(1650),.MOTION_ENABLE(1),.STATUS_ENABLE(1)) u_background_stylize(
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


assign ov=S_trail_vs;assign oh=S_trail_hs;assign od=S_trail_de;assign rgb=S_trail_rgb;
endmodule

module extended_current_path(input clk,rst,vs,hs,de,user,last,input [23:0] camera,
input sw1,sw2,output ov,oh,od,output [23:0] rgb);
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


wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
wire I_sw1=sw1,I_sw2=sw2;wire O_servo_pan,O_servo_tilt;
wire [3:0] S_hdmi_debug_status=0;
assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
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
        .IMG_H(720),
        .PAN_REVERSE(0),
        .TILT_REVERSE(0)
    ) u_visual_servo_pwm (
        .clk_50m          (I_sys_clk),
        .rst_n            (I_rst_n),
        .source_toggle    (S_track2_result_toggle),
        .target_valid_async(S_servo_valid),
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
    display_edge_color u_display_edge_color(
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
    roi_background_stylize #(.IMG_W(1280),.IMG_H(720),.LINE_TOTAL(1650),.MOTION_ENABLE(1),.STATUS_ENABLE(1),.MODEL_STYLE_ENABLE(1)) u_background_stylize(
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


assign ov=S_trail_vs;assign oh=S_trail_hs;assign od=S_trail_de;assign rgb=S_trail_rgb;
endmodule

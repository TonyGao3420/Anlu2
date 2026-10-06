// 双轴视觉伺服输出：50 MHz域内同步帧级质心更新，并产生标准舵机脉冲。
// 坐标稳定保持到下一次更新，采用带限幅的P映射；目标丢失时保持最后角度。
// 舵机由外部电源供电并与FPGA共地，FPGA IO只输出3.3 V控制信号。
module visual_servo_pwm #(
    parameter integer IMG_W = 1280,
    parameter integer IMG_H = 720,
    parameter integer PAN_REVERSE = 0,
    parameter integer TILT_REVERSE = 0,
    parameter integer DEAD_BAND_PIXELS = 3,
    parameter integer PWM_PERIOD_CYCLES = 1000000, // 20 ms at 50 MHz
    parameter integer MIN_PULSE_CYCLES = 50000,    // 1.0 ms
    parameter integer CENTER_PULSE_CYCLES = 75000, // 1.5 ms
    parameter integer MAX_PULSE_CYCLES = 100000,   // 2.0 ms
    parameter integer PAN_TICKS_PER_PIXEL = 31,
    parameter integer TILT_TICKS_PER_PIXEL = 55
) (
    input  wire        clk_50m,
    input  wire        rst_n,

    // Bundled-data CDC: source payload stays fixed until the next toggle event.
    input  wire        source_toggle,
    input  wire        target_valid_async,
    input  wire [15:0] target_x_async,
    input  wire [15:0] target_y_async,

    output wire servo_pan,
    output wire servo_tilt
);
    localparam integer PERIOD_LAST = PWM_PERIOD_CYCLES - 1;
    localparam integer PAN_CENTER_X = IMG_W / 2;
    localparam integer TILT_CENTER_Y = IMG_H / 2;

    reg source_toggle_meta;
    reg source_toggle_sync;
    reg source_toggle_seen;
    // Synchronize the bundled status/coordinate bus as well as the event.
    // The source holds these values until the next frame-level toggle, so the
    // two-stage bus synchronizers have ample settling time before capture.
    (* async_reg = "true" *) reg target_valid_meta;
    (* async_reg = "true" *) reg target_valid_sync;
    (* async_reg = "true" *) reg [15:0] target_x_meta;
    (* async_reg = "true" *) reg [15:0] target_x_sync;
    (* async_reg = "true" *) reg [15:0] target_y_meta;
    (* async_reg = "true" *) reg [15:0] target_y_sync;

    reg [19:0] pan_command_cycles;
    reg [19:0] tilt_command_cycles;
    reg [19:0] pan_active_cycles;
    reg [19:0] tilt_active_cycles;
    reg [19:0] period_counter;

    wire signed [12:0] pan_error_raw =
        $signed({1'b0, target_x_sync[11:0]}) - PAN_CENTER_X;
    wire signed [12:0] tilt_error_raw =
        TILT_CENTER_Y - $signed({1'b0, target_y_sync[11:0]});

    wire signed [12:0] pan_error =
        (pan_error_raw <= DEAD_BAND_PIXELS && pan_error_raw >= -DEAD_BAND_PIXELS)
        ? 13'sd0 : pan_error_raw;
    wire signed [12:0] tilt_error =
        (tilt_error_raw <= DEAD_BAND_PIXELS && tilt_error_raw >= -DEAD_BAND_PIXELS)
        ? 13'sd0 : tilt_error_raw;

    wire signed [18:0] pan_delta = pan_error * PAN_TICKS_PER_PIXEL;
    wire signed [18:0] tilt_delta = tilt_error * TILT_TICKS_PER_PIXEL;
    wire signed [19:0] pan_candidate = CENTER_PULSE_CYCLES +
        (PAN_REVERSE ? -pan_delta : pan_delta);
    wire signed [19:0] tilt_candidate = CENTER_PULSE_CYCLES +
        (TILT_REVERSE ? -tilt_delta : tilt_delta);

    // Synchronize the event; payload is captured only after it has settled.
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            source_toggle_meta <= 1'b0;
            source_toggle_sync <= 1'b0;
            source_toggle_seen <= 1'b0;
            target_valid_meta <= 1'b0;
            target_valid_sync <= 1'b0;
            target_x_meta <= 16'd0;
            target_x_sync <= 16'd0;
            target_y_meta <= 16'd0;
            target_y_sync <= 16'd0;
        end else begin
            source_toggle_meta <= source_toggle;
            source_toggle_sync <= source_toggle_meta;
            target_valid_meta <= target_valid_async;
            target_valid_sync <= target_valid_meta;
            target_x_meta <= target_x_async;
            target_x_sync <= target_x_meta;
            target_y_meta <= target_y_async;
            target_y_sync <= target_y_meta;
            if (source_toggle_sync != source_toggle_seen)
                source_toggle_seen <= source_toggle_sync;
        end
    end

    // A bounded proportional position map keeps the command within 1-2 ms.
    // A missing target intentionally holds the last pulse to avoid a sudden pan.
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            pan_command_cycles  <= CENTER_PULSE_CYCLES;
            tilt_command_cycles <= CENTER_PULSE_CYCLES;
        end else if ((source_toggle_sync != source_toggle_seen) && target_valid_sync) begin
            if (pan_candidate < MIN_PULSE_CYCLES)
                pan_command_cycles <= MIN_PULSE_CYCLES;
            else if (pan_candidate > MAX_PULSE_CYCLES)
                pan_command_cycles <= MAX_PULSE_CYCLES;
            else
                pan_command_cycles <= pan_candidate[19:0];

            if (tilt_candidate < MIN_PULSE_CYCLES)
                tilt_command_cycles <= MIN_PULSE_CYCLES;
            else if (tilt_candidate > MAX_PULSE_CYCLES)
                tilt_command_cycles <= MAX_PULSE_CYCLES;
            else
                tilt_command_cycles <= tilt_candidate[19:0];
        end
    end

    // Apply new positions only at the 20 ms frame boundary to avoid pulse glitches.
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            period_counter   <= 20'd0;
            pan_active_cycles  <= CENTER_PULSE_CYCLES;
            tilt_active_cycles <= CENTER_PULSE_CYCLES;
        end else if (period_counter == PERIOD_LAST) begin
            period_counter   <= 20'd0;
            pan_active_cycles  <= pan_command_cycles;
            tilt_active_cycles <= tilt_command_cycles;
        end else begin
            period_counter <= period_counter + 20'd1;
        end
    end

    assign servo_pan  = (period_counter < pan_active_cycles);
    assign servo_tilt = (period_counter < tilt_active_cycles);
endmodule

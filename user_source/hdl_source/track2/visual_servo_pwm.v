// 双轴视觉伺服输出：根据目标坐标 x/y 的方向，逐帧微调 pan/tilt 位置，
// 再产生 50 Hz 标准舵机 PWM。
//
// 端口保持不变：
//   source_toggle       ：目标坐标更新事件（帧级 toggle）
//   target_valid_async  ：目标有效
//   target_x_async      ：目标 x 坐标
//   target_y_async      ：目标 y 坐标
//   servo_pan/servo_tilt：两路 PWM
//
// 控制逻辑参考 Servo_PWM_Test 的拨码版本：
//   - 位置 0..1024，初始位置由 pan/tilt 各自的 HOME 参数决定；
//   - 每 STEP_PERIOD_MS 走一步，每步 STEP_POSITION；
//   - x 与画面中心的误差决定 pan 增大/减小；
//   - y 与画面中心的误差决定 tilt 增大/减小；
//   - 死区内不动，目标丢失时保持最后位置；
//   - 脉宽 0.5–2.5 ms，20 ms 周期，与测试版一致。
//
// 注意：本模块只做“方向 + 固定步长”的视觉伺服，不做比例/PID；
// 舵机由外部 5 V 电源供电，FPGA 只输出 3.3 V PWM，必须共地。

module visual_servo_pwm #(
    parameter integer IMG_W = 1280,             // 图像宽度
    parameter integer IMG_H = 720,              // 图像高度
    parameter integer PAN_REVERSE = 0,          // 水平方向取反
    parameter integer TILT_REVERSE = 0,         // 垂直方向取反
    parameter integer DEAD_BAND_PIXELS = 3,     // 中心死区（像素）

    // 50 MHz 下的 PWM 参数
    parameter integer PWM_PERIOD_CYCLES = 1000000, // PWM 周期，20 ms
    parameter integer MIN_PULSE_CYCLES   = 25000,  // 最小脉宽，0.5 ms
    parameter integer MAX_PULSE_CYCLES   = 125000, // 最大脉宽，2.5 ms

    // 位置/步进参数
    parameter integer POSITION_FULL_SCALE = 1024, // 公用位置满量程（脉宽映射）
    parameter integer PAN_MIN_POSITION   = 0,     // pan 最小限位
    parameter integer PAN_MAX_POSITION   = 1024,  // pan 最大限位（可改）
    parameter integer PAN_HOME_POSITION  = 512,   // pan 默认位置，90°
    parameter integer TILT_MIN_POSITION  = 0,     // tilt 最小限位
    parameter integer TILT_MAX_POSITION  = 1024,  // tilt 最大限位（可改）
    parameter integer TILT_HOME_POSITION = 512,   // tilt 默认位置，90°
    parameter integer STEP_POSITION      = 8,     // 每步增量
    parameter integer STEP_PERIOD_MS     = 10     // 步进周期，10 ms
) (
    input  wire        clk_50m,          // 50 MHz 系统时钟
    input  wire        rst_n,            // 异步复位，低有效

    // 目标坐标跨时钟域：源端在两次 toggle 之间保持数据稳定
    input  wire        source_toggle,    // 目标更新 toggle（帧级）
    input  wire        target_valid_async, // 目标有效标志
    input  wire [15:0] target_x_async,   // 目标 x 坐标（像素）
    input  wire [15:0] target_y_async,   // 目标 y 坐标（像素）

    output wire        servo_pan,        // pan 舵机 PWM
    output wire        servo_tilt        // tilt 舵机 PWM
);
    localparam integer PERIOD_LAST = PWM_PERIOD_CYCLES - 1;         // 周期计数终值
    localparam integer PAN_CENTER_X = IMG_W / 2;                    // 水平中心
    localparam integer TILT_CENTER_Y = IMG_H / 2;                   // 垂直中心
    localparam integer SPAN_CYCLES = MAX_PULSE_CYCLES - MIN_PULSE_CYCLES; // 脉宽跨度
    localparam integer POSITION_SHIFT = $clog2(POSITION_FULL_SCALE); // 满量程对应移位
    localparam integer PAN_HOME_PULSE = MIN_PULSE_CYCLES +
        ((PAN_HOME_POSITION * SPAN_CYCLES) >> POSITION_SHIFT);       // pan 默认脉宽
    localparam integer TILT_HOME_PULSE = MIN_PULSE_CYCLES +
        ((TILT_HOME_POSITION * SPAN_CYCLES) >> POSITION_SHIFT);      // tilt 默认脉宽
    localparam integer STEP_CYCLES = (50_000_000 / 1_000) * STEP_PERIOD_MS; // 步进周期（时钟数）

    // ------------------------------------------------------------------
    // 经典 bundled-data CDC：source_toggle 每次翻转时采样一次坐标，
    // 其余时间保持上一次的坐标/有效标志不变。
    // ------------------------------------------------------------------
    reg source_toggle_meta;
    reg source_toggle_sync;
    reg source_toggle_seen;

    (* async_reg = "true" *) reg target_valid_meta;
    (* async_reg = "true" *) reg target_valid_sync;
    (* async_reg = "true" *) reg [15:0] target_x_meta;
    (* async_reg = "true" *) reg [15:0] target_x_sync;
    (* async_reg = "true" *) reg [15:0] target_y_meta;
    (* async_reg = "true" *) reg [15:0] target_y_sync;

    // 在 source_toggle 翻转沿更新，之后保持不变
    reg        target_valid_held;
    reg [15:0] target_x_held;
    reg [15:0] target_y_held;

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
            target_valid_held <= 1'b0;
            target_x_held <= 16'd0;
            target_y_held <= 16'd0;
        end else begin
            source_toggle_meta <= source_toggle;
            source_toggle_sync <= source_toggle_meta;
            target_valid_meta <= target_valid_async;
            target_valid_sync <= target_valid_meta;
            target_x_meta <= target_x_async;
            target_x_sync <= target_x_meta;
            target_y_meta <= target_y_async;
            target_y_sync <= target_y_meta;

            // source_toggle 每次翻转（上升沿或下降沿）锁存一次
            if (source_toggle_sync != source_toggle_seen) begin
                source_toggle_seen <= source_toggle_sync;
                target_valid_held <= target_valid_sync;
                target_x_held <= target_x_sync;
                target_y_held <= target_y_sync;
            end
        end
    end

    // ------------------------------------------------------------------
    // x/y 误差：方向只取符号，位置按固定步长移动。
    // PAN_REVERSE / TILT_REVERSE 用于适配舵机安装方向。
    // ------------------------------------------------------------------
    wire signed [12:0] pan_error =
        $signed({1'b0, target_x_held[11:0]}) - PAN_CENTER_X;
    wire signed [12:0] tilt_error =
        TILT_CENTER_Y - $signed({1'b0, target_y_held[11:0]});

    wire pan_step_pos = PAN_REVERSE ?
        (pan_error < -DEAD_BAND_PIXELS) : (pan_error > DEAD_BAND_PIXELS);
    wire pan_step_neg = PAN_REVERSE ?
        (pan_error > DEAD_BAND_PIXELS) : (pan_error < -DEAD_BAND_PIXELS);

    wire tilt_step_pos = TILT_REVERSE ?
        (tilt_error < -DEAD_BAND_PIXELS) : (tilt_error > DEAD_BAND_PIXELS);
    wire tilt_step_neg = TILT_REVERSE ?
        (tilt_error > DEAD_BAND_PIXELS) : (tilt_error < -DEAD_BAND_PIXELS);

    // ------------------------------------------------------------------
    // 10 ms 步进节拍；目标无效时清零并保持位置。
    // ------------------------------------------------------------------
    reg [19:0] step_cnt;
    reg        step_tick;

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            step_cnt  <= 20'd0;
            step_tick <= 1'b0;
        end else if (!target_valid_held) begin
            step_cnt  <= 20'd0;
            step_tick <= 1'b0;
        end else if (step_cnt >= (STEP_CYCLES - 1)) begin
            step_cnt  <= 20'd0;
            step_tick <= 1'b1;
        end else begin
            step_cnt  <= step_cnt + 20'd1;
            step_tick <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // 位置寄存器：pan/tilt 各自 0..1024，初始位置分别取 HOME 参数。
    // 每个 step_tick 只按误差方向走一步，死区内保持。
    // ------------------------------------------------------------------
    reg [10:0] pan_position;
    reg [10:0] tilt_position;

    //确定position
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            pan_position  <= PAN_HOME_POSITION;
            tilt_position <= TILT_HOME_POSITION;
        end else if (step_tick && target_valid_held) begin
            if (pan_step_pos) begin
                if ((pan_position + STEP_POSITION) <= PAN_MAX_POSITION)
                    pan_position <= pan_position + STEP_POSITION;
                else
                    pan_position <= PAN_MAX_POSITION;
            end else if (pan_step_neg) begin
                if (pan_position >= (PAN_MIN_POSITION + STEP_POSITION))
                    pan_position <= pan_position - STEP_POSITION;
                else
                    pan_position <= PAN_MIN_POSITION;
            end

            if (tilt_step_pos) begin
                if ((tilt_position + STEP_POSITION) <= TILT_MAX_POSITION)
                    tilt_position <= tilt_position + STEP_POSITION;
                else
                    tilt_position <= TILT_MAX_POSITION;
            end else if (tilt_step_neg) begin
                if (tilt_position >= (TILT_MIN_POSITION + STEP_POSITION))
                    tilt_position <= tilt_position - STEP_POSITION;
                else
                    tilt_position <= TILT_MIN_POSITION;
            end
        end
    end

    // ------------------------------------------------------------------
    // 位置 -> 脉宽；位置满量程固定为 1024，右移 10 位精确。
    // ------------------------------------------------------------------
    wire [31:0] pan_pulse_target =
        MIN_PULSE_CYCLES + ((pan_position * SPAN_CYCLES) >> POSITION_SHIFT);
    wire [31:0] tilt_pulse_target =
        MIN_PULSE_CYCLES + ((tilt_position * SPAN_CYCLES) >> POSITION_SHIFT);

    wire [19:0] pan_pulse_clamped =
        (pan_pulse_target > MAX_PULSE_CYCLES) ? MAX_PULSE_CYCLES : pan_pulse_target[19:0];
    wire [19:0] tilt_pulse_clamped =
        (tilt_pulse_target > MAX_PULSE_CYCLES) ? MAX_PULSE_CYCLES : tilt_pulse_target[19:0];
    // ------------------------------------------------------------------
    // 20 ms PWM；脉宽只在周期边界更新，避免脉冲中途变宽/变窄。
    // 复位期间仍输出 HOME 脉宽，让舵机主动保持在默认位置。
    // period_counter 不受 rst_n 清零，保证复位时 PWM 继续运行。
    // ------------------------------------------------------------------
    reg [19:0] period_counter = 20'd0;
    reg [19:0] pan_active_cycles = PAN_HOME_PULSE;
    reg [19:0] tilt_active_cycles = TILT_HOME_PULSE;
    reg        pan_pwm = 1'b0;
    reg        tilt_pwm = 1'b0;

    always @(posedge clk_50m) begin
        if (period_counter == PERIOD_LAST)
            period_counter <= 20'd0;
        else
            period_counter <= period_counter + 20'd1;
    end

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时保持默认脉宽，不把 PWM 拉低
            pan_active_cycles <= PAN_HOME_PULSE;
            tilt_active_cycles<= TILT_HOME_PULSE;
            pan_pwm           <= (period_counter < PAN_HOME_PULSE);
            tilt_pwm          <= (period_counter < TILT_HOME_PULSE);
        end else begin
            if (period_counter == PERIOD_LAST) begin
                pan_active_cycles <= pan_pulse_clamped;
                tilt_active_cycles<= tilt_pulse_clamped;
            end

            pan_pwm  <= (period_counter < pan_active_cycles);
            tilt_pwm <= (period_counter < tilt_active_cycles);
        end
    end

    assign servo_pan  = pan_pwm;
    assign servo_tilt = tilt_pwm;

endmodule

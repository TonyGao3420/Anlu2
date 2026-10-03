// =============================================================================
// 文件名 : tb_video_timing_720p60.v
// 模块名 : tb_video_timing_720p60
// 功能   : video_timing_720p60 的自检测试平台。验证 720p60 时序严格符合 VESA
//          参数，以及 AXI-Stream 控制信号落在正确位置。
//
// 校验项（每帧结算一次）:
//   1) 一帧总时钟数 = H_TOTAL * V_TOTAL = 1650 * 750 = 1237500
//   2) 每帧有效像素(valid) = H_ACTIVE * V_ACTIVE = 1280 * 720 = 921600
//   3) 每帧 user 脉冲 = 1，且出现在 (x=0,y=0)
//   4) 每帧 last 脉冲 = V_ACTIVE = 720，且出现在 x=1279
//   5) 行同步低电平拍数 = H_SYNC * V_TOTAL = 40 * 750 = 30000
//   6) 场同步低电平拍数 = V_SYNC * H_TOTAL = 5 * 1650 = 8250
//   7) valid 与 de 完全一致；x/y 连续且在有效范围内；像素无 X
//
// 运行: vsim -c -do scripts/run_tb_video_timing.do
// =============================================================================
`timescale 1ns / 1ps

module tb_video_timing_720p60;

    localparam integer H_ACTIVE = 1280;
    localparam integer H_FRONT  = 110;
    localparam integer H_SYNC   = 40;
    localparam integer H_BACK   = 220;
    localparam integer V_ACTIVE = 720;
    localparam integer V_FRONT  = 5;
    localparam integer V_SYNC   = 5;
    localparam integer V_BACK   = 20;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;  // 1650
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;  // 750

    localparam integer EXP_CLK   = H_TOTAL * V_TOTAL;      // 1237500
    localparam integer EXP_VALID = H_ACTIVE * V_ACTIVE;    // 921600
    localparam integer EXP_HS    = H_SYNC * V_TOTAL;       // 30000
    localparam integer EXP_VS    = V_SYNC * H_TOTAL;       // 8250

    // 期望统计 2 帧
    localparam integer NUM_FRAMES = 2;

    reg         clk;
    reg         rst_n;
    reg  [1:0]  pattern_sel;

    wire        axis_user, axis_valid, axis_last;
    wire [23:0] axis_data;
    wire        hs, vs, de;
    wire [11:0] x, y;

    // ---------------- 统计量（只在唯一一个 always 块里更新） ----------------
    integer errors;
    integer frame_idx;
    integer clk_cnt;
    integer valid_cnt;
    integer user_cnt;
    integer last_cnt;
    integer hs_low_cnt;
    integer vs_low_cnt;

    // 上一拍的值
    reg        axis_valid_d;
    reg [11:0] x_d;

    reg        done;

    // ---------------- 例化被测模块 ----------------
    video_timing_720p60 #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) dut (
        .I_pix_clk      (clk),
        .I_rst_n        (rst_n),
        .I_pattern_sel  (pattern_sel),
        .O_axis_user    (axis_user),
        .O_axis_valid   (axis_valid),
        .O_axis_last    (axis_last),
        .O_axis_data    (axis_data),
        .I_axis_ready   (1'b1),
        .O_hs           (hs),
        .O_vs           (vs),
        .O_de           (de),
        .O_x            (x),
        .O_y            (y),
        .O_frame_toggle ()
    );

    // 75MHz 像素时钟（720p60 像素时钟 74.25MHz，这里取 75MHz 便于计数）
    initial begin
        clk = 0;
        forever #6.667 clk = ~clk;
    end

    // ---------------- 唯一的检查/统计块 ----------------
    always @(posedge clk) begin
        if (rst_n && !done) begin

            // ---- 每拍一致性检查 ----
            if (axis_valid && axis_valid_d) begin
                if (x !== ((x_d + 12'd1) % H_ACTIVE)) begin
                    errors = errors + 1;
                    if (errors <= 5) $display("ERROR: column not continuous x=%0d prev=%0d", x, x_d);
                end
            end

            if (axis_valid !== de) begin
                errors = errors + 1;
                if (errors <= 5) $display("ERROR: valid(%b) != de(%b) at x=%0d y=%0d", axis_valid, de, x, y);
            end

            if (axis_user && !(axis_valid && (y == 12'd0) && (x == 12'd0))) begin
                errors = errors + 1;
                if (errors <= 5) $display("ERROR: user wrong pos x=%0d y=%0d valid=%b", x, y, axis_valid);
            end

            if (axis_last && !(axis_valid && (x == (H_ACTIVE-1)))) begin
                errors = errors + 1;
                if (errors <= 5) $display("ERROR: last wrong pos x=%0d y=%0d valid=%b", x, y, axis_valid);
            end

            if (axis_valid && (^axis_data === 1'bx)) begin
                errors = errors + 1;
                if (errors <= 5) $display("ERROR: pixel data has X");
            end

            if (axis_valid && ((x >= H_ACTIVE) || (y >= V_ACTIVE))) begin
                errors = errors + 1;
                if (errors <= 5) $display("ERROR: x/y out of range x=%0d y=%0d", x, y);
            end

            // ---- 累计统计 ----
            clk_cnt = clk_cnt + 1;
            if (axis_valid) valid_cnt = valid_cnt + 1;
            if (axis_user)  user_cnt  = user_cnt  + 1;
            if (axis_last)  last_cnt  = last_cnt  + 1;
            if (!hs) hs_low_cnt = hs_low_cnt + 1;
            if (!vs) vs_low_cnt = vs_low_cnt + 1;

            // ---- 一帧结束：结算并复位统计 ----
            if (clk_cnt == EXP_CLK) begin
                frame_idx = frame_idx + 1;
                $display("FRAME %0d: clk=%0d valid=%0d user=%0d last=%0d hs_low=%0d vs_low=%0d",
                         frame_idx, clk_cnt, valid_cnt, user_cnt, last_cnt, hs_low_cnt, vs_low_cnt);

                if (clk_cnt   !== EXP_CLK)   begin errors=errors+1; $display("ERROR: frame clk=%0d expect %0d", clk_cnt, EXP_CLK); end
                if (valid_cnt !== EXP_VALID) begin errors=errors+1; $display("ERROR: frame valid=%0d expect %0d", valid_cnt, EXP_VALID); end
                if (user_cnt  !== 1)         begin errors=errors+1; $display("ERROR: frame user=%0d expect 1", user_cnt); end
                if (last_cnt  !== V_ACTIVE)  begin errors=errors+1; $display("ERROR: frame last=%0d expect %0d", last_cnt, V_ACTIVE); end
                if (hs_low_cnt !== EXP_HS)   begin errors=errors+1; $display("ERROR: hs low=%0d expect %0d", hs_low_cnt, EXP_HS); end
                if (vs_low_cnt !== EXP_VS)   begin errors=errors+1; $display("ERROR: vs low=%0d expect %0d", vs_low_cnt, EXP_VS); end

                // 复位统计
                clk_cnt     = 0;
                valid_cnt   = 0;
                user_cnt    = 0;
                last_cnt    = 0;
                hs_low_cnt  = 0;
                vs_low_cnt  = 0;

                if (frame_idx >= NUM_FRAMES) begin
                    done = 1;
                end
            end

            axis_valid_d <= axis_valid;
            x_d          <= x;
        end
    end

    // ---------------- 激励与结果 ----------------
    initial begin
        errors      = 0;
        frame_idx   = 0;
        clk_cnt     = 0;
        valid_cnt   = 0;
        user_cnt    = 0;
        last_cnt    = 0;
        hs_low_cnt  = 0;
        vs_low_cnt  = 0;
        axis_valid_d= 1'b0;
        x_d         = 12'd0;
        done        = 1'b0;

        clk         = 0;
        rst_n       = 0;
        pattern_sel = 2'd0;

        repeat (10) @(posedge clk);
        rst_n = 1;

        wait (done == 1'b1);
        repeat (10) @(posedge clk);

        $display("--------------------------------------------------");
        $display("video_timing_720p60: frames=%0d errors=%0d", frame_idx, errors);
        if (errors == 0 && frame_idx >= NUM_FRAMES) begin
            $display("TEST PASSED: tb_video_timing_720p60");
        end
        else begin
            $display("TEST FAILED: tb_video_timing_720p60");
        end
        $display("--------------------------------------------------");
        $finish;
    end

    // 超时保护（2 帧约 33ms 仿真时间，给足余量）
    initial begin
        #200000000;
        $display("TEST FAILED: tb_video_timing_720p60 TIMEOUT frames=%0d clk_cnt=%0d", frame_idx, clk_cnt);
        $finish;
    end

endmodule

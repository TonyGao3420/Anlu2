`timescale 1ns / 1ps

module led_blink #(
    // 参数化设计：为了方便仿真快速跑出结果，我们加一个参数
    // 真实上板时用 25_000_000 (0.5秒)，仿真时我们在Testbench里把它改小
    parameter CNT_MAX = 25_000_000
)(
    input  wire clk,     // 50MHz 系统时钟
    input  wire rst_n,   // 低电平复位信号
    output reg  led      // LED 输出信号
);

    reg [25:0] cnt;      // 26位计数器，最多可以计数到 67,108,863 (足够装下 25,000,000)

    // 计数器逻辑：每次时钟上升沿或者复位下降沿触发
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 26'd0;
        end
        else if (cnt == CNT_MAX - 1) begin
            cnt <= 26'd0;
        end
        else begin
            cnt <= cnt + 1'b1;
        end
    end

    // LED控制逻辑：计数器满的时候翻转LED状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 1'b0;
        end
        else if (cnt == CNT_MAX - 1) begin
            led <= ~led; // 翻转LED
        end
    end

endmodule

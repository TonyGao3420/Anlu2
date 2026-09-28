`timescale 1ns / 1ps

module tb_led_blink();

    // 1. 声明测试平台的信号
    reg  clk;
    reg  rst_n;
    wire led;

    // 2. 例化待测模块 (DUT)，并重写参数！
    // 注意：这里我们把 CNT_MAX 改成了 10，这样仿真里几纳秒就闪一次，不然要跑几千万个时钟周期，电脑会卡死！
    led_blink #(
        .CNT_MAX(10)
    ) u_led_blink (
        .clk   (clk),
        .rst_n (rst_n),
        .led   (led)
    );

    // 3. 产生 50MHz 时钟 (周期 20ns，每 10ns 翻转一次)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // 4. 产生复位和激励信号
    initial begin
        // 初始化
        rst_n = 0;

        // 释放复位
        #100;
        rst_n = 1;

        // 运行足够的时间，让我们看到 LED 多次翻转
        // 1000ns / 20ns = 50个时钟周期，CNT_MAX=10，会翻转5次
        #1000;

        // 告诉仿真器停止
        $display("Simulation Finished Successfully!");
        $stop;
    end

    // 5. 生成波形文件 (用于ModelSim查看)
    initial begin
        $dumpfile("tb_led_blink.vcd");
        $dumpvars(0, tb_led_blink);
    end

endmodule

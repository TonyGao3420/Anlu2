// =============================================================================
// 文件名 : led_test_top.v
// 模块名 : led_test_top
// 功能   : **硬件诊断用**顶层 —— 完全不用 PLL，直接用 50MHz 系统时钟闪 LED。
//
// 目的：在排查"HDMI 黑屏 + LED0(PLL锁定)不亮"时，先用最小设计分离问题：
//   1) 验证板子能正常烧录、能跑；
//   2) 验证 C4 的 50MHz 时钟存在；
//   3) **验证 LED 引脚(D10/E10/C6/D6)与极性是否正确** ——
//      这直接检验 constrs/anlu2_pins.adc 中 LED 约束的对错。
//
// 预期现象：四个 LED 一起以约 0.75Hz 闪烁(亮 0.67s / 灭 0.67s)。
//   若 LED 闪烁 → 板子/时钟/LED 引脚全部正确，问题锁定在 PLL 或 HDMI 侧；
//   若 LED 不亮 → 说明 LED 引脚约束或极性有问题(或板子 LED 坏)。
//
// 注意：本文件不参与主工程综合，仅供诊断，放在 sim/ 下通过独立流程构建。
// =============================================================================
`timescale 1ns / 1ps

module led_test_top (
    input  wire       I_sys_clk,    // 50MHz @ C4
    input  wire       I_rst_n,      // 复位 @ R10
    output wire [3:0] O_led         // LED0..3 @ D10/E10/C6/D6
);

    // 50MHz 下计数到 33_554_431 约 0.671 秒
    reg [24:0] r_cnt;

    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cnt <= 25'd0;
        end
        else begin
            r_cnt <= r_cnt + 1'b1;
        end
    end

    // 用最高位驱动全部 4 个 LED：约 0.75Hz 闪烁
    // （同时点亮 4 个，便于确认每个 LED 及其引脚都能工作）
    assign O_led[0] = r_cnt[24];
    assign O_led[1] = r_cnt[24];
    assign O_led[2] = r_cnt[24];
    assign O_led[3] = r_cnt[24];

endmodule

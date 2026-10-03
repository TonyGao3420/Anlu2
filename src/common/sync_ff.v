// =============================================================================
// 文件名 : sync_ff.v
// 模块名 : sync_ff
// 功能   : 多拍同步器。把异步单比特信号同步到目标时钟域，消除亚稳态传播。
//          用于跨时钟域控制信号（如 PLL lock、按键、帧号单比特、FIFO 指针等）。
// 说明   : 只能用于单比特电平类信号，不能用于多位总线（多位须用 async_fifo 或
//          加握手/格雷码）。综合时会被识别为普通触发器链，无需特殊原语。
// =============================================================================
`timescale 1ns / 1ps

module sync_ff #(
    parameter integer STAGES = 2,      // 打拍级数，2 拍适用于一般控制信号
    parameter         RST_VAL = 1'b0   // 复位后的输出值
)(
    input  wire I_clk,                 // 目标时钟域时钟
    input  wire I_rst_n,               // 低电平复位
    input  wire I_d,                   // 源时钟域的异步输入
    output wire O_q                    // 同步后的输出
);

    // 声明一个固定长度的移位链，Verilog-2001 下用 reg 数组并显式复位
    reg [STAGES-1:0] r_sync;

    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            // 复位时整条链置为指定默认值
            for (i = 0; i < STAGES; i = i + 1) begin
                r_sync[i] <= RST_VAL;
            end
        end
        else begin
            // 链首接收新数据，其余逐级后移
            r_sync[0] <= I_d;
            for (i = 1; i < STAGES; i = i + 1) begin
                r_sync[i] <= r_sync[i-1];
            end
        end
    end

    assign O_q = r_sync[STAGES-1];

endmodule

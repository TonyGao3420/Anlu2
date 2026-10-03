// =============================================================================
// 文件名 : debounce.v
// 模块名 : debounce
// 功能   : 机械按键消抖。对低电平有效的按键输入做同步 + 计数确认，
//          按键稳定按下后输出一个时钟周期的高电平脉冲（O_press_pulse）。
//          同时输出稳定后的按键电平 O_key_level 供拨码/长按判断使用。
// 说明   : PH1P35A 开发板 KEY0-KEY3 为低电平有效（按下为 0）。
//          消抖时间 = (2^CNT_BITS) / f_clk。50MHz 下 CNT_BITS=18 约 5.2ms。
// =============================================================================
`timescale 1ns / 1ps

module debounce #(
    parameter integer CNT_BITS = 18     // 消抖计数器位宽
)(
    input  wire I_clk,                  // 系统时钟（50MHz）
    input  wire I_rst_n,                // 低电平复位
    input  wire I_key_n,                // 按键输入，低电平有效
    output reg  O_press_pulse,          // 确认按下时输出单拍脉冲
    output reg  O_key_level             // 消抖后的稳定电平（0=按下）
);

    // 同步 + 消抖计数
    reg [3:0]           r_sync;         // 输入同步链，防止亚稳态
    reg [CNT_BITS-1:0]  r_cnt;          // 稳定计数器
    reg                 r_stable;       // 消抖后的稳定值

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_sync    <= 4'b1111;       // 按键未按下时为高电平
            r_cnt     <= {CNT_BITS{1'b0}};
            r_stable  <= 1'b1;
        end
        else begin
            // 第一步：4 拍同步，消除异步输入的亚稳态
            r_sync <= {r_sync[2:0], I_key_n};

            // 第二步：只有同步后的电平与当前稳定值不同时才计数
            if (r_sync[3] == r_stable) begin
                r_cnt <= {CNT_BITS{1'b0}};      // 电平一致，计数清零
            end
            else if (r_cnt == {CNT_BITS{1'b1}}) begin
                // 计满说明电平已稳定保持足够长时间，接受新电平
                r_stable <= r_sync[3];
                r_cnt    <= {CNT_BITS{1'b0}};
            end
            else begin
                r_cnt <= r_cnt + 1'b1;
            end
        end
    end

    // 第三步：检测稳定值由 1 -> 0（按下沿），输出单拍脉冲
    reg r_stable_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_stable_d     <= 1'b1;
            O_press_pulse  <= 1'b0;
            O_key_level    <= 1'b1;
        end
        else begin
            r_stable_d    <= r_stable;
            // 上一拍为高、这一拍为低 => 按下
            O_press_pulse <= (r_stable_d == 1'b1) && (r_stable == 1'b0);
            O_key_level   <= r_stable;
        end
    end

endmodule

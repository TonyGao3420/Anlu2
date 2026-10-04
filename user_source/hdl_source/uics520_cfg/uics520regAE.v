// Anlu2 源码说明：曝光/增益写入表，先开启组保持，再写曝光高低位、模拟/数字增益，最后释放。
// 接口与使用约定：8项写入；I_AE以半行为单位，I_AG由SC520GainTbl提供三个寄存器字节。
// 工程状态：已列入TD编译清单。

`timescale 1ns / 1ps

module uics520regAE (
    input  wire [ 8:0] REG_INDEX,
    output reg  [23:0] REG_DATA,
    output wire [ 8:0] REG_SIZE,
    input  wire [15:0] I_AE,
    input  wire [23:0] I_AG
);
    // 0x3812组保持确保曝光和增益在同一批更新中生效。
    assign REG_SIZE = 9'd8;

    always @(*) begin
        case (REG_INDEX)
            9'd0: REG_DATA = {16'h3812, 8'h00};
            9'd1: REG_DATA = {16'h3e00, 4'h0, I_AE[15:12]};
            9'd2: REG_DATA = {16'h3e01, I_AE[11:4]};
            9'd3: REG_DATA = {16'h3e02, I_AE[3:0], 4'h0};
            9'd4: REG_DATA = {16'h3e09, I_AG[23:16]};
            9'd5: REG_DATA = {16'h3e06, I_AG[15:8]};
            9'd6: REG_DATA = {16'h3e07, I_AG[7:0]};
            9'd7: REG_DATA = {16'h3812, 8'h30};
            default: REG_DATA = {16'h0000, 8'h00};
        endcase
    end
endmodule


// Anlu2 源码说明：可选RAW10黑电平校正，对四个采样分别减去偏置并向0饱和。
// 接口与使用约定：当前主ISP未实例化。它会降低暗部数值，未经标定不应为解决偏暗而直接启用；O_tdest未赋值。
// 工程状态：未直接列入TD编译清单；见doc/CODE_GUIDE.md。

/*****************************************************************
Company : Nanjing Weiku Robot Technology Co., Ltd.
Brand   : VLKUS
Technical forum:www.uisrc.com
@Author      :   XiaoQingquan 
@Time        :   2024/09/11 
@Description :   ISP_black_level_correction
*****************************************************************/
`timescale 1ns / 1ps

module BLC #(
    parameter [9:0] Black_level_offset_r0 = 15,
    parameter [9:0] Black_level_offset_r1 = 15,
    parameter [9:0] Black_level_offset_r2 = 15,
    parameter [9:0] Black_level_offset_r3 = 15
) (
    input I_clk,
    input I_rst_n,

    input         I_tlast,
    input         I_tuser,
    input  [39:0] I_tdata,
    input         I_tvalid,
    input  [ 9:0] I_tdest,
    output        I_tready,

    output        O_tlast,
    output        O_tuser,
    output [39:0] O_tdata,
    output        O_tvalid,
    output [ 9:0] O_tdest,
    input         O_tready

);


    reg        I_tlast_r;
    reg        I_tuser_r;
    reg        I_tvalid_r;

    wire [9:0] I_blc_data        [3:0];
    wire [9:0] black_level_offset[3:0];
    assign black_level_offset[0] = Black_level_offset_r0;
    assign black_level_offset[1] = Black_level_offset_r1;
    assign black_level_offset[2] = Black_level_offset_r2;
    assign black_level_offset[3] = Black_level_offset_r3;

    reg [9:0] data_out[3:0];

    assign I_blc_data[0] = I_tdata[9:0];
    assign I_blc_data[1] = I_tdata[19:10];
    assign I_blc_data[2] = I_tdata[29:20];
    assign I_blc_data[3] = I_tdata[39:30];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : BLACK_LEVEL_OFFSET
            always @(posedge I_clk) begin
                if (I_tvalid) begin
                    // 执行黑电平矫正，防止出现负数
                    if (I_blc_data[i] > black_level_offset[i]) begin
                        data_out[i] <= I_blc_data[i] - black_level_offset[i];
                    end else begin
                        data_out[i] <= 10'd0;  // 将结果裁剪为0，防止负数
                    end
                end
            end
        end
    endgenerate


    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) {I_tlast_r, I_tuser_r, I_tvalid_r} <= 0;
        else begin
            I_tlast_r  <= I_tlast;
            I_tuser_r  <= I_tuser;
            I_tvalid_r <= I_tvalid;
        end
    end


    assign O_tlast  = I_tlast_r;
    assign O_tuser  = I_tuser_r;
    assign O_tvalid = I_tvalid_r;

    assign O_tdata  = {data_out[3], data_out[2], data_out[1], data_out[0]};
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign I_tready = O_tready;


endmodule

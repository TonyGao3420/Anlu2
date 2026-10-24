// Anlu2 源码说明：提取每个RAW10采样的高8位，并调整四像素的字节排列。
// 接口与使用约定：输出高字节是时间上第一个像素；RGB通路的位序依赖这里与data128_96的配合，不能只反转其中一级。
// 工程状态：已列入TD编译清单。

/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/11 
version:     :   
@Description :   
*****************************************************************/
`timescale 1ns / 1ns

module mipi_to_raw_converter (
    input I_clk,
    input I_rst_n,

    input  [39:0] I_raw_tdata,
    input  [ 9:0] I_raw_tdest,
    input         I_raw_tlast,
    input         I_raw_tvalid,
    input         I_raw_tuser,
    output        I_raw_tready,

    // 输出RAW10数据
    output [31:0] O_raw_tdata,
    output        O_raw_tlast,
    output        O_raw_tvalid,
    output        O_raw_tuser,
    input         O_raw_tready
);
    reg        I_tlast_r0;
    reg        I_tuser_r0;

    reg        I_tvalid_r0;
    reg [31:0] raw_data_r0;

    ///此处对于每个RAW10取高8位是因为高位所包含的颜色数据更多。
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) raw_data_r0 <= 0;
        else if (I_raw_tvalid) begin
            raw_data_r0 <= {
                I_raw_tdata[9:2], I_raw_tdata[19:12], I_raw_tdata[29:22], I_raw_tdata[39:32]
            };
        end
    end



    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {I_tlast_r0, I_tuser_r0, I_tvalid_r0} <= 0;
        end else begin
            I_tlast_r0  <= I_raw_tlast;
            I_tuser_r0  <= I_raw_tuser;
            I_tvalid_r0 <= I_raw_tvalid;
        end
    end


    assign O_raw_tlast  = I_tlast_r0;
    assign O_raw_tuser  = I_tuser_r0;
    assign O_raw_tvalid = I_tvalid_r0;

    assign O_raw_tdata  = raw_data_r0;

    assign I_raw_tready = O_raw_tready;


endmodule



// Anlu2 源码说明：移除四个32位RGB字中的8位填充，输出紧凑的96位像素组。
// 接口与使用约定：组合逻辑；输出高24位是第一个显示像素，重排与demosaic输出位序配套，不是图像镜像。
// 工程状态：已列入TD编译清单。

/*****************************************************************
Company : Nanjing Weiku Robot Technology Co., Ltd.
Brand   : VLKUS
Technical forum:www.uisrc.com
@Author      :   XiaoQingquan 
@Time        :   2024/09/18 
@Description :   
*****************************************************************/

module data128_96 (

    input  wire [127:0] I_tdata,
    output wire [ 95:0] O_tdata
);

    // 从RGB0到RGB3按显示先后顺序放入高到低24位槽。
    assign O_tdata = {I_tdata[23:0], I_tdata[55:32], I_tdata[87:64], I_tdata[119:96]};
    //assign O_tdata = {I_tdata, I_tdata, I_tdata[55:32], I_tdata[23:0]};

endmodule

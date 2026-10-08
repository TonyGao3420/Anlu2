// Anlu2 源码说明：ISP组合：RAW10四像素并行→Bayer插值→去填充→白平衡→96/128位打包。
// 接口与使用约定：IMG=1280×720、BAYER_MODE=BGGR；这是连续流接口，不支持背压。O_tready 是下游就绪输入，I_tready 是上游就绪输出。
// 工程状态：已列入TD编译清单。

module isp_top (
    input    axi4s_video_aclk,
    input    I_rst_n   ,
    input    I_lsc_cal_request, I_lsc_clear_request,
    output   O_lsc_valid, O_lsc_busy, O_lsc_failed,
    input    I_tlast   ,
    input    I_tuser   ,
    input [39:0]  I_tdata   ,
    input    I_tvalid  ,
    input [9:0]  I_tdest   ,
    input    O_tready  ,
    output [127:0]  O_tdata   ,
    output    O_tlast   ,
    output    O_tuser   ,
    output    O_tvalid  ,
    output    I_tready
);

    wire         m_aixs_tvalid;  //synthesis keep 
    wire [127:0] m_aixs_tdata;  //synthesis keep 
    wire         m_aixs_tuser;  //synthesis keep 
    wire         m_aixs_tlast;  //synthesis keep 
    wire         m_aixs_tready;  //synthesis keep 

    wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


    wire         awb_O_tlast;  //synthesis keep 
    wire         awb_O_tuser;  //synthesis keep 
    wire [ 95:0] awb_O_tdata;  //synthesis keep 
    wire         awb_O_tvalid;  //synthesis keep 
    wire         awb_O_tready;  //synthesis keep 

    wire         awb_O_tuser_128;  //synthesis keep 
    wire         awb_O_tvalid_128;  //synthesis keep 
    wire [127:0] awb_O_tdata_128;  //synthesis keep 

    assign awb_O_tready = O_tready;
    assign O_tdata      = awb_O_tdata_128;
    assign O_tlast      = awb_O_tlast;
    assign O_tuser      = awb_O_tuser_128;
    assign O_tvalid     = awb_O_tvalid_128;

    //assign m_aixs_tready = O_tready;
    //assign O_tdata  = m_aixs_tdata;
    //assign O_tlast  = m_aixs_tlast    ;
    //assign O_tuser  = m_aixs_tuser    ;
    //assign O_tvalid = m_aixs_tvalid   ;


    wire [39:0] lsc_data;
    wire [9:0] lsc_dest;
    wire lsc_valid,lsc_user,lsc_last;
    // Calibrated RAW shading correction precedes interpolation and global AWB.
    raw_color_shading u_color_shading (
        .clk(axi4s_video_aclk), .rst_n(I_rst_n),
        .cal_request(I_lsc_cal_request), .clear_request(I_lsc_clear_request),
        .in_data(I_tdata),.in_dest(I_tdest),.in_valid(I_tvalid),.in_user(I_tuser),.in_last(I_tlast),
        .out_data(lsc_data),.out_dest(lsc_dest),.out_valid(lsc_valid),.out_user(lsc_user),.out_last(lsc_last),
        .map_valid(O_lsc_valid),.cal_busy(O_lsc_busy),.cal_failed(O_lsc_failed)
    );

    demosaic #(
        .IMG_HEIGHT         (720),    // 图像高度
        .IMG_WIDTH          (1280),   // 图像宽度
        .data_complete_delay(50),
        .BAYER_MODE         ("BGGR")
    ) u_demosaic (
        .I_clk             (axi4s_video_aclk),  // 时钟信号
        .I_rst_n           (I_rst_n),           // 复位信号，低有效
        .axi4s_video_tdata (lsc_data),           // AXI4-Stream视频数据
        .axi4s_video_tdest (lsc_dest),
        .axi4s_video_tlast (lsc_last),           // 行结束信号
        .axi4s_video_tvalid(lsc_valid),          // 数据有效信号
        .axi4s_video_tuser (lsc_user),           // 帧开始信号
        .axi4s_video_tready(I_tready),          // 从模块准备好接受数据
        .O_tlast           (m_aixs_tlast),      // 输出行结束信号
        .O_tuser           (m_aixs_tuser),      // 输出帧开始信号
        .O_tdata           (m_aixs_tdata),      // 输出数据
        .O_tvalid          (m_aixs_tvalid),     // 输出数据有效信号
        .O_tready          (m_aixs_tready)      // 输出数据准备好信号
    );

    data128_96 u_data128_96 (
        .I_tdata(m_aixs_tdata),
        .O_tdata(m_aixs_tdata_96)
    );

    awb #(
        .IMG_HEIGHT(720),
        .IMG_WIDTH (1280),
        // Enable the bounded, frame-smoothed AWB stage to compensate the green
        // cast observed on the display. Gains use neutral mid-tone samples.
        .AUTO_GAIN_ENABLE(1)
    ) u_awb (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_tlast (m_aixs_tlast),
        .I_tuser (m_aixs_tuser),
        .I_tdata (m_aixs_tdata_96),
        .I_tvalid(m_aixs_tvalid),
        .I_tready(m_aixs_tready),
        .O_tlast (awb_O_tlast ),
        .O_tuser (awb_O_tuser ),
        .O_tdata (awb_O_tdata ),
        .O_tvalid(awb_O_tvalid),
        .O_tready(awb_O_tready)
    );

    data_96bit_to_128bit u_data_96bit_to_128bit (
        .I_clk  (axi4s_video_aclk),
        .I_rst_n(I_rst_n),

        .I_96b_frame_start(awb_O_tuser),
        .I_96b_valid      (awb_O_tvalid),
        .I_96b_data       (awb_O_tdata),

        .O_128b_frame_start(awb_O_tuser_128),
        .O_128b_valid      (awb_O_tvalid_128),
        .O_128b_data       (awb_O_tdata_128)
    );



    //data96_128 u_data96_128 (
    //    .I_tdata(awb_O_tdata),
    //    .O_tdata(awb_O_tdata_128)
    //);

endmodule

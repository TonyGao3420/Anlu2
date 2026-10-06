// Anlu2 源码说明：四像素RGB流白平衡节点；默认关闭动态通道增益，采用单位增益。
// 接口与使用约定：数据延迟/打包接口保持不变；AUTO_GAIN_ENABLE=1时才按上一帧统计更新R/B的Q16增益。
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
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
module awb #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    // Keep the color baseline neutral until the sensor/AWB response is verified on board.
    parameter integer AUTO_GAIN_ENABLE = 0
) (
    input I_clk,
    input I_rst_n,


    input         I_tlast,
    input         I_tuser,
    input  [95:0] I_tdata,
    input         I_tvalid,
    output        I_tready,

    output        O_tlast,
    output        O_tuser,
    output [95:0] O_tdata,
    output        O_tvalid,
    input         O_tready
);

    // Keep the correction deliberately modest; aggressive gray-world gains
    // clip red highlights and amplify channel noise in shadows.
    localparam [19:0] AWB_MIN_GAIN_Q16 = 20'h0CCCC; // about 0.8x
    localparam [19:0] AWB_MAX_GAIN_Q16 = 20'h14000; // 1.25x

    /*****************************************************************
                          RGB565תRGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];

    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};

    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;

    /*****************************************************************
                          中间信号                                        
*****************************************************************/


    reg I_tvalid_r0, I_tvalid_r1;
    reg [95:0] I_tdata_d0, I_tdata_d1;


    //累加RGB通道的�??
    reg  [31:0] sum_r      [0:3];
    reg  [31:0] sum_g      [0:3];
    reg  [31:0] sum_b      [0:3];


    wire [95:0] data_d0;
    wire        valid_d0;
    wire        I_tuser_r0;

    reg         I_tuser_r1;

    reg  [95:0] data_d1;
    reg         valid_d1;
    reg  [ 9:0] rgb_sum    [0:3];  //每个像素点RGB的和
    /*****************************************************************
                            平均值计�??                                      
*****************************************************************/

    // 对输入数据和有效信号进行寄存，形成流水线
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            I_tdata_d0 <= 0;
            I_tdata_d1 <= 0;
            {I_tvalid_r0, I_tvalid_r1} <= 0;
        end else begin
            I_tdata_d0  <= I_tdata;
            I_tdata_d1  <= I_tdata_d0;
            I_tvalid_r0 <= I_tvalid;
            I_tvalid_r1 <= I_tvalid_r0;
        end
    end

    // 将输入数据拆分为4个像素的RGB分量
    wire [7:0] rgb888_r_d[0:3];
    wire [7:0] rgb888_g_d[0:3];
    wire [7:0] rgb888_b_d[0:3];

    assign rgb888_r_d[0] = I_tdata[16+:8];
    assign rgb888_g_d[0] = I_tdata[8+:8];
    assign rgb888_b_d[0] = I_tdata[0+:8];


    // 将输入数据拆分为4个像素的RGB分量
    wire [7:0] rgb888_r_d0[0:3];
    wire [7:0] rgb888_g_d0[0:3];
    wire [7:0] rgb888_b_d0[0:3];

    assign rgb888_r_d0[0] = I_tdata_d0[16+:8];
    assign rgb888_g_d0[0] = I_tdata_d0[8+:8];
    assign rgb888_b_d0[0] = I_tdata_d0[0+:8];

    // Estimate white balance from mid-level, low-chroma samples only.
    // Colored objects/backgrounds must not steer the gray-world statistics.
    wire [7:0] neutral_max_rg = (rgb888_r_d0[0] > rgb888_g_d0[0])
                               ? rgb888_r_d0[0] : rgb888_g_d0[0];
    wire [7:0] neutral_max = (neutral_max_rg > rgb888_b_d0[0])
                            ? neutral_max_rg : rgb888_b_d0[0];
    wire [7:0] neutral_min_rg = (rgb888_r_d0[0] < rgb888_g_d0[0])
                               ? rgb888_r_d0[0] : rgb888_g_d0[0];
    wire [7:0] neutral_min = (neutral_min_rg < rgb888_b_d0[0])
                            ? neutral_min_rg : rgb888_b_d0[0];
    wire [7:0] neutral_chroma = neutral_max - neutral_min;
    wire neutral_sample = (rgb_sum[0] >= 10'd96) &&
                          (rgb_sum[0] < 10'd720) &&
                          (neutral_chroma <= (neutral_max >> 2));


    ///削弱白色
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rgb_sum[0] <= 0;
        end else if (I_tvalid) begin
            rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
        end
    end

    // 对每个通道的值进行累加，用于计算平均值
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            // 复位或行开始信号有效时，清零累加器
            sum_r[0] <= 1;
            sum_g[0] <= 1;
            sum_b[0] <= 1;
        end else if (I_tvalid_r0 && neutral_sample) begin
            // Only neutral, non-dark, non-clipped pixels contribute to AWB.
            sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
            sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
            sum_b[0] <= sum_b[0] + rgb888_b_d0[0];
        end
    end

    /*****************************************************************
                           计算增益                                       
*****************************************************************/

    // R and B gains are needed only once per frame. A single 16-step
    // fractional divider is time-multiplexed across both channels instead of
    // instantiating two wide, fully-pipelined divider IP blocks.

    signal_delay #(
        .IMG_HEIGHT (IMG_HEIGHT),
        .IMG_WIDTH  (IMG_WIDTH),
        .DATA_WIDTH (96),
        .DELAY_CYCLE(50)
    ) signal_delay_d (
        /*input                       */.I_clk  (I_clk),
        /*input                       */.I_rst_n(I_rst_n),
        /*input                       */.I_tuser(I_tuser),      //synthesis keep 
        /*input  wire                 */.I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/.I_data (I_tdata_d1),   //synthesis keep 
        /*output wire                 */.O_valid(valid_d0),     //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/.O_data (data_d0),      //synthesis keep 
        /*output wire                 */.O_tuser(I_tuser_r0)
    );



    /*****************************************************************
                            ��������                                      
*****************************************************************/

    localparam [2:0] AWB_IDLE  = 3'd0;
    localparam [2:0] AWB_R_INIT = 3'd1;
    localparam [2:0] AWB_R_DIV  = 3'd2;
    localparam [2:0] AWB_B_INIT = 3'd3;
    localparam [2:0] AWB_B_DIV  = 3'd4;
    localparam [2:0] AWB_UPDATE = 3'd5;

    reg [2:0]  awb_div_state;
    reg [31:0] awb_sum_g_hold;
    reg [31:0] awb_sum_r_hold;
    reg [31:0] awb_sum_b_hold;
    reg [31:0] awb_divisor;
    reg [32:0] awb_remainder;
    reg        awb_integer_bit;
    reg [15:0] awb_fraction;
    reg [4:0]  awb_bit_count;
    reg [19:0] awb_r_target;
    reg [19:0] awb_b_target;
    reg [19:0] in_r_r1;
    reg [19:0] in_b_r1;

    // Ratio bounds expressed as cross-multiplication avoid a second divider.
    // Within [0.8, 1.25], the integer part is either zero or one, so 16
    // restoring steps produce the exact floor((G << 16) / channel).
    wire [31:0] awb_selected_den = (awb_div_state == AWB_R_INIT)
                                   ? awb_sum_r_hold : awb_sum_b_hold;
    wire [34:0] awb_sum_g_x4 = {1'b0, awb_sum_g_hold, 2'b00};
    wire [34:0] awb_sum_g_x5 = {3'b000, awb_sum_g_hold} +
                                ({3'b000, awb_sum_g_hold} << 2);
    wire [34:0] awb_den_x4 = {1'b0, awb_selected_den, 2'b00};
    wire [34:0] awb_den_x5 = {3'b000, awb_selected_den} +
                              ({3'b000, awb_selected_den} << 2);
    wire awb_ratio_below_min = awb_sum_g_x5 < awb_den_x4;
    wire awb_ratio_above_max = awb_sum_g_x4 > awb_den_x5;
    wire [32:0] awb_remainder_shifted = {awb_remainder[31:0], 1'b0};
    wire [32:0] awb_den_extended = {1'b0, awb_divisor};
    wire awb_fraction_bit = awb_remainder_shifted >= awb_den_extended;
    wire [32:0] awb_remainder_next = awb_fraction_bit
                                      ? awb_remainder_shifted - awb_den_extended
                                      : awb_remainder_shifted;
    wire [15:0] awb_fraction_next = {awb_fraction[14:0], awb_fraction_bit};
    wire [19:0] r_gain_delta = (awb_r_target >= in_r_r1)
                               ? (awb_r_target - in_r_r1)
                               : (in_r_r1 - awb_r_target);
    wire [19:0] b_gain_delta = (awb_b_target >= in_b_r1)
                               ? (awb_b_target - in_b_r1)
                               : (in_b_r1 - awb_b_target);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            awb_div_state <= AWB_IDLE;
            awb_sum_g_hold <= 32'd1;
            awb_sum_r_hold <= 32'd1;
            awb_sum_b_hold <= 32'd1;
            awb_divisor <= 32'd1;
            awb_remainder <= 33'd0;
            awb_integer_bit <= 1'b0;
            awb_fraction <= 16'd0;
            awb_bit_count <= 5'd0;
            awb_r_target <= 20'h10000;
            awb_b_target <= 20'h10000;
            in_r_r1 <= 20'h10000;
            in_b_r1 <= 20'h10000;
        end else begin
            case (awb_div_state)
                AWB_IDLE: begin
                    if (AUTO_GAIN_ENABLE && I_tuser) begin
                        // Capture the completed frame before the accumulators reset.
                        awb_sum_g_hold <= sum_g[0];
                        awb_sum_r_hold <= sum_r[0];
                        awb_sum_b_hold <= sum_b[0];
                        awb_div_state <= AWB_R_INIT;
                    end
                end

                AWB_R_INIT, AWB_B_INIT: begin
                    if (awb_ratio_below_min) begin
                        if (awb_div_state == AWB_R_INIT)
                            awb_r_target <= AWB_MIN_GAIN_Q16;
                        else
                            awb_b_target <= AWB_MIN_GAIN_Q16;
                        awb_div_state <= (awb_div_state == AWB_R_INIT)
                                         ? AWB_B_INIT : AWB_UPDATE;
                    end else if (awb_ratio_above_max) begin
                        if (awb_div_state == AWB_R_INIT)
                            awb_r_target <= AWB_MAX_GAIN_Q16;
                        else
                            awb_b_target <= AWB_MAX_GAIN_Q16;
                        awb_div_state <= (awb_div_state == AWB_R_INIT)
                                         ? AWB_B_INIT : AWB_UPDATE;
                    end else begin
                        awb_divisor <= awb_selected_den;
                        if (awb_sum_g_hold >= awb_selected_den) begin
                            awb_remainder <= {1'b0, awb_sum_g_hold - awb_selected_den};
                            awb_integer_bit <= 1'b1;
                        end else begin
                            awb_remainder <= {1'b0, awb_sum_g_hold};
                            awb_integer_bit <= 1'b0;
                        end
                        awb_fraction <= 16'd0;
                        awb_bit_count <= 5'd16;
                        awb_div_state <= (awb_div_state == AWB_R_INIT)
                                         ? AWB_R_DIV : AWB_B_DIV;
                    end
                end

                AWB_R_DIV: begin
                    awb_remainder <= awb_remainder_next;
                    awb_fraction <= awb_fraction_next;
                    if (awb_bit_count == 5'd1) begin
                        awb_r_target <= {3'b000, awb_integer_bit, awb_fraction_next};
                        awb_div_state <= AWB_B_INIT;
                    end else begin
                        awb_bit_count <= awb_bit_count - 5'd1;
                    end
                end

                AWB_B_DIV: begin
                    awb_remainder <= awb_remainder_next;
                    awb_fraction <= awb_fraction_next;
                    if (awb_bit_count == 5'd1) begin
                        awb_b_target <= {3'b000, awb_integer_bit, awb_fraction_next};
                        awb_div_state <= AWB_UPDATE;
                    end else begin
                        awb_bit_count <= awb_bit_count - 5'd1;
                    end
                end

                AWB_UPDATE: begin
                    // Preserve the 1/8 frame-to-frame gain slew.
                    if (awb_r_target >= in_r_r1)
                        in_r_r1 <= in_r_r1 + (r_gain_delta >> 3);
                    else
                        in_r_r1 <= in_r_r1 - (r_gain_delta >> 3);
                    if (awb_b_target >= in_b_r1)
                        in_b_r1 <= in_b_r1 + (b_gain_delta >> 3);
                    else
                        in_b_r1 <= in_b_r1 - (b_gain_delta >> 3);
                    awb_div_state <= AWB_IDLE;
                end

                default: awb_div_state <= AWB_IDLE;
            endcase
        end
    end

    ////信号同步
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d1 <= 0;
            data_d1 <= 0;
            I_tuser_r1 <= 0;
        end else begin
            valid_d1 <= valid_d0;
            data_d1 <= data_d0;
            I_tuser_r1 <= I_tuser_r0;
        end
    end
    /*****************************************************************
                           ��������                                       
*****************************************************************/

    reg  [27:0] R_new_r1;
    reg  [27:0] G_new_r1;
    reg  [27:0] B_new_r1;

    reg  [27:0] R_new_r2;
    reg  [27:0] G_new_r2;
    reg  [27:0] B_new_r2;

    reg  [27:0] R_new_r3;
    reg  [27:0] G_new_r3;
    reg  [27:0] B_new_r3;

    reg  [27:0] R_new_r4;
    reg  [27:0] G_new_r4;
    reg  [27:0] B_new_r4;


    wire [ 7:0] rgb888_r_d1[0:3];
    wire [ 7:0] rgb888_g_d1[0:3];
    wire [ 7:0] rgb888_b_d1[0:3];

    assign rgb888_r_d1[0] = data_d1[16+:8];
    assign rgb888_g_d1[0] = data_d1[8+:8];
    assign rgb888_b_d1[0] = data_d1[0+:8];

    assign rgb888_r_d1[1] = data_d1[40+:8];
    assign rgb888_g_d1[1] = data_d1[32+:8];
    assign rgb888_b_d1[1] = data_d1[24+:8];

    assign rgb888_r_d1[2] = data_d1[64+:8];
    assign rgb888_g_d1[2] = data_d1[56+:8];
    assign rgb888_b_d1[2] = data_d1[48+:8];

    assign rgb888_r_d1[3] = data_d1[88+:8];
    assign rgb888_g_d1[3] = data_d1[80+:8];
    assign rgb888_b_d1[3] = data_d1[72+:8];
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end else if (valid_d1) begin
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <= rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
            G_new_r2 <= rgb888_g_d1[1];
            B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
            G_new_r3 <= rgb888_g_d1[2];
            B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
            G_new_r4 <= rgb888_g_d1[3];
            B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
        end
    end

    /*****************************************************************
                            �������???                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (R_new_r1[27:24]) ? 255 : R_new_r1[23:16];
    assign G_new_x1 = G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24]) ? 255 : B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24]) ? 255 : R_new_r2[23:16];
    assign G_new_x2 = G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24]) ? 255 : B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24]) ? 255 : R_new_r3[23:16];
    assign G_new_x3 = G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24]) ? 255 : B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24]) ? 255 : R_new_r4[23:16];
    assign G_new_x4 = G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24]) ? 255 : B_new_r4[23:16];
    /*****************************************************************
                           ͬ���ź�                                       
*****************************************************************/

    reg valid_d2, I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d2   <= 0;
            I_tuser_r2 <= 0;
        end else begin
            valid_d2   <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign O_tlast = (valid_d1 == 0) && (valid_d2 == 1);
    // 提前帧首用于后级video_in复位FIFO，保持原有提前量。
    assign O_tuser = I_tuser;
    assign O_tvalid = valid_d2;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign I_tready = O_tready;

endmodule

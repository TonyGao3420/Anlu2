// Anlu2 源码说明：DDR到HDMI读通路：预读128位字到异步FIFO，再按24位RGB顺序输出。
// 接口与使用约定：每16像素读取3个128位字；读请求到RGB经过FIFO及输出寄存级，hdmi_mixer的DE必须与这两级一致。
// 工程状态：已列入TD编译清单。




module video_out #(
    parameter integer ROTATE_180=0, IMG_W=1280, IMG_H=720
) (
    input wire I_rst_n,

    input  wire         I_ddr_clk,
    output wire         O_video_out_rd_busy,
    input  wire         I_video_in_wr_busy,
    input  wire [  1:0] I_video_out_rp,
    output wire         O_ddr_user_rd_en,
    output reg  [ 24:0] O_ddr_user_addr,
    input  wire         I_ddr_user_ready,
    input  wire         I_ddr_user_rd_valid,
    input  wire [127:0] I_ddr_user_rd_data,

    input  wire        I_dsi_clk,
    input  wire        I_video_vsync,
    input  wire        I_video_rd_en,
    output wire O_frame_read_start,
    output wire [23:0] O_vdieo_data
);

    reg          S_fifo_rst;
    reg  [  7:0] S_fifo_rst_cnt;
    wire [  8:0] S_fifo_wr_num;
    wire         S_fifo_rd_en;
    wire [127:0] S_fifo_rd_data;
    reg          S_video_vsync_1d;
    reg          S_video_vsync_2d;
    reg          S_video_vsync_3d;
    wire         S_video_frame_start;
    wire         S_ddr_rd_trig;
    reg          S_ddr_rd_valid;
    reg  [  9:0] S_ddr_rd_cnt;
    reg  [  3:0] S_fifo_rd_cnt;
    reg          S_video_rd_en_1d;
    reg  [  3:0] S_fifo_rd_cnt_1d;
    reg  [127:0] S_fifo_rd_data_1d;
    wire         S_fifo_emtpy;



    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;
    localparam integer FRAME_WORDS=IMG_W*IMG_H*3/16;
    localparam [24:0] LAST_WORD_OFFSET=(FRAME_WORDS-1)*8;
    reg [17:0] words_left;
    reg [23:0] unpacked_data;
    wire [127:0] fifo_write_data;
    genvar byte_n;
    generate for(byte_n=0;byte_n<16;byte_n=byte_n+1)begin: byte_reverse
        assign fifo_write_data[byte_n*8+:8]=ROTATE_180?
            I_ddr_user_rd_data[(15-byte_n)*8+:8]:I_ddr_user_rd_data[byte_n*8+:8];
    end endgenerate
    // Reversing the byte stream yields BGR pixels; restore RGB channels.
    assign O_vdieo_data=ROTATE_180?{unpacked_data[7:0],unpacked_data[15:8],unpacked_data[23:16]}:unpacked_data;


    always @(posedge I_ddr_clk) begin
        S_video_vsync_1d <= I_video_vsync;
        S_video_vsync_2d <= S_video_vsync_1d;
        S_video_vsync_3d <= S_video_vsync_2d;
    end

    assign O_frame_read_start=S_video_frame_start;
    assign S_video_frame_start = ~S_video_vsync_3d & S_video_vsync_2d;


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) S_fifo_rst <= 1'b0;
        else if (S_video_frame_start) S_fifo_rst <= 1'b1;
        else if (S_fifo_rst_cnt == 'd10) S_fifo_rst <= 1'b0;
        else S_fifo_rst <= S_fifo_rst;
    end


    always @(posedge I_ddr_clk) begin
        if (S_fifo_rst) S_fifo_rst_cnt <= S_fifo_rst_cnt + 'd1;
        else S_fifo_rst_cnt <= 'd0;
    end

    /*
        这里需要注意fifo的剩余空间一定要大于将要写入的长度，因为ddr读出的时候会有至少40个时钟周期的延时，
        例如每次从ddr读出240个长度的数据，那么fifo的剩余空间最少要设为280，否则会引起fifo写满丢失数据。
    */
    assign S_ddr_rd_trig = (('d511 - S_fifo_wr_num) >= 'd300) && (!I_video_in_wr_busy) && (!S_ddr_rd_valid) && (!S_fifo_rst) && I_rst_n ? 1'b1 : 1'b0;

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次写入会引起fifo写满，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) S_ddr_rd_valid <= 1'b0;
        else if (O_ddr_user_rd_en && S_ddr_rd_cnt == 'd239) S_ddr_rd_valid <= 1'b0;
        else if (S_ddr_rd_trig) S_ddr_rd_valid <= 1'b1;
        else S_ddr_rd_valid <= S_ddr_rd_valid;
    end

    assign O_ddr_user_rd_en = S_ddr_rd_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        if (S_ddr_rd_valid) begin
            if (O_ddr_user_rd_en) S_ddr_rd_cnt <= S_ddr_rd_cnt + 'd1;
            else S_ddr_rd_cnt <= S_ddr_rd_cnt;
        end else S_ddr_rd_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin O_ddr_user_addr <= ROTATE_180?LAST_WORD_OFFSET:25'd0;words_left<=FRAME_WORDS-1;end
        else if (S_video_frame_start) begin
            case (I_video_out_rp)
                'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0+(ROTATE_180?LAST_WORD_OFFSET:25'd0);
                'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1+(ROTATE_180?LAST_WORD_OFFSET:25'd0);
                'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2+(ROTATE_180?LAST_WORD_OFFSET:25'd0);
                'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3+(ROTATE_180?LAST_WORD_OFFSET:25'd0);
            endcase
            words_left<=FRAME_WORDS-1;
        end else if (O_ddr_user_rd_en)begin
            if(ROTATE_180)begin
                // Keep blanking-time over-prefetch inside the selected buffer.
                if(words_left==0)begin O_ddr_user_addr<=O_ddr_user_addr+LAST_WORD_OFFSET;words_left<=FRAME_WORDS-1;end
                else begin O_ddr_user_addr<=O_ddr_user_addr-25'd8;words_left<=words_left-1'b1;end
            end else O_ddr_user_addr<=O_ddr_user_addr+25'd8;
        end
        else O_ddr_user_addr <= O_ddr_user_addr;
    end


    assign O_video_out_rd_busy = S_ddr_rd_trig | S_ddr_rd_valid;


    w128_d512_fifo U_w128_d512_fifo (
        .rst(S_fifo_rst),

        .clkw     (I_ddr_clk),
        .we       (I_ddr_user_rd_valid),
        .di       (fifo_write_data),
        .wrusedw  (S_fifo_wr_num),
        .afull    (),
        .full_flag(),

        .clkr      (I_dsi_clk),
        .re        (S_fifo_rd_en),
        .dout      (S_fifo_rd_data),
        .rdusedw   (),
        .valid     (),
        .empty_flag(S_fifo_emtpy),
        .aempty    ()
    );


    always @(posedge I_dsi_clk) begin
        if (I_video_rd_en) S_fifo_rd_cnt <= S_fifo_rd_cnt + 'd1;
        else S_fifo_rd_cnt <= 'd0;
    end

    // 16×24=3×128，像素5和10跨128位字边界，须拼接上一字尾部。
    assign S_fifo_rd_en = I_video_rd_en && (S_fifo_rd_cnt == 'd0)  ? 1'b1 :
                         I_video_rd_en && (S_fifo_rd_cnt == 'd5)  ? 1'b1 :
                         I_video_rd_en && (S_fifo_rd_cnt == 'd10) ? 1'b1 : 1'b0;

    always @(posedge I_dsi_clk) begin
        S_video_rd_en_1d  <= I_video_rd_en;
        S_fifo_rd_cnt_1d  <= S_fifo_rd_cnt;
        S_fifo_rd_data_1d <= S_fifo_rd_data;
    end

    always @(posedge I_dsi_clk) begin
        if (S_video_rd_en_1d) begin
            case (S_fifo_rd_cnt_1d)
                'd0:  unpacked_data <= S_fifo_rd_data[127:104];
                'd1:  unpacked_data <= S_fifo_rd_data[103:80];
                'd2:  unpacked_data <= S_fifo_rd_data[79:56];
                'd3:  unpacked_data <= S_fifo_rd_data[55:32];
                'd4:  unpacked_data <= S_fifo_rd_data[31:8];
                'd5:  unpacked_data <= {S_fifo_rd_data_1d[7:0], S_fifo_rd_data[127:112]};
                'd6:  unpacked_data <= S_fifo_rd_data[111:88];
                'd7:  unpacked_data <= S_fifo_rd_data[87:64];
                'd8:  unpacked_data <= S_fifo_rd_data[63:40];
                'd9:  unpacked_data <= S_fifo_rd_data[39:16];
                'd10: unpacked_data <= {S_fifo_rd_data_1d[15:0], S_fifo_rd_data[127:120]};
                'd11: unpacked_data <= S_fifo_rd_data[119:96];
                'd12: unpacked_data <= S_fifo_rd_data[95:72];
                'd13: unpacked_data <= S_fifo_rd_data[71:48];
                'd14: unpacked_data <= S_fifo_rd_data[47:24];
                'd15: unpacked_data <= S_fifo_rd_data[23:0];
            endcase
        end else unpacked_data <= 'd0;
    end


endmodule

// Observer only. Timestamp follows the actual DDR bank selected for display.
// Endpoint: RAW frame header reception -> first HDMI active pixel (microseconds).
module frame_latency(input wire sys_clk,rst_n,raw_clk,raw_sof,ddr_clk,
 input wire write_start,input wire [1:0] write_bank,input wire write_en,input wire [24:0] write_addr,
 input wire read_start,input wire [1:0] read_bank,input wire pixel_clk,
 output wire [23:0] age_us,output wire [15:0] frame_id,output wire valid);
 reg [5:0] div50;reg [23:0] now_us,gray_us;
 wire [23:0] next_us=now_us+1'b1;
 always @(posedge sys_clk or negedge rst_n)if(!rst_n)begin div50<=0;now_us<=0;gray_us<=0;end
 else if(div50==49)begin div50<=0;now_us<=next_us;gray_us<=next_us^(next_us>>1);end else div50<=div50+1'b1;
 (* ASYNC_REG="TRUE" *) reg [23:0] raw_g1,raw_g2,pix_g1,pix_g2;
 wire [23:0] raw_now,pix_now;genvar k;
 generate for(k=0;k<24;k=k+1)begin:gray_decode
  assign raw_now[k]=^raw_g2[23:k];assign pix_now[k]=^pix_g2[23:k];
 end endgenerate
 reg [23:0] raw_stamp;reg [15:0] raw_id;reg raw_seen;
 always @(posedge raw_clk or negedge rst_n)if(!rst_n)begin raw_g1<=0;raw_g2<=0;raw_stamp<=0;raw_id<=0;raw_seen<=0;end
 else begin raw_g1<=gray_us;raw_g2<=raw_g1;if(raw_sof)begin raw_stamp<=raw_now;raw_id<=raw_id+1'b1;raw_seen<=1;end end
 // Bundled metadata is held throughout a camera frame, before delayed ISP SOF.
 (* ASYNC_REG="TRUE" *) reg [40:0] meta1,meta2;
 reg [40:0] bank[0:3],selected;
 reg [3:0] complete;integer i;
 wire [1:0] last_bank=(write_addr==25'd1382392)?2'd0:(write_addr==25'd8382392)?2'd1:
                         (write_addr==25'd15382392)?2'd2:2'd3;
 wire last_word=write_addr==25'd1382392 || write_addr==25'd8382392 || write_addr==25'd15382392 || write_addr==25'd22382392;
 always @(posedge ddr_clk or negedge rst_n)if(!rst_n)begin
  meta1<=0;meta2<=0;complete<=0;selected<=0;for(i=0;i<4;i=i+1)bank[i]<=0;
 end else begin
  meta1<={raw_seen,raw_id,raw_stamp};meta2<=meta1;
  if(write_en && last_word)complete[last_bank]<=1;
  if(write_start)begin bank[write_bank]<=meta2;complete[write_bank]<=0;end
  if(read_start)selected<={bank[read_bank][40] && complete[read_bank] && !(write_start && write_bank==read_bank),bank[read_bank][39:0]};
 end
 (* ASYNC_REG="TRUE" *) reg [40:0] sel1,sel2;
 always @(posedge pixel_clk or negedge rst_n)if(!rst_n)begin pix_g1<=0;pix_g2<=0;sel1<=0;sel2<=0;end
 else begin pix_g1<=gray_us;pix_g2<=pix_g1;sel1<=selected;sel2<=sel1;end
 assign age_us=pix_now-sel2[23:0];assign frame_id=sel2[39:24];assign valid=sel2[40];
endmodule

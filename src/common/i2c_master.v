// =============================================================================
// 文件名 : i2c_master.v
// 模块名 : i2c_master
// 功能   : 标准 I2C 主机控制器（约 100kHz），支持两种操作：
//            - OP_WRITE : 写 N 个字节（给 SC520 摄像头写寄存器）
//            - OP_READ  : 写 1 字节子地址 + 重复起始 + 读 N 个字节（读芯片 ID）
//          带**超时保护**：从机长时间不应答或卡住总线时，自动发 STOP 并置 O_err，
//          绝不让整条图像流水线挂死。
//
// 实现要点:
//   - 一个 SCL 位周期 = 4 个相位，每个相位 CLK_DIV 拍；
//     SCL 在相位 0/1 为低、相位 2/3 为高，占空比约 50%。
//   - SDA 由组合逻辑直接取移位寄存器最高位驱动，保证"SCL 低电平期间变化、
//     高电平期间保持稳定"这一 I2C 基本要求，同时不会多移一位。
//   - 从机应答在相位 2（SCL 高电平中间）采样。
//
// 使用说明:
//   I_req 给一个时钟周期脉冲启动传输；传输期间 O_busy 为高，结束时 O_done 单拍。
//   I_wr_data 在 I_req 有效时被锁存，字节序 {byte0,byte1,byte2,byte3}，
//   byte0 = I_wr_data[31:24] 最先发送（OP_READ 时它就是子地址）。
//   O_sda_oe 为 1 表示把 SDA 拉低，为 0 表示释放为高阻，顶层接三态口：
//       assign IO_sda = O_sda_oe ? 1'b0 : 1'bz;
// =============================================================================
`timescale 1ns / 1ps

module i2c_master #(
    parameter integer CLK_DIV    = 125,   // 四分之一位周期计数：SCL = f_clk/(4*CLK_DIV)
                                          // 50MHz/(4*125) = 100kHz
    parameter integer NACK_LIMIT = 4,     // 连续 NACK 次数上限（0 = 不限制）
    parameter integer TO_LIMIT   = 2048   // 超时阈值（单位：位周期），约 20ms
)(
    input  wire        I_clk,             // 系统时钟 50MHz
    input  wire        I_rst_n,           // 低电平复位
    input  wire        I_req,             // 启动脉冲
    input  wire        I_rd_wr,           // 0=写, 1=读（写子地址后读）
    input  wire [7:0]  I_dev_addr,        // 7 位从机地址（高 7 位有效，不含读写位）
    input  wire [31:0] I_wr_data,         // 待写数据（byte0 在高 8 位，先发）
    input  wire [7:0]  I_wr_num,          // 写字节数（>=1）
    input  wire [7:0]  I_rd_num,          // 读字节数（>=1，读操作时有效）
    output reg         O_busy,            // 传输进行中
    output reg         O_done,            // 传输结束单拍脉冲
    output reg         O_ack_err,         // 从机未应答
    output reg         O_err,             // 超时/总线异常
    output reg  [31:0] O_rd_data,         // 读回数据（byte0 在高 8 位）
    output wire        O_scl,             // SCL（开漏，外部上拉）
    output wire        O_sda_oe,          // SDA 驱动使能：1=拉低，0=释放
    input  wire        I_sda_in           // SDA 回读电平
);

    // ---------------------------------------------------------------------
    // 操作码与状态编码
    // ---------------------------------------------------------------------
    localparam [1:0] OP_WRITE = 2'd0,
                     OP_READ  = 2'd1;

    localparam [3:0] S_IDLE   = 4'd0,     // 空闲等请求
                     S_START  = 4'd1,     // 起始/重复起始条件
                     S_ADDR   = 4'd2,     // 发送地址+读写位
                     S_ADACK  = 4'd3,     // 接收地址应答
                     S_DATA   = 4'd4,     // 发送 1 个数据字节
                     S_DADACK = 4'd5,     // 接收数据应答
                     S_RDAT   = 4'd6,     // 接收 1 个数据字节
                     S_MACK   = 4'd7,     // 主机发送应答/NACK
                     S_STOP   = 4'd8,     // 停止条件
                     S_DONE   = 4'd9,     // 收尾
                     S_TO     = 4'd10;    // 超时后强制收尾

    reg [3:0]  r_state;
    reg [1:0]  r_op;                      // 锁存的操作类型
    reg [7:0]  r_dev;                     // 锁存的 7 位从机地址
    reg [7:0]  r_wr_num;                  // 待写字节总数
    reg [7:0]  r_rd_num;                  // 待读字节总数
    reg [7:0]  r_byte_cur;                // 当前字节序号（0 起）
    reg [7:0]  r_shift;                   // 收发移位寄存器（最高位为当前数据位）
    reg [2:0]  r_bit;                     // 位计数 0~7
    reg [1:0]  r_phase;                   // 步骤内相位 0~3
    reg        r_scl;                     // SCL 输出电平
    reg        r_sda_drv_n;               // SDA 驱动：1=拉低，0=释放
    reg [31:0] r_rd_shift;                // 读数据累积（每收 1 字节左移 8 位）
    reg [7:0]  r_bad_ack;                 // 连续 NACK 计数
    reg [15:0] r_to_cnt;                  // 超时计数
    reg        r_rd_phase;                // 1=已进入读数据阶段（用于区分地址/数据字节）
    reg [31:0] r_wr_latched;              // 锁存的待写数据
    reg [3:0]  r_step;                    // 当前步骤编号

    wire w_tick    = (r_phase == 2'd3);   // 相位计满，推进到下一步骤
    wire w_phase0  = (r_phase == 2'd0);   // 步骤内第一个相位（SCL 低，可改 SDA）
    wire w_bus_stuck = (r_to_cnt == TO_LIMIT[15:0]);

    // ---------------------------------------------------------------------
    // 相位计数器
    // ---------------------------------------------------------------------
    reg [15:0] r_div_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_div_cnt <= 16'd0;
            r_phase   <= 2'd0;
        end
        else if (r_state == S_IDLE) begin
            r_div_cnt <= 16'd0;
            r_phase   <= 2'd0;
        end
        else if (r_div_cnt == (CLK_DIV - 1)) begin
            r_div_cnt <= 16'd0;
            r_phase   <= r_phase + 1'b1;      // 3 -> 0 自然回绕
        end
        else begin
            r_div_cnt <= r_div_cnt + 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // 超时计数：只在"等待从机"的状态里累加
    // ---------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_to_cnt <= 16'd0;
        end
        else if (r_state == S_ADDR  || r_state == S_ADACK ||
                 r_state == S_DATA  || r_state == S_DADACK ||
                 r_state == S_RDAT  || r_state == S_MACK) begin
            if (r_to_cnt == TO_LIMIT[15:0]) begin
                r_to_cnt <= r_to_cnt;          // 保持计满，触发超时
            end
            else if (w_tick) begin
                r_to_cnt <= r_to_cnt + 1'b1;
            end
        end
        else begin
            r_to_cnt <= 16'd0;
        end
    end

    // ---------------------------------------------------------------------
    // 组合逻辑：确定下一个待写/待读的字节
    // ---------------------------------------------------------------------
    // 当前序号对应 I_wr_data 中的字节（byte0 在高 8 位）
    wire [7:0] w_wr_byte_cur = (r_byte_cur == 8'd0) ? r_wr_latched[31:24] :
                               (r_byte_cur == 8'd1) ? r_wr_latched[23:16] :
                               (r_byte_cur == 8'd2) ? r_wr_latched[15:8]  :
                                                      r_wr_latched[7:0];
    // 下一个序号对应的字节（用于多字节写的连续性）
    wire [7:0] w_wr_byte_nxt = (r_byte_cur == 8'd0) ? r_wr_latched[23:16] :
                               (r_byte_cur == 8'd1) ? r_wr_latched[15:8]  :
                               (r_byte_cur == 8'd2) ? r_wr_latched[7:0]   :
                                                      r_wr_latched[31:24];

    // 地址字节：7 位地址 + 读写位（读数据阶段用 1，写阶段用 0）
    wire [7:0] w_addr_byte = {r_dev[7:1],
                              (r_rd_phase && (r_op == OP_READ)) ? 1'b1 : 1'b0};

    // SDA 驱动：发送阶段由移位寄存器最高位决定；接收阶段一律释放
    wire w_send_active = (r_state == S_ADDR) || (r_state == S_DATA);
    wire w_sda_from_shift = ~r_shift[7];   // 数据位=1 时释放(高)，=0 时拉低

    // ---------------------------------------------------------------------
    // 主状态机
    // ---------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_state     <= S_IDLE;
            r_op        <= OP_WRITE;
            r_dev       <= 8'h00;
            r_wr_num    <= 8'd0;
            r_rd_num    <= 8'd0;
            r_byte_cur  <= 8'd0;
            r_shift     <= 8'hFF;
            r_bit       <= 3'd0;
            r_scl       <= 1'b1;
            r_sda_drv_n <= 1'b0;
            r_rd_shift  <= 32'd0;
            r_bad_ack   <= 8'd0;
            r_rd_phase  <= 1'b0;
            r_step      <= 4'd0;
            O_busy      <= 1'b0;
            O_done      <= 1'b0;
            O_ack_err   <= 1'b0;
            O_err       <= 1'b0;
            O_rd_data   <= 32'd0;
        end
        else begin
            O_done <= 1'b0;                // 单拍脉冲默认清零

            case (r_state)

            // -------------------------------------------------------------
            // 空闲：等待启动请求
            // -------------------------------------------------------------
            S_IDLE: begin
                r_scl       <= 1'b1;
                r_sda_drv_n <= 1'b0;
                O_busy      <= 1'b0;
                if (I_req) begin
                    r_op        <= I_rd_wr ? OP_READ : OP_WRITE;
                    r_dev       <= I_dev_addr;
                    r_wr_num    <= I_wr_num;
                    r_rd_num    <= I_rd_num;
                    r_byte_cur  <= 8'd0;
                    r_bit       <= 3'd0;
                    r_phase     <= 2'd0;
                    r_bad_ack   <= 8'd0;
                    r_rd_phase  <= 1'b0;
                    O_ack_err   <= 1'b0;
                    O_err       <= 1'b0;
                    O_busy      <= 1'b1;
                    r_state     <= S_START;
                end
            end

            // -------------------------------------------------------------
            // 起始条件：SCL 保持高时 SDA 由高变低
            // -------------------------------------------------------------
            S_START: begin
                case (r_phase)
                2'd0:    begin r_scl <= 1'b1; r_sda_drv_n <= 1'b0; end // SDA=1
                2'd1:    begin r_scl <= 1'b1; r_sda_drv_n <= 1'b0; end // 保持
                2'd2:    begin r_scl <= 1'b1; r_sda_drv_n <= 1'b1; end // SDA 下降沿
                default: begin r_scl <= 1'b0; r_sda_drv_n <= 1'b1; end // SCL 拉低
                endcase
                if (w_tick) begin
                    // 起始完成，装载地址字节并进入地址发送
                    r_shift   <= w_addr_byte;
                    r_bit     <= 3'd0;
                    r_phase   <= 2'd0;
                    r_state   <= S_ADDR;
                end
            end

            // -------------------------------------------------------------
            // 发送地址字节
            // -------------------------------------------------------------
            S_ADDR: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (w_tick) begin
                    if (r_bit == 3'd7) begin
                        r_bit   <= 3'd0;
                        r_phase <= 2'd0;
                        r_state <= S_ADACK;    // 转为接收应答（SDA 自动释放）
                    end
                    else begin
                        r_bit   <= r_bit + 1'b1;
                        r_shift <= {r_shift[6:0], 1'b1};
                        r_phase <= 2'd0;
                    end
                end
            end

            // -------------------------------------------------------------
            // 地址应答：相位 2 采样 SDA（0=ACK，1=NACK）
            // -------------------------------------------------------------
            S_ADACK: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (r_phase == 2'd2 && I_sda_in == 1'b1) begin
                    O_ack_err <= 1'b1;
                    r_bad_ack <= r_bad_ack + 1'b1;
                end
                if (w_tick) begin
                    r_phase <= 2'd0;
                    if (O_ack_err && (NACK_LIMIT != 0) &&
                        (r_bad_ack >= NACK_LIMIT[7:0])) begin
                        r_state <= S_STOP;                 // 连续 NACK，放弃
                    end
                    else if ((r_op == OP_READ) && !r_rd_phase) begin
                        // 子地址写完：发重复起始条件，转入地址(读) + 读数据
                        r_rd_phase <= 1'b1;
                        r_byte_cur <= 8'd0;
                        r_state    <= S_START;
                    end
                    else begin
                        // 进入数据阶段
                        r_byte_cur <= 8'd0;
                        r_bit      <= 3'd0;
                        if (r_op == OP_READ && r_rd_phase) begin
                            r_shift <= 8'hFF;              // 接收阶段不使用
                            r_state <= S_RDAT;
                        end
                        else begin
                            r_shift <= w_wr_byte_cur;      // 装载第 0 个待写字节
                            r_state <= S_DATA;
                        end
                    end
                end
            end

            // -------------------------------------------------------------
            // 写 1 个数据字节（SDA 组合自 r_shift[7]）
            // -------------------------------------------------------------
            S_DATA: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (w_tick) begin
                    if (r_bit == 3'd7) begin
                        r_bit   <= 3'd0;
                        r_phase <= 2'd0;
                        r_state <= S_DADACK;
                    end
                    else begin
                        r_bit   <= r_bit + 1'b1;
                        r_shift <= {r_shift[6:0], 1'b1};
                        r_phase <= 2'd0;
                    end
                end
            end

            // -------------------------------------------------------------
            // 数据应答：判断是否还有下一个字节
            // -------------------------------------------------------------
            S_DADACK: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (r_phase == 2'd2 && I_sda_in == 1'b1) begin
                    O_ack_err <= 1'b1;
                    r_bad_ack <= r_bad_ack + 1'b1;
                end
                if (w_tick) begin
                    r_phase <= 2'd0;
                    if (O_ack_err && (NACK_LIMIT != 0) &&
                        (r_bad_ack >= NACK_LIMIT[7:0])) begin
                        r_state <= S_STOP;                 // 连续 NACK，放弃
                    end
                    else if (r_byte_cur >= (r_wr_num - 8'd1)) begin
                        r_state <= S_STOP;                 // 字节发完，结束
                    end
                    else begin
                        // 还有字节：装载下一个并继续发送
                        r_byte_cur <= r_byte_cur + 1'b1;
                        r_shift    <= w_wr_byte_nxt;
                        r_bit      <= 3'd0;
                        r_state    <= S_DATA;
                    end
                end
            end

            // -------------------------------------------------------------
            // 读 1 个数据字节：相位 2 采样并移入
            // -------------------------------------------------------------
            S_RDAT: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (r_phase == 2'd2) begin
                    r_shift <= {r_shift[6:0], I_sda_in};
                end
                if (w_tick) begin
                    if (r_bit == 3'd7) begin
                        r_bit   <= 3'd0;
                        r_phase <= 2'd0;
                        r_state <= S_MACK;
                    end
                    else begin
                        r_bit   <= r_bit + 1'b1;
                        r_phase <= 2'd0;
                    end
                end
            end

            // -------------------------------------------------------------
            // 主机应答：最后一个字节回 NACK，其余回 ACK
            // -------------------------------------------------------------
            S_MACK: begin
                r_scl <= (r_phase >= 2'd2) ? 1'b1 : 1'b0;
                if (w_phase0) begin
                    // 保存刚收到的字节
                    r_rd_shift <= {r_rd_shift[23:0], r_shift};
                    // 最后一字节回 NACK（释放 SDA），否则拉低 SDA 表示 ACK
                    if (r_byte_cur >= (r_rd_num - 8'd1)) begin
                        r_sda_drv_n <= 1'b0;
                    end
                    else begin
                        r_sda_drv_n <= 1'b1;
                    end
                end
                if (w_tick) begin
                    r_phase <= 2'd0;
                    if (r_byte_cur >= (r_rd_num - 8'd1)) begin
                        r_state <= S_STOP;
                    end
                    else begin
                        r_byte_cur <= r_byte_cur + 1'b1;
                        r_shift    <= 8'hFF;
                        r_bit      <= 3'd0;
                        r_state    <= S_RDAT;
                    end
                end
            end

            // -------------------------------------------------------------
            // 停止条件：SCL 高时 SDA 由低变高
            // -------------------------------------------------------------
            S_STOP: begin
                case (r_phase)
                2'd0:    begin r_scl <= 1'b0; r_sda_drv_n <= 1'b1; end
                2'd1:    begin r_scl <= 1'b1; r_sda_drv_n <= 1'b1; end
                default: begin r_scl <= 1'b1; r_sda_drv_n <= 1'b0; end
                endcase
                if (w_tick) begin
                    r_phase <= 2'd0;
                    r_state <= S_DONE;
                end
            end

            // -------------------------------------------------------------
            // 超时收尾：给出错误标志并直接释放总线
            // -------------------------------------------------------------
            S_TO: begin
                O_err       <= 1'b1;
                r_scl       <= 1'b1;
                r_sda_drv_n <= 1'b0;
                r_phase     <= 2'd0;
                r_state     <= S_DONE;
            end

            // -------------------------------------------------------------
            // 收尾：输出结果，回到空闲
            // -------------------------------------------------------------
            S_DONE: begin
                r_scl       <= 1'b1;
                r_sda_drv_n <= 1'b0;
                O_busy      <= 1'b0;
                O_done      <= 1'b1;
                if (r_op == OP_READ) begin
                    O_rd_data <= r_rd_shift;
                end
                r_state <= S_IDLE;
            end

            default: r_state <= S_IDLE;
            endcase

            // 等待从机时若长时间无进展，转入超时处理
            if (w_bus_stuck &&
                (r_state == S_ADDR   || r_state == S_ADACK ||
                 r_state == S_DATA   || r_state == S_DADACK ||
                 r_state == S_RDAT   || r_state == S_MACK)) begin
                r_state <= S_TO;
            end
        end
    end

    // 锁存待写数据，避免传输过程中输入变化
    always @(posedge I_clk) begin
        if (I_req) begin
            r_wr_latched <= I_wr_data;
        end
    end

    // SDA 输出驱动：
    //   发送阶段 -> 由移位寄存器最高位决定（数据位 0 则拉低）
    //   起始/停止/应答阶段 -> 由 r_sda_drv_n 直接决定
    assign O_scl    = r_scl;
    assign O_sda_oe = w_send_active ? w_sda_from_shift : r_sda_drv_n;

endmodule

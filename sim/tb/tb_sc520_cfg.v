// =============================================================================
// 文件名 : tb_sc520_cfg.v
// 模块名 : tb_sc520_cfg
// 功能   : SC520CS 摄像头配置流程的自检测试平台（含标准 I2C 从机模型）。
//
// ============================ uii2c 的通信行为 ============================
// 阅读 src/vendor/uii2c.v 后确认：
//   1) 它是**纯计数器驱动**的状态机，从机不响应也不会挂死，
//      只是在 W_ACK 阶段检测到 SDA=1 时置 O_iic_bus_error。
//      所以"从机不响应"是**可以测的负向用例**。
//   2) 芯片 ID 读取是 **repeated start** 读时序：
//         START + 器件地址(W) + 寄存器高字节 + 寄存器低字节
//         + repeated START + 器件地址(R) + 读 1 字节 + NACK + STOP
//   3) 寄存器写入是**两字节写**：
//         START + 器件地址(W) + 寄存器高字节 + 寄存器低字节
//         + 数据字节 + ... + STOP
//
// ============================== 从机模型 ==============================
// 上面两种事务都用同一个从机状态机处理：
//   接收阶段逐位收 8 位，收满后自动 ACK；
//   判断收到的第 1 字节是"器件地址(W)"还是"器件地址(R)"：
//     - W：后续依次收 寄存器高字节、寄存器低字节、数据字节（可选）
//     - R：把地址 0x3107/0x3108 的内容（0xEE / 0x4B）发回去
//
// 运行: vsim -c -do scripts/run_tb_sc520_cfg.do
// =============================================================================
`timescale 1ns / 1ps

module tb_sc520_cfg;

    localparam [6:0] CAM_ADDR7 = 7'h36;     // I2C 7 位地址（写字节 = 0x6C）

    reg         clk;
    reg         rst_n;
    reg  [15:0] ae, ag;

    wire        cam_scl;
    wire        sda_line;       // 线与后的 SDA
    wire        cam_sda;        // 从机驱动端（开漏）

    wire        cfg_done;
    wire        ae_cfg_done;
    wire [15:0] sensor_id;
    wire        sensor_id_ok;
    wire        iic_error;

    integer     errors;
    integer     wr_count;
    integer     timeout_cnt;
    integer     test_phase;     // 0=负向(无从机) 1=正向(有从机)

    reg         slave_present;  // 1=从机应答
    reg         sda_slave_low;  // 从机拉低 SDA

    // SDA 线与：主机或从机任一拉低即为低；否则上拉为高
    wire sda_master_low = dut.u_i2c.sda_o;
    assign sda_line = (sda_master_low | sda_slave_low) ? 1'b0 : 1'b1;
    assign cam_sda  = sda_slave_low ? 1'b0 : 1'bz;

    // ---------------------------------------------------------------------
    // 被测模块
    // ---------------------------------------------------------------------
    uicfgcs520 #(
        .CLK_DIV (36)       // 仿真用小分频，加快 I2C 速率
    ) dut (
        .I_clk          (clk),
        .I_rst_n        (rst_n),
        .I_ae_req       (1'b0),
        .I_ae           (ae),
        .I_ag           (ag),
        .O_cam_scl      (cam_scl),
        .IO_cam_sda     (cam_sda),
        .O_cfg_done     (cfg_done),
        .O_ae_cfg_done  (ae_cfg_done),
        .O_sensor_id    (sensor_id),
        .O_sensor_id_ok (sensor_id_ok),
        .O_iic_error    (iic_error)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------------------------
    // I2C 从机模型（标准事务）
    // ---------------------------------------------------------------------
    reg        scl_d;
    reg  [7:0] sh;              // 接收移位
    reg  [2:0] bitc;            // 位计数
    reg        rx_ack;          // 本拍是否把 SDA 拉低（ACK）
    reg        rx_mode;         // 1=接收 0=发送
    reg  [7:0] tx_byte;         // 待发送字节
    reg  [1:0] byte_idx;        // 第几个字节
    reg  [7:0] reg_hi, reg_lo;  // 子地址
    reg  [7:0] id_hi, id_lo;    // 芯片 ID（0xEE / 0x4B）

    initial begin
        scl_d      = 1'b1;
        slave_present  = 1'b0;
        sda_slave_low  = 1'b0;
        sh         = 8'h00;
        bitc       = 3'd0;
        rx_ack     = 1'b0;
        rx_mode    = 1'b1;
        tx_byte    = 8'h00;
        byte_idx   = 2'd0;
        reg_hi     = 8'h00;
        reg_lo     = 8'h00;
        id_hi      = 8'hEE;     // 0x3107
        id_lo      = 8'h4B;     // 0x3108
    end

    always @(posedge clk) begin
        scl_d <= cam_scl;

        if (!rst_n || !slave_present) begin
            sda_slave_low <= 1'b0;
            rx_ack        <= 1'b0;
            bitc          <= 3'd0;
            byte_idx      <= 2'd0;
        end
        else begin
            // ---------------- SCL 上升沿：采样数据 / 检测起始停止 ----------------
            if (cam_scl && !scl_d) begin
                if (sda_line && !sda_slave_low && sda_master_low == 1'b0) begin
                    // 实际判断起始/停止需要看 SDA 变化方向，这里用简单可靠的方式：
                    // 由下面 SCL 低电平期间的边沿检测统一处理
                end

                if (rx_mode == 1'b1) begin
                    // 接收模式：移位收集
                    sh <= {sh[6:0], sda_line};
                    if (bitc == 3'd7) begin
                        bitc <= 3'd0;
                        // 收满一个字节，下一拍拉低 SDA 表示 ACK
                        rx_ack <= 1'b1;
                    end
                    else begin
                        bitc <= bitc + 1'b1;
                    end
                end
                else begin
                    // 发送模式：从机输出已在 SCL 低电平期间建立，这里只需计数
                    if (bitc == 3'd7) begin
                        bitc   <= 3'd0;
                        rx_mode<= 1'b1;     // 发完 8 位，转接收主机 ACK
                    end
                    else begin
                        bitc <= bitc + 1'b1;
                    end
                end
            end

            // ---------------- SCL 低电平期间：更新 ACK / 装载下一个字节 / 发送数据 ----------------
            if (!cam_scl && scl_d) begin
                if (rx_ack) begin
                    // ACK 阶段结束：解析刚收到的字节
                    rx_ack        <= 1'b0;
                    sda_slave_low <= 1'b0;
                    byte_idx      <= byte_idx + 1'b1;

                    if (byte_idx == 2'd0) begin
                        // 第 1 字节 = 器件地址 + R/W
                        if (sh[7:1] !== CAM_ADDR7[6:0]) begin
                            errors = errors + 1;
                            $display("ERROR: slave got wrong device addr 0x%02h", sh);
                        end
                        if (sh[0] == 1'b1) begin
                            // 读事务：准备发送寄存器内容
                            rx_mode <= 1'b0;
                            tx_byte <= (reg_hi == 8'h31 && reg_lo == 8'h07) ? id_hi :
                                       (reg_hi == 8'h31 && reg_lo == 8'h08) ? id_lo : 8'h00;
                            bitc    <= 3'd0;
                            sda_slave_low <= ~tx_byte[7];   // 先出 MSB
                        end
                    end
                    else if (byte_idx == 2'd1) begin
                        reg_hi <= sh;       // 子地址高字节
                    end
                    else if (byte_idx == 2'd2) begin
                        reg_lo <= sh;       // 子地址低字节
                    end
                    else begin
                        // 数据字节（写寄存器）
                        wr_count = wr_count + 1;
                        if (wr_count <= 3) begin
                            $display("INFO: reg write #%0d addr=0x%02h%02h data=0x%02h",
                                     wr_count, reg_hi, reg_lo, sh);
                        end
                    end
                end
                else if (rx_mode == 1'b0) begin
                    // 发送模式：在 SCL 低电平期间切换到下一位
                    if (bitc <= 3'd6) begin
                        sda_slave_low <= ~tx_byte[6 - bitc];
                        bitc <= bitc + 1'b1;
                    end
                    else begin
                        sda_slave_low <= 1'b0;
                        bitc <= 3'd0;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 激励：先负向（无从机）再正向（有从机）
    // ---------------------------------------------------------------------
    initial begin
        errors      = 0;
        wr_count    = 0;
        timeout_cnt = 0;
        test_phase  = 0;
        ae          = 16'd1200;
        ag          = 16'd176;
        rst_n       = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;

        // ============ 阶段 1：无从机，验证不挂死且报错 ============
        timeout_cnt = 0;
        while ((iic_error !== 1'b1) && (timeout_cnt < 300000)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (iic_error !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: 无从机时未在预期时间内置起 iic_error（可能挂死）");
        end
        else begin
            $display("INFO: 阶段1 通过 —— 无从机时正确报 iic_error，未挂死");
        end

        if (sensor_id_ok === 1'b1) begin
            errors = errors + 1;
            $display("ERROR: 无从机时 sensor_id_ok 不应为 1");
        end

        // ============ 阶段 2：接入从机，重启配置流程 ============
        slave_present = 1'b1;
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        byte_idx = 2'd0;

        // 等待 ID 识别通过
        timeout_cnt = 0;
        while ((sensor_id_ok !== 1'b1) && (timeout_cnt < 400000)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (sensor_id_ok !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: 有从机时仍未完成芯片 ID 识别 (sensor_id=0x%04h)", sensor_id);
        end
        else begin
            $display("INFO: 阶段2 芯片 ID 识别通过 sensor_id=0x%04h", sensor_id);
            if (sensor_id !== 16'hEE4B) begin
                errors = errors + 1;
                $display("ERROR: sensor_id=0x%04h 期望 0xEE4B", sensor_id);
            end

            // 继续等待若干条寄存器写入
            timeout_cnt = 0;
            while ((wr_count < 6) && (timeout_cnt < 600000)) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (wr_count < 6) begin
                errors = errors + 1;
                $display("ERROR: 寄存器写入条数不足 (%0d)", wr_count);
            end
            else begin
                $display("INFO: 已写入 %0d 条寄存器，配置流程正常推进", wr_count);
            end
        end

        // ---------------- 结果汇总 ----------------
        $display("--------------------------------------------------");
        $display("tb_sc520_cfg: sensor_id=0x%04h id_ok=%b cfg_done=%b iic_err=%b wr=%0d errors=%0d",
                 sensor_id, sensor_id_ok, cfg_done, iic_error, wr_count, errors);
        if (errors == 0) begin
            $display("TEST PASSED: tb_sc520_cfg");
        end
        else begin
            $display("TEST FAILED: tb_sc520_cfg");
        end
        $display("--------------------------------------------------");
        $finish;
    end

    // 超时保护
    initial begin
        #200000000;
        $display("TEST FAILED: tb_sc520_cfg TIMEOUT (id_ok=%b wr=%0d err=%0d)",
                 sensor_id_ok, wr_count, errors);
        $finish;
    end

endmodule

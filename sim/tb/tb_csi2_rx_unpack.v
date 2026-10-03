// =============================================================================
// 文件名 : tb_csi2_rx_unpack.v
// 模块名 : tb_csi2_rx_unpack
// 功能   : csi2_rx_unpack 的自检测试平台（不需要人工看波形）。
//
// ===================== 关键：字节馈送节奏（实测确定） =====================
// csi2_rx_unpack 的字节采集逻辑是：
//   * 一个 I_hs_valid 拍，模块**依次取出 LANE_NUM 个 Lane 的字节**，
//     即 **一拍消耗 CSI_LANES 个字节**。
//     （用 trace 实测确认：CSI_LANES=2 时每拍 r_byte_vld 两次，
//       依次给出 lane0、lane1 的字节。）
//   * I_hs_data 位序：lane i 位于 [8*(i+1)-1 : 8*i]，
//     即 **lane0 在最低 8 位、lane1 在次低 8 位**。
//
// 因此本平台按"**每拍送 CSI_LANES 个字节**"馈送：
//   把待发字节流两两分组，第 1 个放 lane0、第 2 个放 lane1；
//   总字节数为奇数时最后一拍补 0x00。
//
// 早期版本"每个字节单独送一拍"（等于把字节流拉长一倍），
// 导致状态机错位解析、反复产生 frame_start —— 那是**测试平台**的问题，
// 与 RTL 无关。
//
// 测试图尺寸取 4x4（H_ACTIVE=4）：
//   每行 4 个像素，RAW10 恰好打包成 5 字节，整行对齐、便于逐字节核对。
//   像素值取 row*10 + col（唯一可区分每个位置）。
//
// 运行: vsim -c -do scripts/run_tb_csi2_rx_unpack.do
// =============================================================================
`timescale 1ns / 1ps

module tb_csi2_rx_unpack;

    localparam integer H_ACTIVE  = 4;       // 每行像素数
    localparam integer V_ACTIVE  = 4;       // 行数
    localparam integer LANES     = 2;       // 2 Lane
    localparam integer NB        = 200;     // 待发字节缓冲大小

    reg [9:0] img   [0:V_ACTIVE*H_ACTIVE-1];    // 参考图像
    reg [7:0] txbuf [0:NB-1];                   // 待发字节流
    integer   txlen;

    reg                    clk;
    reg                    rst_n;
    reg                    hs_valid;
    reg  [LANES*8-1:0]     hs_data;

    wire                   pix_valid;
    wire [11:0]            pix_data;
    wire                   frame_start, frame_end;
    wire                   line_start, line_end;
    wire [15:0]            line_cnt, pix_cnt, frame_cnt;
    wire                   err_pulse;
    wire [15:0]            err_cnt;
    wire                   line_wrap_err;

    integer errors;
    integer got_pixels;
    integer n_frame_starts;
    integer n_frame_ends;
    integer timeout_cnt;
    integer i, n, g;

    reg [LANES*8-1:0] word;

    // ---------------------------------------------------------------------
    // 例化被测模块
    // ---------------------------------------------------------------------
    csi2_rx_unpack #(
        .CSI_LANES (LANES),
        .DATA_BITS (10),
        .H_ACTIVE  (H_ACTIVE),
        .PIX_BITS  (12)
    ) dut (
        .I_clk          (clk),
        .I_rst_n        (rst_n),
        .I_hs_valid     (hs_valid),
        .I_hs_data      (hs_data),
        .O_pix_valid    (pix_valid),
        .O_pix_data     (pix_data),
        .O_frame_start  (frame_start),
        .O_frame_end    (frame_end),
        .O_line_start   (line_start),
        .O_line_end     (line_end),
        .O_line_cnt     (line_cnt),
        .O_pix_cnt      (pix_cnt),
        .O_frame_cnt    (frame_cnt),
        .O_err_pulse    (err_pulse),
        .O_err_cnt      (err_cnt),
        .O_line_wrap_err(line_wrap_err)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------------------------
    // 检查进程：每收到一个有效像素就与参考图比对
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_start) n_frame_starts = n_frame_starts + 1;
            if (frame_end)   n_frame_ends   = n_frame_ends   + 1;

            if (pix_valid) begin
                if (got_pixels < V_ACTIVE*H_ACTIVE) begin
                    if (pix_data[9:0] !== img[got_pixels]) begin
                        errors = errors + 1;
                        if (errors <= 10) begin
                            $display("ERROR: pixel %0d = 0x%03h, expected 0x%03h",
                                     got_pixels, pix_data[9:0], img[got_pixels]);
                        end
                    end
                end
                else begin
                    errors = errors + 1;
                    if (errors <= 10) begin
                        $display("ERROR: extra pixel %0d = 0x%03h (frame has %0d)",
                                 got_pixels, pix_data[9:0], V_ACTIVE*H_ACTIVE);
                    end
                end
                got_pixels = got_pixels + 1;
            end
        end
    end

    // 向缓冲追加 1 个字节
    task push_byte;
        input [7:0] b;
        begin
            txbuf[txlen] = b;
            txlen = txlen + 1;
        end
    endtask

    // ---------------------------------------------------------------------
    // 把缓冲里的字节流按 LANES 个一组送出
    // ---------------------------------------------------------------------
    task flush_txbuf;
        begin
            g = 0;
            while ((g*LANES) < txlen) begin
                word = 0;
                for (n = 0; n < LANES; n = n + 1) begin
                    if ((g*LANES + n) < txlen) begin
                        // 第 (g*LANES+n) 个字节放到 lane n
                        case (n)
                        0: word[7:0]   = txbuf[g*LANES + n];
                        1: word[15:8]  = txbuf[g*LANES + n];
                        2: word[23:16] = txbuf[g*LANES + n];
                        default: word[31:24] = txbuf[g*LANES + n];
                        endcase
                    end
                end
                @(posedge clk);
                hs_valid <= 1'b1;
                hs_data  <= word;
                g = g + 1;
            end
            @(posedge clk);
            hs_valid <= 1'b0;
            hs_data  <= 0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 激励
    // ---------------------------------------------------------------------
    initial begin
        errors         = 0;
        got_pixels     = 0;
        n_frame_starts = 0;
        n_frame_ends   = 0;
        timeout_cnt    = 0;
        txlen          = 0;
        rst_n          = 0;
        hs_valid       = 0;
        hs_data        = 0;
        word           = 0;

        // 生成参考图像：像素值 = row*10 + col
        for (i = 0; i < V_ACTIVE*H_ACTIVE; i = i + 1) begin
            img[i] = (i / H_ACTIVE) * 10 + (i % H_ACTIVE);
        end

        // ---------------- 组装一帧的字节流 ----------------
        // 1) FSYNC 短包：{VC,DT}=0x00, 帧号, ECC, ECC
        push_byte(8'h00);
        push_byte(8'h00);
        push_byte(8'h00);
        push_byte(8'h00);

        // 2) 每行一个 RAW10 长包：包头 4 字节 + 负载 5 字节
        for (i = 0; i < V_ACTIVE; i = i + 1) begin
            push_byte({2'b00, 6'h2B});      // DT = RAW10
            push_byte(8'd5);                // WC 低字节 = 5
            push_byte(8'd0);                // WC 高字节
            push_byte(8'h00);               // ECC
            // 负载：4 个像素按 RAW10 打包成 5 字节
            push_byte(img[i*H_ACTIVE+0][9:2]);
            push_byte(img[i*H_ACTIVE+1][9:2]);
            push_byte(img[i*H_ACTIVE+2][9:2]);
            push_byte(img[i*H_ACTIVE+3][9:2]);
            // 第 5 字节 = 4 个像素各自的 2 位 LSB 拼成 1 字节
            push_byte({img[i*H_ACTIVE+3][1:0], img[i*H_ACTIVE+2][1:0],
                       img[i*H_ACTIVE+1][1:0], img[i*H_ACTIVE+0][1:0]});
        end

        // 3) FEEND 短包
        push_byte(8'h01);
        push_byte(8'h00);
        push_byte(8'h00);
        push_byte(8'h00);

        // ---------------- 复位并发送 ----------------
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        flush_txbuf();

        // 等队列把剩余像素吐完
        while ((n_frame_ends == 0) && (timeout_cnt < 5000)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        repeat (30) @(posedge clk);

        // ---------------- 结果汇总 ----------------
        $display("--------------------------------------------------");
        $display("tb_csi2_rx_unpack:");
        $display("  bytes sent  = %0d", txlen);
        $display("  pixels      = %0d (expected %0d)", got_pixels, V_ACTIVE*H_ACTIVE);
        $display("  frame_start = %0d (expected 1)", n_frame_starts);
        $display("  frame_end   = %0d (expected 1)", n_frame_ends);
        $display("  errors      = %0d", errors);

        if (errors == 0 &&
            got_pixels == V_ACTIVE*H_ACTIVE &&
            n_frame_starts == 1 &&
            n_frame_ends == 1) begin
            $display("TEST PASSED: tb_csi2_rx_unpack");
        end
        else begin
            $display("TEST FAILED: tb_csi2_rx_unpack");
        end
        $display("--------------------------------------------------");
        $finish;
    end

    // 超时保护
    initial begin
        #500000;
        $display("TEST FAILED: tb_csi2_rx_unpack TIMEOUT (pixels=%0d frame_end=%0d)",
                 got_pixels, n_frame_ends);
        $finish;
    end

endmodule

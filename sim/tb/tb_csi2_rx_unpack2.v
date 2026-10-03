// =============================================================================
// 文件名 : tb_csi2_rx_unpack2.v
// 模块名 : tb_csi2_rx_unpack2
// 功能   : csi2_rx_unpack 自检 —— **按 MIPI 硬核真实行为驱动：每拍 2 个字节**。
//
// 背景：早期测试平台每拍只送 1 个字节，与被测模块"每拍取 1 字节"的错误实现
//       恰好互相匹配，于是"测试通过"但上板是噪点。
//       本平台严格按 2 Lane / 1 Byte 模式驱动：
//           I_hs_data[15:8] = lane0 的字节
//           I_hs_data[7:0]  = lane1 的字节
//       即每拍送 2 个字节（MSB 先行）。
//
// 测试图 4x4、RAW10：每行 4 像素 → 5 字节 → 需 3 拍（最后一个字节是填充）
// =============================================================================
`timescale 1ns / 1ps

module tb_csi2_rx_unpack2;

    localparam integer H_ACTIVE = 4;
    localparam integer V_ACTIVE = 4;

    reg [9:0] img [0:V_ACTIVE*H_ACTIVE-1];

    reg                    clk;
    reg                    rst_n;
    reg                    hs_valid;
    reg  [15:0]            hs_data;

    wire                   pix_valid;
    wire [11:0]            pix_data;
    wire                   frame_start, frame_end;
    wire                   line_start, line_end;
    wire [15:0]            line_cnt, pix_cnt, frame_cnt;
    wire                   err_pulse, line_wrap_err;
    wire [15:0]            err_cnt;

    integer errors, got_pixels, n_fs, n_fe, n_le;
    integer i, bi;
    reg [7:0] tx [0:255];
    integer   txlen;

    csi2_rx_unpack #(
        .CSI_LANES (2),
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

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer dbg_i; initial dbg_i = 0;
    always @(posedge clk) begin
        if (rst_n && dut.I_hs_valid && dbg_i < 34) begin
            dbg_i = dbg_i + 1;
            $display("WORD %0d = %04h", dbg_i, dut.I_hs_data);
        end
    end



    // 收集像素并比对
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_start) n_fs = n_fs + 1;
            if (frame_end)   n_fe = n_fe + 1;
            if (line_end)    n_le = n_le + 1;
            if (pix_valid) begin
                if (got_pixels < V_ACTIVE*H_ACTIVE) begin
                    if (pix_data[9:0] !== img[got_pixels]) begin
                        errors = errors + 1;
                        if (errors <= 8)
                            $display("ERROR: pix %0d = 0x%03h exp 0x%03h",
                                     got_pixels, pix_data[9:0], img[got_pixels]);
                    end
                end
                else begin
                    errors = errors + 1;
                end
                got_pixels = got_pixels + 1;
            end
        end
    end

    task push; input [7:0] b; begin tx[txlen] = b; txlen = txlen + 1; end endtask

    // 每拍送 2 字节：先送的在 I_hs_data[15:8]
    task send_all;
        begin
            bi = 0;
            hs_valid <= 1'b0;
            hs_data  <= 16'd0;
            @(posedge clk);
            while (bi < txlen) begin
                hs_data  <= {tx[bi], tx[bi+1]};      // MSB 先
                hs_valid <= 1'b1;
                @(posedge clk);
                bi = bi + 2;
            end
            hs_valid <= 1'b0;
            hs_data  <= 16'd0;
            @(posedge clk);
        end
    endtask

    integer t;
    initial begin
        errors = 0; got_pixels = 0; n_fs = 0; n_fe = 0; n_le = 0; txlen = 0;
        rst_n = 0; hs_valid = 0; hs_data = 0;

        for (i = 0; i < V_ACTIVE*H_ACTIVE; i = i + 1)
            img[i] = (i / H_ACTIVE) * 10 + (i % H_ACTIVE);

        // ---- 组装字节流 ----
        // FSYNC 短包: DT=0x00 + 帧号 + ECC×2  (4 字节)
        push(8'h00); push(8'h00); push(8'h00); push(8'h00);

        // 每行: 长包头 4 字节 + 负载 5 字节(4 像素 RAW10) + 填充 1 字节 = 10 字节
        for (i = 0; i < V_ACTIVE; i = i + 1) begin
            push({2'b00, 6'h2B});        // DT = RAW10
            push(8'd5);                  // WC 低字节 = 5 字节
            push(8'd0);                  // WC 高字节
            push(8'h00);                 // ECC
            push(img[i*H_ACTIVE+0][9:2]);
            push(img[i*H_ACTIVE+1][9:2]);
            push(img[i*H_ACTIVE+2][9:2]);
            push(img[i*H_ACTIVE+3][9:2]);
            push({img[i*H_ACTIVE+3][1:0], img[i*H_ACTIVE+2][1:0],
                  img[i*H_ACTIVE+1][1:0], img[i*H_ACTIVE+0][1:0]});
            push(8'h00);                 // 填充(凑成 10 字节 = 5 拍)
        end

        // FEEND 短包
        push(8'h01); push(8'h00); push(8'h00); push(8'h00);

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        send_all();

        t = 0;
        while ((n_fe == 0) && (t < 2000)) begin @(posedge clk); t = t + 1; end
        repeat (20) @(posedge clk);

        $display("--------------------------------------------------");
        $display("tb_csi2_rx_unpack2 (每拍 2 字节):");
        $display("  pixels      = %0d (exp %0d)", got_pixels, V_ACTIVE*H_ACTIVE);
        $display("  frame_start = %0d (exp 1)", n_fs);
        $display("  frame_end   = %0d (exp 1)", n_fe);
        $display("  line_end    = %0d (exp %0d)", n_le, V_ACTIVE);
        $display("  errors      = %0d", errors);
        if (errors == 0 && got_pixels == V_ACTIVE*H_ACTIVE &&
            n_fs == 1 && n_fe == 1 && n_le == V_ACTIVE)
            $display("TEST PASSED: tb_csi2_rx_unpack2");
        else
            $display("TEST FAILED: tb_csi2_rx_unpack2");
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin #500000; $display("TEST FAILED: TIMEOUT pixels=%0d fe=%0d", got_pixels, n_fe); $finish; end

endmodule

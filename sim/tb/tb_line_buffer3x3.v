// =============================================================================
// 文件名 : tb_line_buffer3x3.v
// 模块名 : tb_line_buffer3x3
// 功能   : line_buffer3x3 的自检测试平台（不需要人工看波形）。
//
// 测试方法:
//   1) 输入一张 8x8 的测试图，像素值 = row*16 + col（唯一可区分每个位置）。
//   2) 在输出侧对每个"完整窗口"计算期望的 3x3 邻域：
//        中心像素 (row, col) 的期望窗口为 (row-1..row+1, col-1..col+1)。
//   3) 与 DUT 输出的 9 个像素逐一比对；并检查随路信号 O_col/O_row 正确。
//   4) 任何一处不符立即打印错误并计入错误计数，末尾给出 PASS/FAIL。
//
// 运行: vsim -c -do "do scripts/run_tb_line_buffer3x3.do"
// =============================================================================
`timescale 1ns / 1ps

module tb_line_buffer3x3;

    localparam integer H       = 8;      // 图像宽度
    localparam integer V       = 8;      // 图像高度
    localparam integer DW      = 8;      // 像素位宽
    localparam integer AW      = 4;      // 地址位宽（深度 16 >= 8）

    // 原始测试图，像素值 = row*16 + col
    reg [DW-1:0] img [0:V*H-1];

    reg                clk;
    reg                rst_n;
    reg                pix_valid;
    reg  [DW-1:0]      pix_data;
    reg                frame_start;
    reg                line_end;

    wire               win_valid;
    wire [DW-1:0]      x00,x01,x02,x10,x11,x12,x20,x21,x22;
    wire [AW-1:0]      col;
    wire [15:0]        row;
    wire               pix_valid_d;
    wire               line_end_d;

    integer errors;
    integer checks;
    integer i;

    // 期望值计算用的行列号
    integer exp_row, exp_col;
    reg [DW-1:0] exp_x00,exp_x01,exp_x02,exp_x10,exp_x11,exp_x12,exp_x20,exp_x21,exp_x22;

    // ---------------- 例化被测模块 ----------------
    line_buffer3x3 #(
        .DWIDTH   (DW),
        .AWIDTH   (AW),
        .H_ACTIVE (H)
    ) dut (
        .I_clk         (clk),
        .I_rst_n       (rst_n),
        .I_pix_valid   (pix_valid),
        .I_pix_data    (pix_data),
        .I_frame_start (frame_start),
        .I_line_end    (line_end),
        .O_win_valid   (win_valid),
        .O_x00(x00), .O_x01(x01), .O_x02(x02),
        .O_x10(x10), .O_x11(x11), .O_x12(x12),
        .O_x20(x20), .O_x21(x21), .O_x22(x22),
        .O_col         (col),
        .O_row         (row),
        .O_pix_valid_d (pix_valid_d),
        .O_line_end_d  (line_end_d)
    );

    // ---------------- 时钟 ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;      // 100MHz 仿真时钟，周期 10ns
    end

    // ---------------- 期望值函数 ----------------
    // 取图像中 (r,c) 的像素；越界时返回 0（DUT 在边界会给出残留/0，仅用于完整窗口）
    function [DW-1:0] pix;
        input integer r;
        input integer c;
        begin
            if ((r < 0) || (r >= V) || (c < 0) || (c >= H)) begin
                pix = {DW{1'b0}};
            end
            else begin
                pix = img[r*H + c];
            end
        end
    endfunction

    // ---------------- 检查过程 ----------------
    always @(posedge clk) begin
        if (rst_n && win_valid && pix_valid_d) begin
            exp_row = row;
            exp_col = col;

            exp_x00 = pix(exp_row-1, exp_col-1);
            exp_x01 = pix(exp_row-1, exp_col  );
            exp_x02 = pix(exp_row-1, exp_col+1);

            exp_x10 = pix(exp_row  , exp_col-1);
            exp_x11 = pix(exp_row  , exp_col  );
            exp_x12 = pix(exp_row  , exp_col+1);

            exp_x20 = pix(exp_row+1, exp_col-1);
            exp_x21 = pix(exp_row+1, exp_col  );
            exp_x22 = pix(exp_row+1, exp_col+1);

            checks = checks + 1;

            if ({x00,x01,x02,x10,x11,x12,x20,x21,x22} !==
                {exp_x00,exp_x01,exp_x02,exp_x10,exp_x11,exp_x12,exp_x20,exp_x21,exp_x22}) begin
                errors = errors + 1;
                if (errors <= 10) begin
                    $display("ERROR @ row=%0d col=%0d", row, col);
                    $display("   got      x00..x22 = %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                             x00,x01,x02,x10,x11,x12,x20,x21,x22);
                    $display("   expected x00..x22 = %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                             exp_x00,exp_x01,exp_x02,exp_x10,exp_x11,exp_x12,
                             exp_x20,exp_x21,exp_x22);
                end
            end
        end
    end

    // ---------------- 激励 ----------------
    initial begin
        errors       = 0;
        checks       = 0;
        rst_n        = 0;
        pix_valid    = 0;
        pix_data     = 0;
        frame_start  = 0;
        line_end     = 0;

        // 生成测试图
        for (i = 0; i < V*H; i = i + 1) begin
            img[i] = ((i / H) * 16 + (i % H));
        end

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // 逐帧发送（发两帧，验证帧起始能正确复位行列计数）
        send_frame();
        send_frame();

        repeat (20) @(posedge clk);

        // ---------------- 结果汇总 ----------------
        $display("--------------------------------------------------");
        $display("line_buffer3x3: checks=%0d errors=%0d", checks, errors);
        if (errors == 0 && checks > 0) begin
            $display("TEST PASSED: tb_line_buffer3x3");
        end
        else begin
            $display("TEST FAILED: tb_line_buffer3x3");
        end
        $display("--------------------------------------------------");
        $finish;
    end

    // 发送一帧：逐行逐像素
    task send_frame;
        integer r, c;
        begin
            for (r = 0; r < V; r = r + 1) begin
                for (c = 0; c < H; c = c + 1) begin
                    @(posedge clk);
                    pix_valid   <= 1'b1;
                    pix_data    <= img[r*H + c];
                    frame_start <= (r == 0) && (c == 0);
                    line_end    <= (c == H-1);
                end
            end
            @(posedge clk);
            pix_valid   <= 1'b0;
            frame_start <= 1'b0;
            line_end    <= 1'b0;
            repeat (24) @(posedge clk);
        end
    endtask

endmodule

// Anlu2 源码说明：用像素时钟与5倍串行时钟把10位TMDS字转换成串行输出。
// 接口与使用约定：在串行域检测像素翻转标志，每拍移出两位并经器件ODDR发送；PH1P分支由顶层选用。
// 工程状态：已列入TD编译清单。




module lane_lvds_10_1 #(
    parameter DEVICE = "EG"
) (
    input wire I_pixel_clk,
    input wire I_serial_clk,
    input wire I_rst,

    input wire [9:0] I_data_in,

    output wire O_serial_out
);

    reg       S_odd_even;
    reg       S_odd_even_1d;
    reg       S_odd_even_2d;
    reg       S_load_en;
    reg       S_load_en_1d;
    reg       S_load_en_2d;
    reg [9:0] S_shift_data;
    reg [1:0] S_oddr_data;


    always @(posedge I_pixel_clk or posedge I_rst) begin
        if (I_rst) S_odd_even <= 1'b0;
        else S_odd_even <= ~S_odd_even;
    end

    always @(posedge I_serial_clk) begin
        S_odd_even_1d <= S_odd_even;
        S_odd_even_2d <= S_odd_even_1d;
    end

    always @(posedge I_serial_clk) begin
        S_load_en    <= S_odd_even_1d ^ S_odd_even_2d;
        S_load_en_1d <= S_load_en;
        S_load_en_2d <= S_load_en_1d;
    end

    always @(posedge I_serial_clk or posedge I_rst) begin
        if (I_rst) S_shift_data <= 'd0;
        else if (S_load_en_2d) S_shift_data <= I_data_in;
        else S_shift_data <= S_shift_data << 2;
    end

    always @(posedge I_serial_clk) begin
        S_oddr_data <= S_shift_data[9:8];
    end

    generate
        if (DEVICE == "EF2") begin
            EF2_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "EF3") begin
            EF3_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "EF4") begin
            EF4_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "SF1") begin
            SF1_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "EG") begin
            EG_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "PH1A") begin
            PH1_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "PH1P") begin
            PH1P_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end else if (DEVICE == "DR1") begin
            DR1_LOGIC_ODDR U_EG4_ODDR (
                .clk(I_serial_clk),
                .rst(I_rst),

                .d1(S_oddr_data[0]),
                .d0(S_oddr_data[1]),

                .q(O_serial_out)
            );
        end
    endgenerate

endmodule

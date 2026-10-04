// Anlu2 源码说明：把连续的4组96位RGB重排成3组128位DDR写数据。
// 接口与使用约定：实际模块名为data_96bit_to_128bit，主工程使用此文件；每行320个输入组形成240个DDR字，行中不得插空拍。
// 工程状态：已列入TD编译清单。



module data_96bit_to_128bit (
    input wire I_clk,
    input wire I_rst_n,

    input wire        I_96b_frame_start,
    input wire        I_96b_valid,
    input wire [95:0] I_96b_data,

    output reg         O_128b_frame_start,
    output reg         O_128b_valid,
    output reg [127:0] O_128b_data
);



    // 输入必须行内连续；行间valid=0将四组打包相位复位。
    reg [95:0] S_96b_data_1d;
    reg        S_96b_valid_1d;
    reg [ 1:0] S_cnt;


    always @(posedge I_clk) begin
        S_96b_valid_1d <= I_96b_valid;
        S_96b_data_1d <= I_96b_data;

        O_128b_frame_start <= I_96b_frame_start;
    end


    always @(posedge I_clk) begin
        if (I_96b_valid) S_cnt <= S_cnt + 'd1;
        else S_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        if (I_96b_valid) begin
            case (S_cnt)
                'd0: begin
                    O_128b_valid <= 1'b0;
                    O_128b_data  <= 'd0;
                end
                'd1: begin
                    O_128b_valid <= 1'b1;
                    O_128b_data  <= {S_96b_data_1d, I_96b_data[95:64]};
                end
                'd2: begin
                    O_128b_valid <= 1'b1;
                    O_128b_data  <= {S_96b_data_1d[63:0], I_96b_data[95:32]};
                end
                'd3: begin
                    O_128b_valid <= 1'b1;
                    O_128b_data  <= {S_96b_data_1d[31:0], I_96b_data};
                end
                default: begin
                    O_128b_valid <= 1'b0;
                    O_128b_data  <= 'd0;
                end
            endcase
        end else begin
            O_128b_valid <= 1'b0;
            O_128b_data  <= 'd0;
        end
    end



endmodule







/*
module data96_128 (

    input wire [95:0] I_tdata,

    output wire [127:0] O_tdata

);

  assign O_tdata = {
    {8'd0}, I_tdata[95:72], {8'd0}, I_tdata[71:48], {8'd0}, I_tdata[47:24], {8'd0}, I_tdata[23:0]
  };
 
endmodule
*/


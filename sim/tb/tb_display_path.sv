`timescale 1ns/1ps
// FIFO行为模型仅用于验证字节打包、读取拍数和像素顺序，不验证厂商CDC实现。
module w128_d512_fifo(input rst,clkw,we,input [127:0] di,
    output afull,full_flag,output [8:0] wrusedw,input clkr,re,
    output reg [127:0] dout,output [8:0] rdusedw,output valid,empty_flag,aempty);
    reg [127:0] mem[0:511];
    integer wp=0,rp=0;
    always @(posedge clkw) if(rst) wp<=0; else if(we) begin mem[wp]<=di;wp<=wp+1;end
    always @(posedge clkr) if(rst) begin rp<=0;dout<=0;end
        else if(re) begin dout<=mem[rp];rp<=rp+1;end
    assign wrusedw=wp-rp;assign rdusedw=wp-rp;
    assign empty_flag=(wp==rp);assign full_flag=0;assign afull=0;assign aempty=0;assign valid=re;
endmodule
module tb_display_path;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,packed_valid=0;
    reg [95:0] source=0;
    wire word_valid;wire [127:0] word_data;
    reg de=0,vs=0,hs=0,user=0,last=0;
    wire [23:0] pixel,rgb;
    wire out_de,out_vs,out_hs,protect,request;
    wire fs;
    data_96bit_to_128bit packer(clk,rst_n,1'b0,packed_valid,source,fs,word_valid,word_data);
    video_out reader(.I_rst_n(rst_n),.I_ddr_clk(clk),.O_video_out_rd_busy(),
        .I_video_in_wr_busy(1'b0),.I_video_out_rp(2'b0),.O_ddr_user_rd_en(),
        .O_ddr_user_addr(),.I_ddr_user_ready(1'b0),.I_ddr_user_rd_valid(word_valid),
        .I_ddr_user_rd_data(word_data),.I_dsi_clk(clk),.I_video_vsync(1'b0),
        .I_video_rd_en(request),.O_vdieo_data(pixel));
    hdmi_mixer #(.OSD_ENABLE(0)) mixer(.I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),
        .I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
        .I_debug_status(4'b0),.O_video_rd_en(request),.I_video_rd_data(pixel),
        .O_hdmi_vsync(out_vs),.O_hdmi_hsync(out_hs),.O_hdmi_de(out_de),
        .O_hdmi_data(rgb),.O_hdmi_protect(protect));
    function [23:0] pattern(input integer x);
        pattern={8'(x),8'(x>>3),8'(255-(x%256))};
    endfunction
    integer i,j,seen=0;
    reg [2:0] dq=0,vq=0,hq=0;
    always @(posedge clk) begin
        if(!rst_n) begin dq=0;vq=0;hq=0;end
        else begin
            dq={dq[1:0],de};vq={vq[1:0],vs};hq={hq[1:0],hs};
            #1;
            if({out_de,out_vs,out_hs} !== {dq[2],vq[2],hq[2]}) $fatal(1,"Mixer sync alignment");
            if(out_de) begin
                if(rgb !== pattern(seen)) $fatal(1,"Pixel %0d got %h expected %h",seen,rgb,pattern(seen));
                if(protect) $fatal(1,"Unexpected protection without OSD");
                seen=seen+1;
            end else if(rgb !== 0) $fatal(1,"Nonblack blanking");
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        // 两行，每行320个RGBx4输入生成240个128位字，合计480字。
        for(j=0;j<2;j=j+1) begin
            for(i=0;i<320;i=i+1) begin
                packed_valid=1;
                source={pattern(j*1280+i*4),pattern(j*1280+i*4+1),
                        pattern(j*1280+i*4+2),pattern(j*1280+i*4+3)};
                @(negedge clk);
            end
            packed_valid=0;repeat(8) @(negedge clk);
        end
        repeat(10) @(negedge clk);
        for(j=0;j<2;j=j+1) begin
            for(i=0;i<1280;i=i+1) begin
                de=1;last=(i==1279);user=(j==0 && i==0);
                @(negedge clk);
            end
            de=0;last=0;user=0;hs=1;repeat(40) @(negedge clk);hs=0;
        end
        repeat(5) @(negedge clk);
        if(seen!=2560) $fatal(1,"Pixel count %0d",seen);
        $display("PASS display_path: 2560 ordered pixels, 480 DDR words, blanking and sync");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout");end
endmodule

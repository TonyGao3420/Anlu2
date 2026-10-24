`timescale 1ns/1ps
module tb_color_diagnostic_render;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,vs=0,hs=0,de=0;
    reg [11:0] x=0,y=0;
    reg [359:0] raw_values=0;
    reg [215:0] rgb_values=0;
    wire dvs,dhs,dde,dp;wire [23:0] drgb;
    wire ovs,ohs,ode;wire [23:0] orgb;
    wire ack;
    color_diagnostic_display #(.GRAY_FRAMES(1),.UPDATE_FRAMES(1)) dut (
        .clk(clk),.rst_n(rst_n),.vs(vs),.hs(hs),.de(de),.protect(1'b0),
        .x(x),.y(y),.rgb(24'h285078),.raw_mailbox(raw_values),
        .raw_good_mailbox(9'h1ff),.raw_clip_mailbox(9'h000),.raw_toggle_async(1'b1),
        .raw_ack(ack),.rgb_means(rgb_values),.rgb_good(9'h1ff),.rgb_clip(9'h000),
        .out_vs(dvs),.out_hs(dhs),.out_de(dde),.out_protect(dp),.out_rgb(drgb)
    );
    video_enhance #(.ENABLE(0),.GAMMA_ENABLE(0),.SHARPEN_ENABLE(0),
        .CONTRAST_ENABLE(0),.SATURATION_ENABLE(0),.BRIGHTNESS_OFFSET(0),.RGB_GAIN_Q8(272)) gain (
        .clk(clk),.rst_n(rst_n),.in_vsync(dvs),.in_hsync(dhs),.in_de(dde),
        .in_protect(dp),.in_rgb(drgb),.out_vsync(ovs),.out_hsync(ohs),.out_de(ode),.out_rgb(orgb)
    );
    reg capture=0;integer file_id,pixels=0,i,a,b;
    always @(negedge clk) if(capture && ode) begin
        $fwrite(file_id,"%c%c%c",orgb[23:16],orgb[15:8],orgb[7:0]);
        pixels=pixels+1;
    end
    initial begin
        for(i=0;i<9;i++) begin
            raw_values[(i*4)*10+:10]=100+i;
            raw_values[(i*4+1)*10+:10]=200+i;
            raw_values[(i*4+2)*10+:10]=300+i;
            raw_values[(i*4+3)*10+:10]=400+i;
            rgb_values[(i*3)*8+:8]=40+i;
            rgb_values[(i*3+1)*8+:8]=80+i;
            rgb_values[(i*3+2)*8+:8]=120+i;
        end
        repeat(5) @(negedge clk);rst_n=1;
        @(negedge clk);de=1;x=800;y=500;
        repeat(12) @(negedge clk);
        if(orgb!==24'h808080) $fatal(1,"Gray was tinted/lifted by final enhancement");
        de=0;vs=1;repeat(4) @(negedge clk);vs=0;
        repeat(12) @(negedge clk);
        if(!ack || dut.raw_stats!==raw_values) $fatal(1,"CDC stats snapshot mismatch");
        file_id=$fopen("../build/color_diagnosis_20261009/diagnostic_panel_synthetic.ppm","wb");
        if(!file_id) $fatal(1,"Cannot open rendering output");
        $fwrite(file_id,"P6\n1280 720\n255\n");capture=1;
        for(b=0;b<720;b++) begin
            for(a=0;a<1280;a++) begin
                @(posedge clk);#1;de=1;x=a;y=b;
            end
            @(posedge clk);#1;de=0;
            repeat(15) @(posedge clk);
        end
        repeat(16) @(posedge clk);
        @(negedge clk);capture=0;$fclose(file_id);
        if(pixels!=1280*720) $fatal(1,"Rendered frame size mismatch: %0d",pixels);
        $display("PASS diagnostic_render: equal-channel gray, stable mailbox, 921600 full-frame pixels");
        $finish;
    end
    initial begin #20000000;$fatal(1,"render timeout");end
endmodule

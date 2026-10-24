`timescale 1ns/1ps
module tb_official_awb;
    localparam BEATS=320,FRAMES=4;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,last=0,user=0,valid=0;
    reg [95:0] data=0;
    wire ready,out_last,out_user,out_valid;wire [95:0] out_data;
    awb #(.IMG_WIDTH(1280),.IMG_HEIGHT(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(last),.I_tuser(user),.I_tdata(data),
        .I_tvalid(valid),.I_tready(ready),.O_tlast(out_last),.O_tuser(out_user),
        .O_tdata(out_data),.O_tvalid(out_valid),.O_tready(1'b1));
    function automatic [23:0] sample(input integer phase,index);
        reg [7:0] gray;
        begin
            gray=20+(index%160);
            case(phase)
                0:sample={gray,gray,gray};
                1:sample={8'd96,8'd120,8'd100};
                2:sample={8'd32,8'd160,8'd32};
                default:sample=(index%4==0)?{8'd16,8'd128,8'd16}:{8'd240,8'd128,8'd200};
            endcase
        end
    endfunction
    function automatic [95:0] beat(input integer phase,index);
        beat={sample(phase,index*4+3),sample(phase,index*4+2),sample(phase,index*4+1),sample(phase,index*4)};
    endfunction
    integer count=0,phase,index,lane,corrected=0,clipped=0;reg [23:0] p;
    always @(posedge clk)begin
        #1;
        if(rst_n && out_valid)begin
            if(count>=BEATS*FRAMES)$fatal(1,"Official AWB emitted extra beats");
            phase=count/BEATS;index=count%BEATS;
            if(phase==0 && out_data!==beat(0,index))$fatal(1,"Neutral RGB/order mismatch at beat %0d",index);
            for(lane=0;lane<4;lane=lane+1)begin
                p=out_data[lane*24+:24];
                if(phase==1)begin
                    if(p[15:8]!==120)$fatal(1,"Official AWB changed green channel");
                    if(index>150 && (p[23:16]<118 || p[7:0]<118))$fatal(1,"Official AWB failed gray-world correction");
                    if(p[23:16]>96 && p[7:0]>100)corrected=corrected+1;
                end
                if(phase==2 && index>150)begin
                    if(p[15:8]!==160 || p[23:16]<150 || p[7:0]<150)$fatal(1,"Official gain range was not restored");
                    if(dut.in_r_r1<=20'h40000 || dut.in_b_r1<=20'h40000)$fatal(1,"Old gain cap still active");
                end
                if(phase==3 && index>150 && lane!=0)begin
                    if(p!==24'hff80ff)$fatal(1,"Official highlight saturation mismatch: %h",p);
                    clipped=clipped+1;
                end
            end
            count=count+1;
        end
    end
    integer f,i;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(f=0;f<FRAMES;f=f+1)begin
            for(i=0;i<BEATS;i=i+1)begin
                @(negedge clk);valid=1;user=(i==0);last=(i==BEATS-1);data=beat(f,i);
            end
            @(negedge clk);valid=0;user=0;last=0;data=0;
            repeat(400)@(negedge clk);
        end
        if(count!=BEATS*FRAMES || corrected==0 || clipped==0)$fatal(1,"Official AWB coverage/stream length failed");
        if(ready!==1)$fatal(1,"Ready propagation changed");
        $display("PASS official_awb: neutral/order, green-cast correction, original gain range, saturation, %0d beats",count);
        $finish;
    end
    initial begin #100000;$fatal(1,"Official AWB timeout");end
endmodule

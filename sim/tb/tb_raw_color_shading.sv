`timescale 1ns/1ps
module tb_raw_color_shading;
    localparam W=64,H=32;
    localparam XL=4,YL=3,HX=4,HY=2;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cal=0,clear=0,iv=0,iu=0,il=0;
    reg [39:0] data=0;reg [9:0] dest=0;
    wire ov,ou,ol,map_valid,busy,failed;
    wire [39:0] out;wire [9:0] od;
    raw_color_shading #(.IMG_W(W),.IMG_H(H),.X_STEP_LOG(XL),.Y_STEP_LOG(YL),
       .SAMPLE_HALF_X(HX),.SAMPLE_HALF_Y(HY)) dut(
        .clk(clk),.rst_n(rst_n),.cal_request(cal),.clear_request(clear),
        .in_valid(iv),.in_user(iu),.in_last(il),.in_data(data),.in_dest(dest),
        .out_valid(ov),.out_user(ou),.out_last(ol),.out_data(out),.out_dest(od),
        .map_valid(map_valid),.cal_busy(busy),.cal_failed(failed));
    integer checked=0,mode=0,max_error=0,p,n,value,err;
    reg [42:0] ctrl_q[0:4];reg [39:0] data_q[0:4];integer mode_q[0:4];
    // Independent delayed transaction scoreboard includes gaps and SOF+valid.
    always @(posedge clk) begin
        if(!rst_n) begin
            for(n=0;n<5;n=n+1) begin ctrl_q[n]=0;data_q[n]=0;mode_q[n]=0;end
        end else begin
            for(n=4;n>0;n=n-1) begin ctrl_q[n]=ctrl_q[n-1];data_q[n]=data_q[n-1];mode_q[n]=mode_q[n-1];end
            ctrl_q[0]={30'd0,iv,iu,il,dest};data_q[0]=data;mode_q[0]=mode;
            #1;
            if({ov,ou,ol,od} !== ctrl_q[4][12:0]) $fatal(1,"LSC stream flags/dest lost alignment");
            if(ov) begin
                checked=checked+4;
                if(mode_q[4]==0 && out!==data_q[4]) $fatal(1,"Unity altered pixel/word order: %h/%h",out,data_q[4]);
                if(mode_q[4]==1) begin
                    for(p=0;p<4;p=p+1) begin
                        value=out[p*10+:10];err=(value>512)?value-512:512-value;
                        if(err>max_error)max_error=err;
                        if(err>25) $fatal(1,"Residual flat-field error >25: plane value=%d",value);
                    end
                end
                if(mode_q[4]==2) begin
                    // Red target remains red after the frozen spatial map.
                    for(p=0;p<4;p=p+1) begin
                        value=out[p*10+:10];
                        if(data_q[4][p*10+:10]==800 && value<600) $fatal(1,"Red target suppressed");
                        if(data_q[4][p*10+:10]==150 && value>180) $fatal(1,"Red target green exaggerated");
                    end
                end
            end
        end
    end
    function integer field(input integer x,input integer y);
        integer dx,dy,chan;
        begin
            dx=(x>W/2)?x-W/2:W/2-x;if(dx>(1<<XL))dx=(1<<XL);
            dy=(y>H/2)?y-H/2:H/2-y;if(dy>(1<<YL))dy=(1<<YL);
            chan=(y%2)*2+x%2;
            case(chan)
              0:field=470+(40*dx>>XL)+(20*dy>>YL);
              1:field=520;
              2:field=504;
              3:field=430+(90*dx>>XL)+(40*dy>>YL);
            endcase
        end
    endfunction
    task frame(input integer pattern);
        integer x,y,k;
        begin
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+4) begin
                    @(negedge clk);iv=1;iu=(x==0 && y==0);il=(x==W-4);dest=(x+y)%1024;
                    for(k=0;k<4;k=k+1) begin
                        if(pattern==0)data[k*10+:10]=field(x+k,y);
                        else if(pattern==1)data[k*10+:10]=0;
                        else if(pattern==2)data[k*10+:10]=(y%2==1 && k%2==1)?800:
                                               (y%2==0 && k%2==0)?120:150;
                        else data[k*10+:10]=1005;
                    end
                    // Uneven valid gaps must not advance image coordinates.
                    if(x%12==0)begin @(negedge clk);iv=0;iu=0;il=0;end
                end
                @(negedge clk);iv=0;iu=0;il=0;
                repeat(3)@(negedge clk);
            end
            repeat(1300)@(negedge clk);
        end
    endtask
    task request_cal;
        begin @(negedge clk);cal=1;@(negedge clk);cal=0;end
    endtask
    integer g;reg [11:0] held[0:35];
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        frame(0);if(map_valid)$fatal(1,"Unexpected auto calibration");
        $display("PASS LSC unity: every RAW10 bit and stream flag retained");
        request_cal();frame(0);if(!busy)$fatal(1,"Calibration did not arm/compute");
        // Computation is complete in blanking; commit and first pixel share SOF.
        mode=1;frame(0);
        if(!map_valid || failed || busy)$fatal(1,"Valid calibration failed");
        $display("PASS LSC spatial: center green / red edges corrected, max residual=%0d/1023",max_error);
        for(g=0;g<36;g=g+1)held[g]=dut.gain[g];
        mode=2;frame(2);
        for(g=0;g<36;g=g+1)if(held[g]!==dut.gain[g])$fatal(1,"Scene altered frozen gain map");
        $display("PASS LSC red target: frozen gains preserve colored scene");
        request_cal();mode=3;frame(1);
        if(!failed || !map_valid || busy)$fatal(1,"Dark calibration not rejected transactionally");
        for(g=0;g<36;g=g+1)if(held[g]!==dut.gain[g])$fatal(1,"Invalid capture replaced map");
        request_cal();frame(3);
        if(!failed || !map_valid)$fatal(1,"Clipped calibration not rejected");
        $display("PASS LSC invalid: dark/clipped captures retain previous complete map");
        @(negedge clk);clear=1;@(negedge clk);clear=0;
        mode=0;frame(0);
        if(map_valid || failed || busy)$fatal(1,"Clear failed");
        $display("PASS LSC clear: first pixel at SOF uses unity; checked %0d pixels",checked);
        $finish;
    end
    initial begin #5_000_000;$fatal(1,"LSC timeout");end
endmodule

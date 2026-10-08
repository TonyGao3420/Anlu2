`timescale 1ns/1ps
module tb_roi_target_tracker;
    localparam W=160,H=96;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,sof=0,de=0,last=0;
    reg [23:0] rgb=0;
    wire valid,done,update;
    wire [15:0] x0,y0,x1,y1,cx,cy;
    wire [19:0] area;
    roi_target_tracker #(.IMG_W(W),.IMG_H(H),.MIN_AREA(64)) dut(
        .clk(clk),.rst_n(rst_n),.in_frame_start(sof),.in_de(de),.in_line_last(last),.in_rgb(rgb),
        .target_valid(valid),.bbox_x0(x0),.bbox_y0(y0),.bbox_x1(x1),.bbox_y1(y1),
        .centroid_x(cx),.centroid_y(cy),.target_area(area),.frame_done(done),.result_update(update),
        .mask_valid(),.green_mask(),.mask_x(),.mask_y(),.dbg_roi_valid(),.dbg_color_match());
    task reset;
        begin @(negedge clk);rst_n=0;de=0;last=0;sof=0;repeat(5)@(negedge clk);
            rst_n=1;repeat(100)@(negedge clk);end
    endtask
    task start;
        begin @(negedge clk);sof=1;@(negedge clk);sof=0;end
    endtask
    integer ix,iy;
    reg coincident_sof=0,h_shape=0;
    reg [64:0] held;
    task frame(input integer a0,b0,a1,b1,input [23:0] color,
               input integer c0,d0,c1,d1,input [23:0] color2);
        begin
            held={valid,x0,y0,x1,y1};
            for(iy=0;iy<H;iy=iy+1)begin
                for(ix=0;ix<W;ix=ix+1)begin
                    @(negedge clk);de=1;last=(ix==W-1);rgb=24'h303030;
                    sof=coincident_sof && ix==0 && iy==0;
                    if(ix>=a0 && ix<=a1 && iy>=b0 && iy<=b1)rgb=color;
                    if(ix>=c0 && ix<=c1 && iy>=d0 && iy<=d1)rgb=color2;
                    if(h_shape)rgb=(((ix>=16 && ix<=18)||(ix>=33 && ix<=35)||
                        (iy>=30 && iy<=32)) && ix>=16 && ix<=35 && iy>=8 && iy<=63)?
                        24'h20A030:24'h303030;
                    #1;if({valid,x0,y0,x1,y1}!==held)$fatal(1,"Box changed within active frame");
                end
                @(negedge clk);de=0;last=0;repeat(3)@(negedge clk);
            end
            repeat(5000)@(negedge clk);
            if(!dut.regions.ready)$fatal(1,"Region processing missed blank deadline");
            start();#1;if(!done || !update)$fatal(1,"Missing atomic result");
        end
    endtask
    task color_check(input [23:0] color,input bit expected);
        begin reset();start();frame(20,20,51,59,color,-1,-1,-1,-1,0);
            if(valid!==expected)$fatal(1,"Green classifier RGB=%h expected=%b actual=%b",color,expected,valid);
            if(expected && (x0!=20 || x1!=51 || y0!=20 || y1!=59))$fatal(1,"Incorrect pixel bounds");
        end
    endtask
    reg [15:0] saved_x0,saved_y0,saved_x1,saved_y1;
    integer i;
    initial begin
        coincident_sof=1;color_check(24'h20A030,1);coincident_sof=0;
        $display("PASS green SOF: frame start coincident with first active pixel stays aligned");
        color_check(24'h20A030,1);color_check(24'h103820,1);color_check(24'hA0D8A0,1);
        color_check(24'hA8E0B0,1);color_check(24'h081808,1);
        color_check(24'hA04840,0);color_check(24'hFFAAAA,0);color_check(24'h501008,0);
        color_check(24'hC0C020,0);color_check(24'h20C0C0,0);color_check(24'hD8E0D8,0);
        color_check(24'hF8F8F8,0);color_check(24'hB020B0,0);color_check(24'h101810,0);
        $display("PASS green classifier: dark/light greens accepted; red/yellow/cyan/neutral rejected");
        reset();start();h_shape=1;frame(-1,-1,-1,-1,0,-1,-1,-1,-1,0);h_shape=0;
        if(!valid || x0<16 || x1>35 || y0<8 || y1>63 || y1-y0<50)
            $fatal(1,"Sparse connected green object lost its full extent");
        $display("PASS green hollow-object: connected H outline retains full extent");
        reset();start();frame(16,16,27,47,24'h20A030,34,16,45,47,24'h20A030);
        if(!valid || x0!=16 || x1!=27)$fatal(1,"Adjacent tile objects with six-pixel gap merged");
        $display("PASS green gap: nearby disjoint objects kept separate across adjacent buckets");
        reset();start();frame(16,16,47,63,24'h20A030,112,24,135,55,24'h20A030);
        if(!valid || x0!=16 || x1!=47 || y0!=16 || y1!=63)$fatal(1,"Separate green objects merged");
        // A larger distractor must not steal the lock from the original target.
        repeat(3)begin
            frame(16,16,47,63,24'h20A030,96,8,151,87,24'h20A030);
            if(!valid || x0!=16 || x1!=47)$fatal(1,"Lock switched to larger distractor");
        end
        $display("PASS green single-object: isolated components, largest acquisition, sticky association");
        saved_x0=x0;saved_y0=y0;saved_x1=x1;saved_y1=y1;
        for(i=0;i<8;i=i+1)begin
            frame(16+(i%2),16+(i%2),47-(i%2),63-(i%2),24'h20A030,-1,-1,-1,-1,0);
            if({x0,y0,x1,y1}!={saved_x0,saved_y0,saved_x1,saved_y1})$fatal(1,"One-pixel edge jitter moved box");
        end
        frame(16,16,39,55,24'h20A030,-1,-1,-1,-1,0);
        if(x1<43 || y1<59)$fatal(1,"Box collapsed on one-frame partial occlusion");
        repeat(12)frame(16,16,39,55,24'h20A030,-1,-1,-1,-1,0);
        if(x1>41 || y1>57)$fatal(1,"Stable smaller target never converged");
        $display("PASS green stability: edge deadband, bounded shrink, stable size convergence");
        frame(-1,-1,-1,-1,0,-1,-1,-1,-1,0);if(!valid)$fatal(1,"One-frame dropout flickered");
        frame(16,16,39,55,24'h20A030,-1,-1,-1,-1,0);if(!valid)$fatal(1,"Dropout recovery failed");
        repeat(3)frame(16,16,39,55,24'hA04840,-1,-1,-1,-1,0);
        if(valid)$fatal(1,"Red object retained green ROI after hold timeout");
        $display("PASS green release: brief hold, reacquisition, red-only scene releases after three frames");
        frame(112,24,143,71,24'h20A030,-1,-1,-1,-1,0);
        if(!valid || x0!=112 || x1!=143)$fatal(1,"Far target full-frame reacquisition failed");
        $display("PASS ROI acquire: green-only isolated stable object and frame-atomic updates");
        $finish;
    end
    initial begin #100_000_000;$fatal(1,"Green ROI timeout");end
endmodule

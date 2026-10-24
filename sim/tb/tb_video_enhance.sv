`timescale 1ns/1ps
module tb_video_enhance;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [27:0] sample=0;
    wire [26:0] result, bypass, gamma_only;
    video_enhance dut(clk,rst_n,sample[27],sample[26],sample[25],sample[24],
                      sample[23:0],result[26],result[25],result[24],result[23:0],12'd0,12'd0);
    video_enhance #(.ENABLE(0)) dut_bypass(clk,rst_n,sample[27],sample[26],
                      sample[25],sample[24],sample[23:0],
                      bypass[26],bypass[25],bypass[24],bypass[23:0],12'd0,12'd0);
    video_enhance #(.SHARPEN_ENABLE(0)) dut_gamma(clk,rst_n,sample[27],sample[26],
                      sample[25],sample[24],sample[23:0],
                      gamma_only[26],gamma_only[25],gamma_only[24],gamma_only[23:0],12'd0,12'd0);
    integer fd, rc, n=0, pixels=0;
    reg [27:0] stim;
    reg [26:0] a,b,c,qa[0:5],qb[0:5],qc[0:5];
    initial begin
        qa[0]=0;qa[1]=0;qa[2]=0;qa[3]=0;qa[4]=0;qa[5]=0;
        qb[0]=0;qb[1]=0;qb[2]=0;qb[3]=0;qb[4]=0;qb[5]=0;
        qc[0]=0;qc[1]=0;qc[2]=0;qc[3]=0;qc[4]=0;qc[5]=0;
        repeat(4) @(negedge clk);
        rst_n=1;
        fd=$fopen("enhance_vectors.txt","r");
        if(fd==0) $fatal(1,"Missing vectors");
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %h\n",stim,a,b,c);
            if(rc==4) begin
                sample=stim;
                qa[5]=qa[4];qa[4]=qa[3];qa[3]=qa[2];qa[2]=qa[1];qa[1]=qa[0];qa[0]=a;
                qb[5]=qb[4];qb[4]=qb[3];qb[3]=qb[2];qb[2]=qb[1];qb[1]=qb[0];qb[0]=b;
                qc[5]=qc[4];qc[4]=qc[3];qc[3]=qc[2];qc[2]=qc[1];qc[1]=qc[0];qc[0]=c;
                @(posedge clk); #1;
                if(result !== qa[5]) $fatal(1,"Enhanced mismatch cycle %0d got %h expected %h",n,result,qa[5]);
                if(bypass !== qb[5]) $fatal(1,"Bypass mismatch cycle %0d",n);
                if(gamma_only !== qc[5]) $fatal(1,"Gamma mismatch cycle %0d",n);
                if(result[24]) pixels=pixels+1;
                n=n+1; @(negedge clk);
            end
        end
        // 异步复位必须立即撤销 DE，不能留下一个伪像素。
        #1 rst_n=0; #1;
        if(result !== 0 || bypass !== 0) $fatal(1,"Reset did not clear output");
        $display("PASS video_enhance cycles=%0d pixels=%0d (3 modes)",n,pixels);
        $finish;
    end
    initial begin #50000000; $fatal(1,"Timeout"); end
endmodule

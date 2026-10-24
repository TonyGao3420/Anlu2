`timescale 1ns/1ps
module tb_color_diagnostic;
    localparam W=128,H=96,HX=8,HY=4;
    reg clk=0;always #5 clk=~clk;
    reg hclk=0;always #7 hclk=~hclk;
    reg rst_n=0,valid=0,user=0,last=0;
    reg [39:0] data=0;
    reg ack=0,auto_ack=0;
    wire display_ack;
    wire toggle;
    wire [359:0] raw_means;
    wire [8:0] raw_good,raw_clip;
    color_raw_probe #(.W(W),.H(H),.HX(HX),.HY(HY)) raw_dut (
        .clk(clk),.rst_n(rst_n),.valid(valid),.user(user),.last(last),.data(data),
        .ack_async(auto_ack?display_ack:ack),.publish_toggle(toggle),.means(raw_means),.good(raw_good),.clipped(raw_clip)
    );
    reg de=0;reg [11:0] x=0,y=0;reg [23:0] rgb=0;
    wire [215:0] rgb_means;
    wire [8:0] rgb_good,rgb_clip;
    wire rgb_ready;
    color_rgb_probe #(.W(W),.H(H),.HX(HX),.HY(HY)) rgb_dut (
        .clk(hclk),.rst_n(rst_n),.de(de),.x(x),.y(y),.rgb(rgb),
        .means(rgb_means),.good(rgb_good),.clipped(rgb_clip),.ready(rgb_ready)
    );
    integer row,col,n,cx,cy;
    function automatic integer node_at(input integer a,b);
        integer i,xx,yy;
        begin
            node_at=-1;
            for(i=0;i<9;i++) begin
                xx=(i%3==0)?12:((i%3==1)?64:116);
                yy=(i/3==0)?12:((i/3==1)?48:84);
                if(a>=xx-HX && a<xx+HX && b>=yy-HY && b<yy+HY) node_at=i;
            end
        end
    endfunction
    task automatic send_raw(input integer scenario);
        integer a,b,j,m,values[0:3];
        begin
            for(b=0;b<H;b++) begin
                for(a=0;a<W;a+=4) begin
                    @(negedge clk);
                    user=(a==0 && b==0);valid=1;last=(a==W-4);
                    m=node_at(a,b);
                    for(j=0;j<4;j++) begin
                        if(m<0) values[j]=128;
                        else if(!b[0]) values[j]=(j%2==0)?100+m:200+m;
                        else values[j]=(j%2==0)?300+m:400+m;
                        if(scenario==1 && m==8) values[j]=1008;
                    end
                    data={10'(values[3]),10'(values[2]),10'(values[1]),10'(values[0])};
                    if(scenario==2 && b==12 && a==8) valid=0;
                end
                @(negedge clk);valid=0;user=0;last=0;
                repeat(2) @(negedge clk);
            end
            @(negedge clk);valid=0;user=0;last=0;
        end
    endtask
    task automatic send_rgb(input integer scenario);
        integer a,b,m;
        begin
            for(b=0;b<H;b++) begin
                for(a=0;a<W;a++) begin
                    @(negedge hclk);de=1;x=a;y=b;m=node_at(a,b);
                    rgb=(m<0)?24'h808080:{8'(40+m),8'(80+m),8'(120+m)};
                    if(scenario==1 && m==8) rgb=24'hfffefe;
                    if(scenario==2 && b==12 && a==8) de=0;
                end
                @(negedge hclk);de=0;
                repeat(2) @(negedge hclk);
            end
            @(negedge hclk);de=0;
        end
    endtask
    reg [359:0] saved;
    reg saved_toggle;
    reg vs=0;
    wire ovs,ohs,ode,op;
    wire [23:0] orgb;
    color_diagnostic_display #(.GRAY_FRAMES(2),.UPDATE_FRAMES(1)) display_dut (
        .clk(hclk),.rst_n(rst_n),.vs(vs),.hs(1'b0),.de(de),.protect(1'b0),
        .x(x),.y(y),.rgb(rgb),.raw_mailbox(raw_means),
        .raw_good_mailbox(raw_good),.raw_clip_mailbox(raw_clip),
        .raw_toggle_async(toggle),.raw_ack(display_ack),.rgb_means(rgb_means),
        .rgb_good(rgb_good),.rgb_clip(rgb_clip),
        .out_vs(ovs),.out_hs(ohs),.out_de(ode),.out_protect(op),.out_rgb(orgb)
    );
    task automatic pulse_vs;
        @(negedge hclk);vs=1;
        repeat(3) @(negedge hclk);
        vs=0;repeat(3) @(negedge hclk);
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        fork send_raw(0);send_rgb(0);join
        repeat(5) @(negedge clk);
        if(raw_good!==9'h1ff || raw_clip!==0 || rgb_good!==9'h1ff || rgb_clip!==0)
            $fatal(1,"Clean field quality/count mismatch RAW %h/%h RGB %h/%h",raw_good,raw_clip,rgb_good,rgb_clip);
        for(n=0;n<9;n++) begin
            if(raw_means[(n*4)*10+:10]!==10'(100+n) ||
               raw_means[(n*4+1)*10+:10]!==10'(200+n) ||
               raw_means[(n*4+2)*10+:10]!==10'(300+n) ||
               raw_means[(n*4+3)*10+:10]!==10'(400+n))
                $fatal(1,"RAW phase/window mean mismatch at node %0d",n);
            if(rgb_means[(n*3)*8+:8]!==8'(40+n) ||
               rgb_means[(n*3+1)*8+:8]!==8'(80+n) ||
               rgb_means[(n*3+2)*8+:8]!==8'(120+n))
                $fatal(1,"RGB window mean mismatch at node %0d",n);
        end
        saved=raw_means;saved_toggle=toggle;
        fork send_raw(1);send_rgb(1);join
        if(raw_means!==saved || toggle!==saved_toggle)
            $fatal(1,"Mailbox changed before destination ack");
        ack=toggle;repeat(5) @(negedge clk);
        send_raw(1);
        if(raw_clip!==9'h100 || rgb_clip!==9'h100) $fatal(1,"Highlight flags missing");
        ack=toggle;repeat(5) @(negedge clk);
        fork send_raw(2);send_rgb(2);join
        if(raw_good===9'h1ff || rgb_good===9'h1ff) $fatal(1,"Truncated field accepted");
        // Pure gray really is equal RGB and protected from the 17/16 gain.
        @(negedge hclk);de=1;x=800;y=500;rgb=24'h285078;
        repeat(4) @(negedge hclk);
        if(!ode || !op || orgb!==24'h808080) $fatal(1,"Gray diagnostic mismatch");
        de=0;auto_ack=1;pulse_vs();pulse_vs();
        if(display_ack!==toggle || display_dut.raw_stats!==raw_means)
            $fatal(1,"Destination did not receive/ack complete RAW mailbox");
        repeat(5) @(negedge clk);send_raw(0);
        repeat(5) @(negedge hclk);pulse_vs();
        if(display_ack!==toggle || display_dut.raw_stats!==raw_means || display_dut.raw_ok!==9'h1ff)
            $fatal(1,"Coupled asynchronous mailbox lost/corrupted next field");
        @(negedge hclk);de=1;x=800;y=500;rgb=24'h285078;
        repeat(4) @(negedge hclk);
        if(orgb!==24'h285078 || op) $fatal(1,"Camera pass-through mismatch");
        de=0;repeat(4) @(negedge hclk);
        if(ode || orgb!==0) $fatal(1,"Blanking mismatch");
        $display("PASS color_diagnostic: nine RAW/RGB windows, Bayer planes, mailbox hold, clipping, incomplete frames, gray/pass-through");
        $finish;
    end
    initial begin #10000000;$fatal(1,"diagnostic timeout");end
endmodule

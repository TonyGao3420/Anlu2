`timescale 1ns/1ps
module tb_display_edge_color;
reg clk=0;always #5 clk=~clk;reg rst_n=0,vs=0,hs=0,de=0,p=0;reg [23:0] rgb=0,e=0,f=0;
wire ov,oh,od,op;wire [23:0] out;wire bv,bh,bd,bp;wire [23:0] bypass_rgb;
display_edge_color dut(clk,rst_n,vs,hs,de,p,rgb,ov,oh,od,op,out);
display_edge_color #(.ENABLE(0)) bypass(clk,rst_n,vs,hs,de,p,rgb,bv,bh,bd,bp,bypass_rgb);
wire ev,eh,ed;wire [23:0] ergb;reg [5:0] protect6=0;
always @(posedge clk)if(!rst_n)protect6<=0;else protect6<={protect6[4:0],op};
video_enhance #(.ENABLE(0),.GAMMA_ENABLE(0),.SHARPEN_ENABLE(0),.CONTRAST_ENABLE(0),.SATURATION_ENABLE(0),.RGB_GAIN_Q8(256))
enhance(.clk(clk),.rst_n(rst_n),.in_vsync(ov),.in_hsync(oh),.in_de(od),.in_protect(op),.in_rgb(out),.out_vsync(ev),.out_hsync(eh),.out_de(ed),.out_rgb(ergb));
wire tv,th,td;wire [23:0] tone_rgb;
display_common_tone tone(clk,rst_n,ev,eh,ed,protect6[5],ergb,tv,th,td,tone_rgb);
reg [23:0] eq[0:5],rawq[0:5],fq[0:14];reg [3:0] cq[0:14];integer j,checked=0;
always @(posedge clk)begin
 if(!rst_n)begin for(j=0;j<6;j=j+1)begin eq[j]=0;rawq[j]=0;end for(j=0;j<15;j=j+1)begin fq[j]=0;cq[j]=0;end end
 else begin
 for(j=5;j>0;j=j-1)begin eq[j]=eq[j-1];rawq[j]=rawq[j-1];end
 for(j=14;j>0;j=j-1)begin fq[j]=fq[j-1];cq[j]=cq[j-1];end
 eq[0]=de?e:0;rawq[0]=de?rgb:0;fq[0]=de?f:0;cq[0]={vs,hs,de,p};
 #1;
 if({ov,oh,od,op,out}!=={cq[5],eq[5]})$fatal(1,"Edge RGB/control mismatch pixel%0d got%h want%h",checked,out,eq[5]);
 if({bv,bh,bd,bp,bypass_rgb}!=={cq[5],rawq[5]})$fatal(1,"Edge bypass mismatch");
 if({tv,th,td,tone_rgb}!=={cq[14][3:1],fq[14]})$fatal(1,"Complete display branch tone/protect mismatch got%h want%h",tone_rgb,fq[14]);
 if(od)checked=checked+1;
 end
end
integer fd,n,protect_value,x,y;
initial begin
 repeat(5)@(negedge clk);rst_n=1;vs=1;repeat(8)@(negedge clk);vs=0;repeat(20)@(negedge clk);
 fd=$fopen("../build/edge_color_20261009/display_edge_vectors.txt","r");if(!fd)$fatal(1,"Missing vectors");
 for(y=0;y<720;y=y+1)begin
 for(x=0;x<1280;x=x+1)begin
 @(negedge clk);n=$fscanf(fd,"%h %h %h %d\n",rgb,e,f,protect_value);if(n!=4)$fatal(1,"Bad vector");de=1;p=protect_value;
 if(x%37==36)begin @(negedge clk);de=0;p=0;end
 end
 @(negedge clk);de=0;p=0;hs=1;repeat(5)@(negedge clk);hs=0;repeat(20)@(negedge clk);
 end
 repeat(30)@(negedge clk);
 if(checked!=921600)$fatal(1,"Display pixel count");
 $display("PASS display_edge_color: 921600 pixels, all positions, center exact, black/clipping, OSD, bubbles, bypass and complete 15-cycle display/tone controls");$finish;
end
initial begin #15000000;$fatal(1,"Edge display timeout");end
endmodule

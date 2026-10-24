`timescale 1ns/1ps
module tb_raw_measured_shading;
reg clk=0;always #5 clk=~clk;reg rst_n=0,v=0,u=0,l=0;reg [39:0] d=0,e=0;reg [9:0] dest=0;
wire ov,ou,ol,bv,bu,bl;wire [39:0] od,bd;wire [9:0] odst,bdst;
raw_measured_shading dut(clk,rst_n,v,u,l,d,dest,ov,ou,ol,od,odst);
raw_measured_shading #(.ENABLE(0)) bypass(clk,rst_n,v,u,l,d,dest,bv,bu,bl,bd,bdst);
reg [39:0] exp[0:7],inp[0:7];reg [9:0] ds[0:7];reg [7:0] vp=0,up=0,lp=0;integer j,checked=0;
always @(posedge clk)begin
 if(rst_n)begin
 for(j=7;j>0;j=j-1)begin exp[j]=exp[j-1];inp[j]=inp[j-1];ds[j]=ds[j-1];end
 exp[0]=e;inp[0]=d;ds[0]=dest;vp={vp[6:0],v};up={up[6:0],u};lp={lp[6:0],l};
 #1;
 if({ov,ou,ol,odst}!=={vp[7],up[7],lp[7],ds[7]} || {bv,bu,bl,bdst}!=={vp[7],up[7],lp[7],ds[7]})$fatal(1,"RAW metadata/latency mismatch");
 if(ov)begin
 if(od!==exp[7] || bd!==inp[7])$fatal(1,"RAW lane/phase/coordinate/black error beat%0d got %h wanted %h",checked,od,exp[7]);
 checked=checked+1;
 end
 end
end
integer fd,n,uu,ll,dd,count=0;
initial begin
 for(j=0;j<8;j=j+1)begin exp[j]=0;inp[j]=0;ds[j]=0;end
 repeat(5)@(negedge clk);rst_n=1;
 fd=$fopen("../build/raw_color_bright_20261009/raw_vectors.txt","r");if(!fd)$fatal(1,"Missing vectors");
 while(!$feof(fd))begin
 @(negedge clk);n=$fscanf(fd,"%h %h %d %d %d\n",d,e,uu,ll,dd);
 if(n!=5)$fatal(1,"Bad vector");v=1;u=uu;l=ll;dest=dd;count=count+1;
 if(count%37==0)begin @(negedge clk);v=0;u=0;l=0;end
 end
 @(negedge clk);v=0;u=0;l=0;repeat(20)@(negedge clk);
 if(checked!=230400)$fatal(1,"RAW pixel count");
 $display("PASS raw_measured_shading: 230400 four-lane beats, all raster coordinates, bubbles, black, clipping, bypass and metadata");$finish;
end
endmodule

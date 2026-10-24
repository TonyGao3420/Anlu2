from pathlib import Path
import json,random
root=Path('Anlu2');out=root/'sim/build/raw_color_bright_20261009';tb=root/'sim/tb';g=json.loads((out/'calibration.json').read_text())['gain_q10_BGGR'];tone=json.loads((out/'tone_gain.json').read_text())
def rawgain(x,y,ch):
 col=0 if x<640 else 1;row=0 if y<360 else 1;n=row*3+col
 fx=max(0,min(256,(x-(128 if col==0 else 640))//2));fy=0 if y<=90 else 256 if y>=630 else ((y-(90 if row==0 else 360))*243+128)>>8
 a=g[n][ch]+((g[n+1][ch]-g[n][ch])*fx+128>>8);b=g[n+3][ch]+((g[n+4][ch]-g[n+3][ch])*fx+128>>8)
 return a+((b-a)*fy+128>>8)
random.seed(520)
with (out/'raw_vectors.txt').open('w') as f:
 for y in range(720):
  for x in range(0,1280,4):
   orig=[];expected=[]
   for l in range(4):
    v=[0,63,64,65,128,256,512,900,1023,random.randrange(1024)][(x//4+y+l)%10]
    orig.append(v);expected.append(v if v<=64 else min(1023,64+(((v-64)*rawgain(x+l,y,2*(y%2)+l%2)+512)>>10)))
   pack=lambda a:sum(v<<(10*l) for l,v in enumerate(a))
   f.write(f'{pack(orig):010x} {pack(expected):010x} {int(x==0 and y==0)} {int(x==1276)} {(y*320+x//4)%1024}\n')
raw=r'''`timescale 1ns/1ps
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
'''
(tb/'tb_raw_measured_shading.sv').write_text(raw)
# Tone vectors include all gray levels, colored highlights, dark floor, OSD protected.
def tonepixel(p):
 a=[p>>16,(p>>8)&255,p&255];gain=tone[max(a)];return sum((v if v<=14 else min(255,14+(((v-14)*gain+128)>>8)))<<(16-8*i) for i,v in enumerate(a))
colors=[v*0x10101 for v in range(256)]+[0,0xffffff,0x00ff00,0xb4ffb4,0xbeffc6,0x281418]+[random.randrange(1<<24) for _ in range(12000)]
with (out/'tone_vectors.txt').open('w') as f:
 for i,p in enumerate(colors):
  protect=int(i%11==0);de=int(i%29!=0);expected=0 if not de else p if protect else tonepixel(p)
  f.write(f'{p:06x} {expected:06x} {de} {protect} {int(i%53==0)} {int(i%7==0)}\n')
tonetb=r'''`timescale 1ns/1ps
module tb_display_common_tone;
reg clk=0;always #5 clk=~clk;reg rst_n=0,vs=0,hs=0,de=0,p=0;reg [23:0] rgb=0,e=0;
wire ov,oh,od;wire [23:0] o;
display_common_tone dut(clk,rst_n,vs,hs,de,p,rgb,ov,oh,od,o);
reg [23:0] ep[0:2];reg [2:0] vp=0,hp=0,dp=0;integer j,checked=0;
always @(posedge clk)if(rst_n)begin
 ep[2]=ep[1];ep[1]=ep[0];ep[0]=e;vp={vp[1:0],vs};hp={hp[1:0],hs};dp={dp[1:0],de};
 #1;if({ov,oh,od,o}!=={vp[2],hp[2],dp[2],ep[2]})$fatal(1,"Tone mismatch %0d got%h expected%h",checked,o,ep[2]);checked=checked+1;
end
integer fd,n,a,b,c,d,count=0;
initial begin
 for(j=0;j<3;j=j+1)ep[j]=0;
 repeat(5)@(negedge clk);rst_n=1;
 fd=$fopen("../build/raw_color_bright_20261009/tone_vectors.txt","r");
 while(!$feof(fd))begin
 @(negedge clk);n=$fscanf(fd,"%h %h %d %d %d %d\n",rgb,e,a,b,c,d);if(n!=6)$fatal(1,"Bad tone vector");de=a;p=b;vs=c;hs=d;count=count+1;
 end
 @(negedge clk);de=0;p=0;vs=0;hs=0;rgb=0;e=0;repeat(5)@(negedge clk);
 $display("PASS display_common_tone: %0d gray/color/highlight/OSD and timing vectors",count);$finish;
end
endmodule
'''
(tb/'tb_display_common_tone.sv').write_text(tonetb)
awbtb=r'''`timescale 1ns/1ps
module tb_awb_frame_stable;
localparam W=1280,H=8,N=W/4*H,F=6;
reg clk=0;always #5 clk=~clk;reg rst_n=0,v=0,u=0,l=0;reg [95:0] data=0;
wire ov,ou,ol,ready;wire [95:0] od;
awb_frame_stable #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) dut(clk,rst_n,l,u,data,v,ready,ol,ou,od,ov,1'b1);
function automatic [23:0] sample(input integer f,beat,lane);
 reg [7:0] r,g,b;
 begin
 if(f==2)begin r=14;g=14;b=14;end
 else if(f==3)begin r=100;g=100;b=100;end
 else if(lane==0)begin r=100;g=140;b=80;if(beat<160 && f==1)begin r=50;g=160;b=40;end end
 else begin r=40+((beat*3+lane*7)%215);g=30+((beat+lane)%200);b=20+((beat*7+lane*11)%230);end
 sample={r,g,b};
 end
endfunction
function automatic [7:0] correct(input [7:0] v,input [19:0] gain);
 reg [31:0] product;integer t;
 begin product=(v>14?v-14:0)*gain;t=(product>>16)+14;correct=v<=14?v:(t>255?255:t);end
endfunction
function automatic [19:0] approach(input [19:0] a,b);
 begin approach=b>=a?a+((b-a+3)>>2):a-((a-b+3)>>2);end
endfunction
reg [19:0] gr[0:F-1],gb[0:F-1];integer out_count=0,fidx,bidx,j,clipped=0;reg [23:0] pix,expected;
always @(posedge clk)begin
 #1;
 if(rst_n && ov)begin
 fidx=out_count/N;bidx=out_count%N;if(fidx>=F)$fatal(1,"Extra AWB pixels");
 for(j=0;j<4;j=j+1)begin
 pix=sample(fidx,bidx,j);expected={correct(pix[23:16],gr[fidx]),pix[15:8],correct(pix[7:0],gb[fidx])};
 if(od[j*24+:24]!==expected)$fatal(1,"Frame AWB value/order f%0d beat%0d lane%0d got%h expected%h",fidx,bidx,j,od[j*24+:24],expected);
 if(expected[23:16]==255 || expected[7:0]==255)clipped=clipped+1;
 end
 if(dut.in_r_r1!==gr[fidx] || dut.in_b_r1!==gb[fidx])$fatal(1,"AWB changed gain within active frame");
 out_count=out_count+1;
 end
end
integer f,y,x,k;reg [31:0] sr,sg,sb;reg [19:0] cr,cb;reg [23:0] p;
initial begin
 repeat(5)@(negedge clk);rst_n=1;cr=65536;cb=65536;
 for(f=0;f<F;f=f+1)begin
 if(f==0)begin gr[f]=65536;gb[f]=65536;end
 else if(f==1)begin gr[f]=cr;gb[f]=cb;end
 else if(f==3)begin gr[f]=gr[f-1];gb[f]=gb[f-1];end
 else begin gr[f]=approach(gr[f-1],cr);gb[f]=approach(gb[f-1],cb);end
 sr=1;sg=1;sb=1;
 for(y=0;y<H;y=y+1)begin
 for(x=0;x<W/4;x=x+1)begin
 @(negedge clk);v=1;u=(x==0&&y==0);l=(x==W/4-1);
 for(k=0;k<4;k=k+1)data[k*24+:24]=sample(f,y*(W/4)+x,k);
 p=sample(f,y*(W/4)+x,0);if(f!=2)begin sr=sr+p[23:16]-14;sg=sg+p[15:8]-14;sb=sb+p[7:0]-14;end
 end
 @(negedge clk);v=0;u=0;l=0;data=0;repeat(120)@(negedge clk);
 end
 repeat(200)@(negedge clk);
 if(f!=2)begin cr=({16'd0,sg,16'd0}/sr);cb=({16'd0,sg,16'd0}/sb);
 if(!dut.candidate_valid || dut.candidate_r!==cr || dut.candidate_b!==cb)$fatal(1,"Completed frame statistics wrong f%0d samples%0d got%h/%h expected%h/%h",f,dut.samples,dut.candidate_r,dut.candidate_b,cr,cb);
 end else if(dut.candidate_valid)$fatal(1,"Covered lens replaced AWB gains");
 if(out_count!=(f+1)*N)$fatal(1,"AWB stream count f%0d got%0d",f,out_count);
 end
 if(clipped==0 || ready!==1)$fatal(1,"Missing coverage");
 $display("PASS awb_frame_stable: six frames, full-frame statistics, frozen gains, black, empty frame hold, slew, four-lane order and saturation");$finish;
end
initial begin #500000;$fatal(1,"Frame AWB timeout");end
endmodule
'''
(tb/'tb_awb_frame_stable.sv').write_text(awbtb)
for name,files in {
 'raw_measured_shading':['../../user_source/hdl_source/isp/raw_measured_shading.v','../tb/tb_raw_measured_shading.sv'],
 'display_common_tone':['../../user_source/hdl_source/video/display_common_tone.v','../tb/tb_display_common_tone.sv'],
 'awb_frame_stable':['../../user_source/hdl_source/awb_frame_stable.v','../../user_source/hdl_source/signal_delay.v','../tb/official_awb_models.sv','../tb/tb_awb_frame_stable.sv']}.items():
 (root/f'sim/modelsim/run_{name}.do').write_text('transcript on\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv '+' '.join(files)+f'\nvsim -c work.tb_{name}\nrun -all\nquit -f\n')
print('Generated full 720p RAW independent-model vectors and tests for tone/frame AWB.')

from pathlib import Path
import json,random
root=Path('Anlu2');case=root/'sim/build/edge_color_20261009';tone=json.loads((root/'sim/build/raw_color_bright_20261009/tone_gain.json').read_text())
def rgain(x,y):
 l=min(256,(max(0,384-x)*171+128)>>8);r=min(256,(max(0,x-896)*171+128)>>8);t=(max(0,216-y)*303+128)>>8;b=(max(0,y-504)*303+128)>>8
 lc=128+(t>>2)-((b*3)>>3);rc=80-(t>>3)+(b>>4)
 return 1024-((l*lc+r*rc+t*64+b*32+128)>>8),1024-((l*32-r*64+t*32+b*16+128)>>8)
def edge(p,x,y):
 r,g,b=(p>>16),(p>>8)&255,p&255;gr,gb=rgain(x,y)
 fix=lambda v,k:v if v<=14 else min(255,14+(((v-14)*k+512)>>10))
 return (fix(r,gr)<<16)+(g<<8)+fix(b,gb)
def bright(p):
 a=[p>>16,(p>>8)&255,p&255];gain=tone[max(a)];return sum((v if v<=14 else min(255,14+(((v-14)*gain+128)>>8)))<<(16-8*i) for i,v in enumerate(a))
random.seed(520)
mn=9999;mx=0;maxstep=0;count=0
with (case/'display_edge_vectors.txt').open('w') as f:
 for y in range(720):
  for x in range(1280):
   palette=[0x000000,0x0e0e0e,0xffffff,0x00ff00,0xa0e0a8,0x103820,0xbeffc6,0xff0000,0x0000ff,random.randrange(1<<24)]
   p=palette[(x+y)%10];protect=int((32<=x<=287 and 32<=y<=255) or ((x+y)%101==0));expected=p if protect else edge(p,x,y);final=expected if protect else bright(expected)
   f.write(f'{p:06x} {expected:06x} {final:06x} {protect}\n');count+=1
   a,b=rgain(x,y);mn=min(mn,a,b);mx=max(mx,a,b)
   if x:aa,bb=rgain(x-1,y);maxstep=max(maxstep,abs(a-aa),abs(b-bb))
   if y:aa,bb=rgain(x,y-1);maxstep=max(maxstep,abs(a-aa),abs(b-bb))
   if 384<=x<=896 and 216<=y<=504:assert a==b==1024
assert mn>=768 and mx<=1088 and maxstep<=2,(mn,mx,maxstep)
(case/'model_checks.json').write_text(json.dumps({'display_vectors':count,'residual_gain_min':mn,'residual_gain_max':mx,'max_adjacent_pixel_step_q10':maxstep,'center_rectangle_exact_unity':True,'photo_not_used_as_exact_sensor_measurement':True},indent=2)+'\n')
tb=r'''`timescale 1ns/1ps
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
'''
(root/'sim/tb/tb_display_edge_color.sv').write_text(tb)
s='transcript on\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/tb_display_edge_color.sv\nvsim -c work.tb_display_edge_color\nrun -all\nquit -f\n';(root/'sim/modelsim/run_display_edge_color.do').write_text(s)
print('Generated',count,'display edge + tone independent vectors; range',mn,mx,'maxstep',maxstep)


from pathlib import Path
import json
root=Path('Anlu2');out=root/'sim/build/raw_color_bright_20261009';g=json.loads((out/'calibration.json').read_text())['gain_q10_BGGR']
def gain(x,y,c):
 col=int(x>=640);row=int(y>=360);n=3*row+col;fx=max(0,min(256,(x-(128 if col==0 else 640))//2));fy=0 if y<=90 else 256 if y>=630 else ((y-(90 if row==0 else 360))*243+128)>>8
 a=g[n][c]+(((g[n+1][c]-g[n][c])*fx+128)>>8);b=g[n+3][c]+(((g[n+4][c]-g[n+3][c])*fx+128)>>8);return a+(((b-a)*fy+128)>>8)
with (out/'isp_flat_inverse.txt').open('w') as f:
 for y in range(720):
  for x in range(0,1280,4):
   vals=[]
   for l in range(4):
    ch=2*(y%2)+(l%2);target=[180,240,240,200][ch];gg=gain(x+l,y,ch);vals.append(64+((target-64)*1024+gg//2)//gg)
   f.write(f'{sum(v<<(10*l) for l,v in enumerate(vals)):010x}\n')
models=''
for name,width in [('blk_mem_gen_zhenghe',32),('blk_mem_gen_demosaic',33)]:
 models+=f'''module {name}(input [{width-1}:0] dia,input [10:0] addra,input wea,clka,input [10:0] addrb,input clkb,input [{width-1}:0] dib,input web,output [{width-1}:0] doa,output reg [{width-1}:0] dob);
reg [{width-1}:0] mem[0:2047];integer j;initial for(j=0;j<2048;j=j+1)mem[j]=0;
always @(posedge clka)if(wea)mem[addra]<=dia;
always @(posedge clkb)begin dob<=mem[addrb];if(web)mem[addrb]<=dib;end
assign doa=0;
endmodule
'''
(root/'sim/tb/isp_ram_models.sv').write_text(models)
tb=r'''`timescale 1ns/1ps
module tb_isp_raw_color;
reg clk=0;always #5 clk=~clk;reg rst_n=0,v=0,u=0,l=0;reg [39:0] d=0;wire ov,ou,ol,ready;wire [127:0] od;
isp_top dut(.axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_tlast(l),.I_tuser(u),.I_tdata(d),.I_tvalid(v),.I_tdest(10'd0),.O_tready(1'b1),.O_tdata(od),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.I_tready(ready));
reg [39:0] raw[0:230399];integer f=0,x,y,n,packed_count=0,awb_count=0,checks=0;
integer i,r,g,b,minc,maxc;reg [23:0] p;reg [19:0] frozen_r,frozen_b;
always @(posedge clk)begin
 #1;
 if(rst_n)begin
 if(ov)begin if((^od)===1'bx)$fatal(1,"Packed unknown data");packed_count=packed_count+1;end
 if(dut.awb_O_tvalid)begin
  if(dut.u_awb.in_r_r1!==frozen_r || dut.u_awb.in_b_r1!==frozen_b)$fatal(1,"ISP AWB gain scan variation");
  if(f==2 && awb_count/320>16 && awb_count/320<704 && awb_count%320>4 && awb_count%320<316)begin
   for(i=0;i<4;i=i+1)begin
    p=dut.awb_O_tdata[i*24+:24];r=p[23:16];g=p[15:8];b=p[7:0];
    minc=(r<g?r:g);if(b<minc)minc=b;maxc=(r>g?r:g);if(b>maxc)maxc=b;
    if((^p)===1'bx || maxc-minc>3 || minc<55 || maxc>65)$fatal(1,"Integrated neutral shading wrong beat%0d lane%0d rgb%h",awb_count,i,p);
    checks=checks+1;
   end
  end
  awb_count=awb_count+1;
 end
 end
end
initial begin
 $readmemh("../build/raw_color_bright_20261009/isp_flat_inverse.txt",raw);
 repeat(8)@(negedge clk);rst_n=1;
 for(f=1;f<=2;f=f+1)begin
 packed_count=0;awb_count=0;
 for(y=0;y<720;y=y+1)begin
 for(x=0;x<320;x=x+1)begin @(negedge clk);v=1;u=(x==0&&y==0);l=(x==319);d=raw[y*320+x];end
 @(negedge clk);v=0;u=0;l=0;d=0;
 // First-line data has not reached AWB yet; its SOF precedes active output.
 if(y==0)begin repeat(1100)@(negedge clk);frozen_r=dut.u_awb.in_r_r1;frozen_b=dut.u_awb.in_b_r1;end
 else repeat(100)@(negedge clk);
 end
 repeat(3000)@(negedge clk);
 $display("ISP f%0d AWB beats %0d packed %0d samples %0d candidate %b",f,awb_count,packed_count,dut.u_awb.samples,dut.u_awb.candidate_valid);
 if(awb_count!=230400 || packed_count!=172800 || dut.u_awb.beats!=230400 || !dut.u_awb.candidate_valid)$fatal(1,"ISP complete-frame length/candidate failed");
 end
 if(checks<800000)$fatal(1,"Missing neutral spatial coverage");
 $display("PASS isp_raw_color: two complete 720p frames through real RAW/demosaic/AWB/packer RTL; %0d neutral pixels; constant frame gains",checks);$finish;
end
initial begin #9000000;$fatal(1,"ISP timeout");end
endmodule
'''
# Freeze just before the first output, avoiding assumptions about demosaic latency.
tb=tb.replace('reg [19:0] frozen_r,frozen_b;','reg [19:0] frozen_r,frozen_b;').replace('if(dut.awb_O_tvalid)begin','if(dut.awb_O_tvalid)begin\n  if(awb_count==0)begin frozen_r=dut.u_awb.in_r_r1;frozen_b=dut.u_awb.in_b_r1;end')
(root/'sim/tb/tb_isp_raw_color.sv').write_text(tb)
files=['isp/isp_top.v','isp/raw_measured_shading.v','awb_frame_stable.v','signal_delay.v']+['isp/demosaic_4x_2_0/'+f+'.v' for f in ['demosaic','bilinear_interpolation','raw_matrix_3x3_buffer','line_buffer_demosaic','mipi_to_raw_converter','zhenghe']]+['isp/data128_96/data128_96.v','isp/data96_128/data96_128.v']
s='transcript on\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv '+' '.join('../../user_source/hdl_source/'+f for f in files)+' ../tb/official_awb_models.sv ../tb/isp_ram_models.sv ../tb/tb_isp_raw_color.sv\nvsim -c work.tb_isp_raw_color\nrun -all\nquit -f\n'
(root/'sim/modelsim/run_isp_raw_color.do').write_text(s)
print('Integrated ISP test prepared.')

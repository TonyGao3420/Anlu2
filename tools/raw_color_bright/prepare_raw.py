from pathlib import Path
import json,hashlib,shutil,statistics
root=Path('Anlu2');bak=root/'sim/build/backup_raw_color_bright_20261009'
paths=['user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/isp/isp_top.v','user_source/hdl_source/video/scene_color_stream.v','td_project/camera_to_dsi_display.al']
for p in paths:
 q=bak/p;q.parent.mkdir(parents=True,exist_ok=True)
 assert not q.exists(),p
 shutil.copy2(root/p,q)
manifest=json.loads((root/'sim/build/SC520_shared_color_green_roi_20261009_manifest.json').read_text())
for p,h in manifest['source_sha256'].items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
(bak/'before_sha256.json').write_text(json.dumps(manifest['source_sha256'],indent=2)+'\n')
# Values read from FPGA numeric RAW panel, not phone pixel colors.
hexrows=['0C6 13A 134 10C','0D0 131 137 110','0B6 0E8 0E0 0E3',
 '0CB 118 10F 110','0D5 15A 159 111','0BF 0F0 0F0 0EC',
 '0BE 103 0F7 0F8','0CA 136 132 0F0','0B0 0E5 0E4 0D2']
rows=[[int(v,16) for v in s.split()] for s in hexrows]
black=64;gs=[(a[1]+a[2])/2-black for a in rows]
rref=statistics.median((a[3]-black)/g for a,g in zip(rows,gs))
bref=statistics.median((a[0]-black)/g for a,g in zip(rows,gs))
gains=[]
for a,g in zip(rows,gs):
 gains.append([round(1024*bref*g/(a[0]-black)),round(1024*g/(a[1]-black)),round(1024*g/(a[2]-black)),round(1024*rref*g/(a[3]-black))])
assert all(768<=g<=1536 for row in gains for g in row)
report={'source':'numeric RAW white-field panel 0cd0cb898d378aefd5260e57609c96b7.jpg',
 'user_confirmed_dark_raw_interval':[64,65],'selected_black':64,
 'raw_BGGR':rows,'gain_q10_BGGR':gains,'reference_r_over_g':rref,'reference_b_over_g':bref,
 'reference_method':'median channel/mean-green ratios after black subtraction; preserve global sensor response for full-frame AWB',
 'transcription_note':'Node2 B last hex digit appears 6; 5/6 ambiguity changes its signal/gain by <1%. Other supplied black readings are intervals, not an exact per-node table.',
 'interpolation':'nine-point per Bayer plane; four lanes each use their own horizontal fraction; clamp outside measured rectangle'}
(root/'sim/build/raw_color_bright_20261009/calibration.json').write_text(json.dumps(report,indent=2)+'\n')
case='\n'.join(f"            6'd{n*4+c}: gain_node=12'd{gains[n][c]};" for n in range(9) for c in range(4))
rtl=r'''// Static measured BGGR shading, before demosaic/AWB. Four pixels per beat.
// Eight clocks: fixed latency for data/valid/user/last/dest, no backpressure.
// Black 64 is measured, not guessed. No key-driven calibration or new pins.
module raw_measured_shading #(
 parameter integer W=1280,H=720,BLACK_LEVEL=64,ENABLE=1
)(
 input wire clk,rst_n,in_valid,in_user,in_last,
 input wire [39:0] in_data,input wire [9:0] in_dest,
 output wire out_valid,out_user,out_last,
 output reg [39:0] out_data,output wire [9:0] out_dest
);
 reg [11:0] x,y;
 wire [11:0] px=in_user?12'd0:x,py=in_user?12'd0:y;
 function [11:0] gain_node;
 input [5:0] index;
 begin case(index)
@CASES@
 default:gain_node=12'd1024;
 endcase end endfunction
 reg [7:0] vp,up,lp;
 reg [39:0] raw[0:6];reg [9:0] dest[0:7];
 assign out_valid=vp[7];assign out_user=up[7];assign out_last=lp[7];assign out_dest=dest[7];
 reg [8:0] fx1[0:3],fy1,fy2,fy3;
 reg [11:0] a[0:3],b[0:3],c[0:3],d[0:3];
 reg signed [23:0] top_product[0:3],bottom_product[0:3],vertical[0:3];
 reg [11:0] top_base2[0:3],bottom_base2[0:3],top3[0:3],bottom3[0:3],base4[0:3],gain5[0:3],gain6[0:3];
 reg [9:0] signal6[0:3];reg [21:0] product7[0:3];
 integer i,l,xx,tl,ch,index,fy,dy;
 function [9:0] finish;
 input [9:0] original;input [21:0] product;
 reg [22:0] lifted;
 begin
 lifted=BLACK_LEVEL+((product+23'd512)>>10);
 if(!ENABLE || original<=BLACK_LEVEL)finish=original;
 else if(lifted>1023)finish=1023;
 else finish=lifted[9:0];
 end endfunction
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 x<=0;y<=0;vp<=0;up<=0;lp<=0;out_data<=0;fy1<=0;fy2<=0;fy3<=0;
 for(i=0;i<7;i=i+1)raw[i]<=0;
 for(i=0;i<8;i=i+1)dest[i]<=0;
 for(l=0;l<4;l=l+1)begin
  fx1[l]<=0;a[l]<=1024;b[l]<=1024;c[l]<=1024;d[l]<=1024;
  top_product[l]<=0;bottom_product[l]<=0;vertical[l]<=0;
  top_base2[l]<=1024;bottom_base2[l]<=1024;top3[l]<=1024;bottom3[l]<=1024;
  base4[l]<=1024;gain5[l]<=1024;gain6[l]<=1024;signal6[l]<=0;product7[l]<=0;
 end
 end else begin
 if(in_user)begin x<=0;y<=0;end
 if(in_valid)begin
  if(in_last)begin x<=0;y<=py+1'b1;end else begin x<=px+4;y<=py;end
 end
 vp<={vp[6:0],in_valid};up<={up[6:0],in_user};lp<={lp[6:0],in_last};
 raw[0]<=in_data;for(i=1;i<7;i=i+1)raw[i]<=raw[i-1];
 dest[0]<=in_dest;for(i=1;i<8;i=i+1)dest[i]<=dest[i-1];
 if(py<=90)fy=0;else if(py>=630)fy=256;
 else begin dy=(py<360)?py-90:py-360;fy=(dy*243+128)>>8;end
 fy1<=fy;fy2<=fy1;fy3<=fy2;
 for(l=0;l<4;l=l+1)begin
  xx=px+l;tl=((py<360)?0:3)+((xx<640)?0:1);
  ch=(py[0]?2:0)+(l%2);index=tl*4+ch;
  a[l]<=gain_node(index);b[l]<=gain_node(index+4);c[l]<=gain_node(index+12);d[l]<=gain_node(index+16);
  if(xx<=128)fx1[l]<=0;else if(xx>=1152)fx1[l]<=256;
  else fx1[l]<=(xx-((xx<640)?128:640))>>1;
  top_product[l]<=($signed({1'b0,b[l]})-$signed({1'b0,a[l]}))*$signed({1'b0,fx1[l]});
  bottom_product[l]<=($signed({1'b0,d[l]})-$signed({1'b0,c[l]}))*$signed({1'b0,fx1[l]});
  top_base2[l]<=a[l];bottom_base2[l]<=c[l];
  top3[l]<=$signed({1'b0,top_base2[l]})+((top_product[l]+24'sd128)>>>8);
  bottom3[l]<=$signed({1'b0,bottom_base2[l]})+((bottom_product[l]+24'sd128)>>>8);
  vertical[l]<=($signed({1'b0,bottom3[l]})-$signed({1'b0,top3[l]}))*$signed({1'b0,fy3});
  base4[l]<=top3[l];gain5[l]<=$signed({1'b0,base4[l]})+((vertical[l]+24'sd128)>>>8);
  signal6[l]<=(raw[4][l*10+:10]>BLACK_LEVEL)?raw[4][l*10+:10]-BLACK_LEVEL:0;
  gain6[l]<=gain5[l];product7[l]<=signal6[l]*gain6[l];
  out_data[l*10+:10]<=finish(raw[6][l*10+:10],product7[l]);
 end
 end end
endmodule
'''.replace('@CASES@',case)
(root/'user_source/hdl_source/isp/raw_measured_shading.v').write_text(rtl,encoding='ascii')
print('RAW reference ratios:',rref,bref);print('RAW gains Q10:',gains)

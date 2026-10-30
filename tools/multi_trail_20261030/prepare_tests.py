from pathlib import Path
import json,hashlib,re
r=Path(__file__).resolve().parents[2];tag='multi_trail_20261030'
b=r/'sim/build'/tag;tb=r/'sim/tb'/tag;ref=r/'sim/reference'/tag
for d in (b,tb,ref):d.mkdir(exist_ok=True,parents=True)
project=r/'td_project/camera_to_dsi_display.al';project_text=project.read_text(encoding='utf-8-sig')
relocated=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+(r/'td_project').as_posix()+m[2],project_text,count=1)
if relocated!=project_text:project.write_text(relocated,encoding='utf-8')
s=(ref/'trail_before.v').read_text(encoding='utf-8-sig')
for n in ['roi_motion_trail','roi_trail_point_filter','video_ms_clock']:s=s.replace(n,'before_'+n)
(ref/'trail_reference.v').write_text(s,encoding='utf-8')
# Independent integer oracle: eight point streams, per-target conditioning and
# timestamped line segments. No DUT hierarchy is used to predict display RGB.
W,H,N=256,128,320
states=[None]*8;history=[];front=0;stim=[];masks=[];counts=[]
def line(a,c):
 x,y=a;ex,ey=c;dx=abs(ex-x);dy=abs(ey-y);sx=1 if x<ex else -1;sy=1 if y<ey else -1;err=dx-dy;bits=0
 while True:
  bits|=1<<(y*(W//4)+x)
  if (x,y)==(ex,ey):return bits
  e=2*err
  if e>=-dy:err-=dy;x+=sx
  if e<=dx:err+=dx;y+=sy
for f in range(N):
 now=(65000+f*17+(200 if f>=200 else 0))&65535
 valid=255 if f<65 or 170<=f<245 else (254 if f<85 else 0)
 if 40<=f<46:valid &= ~(1<<3) # mid-history loss/reacquisition must break only that path
 centers=[(20+min(f,75)*2,8+16*i) for i in range(8)]
 centers[6]=(110+((f%3)-1)*3,8+16*6) # independent near-stationary jitter
 centers[7]=(20+min(f,75)*2,118+min(f,75)//12) # shallow diagonal
 if 46<=f<60:centers[3]=(200,8+16*3) # do not bridge the missing interval
 xs=sum(x<<(12*i) for i,(x,y) in enumerate(centers));ys=sum(y<<(12*i) for i,(x,y) in enumerate(centers))
 stim.append((now<<200)|(valid<<192)|(xs<<96)|ys)
 masks.append(front)
 for i,(x,y) in enumerate(centers):
  st=states[i]
  if st is None:st={'seed':False,'sample':None,'linked':False};states[i]=st
  if not (valid>>i)&1:st['seed']=False;st['linked']=False;continue
  restart=not st['seed'] or ((now-st['last'])&65535)>150
  mx=x if restart else sorted([x,st['x0'],st['x1']])[1]
  my=y if restart else sorted([y,st['y0'],st['y1']])[1]
  def smooth(v,m,old):
   delta=abs(m-((old+2)>>2))
   return v*4 if restart else (m*4 if delta>320 else (old if delta<=4 else (old+m*4+1)>>1))
  sx=smooth(x,mx,st.get('sx',0));sy=smooth(y,my,st.get('sy',0))
  st.update(seed=True,last=now,sx=sx,sy=sy,x1=x if restart else st['x0'],y1=y if restart else st['y0'],x0=x,y0=y)
  if st['sample'] is None or ((now-st['sample'])&65535)>=50:
   gx=((sx+2)>>2)>>2;gy=((sy+2)>>2)>>2
   link=st['linked'] and ((now-st['sample'])&65535)<=150 and abs(gx-st['gx'])<=80 and abs(gy-st['gy'])<=80
   history.append([now,i,gx,gy,link,True]);st.update(sample=now,linked=True,gx=gx,gy=gy)
   history=history[-256:]
 # Builder invalidates expired entries permanently; scanning is interleaved
 # chronologically, while geometric predecessors are independent per slot.
 previous=[None]*8;front=0
 for e in history:
  ts,i,x,y,link,good=e
  if ((now-ts)&65535)>=1000:e[5]=False;good=False
  if not good:previous[i]=None;continue
  start=previous[i] if link and previous[i] is not None else (x,y)
  front|=line(start,(x,y));previous[i]=(x,y)
 counts.append(len(history))
(b/'stim.hex').write_text('\n'.join(f'{v:054x}' for v in stim)+'\n',encoding='utf-8')
(b/'mask.hex').write_text('\n'.join(f'{v:0{W*H//16//4}x}' for v in masks)+'\n',encoding='utf-8')
(b/'counts.hex').write_text('\n'.join(f'{v:x}' for v in counts)+'\n',encoding='utf-8')
# Preserve the original single-object tests, plus compare current display path
# against the just-published main (not an older pre-calibration version).
old=ref/'top_before.v'
parts=[]
for name,p in [('previous_path',old),('multi_path',r/'user_source/hdl_source/design_top_wrapper.v')]:
 s=p.read_text(encoding='utf-8-sig');decl=s[s.index('    wire         S_hdmi_vsync;'):s.index('    reg          S_dbg_raw_seen;')]
 region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
 if name=='previous_path':region=region.replace('roi_motion_trail #(','before_roi_motion_trail #(')
 parts.append(f'''module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,input sw1,sw2,sw3,output ov,oh,od,output [23:0] rgb);
 localparam CAMERA_ROTATE_180=1,CALIBRATION_MODE=0;
 {decl}
 wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
 wire I_sw1=sw1,I_sw2=sw2,I_sw3=sw3;wire O_servo_pan,O_servo_tilt;wire [3:0] S_hdmi_debug_status=0;
 wire [23:0] S_latency_us=24'd33450;wire [15:0] S_latency_id=16'd42;wire S_latency_valid=1;
 assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
 assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
 {region}
 assign ov=S_dbg_vs;assign oh=S_dbg_hs;assign od=S_dbg_de;assign rgb=S_dbg_rgb;
 endmodule
 ''')
(b/'display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
s=(ref/'display_template.sv').read_text(encoding='utf-8-sig').replace('baseline_path base','previous_path base')
s=s.replace('fc!=4','fc!=8').replace('Four boxes','Eight boxes').replace('j<4','j<8').replace('fx=240+(j%2)*550;fy=170+(j/2)*300','fx=120+(j%4)*270;fy=170+(j/4)*300')
s=s.replace('reg clk=0;', 'reg [7:0] sampled_slots=0;\n reg clk=0;')
s=s.replace('integer input_frame=0', '''always @(posedge clk)if(rst && dut.u_motion_trail.multi_record)
  sampled_slots[dut.u_motion_trail.multi_entry[2:0]]<=1;
 integer input_frame=0''')
s=s.replace('if(combo_pixels!=W*H', 'if(sampled_slots!==8\'hff)$fatal(1,"Actual main failed to sample all eight targets");\n     if(combo_pixels!=W*H')
s=s.replace('PASS combo_integration:', 'PASS eight_trail_display:')
(tb/'tb_display.sv').write_text(s,encoding='utf-8')
common=(ref/'display_compile_template.do').read_text(encoding='utf-8-sig')
common=common.replace('../models/resource_combo_20261030/display_paths.v',f'../build/{tag}/display_paths.v ../reference/{tag}/trail_reference.v')
common=common.replace('../tb/resource_combo_20261030/tb_combo.sv',f'../tb/{tag}/tb_display.sv')
for case,content in [('display',common),('units',f'''onerror {{quit -code 1 -f}}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../reference/{tag}/trail_reference.v ../tb/{tag}/tb_multi_trail.sv
vsim -c work.tb_multi_trail
run -all
quit -f
''')]:
 d=r/'sim'/f'run_multi_trail_{case}';d.mkdir(exist_ok=True);(d/'run.do').write_text(content,encoding='utf-8')
d=r/'sim/run_multi_trail_budget';d.mkdir(exist_ok=True)
(d/'run.do').write_text(f'''onerror {{quit -code 1 -f}}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../tb/{tag}/tb_budget.sv
vsim -c work.tb_multi_trail_budget
run -all
quit -f
''',encoding='utf-8')
print('Prepared independent eight-path bitmap oracle and latest-main display regression')

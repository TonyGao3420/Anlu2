from pathlib import Path
import json,random,math
root=Path('Anlu2');out=root/'sim/build/color_trial_20261009';points=json.loads((out/'calibration.json').read_text())['points']
def gain(x,y,c):
 col=0 if x<640 else 1;row=0 if y<360 else 1;n=row*3+col
 fx=0 if x<=128 else 256 if x>=1152 else (x-(128 if x<640 else 640))//2
 fy=0 if y<=90 else 256 if y>=630 else ((y-(90 if y<360 else 360))*243+128)//256
 table=[p[c] for p in points]
 t=table[n]+((table[n+1]-table[n])*fx+128)//256
 b=table[n+3]+((table[n+4]-table[n+3])*fx+128)//256
 g=t+((b-t)*fy+128)//256
 # Compare quantized hardware against independent floating bilinear geometry.
 u=max(0,min(1,(x-(128 if col==0 else 640))/512))
 v=max(0,min(1,(y-(90 if row==0 else 360))/270))
 exact=(1-v)*((1-u)*table[n]+u*table[n+1])+v*((1-u)*table[n+3]+u*table[n+4])
 assert abs(g-exact)<1.3,(x,y,g,exact)
 return g
def apply(x,y,rgb,p,de):
 if not de:return 0
 if p:return rgb
 r,g,b=(rgb>>16)&255,(rgb>>8)&255,rgb&255
 def ch(c,gn):return c if c<=14 else min(255,14+((c-14)*gn+128)//256)
 return (ch(r,gain(x,y,'r_gain_q8'))<<16)|(g<<8)|ch(b,gain(x,y,'b_gain_q8'))
cases=[]
for p in points:
 rgb=(p['rgb'][0]<<16)|(p['rgb'][1]<<8)|p['rgb'][2]
 result=apply(p['x'],p['y'],rgb,0,1)
 vals=[(result>>16)&255,(result>>8)&255,result&255]
 assert max(vals)-min(vals)<=1
 cases.append((p['x'],p['y'],rgb,0,1))
# Smooth gain everywhere, including boundaries/clamping.
for y in [0,89,90,91,359,360,361,629,630,631,719]:
 for c in ['r_gain_q8','b_gain_q8']:
  gs=[gain(x,y,c) for x in range(1280)]
  assert max(abs(a-b) for a,b in zip(gs,gs[1:]))<=1
  for x in [0,127,128,129,639,640,641,1151,1152,1153,1279]:
   for rgb in [0,0x0e0e0e,0x0f0f0f,0xffffff,0xff0000,0x00ff00,0x0000ff,0x00ffff,0x808080]:
    cases.extend([(x,y,rgb,0,1),(x,y,rgb,1,1),(x,y,rgb,0,0)])
rng=random.Random(520)
for _ in range(12000):cases.append((rng.randrange(1280),rng.randrange(720),rng.randrange(1<<24),rng.randrange(5)==0,rng.randrange(10)!=0))
with (out/'correction_vectors.txt').open('w') as f:
 for i,(x,y,rgb,p,de) in enumerate(cases):
  vs=int(i%713==0);hs=int(i%137<3);expected=apply(x,y,rgb,p,de)
  f.write(f'{x:03x} {y:03x} {rgb:06x} {int(p):x} {int(de):x} {vs:x} {hs:x} {expected:06x}\n')
print('PASS: nine neutral nodes, continuous gain, floating-reference error bound.',len(cases),'vectors')

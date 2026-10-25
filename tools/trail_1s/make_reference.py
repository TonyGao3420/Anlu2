"""Independent numerical trajectory model and complete-frame bitmap oracle."""
from pathlib import Path
from collections import deque
import json,math
root=Path(__file__).resolve().parents[2];dest=root/'sim/build/trail_1s_20261025';dest.mkdir(parents=True,exist_ok=True)
W,H,N,HT,JUMP=256,144,240,320,128
GW,GH=W//4,H//4;HIST=256
jit=[(-3,-2),(2,3),(0,-1),(-2,2),(3,-3),(1,0),(-1,1)]
rows=[];true_centers=[]
for f in range(N):
 now=(65000+(f*33)//2+(200 if f>=95 else 0))&65535
 en,clear,pv=1,0,1
 if f<40:tx,ty=42,42
 elif f<110:tx,ty=36+(f-40)*2,74+int(12*math.sin((f-40)/17))
 elif f<120:tx,ty=180,82;pv=0
 elif f<140:tx,ty=216-(f-120),100
 elif f<225:tx,ty=196,100;pv=0
 else:tx,ty=20+(f-225)*2,24
 jx,jy=jit[f%len(jit)];x=max(0,min(W-1,tx+jx));y=max(0,min(H-1,ty+jy))
 if f==60:x,y=232,6
 if 225<=f<230:en=0
 if f==231:x=W
 if f==233:x,y=W-1,H-1
 if f==234:clear=1
 rows.append((en,clear,pv,now,x,y));true_centers.append((tx,ty))

def raster_line(mask,a,b):
 x,y=a;xx,yy=b;dx=abs(xx-x);dy=abs(yy-y);sx=1 if x<xx else -1;sy=1 if y<yy else -1;error=dx-dy
 while True:
  mask[y*GW+x]=1
  if (x,y)==(xx,yy):return
  twice=2*error
  if twice>=-dy:error-=dy;x+=sx
  if twice<=dx:error+=dx;y+=sy

def run(smooth,ttl,interval):
 history=deque(maxlen=HIST);raw=deque(maxlen=2);q=None;last_ms=0
 previous=None;sample_started=False;deadline=0;pending=None
 fronts=[];sample_flags=[];coords=[];record_counts=[];front=[0]*(GW*GH)
 for f,(en,clear,pv,now,x,y) in enumerate(rows):
  if pending is not None:front=pending
  good=pv and x<W and y<H
  if not en or clear:
   history.clear();raw.clear();q=None;previous=None;sample_started=False;front=[0]*(GW*GH);pending=None
   fronts.append(front.copy());sample_flags.append(False);coords.append((x,y));record_counts.append(0);continue
  gap=(now-last_ms)&65535
  if smooth and good:
   if q is None or gap>150:filtered=(x,y);q=(x*4,y*4);raw.clear()
   else:
    med=tuple(sorted([v,raw[-1][a],raw[0][a]])[1] for a,v in enumerate((x,y)))
    out=[]
    for a,v in enumerate(med):
     delta=abs(v-((q[a]+2)//4))
     out.append(v*4 if delta>JUMP else (q[a] if delta<=4 else (q[a]+v*4+1)//2))
    q=tuple(out);filtered=tuple((v+2)//4 for v in q)
   if not raw:raw.append((x,y))
   raw.append((x,y));last_ms=now
  else:filtered=(x,y)
  if not good:raw.clear();q=None
  age=(now-deadline)&65535
  due=interval==0 or not sample_started or age<32768
  record=not good or previous is None or due
  if record:
   gx,gy=filtered[0]//4,filtered[1]//4
   linked=good and previous is not None and ((now-previous[2])&65535)<=150 and abs(gx-previous[0])<=JUMP//4 and abs(gy-previous[1])<=JUMP//4
   history.append([now,good,linked,gx,gy]);previous=(gx,gy,now) if good else None
   if not good or not sample_started or not linked and previous is None or age>=interval:deadline=(now+interval)&65535
   else:deadline=(deadline+interval)&65535
   sample_started=bool(good)
  mask=[0]*(GW*GH);last=None
  for entry in history:
   if ((now-entry[0])&65535)>=ttl:entry[1]=False
   if entry[1]:
    end=(entry[3],entry[4]);raster_line(mask,last if last is not None and entry[2] else end,end);last=end
   else:last=None
  pending=mask;fronts.append(front.copy());sample_flags.append(bool(record));coords.append(filtered);record_counts.append(len(history))
 return fronts,sample_flags,coords,record_counts
fronts,records,coords,counts=run(True,1000,50)
old_fronts,_,_,_=run(False,3000,0)
(dest/'smooth_stim.hex').write_text(''.join(f'{(en<<50)|(cl<<49)|(pv<<48)|(ms<<32)|(x<<16)|y:013x}\n' for en,cl,pv,ms,x,y in rows),encoding='ascii')
for name,masks in [('smooth_front',fronts),('raw_front',old_fronts)]:
 (dest/(name+'.hex')).write_text(''.join(f'{sum(b<<i for i,b in enumerate(m)) :0{GW*GH//4}x}\n' for m in masks),encoding='ascii')
(dest/'smooth_meta.hex').write_text(''.join(f'{(int(records[i])<<41)|(counts[i]<<32)|(coords[i][0]<<16)|coords[i][1]:011x}\n' for i in range(N)),encoding='ascii')
def variation(points):return sum(abs(a[0]-b[0])+abs(a[1]-b[1]) for a,b in zip(points,points[1:]))
raw_variation=variation([(v[4],v[5]) for v in rows[:40]]);filtered_variation=variation(coords[:40])
assert filtered_variation<raw_variation/4
assert 11<=sum(records[:40])<=15
assert not any(fronts[218])
metrics={'geometry':[W,H,HT,N],'raw_stationary_total_variation':raw_variation,'filtered_stationary_total_variation':filtered_variation,
 'jitter_variation_reduction_percent':100*(raw_variation-filtered_variation)/raw_variation,'records_in_first_40_frames':sum(records[:40]),'raw_frames':40,
 'settings':{'ttl_ms':1000,'sample_interval_ms':50,'median_points':3,'iir_alpha':'1/2','deadband_pixels':4},'synthetic_input':True}
(dest/'smooth_reference_metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
print('Reference generated:',metrics)

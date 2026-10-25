"""Independent complete-frame numpy reference (no streaming RTL state model)."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw

root=Path(__file__).resolve().parents[2]
vectors=root/'sim/build/style_mode_20261025/vectors';vectors.mkdir(parents=True,exist_ok=True)
preview=root/'sim/build/style_mode_20261025/preview';preview.mkdir(exist_ok=True)
def fixture(w,h,f):
 y,x=np.indices((h,w),dtype=np.int32)
 a=np.empty((h,w,3),dtype=np.uint8)
 a[:,:,0]=105+(x//5+y//7+f*3)%35
 a[:,:,1]=116+(x//11+y//4+f*7)%32
 a[:,:,2]=125+(x//13+y//9+f*2)%30
 image=Image.fromarray(a);d=ImageDraw.Draw(image)
 def rect(box,color):d.rectangle(tuple(int(t) for t in box),fill=color)
 rect((w*.04,h*.12,w*.30,h*.75),(55+f*5,78,100))
 rect((w*.08,h*.18,w*.25,h*.42),(235,222,190))
 rect((w*.72,h*.16,w*.93,h*.80),(176,116+f*6,67))
 rect((0,h*.80,w-1,h-1),(60,70,87))
 for k in range(1,6):
  xx=int(w*(.40+k*.04));d.line((xx,int(h*.06),xx,int(h*.30)),fill=(230,230,220),width=max(1,w//400))
 cx=int(w*(.50+.04*(f%3)));cy=int(h*.56);rx=max(5,w//14);ry=max(5,h//8)
 d.ellipse((cx-rx,cy-ry,cx+rx,cy+ry),fill=(30,190,65))
 d.ellipse((cx-rx//2,cy-ry//2,cx,cy),fill=(90,240,125))
 a=np.asarray(image).copy()
 # Deliberately different display-only color/tone processing from camera luma.
 color=np.minimum((a.astype(np.int32)*9+4)//8+3,255).astype(np.uint8)
 p=np.zeros((h,w),dtype=np.bool_)
 p[:max(2,h//25),:max(3,w//8)]=True
 p[h//3:h//3+2,w//5:4*w//5]=True
 color[p]=(255,210,0)
 return a,color,p,(cx-rx-2,cy-ry-2,cx+rx+2,cy+ry+2)
def reference(a,color,protect,valid,box,enable):
 h,w=a.shape[:2];c=a.astype(np.uint32)
 gray=(c[:,:,0]+2*c[:,:,1]+c[:,:,2])//4
 # Explicit 64-pixel reductions, independent of streaming column accumulators.
 means=gray.reshape(h//8,8,w//8,8).sum(axis=(1,3),dtype=np.uint32)//64
 gx=np.zeros_like(means);gy=np.zeros_like(means)
 gx[:,1:]=np.abs(means[:,1:].astype(np.int32)-means[:,:-1].astype(np.int32))
 gy[1:,:]=np.abs(means[1:,:].astype(np.int32)-means[:-1,:].astype(np.int32))
 q=means//32;level=(q<<5)|(q<<2)|(q>>1)
 level[gx+gy>=40]=0
 bg=np.repeat(np.repeat(level,8,axis=0),8,axis=1).astype(np.uint8)
 expected=np.repeat(bg[:,:,None],3,axis=2)
 x0,y0,x1,y1=box;keep=protect.copy()
 if valid and 0<=x0<=x1<w and 0<=y0<=y1<h:keep[y0:y1+1,x0:x1+1]=True
 if not enable:keep[:]=True
 expected[keep]=color[keep]
 return gray,expected
for label,w,h,n in [('small',64,48,12),('720p',1280,720,3)]:
 with (vectors/f'{label}_stim.hex').open('w') as stim,(vectors/f'{label}_expected.hex').open('w') as expected,(vectors/f'{label}_meta.hex').open('w') as meta,(vectors/f'{label}_camera.hex').open('w') as camera:
  for f in range(n):
   a,color,p,box=fixture(w,h,f)
   valid=True;enable=True
   if label=='small':
    if f==0:a[:]=0;color[:]=(31,55,89)
    if f==1:a[:]=255;color[:]=(230,240,250)
    if f==2:box=(0,0,0,0)
    if f==3:box=(0,0,w-1,h-1)
    if f==4:box=(w-1,h-1,w-1,h-1)
    if f==5:valid=False
    if f==6:box=(w//2,h//2,w//2-1,h-1)
    if f==7:box=(0,0,w,h-1)
    if f==8:box=(0,0,w-1,h)
    if f==9:enable=False
    if f==10:
     rng=np.random.default_rng(321);a=rng.integers(0,256,a.shape,dtype=np.uint8)
     color=rng.integers(0,256,a.shape,dtype=np.uint8);p=rng.random(p.shape)<.15
    if f==11:box=(8,8,31,31)
   else:
    if f==1:valid=False
    if f==2:enable=False
   gray,out=reference(a,color,p,valid,box,enable)
   x0,y0,x1,y1=box
   metadata=(int(enable)<<65)|(int(valid)<<64)|(x0<<48)|(y0<<32)|(x1<<16)|y1
   meta.write(f'{metadata:017x}\n')
   c=color.astype(np.uint64)
   words=(gray.astype(np.uint64)<<25)|(p.astype(np.uint64)<<24)|(c[:,:,0]<<16)|(c[:,:,1]<<8)|c[:,:,2]
   result=out.astype(np.uint32);words_out=(result[:,:,0]<<16)|(result[:,:,1]<<8)|result[:,:,2]
   stim.writelines(f'{int(v):09x}\n' for v in words.flat)
   expected.writelines(f'{int(v):06x}\n' for v in words_out.flat)
   c0=a.astype(np.uint32);cw=(c0[:,:,0]<<16)|(c0[:,:,1]<<8)|c0[:,:,2]
   camera.writelines(f'{int(v):06x}\n' for v in cw.flat)
   if label=='720p' and f==0:
    Image.fromarray(color).save(preview/'input.png')
    Image.fromarray(out).save(preview/'reference.png')
 print(label,'frames:',n,'pixels:',w*h*n)

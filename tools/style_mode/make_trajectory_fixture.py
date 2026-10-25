from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];dest=root/'sim/build/style_mode_20261025/vectors/trajectory_camera.hex';dest.parent.mkdir(parents=True,exist_ok=True)
w,h=1280,720;y,x=np.indices((h,w),dtype=np.int32)
with dest.open('w') as f:
 for n,(cx,cy) in enumerate([(180,430),(240,430),(300,410),(360,390),(420,370),(480,350),(540,330),(600,310)]):
  a=np.empty((h,w,3),dtype=np.uint8)
  a[:,:,0]=105+(x//7+y//9)%28;a[:,:,1]=110+(x//13)%18;a[:,:,2]=125+(y//11)%24
  image=Image.fromarray(a);d=ImageDraw.Draw(image)
  d.rectangle((900,90,1170,600),fill=(180,120,70));d.rectangle((50,70,280,240),fill=(230,230,230))
  d.ellipse((cx-24,cy-24,cx+24,cy+24),fill=(25,190,55));d.ellipse((cx-10,cy-10,cx,cy),fill=(80,235,110))
  a=np.asarray(image).astype(np.uint32);v=(a[:,:,0]<<16)|(a[:,:,1]<<8)|a[:,:,2]
  f.writelines(f'{int(q):06x}\n' for q in v.flat)
print('Trajectory full-chain camera fixture:',w*h*8,'pixels')

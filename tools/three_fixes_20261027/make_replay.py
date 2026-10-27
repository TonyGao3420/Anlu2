"""Replay a real supplied phone-video frame through RTL, not a board capture."""
from pathlib import Path
import json,re,hashlib
import cv2
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[2];build=root/'sim/build/three_fixes_20261027'
video='C:/Users/11512/xwechat_files/wxid_rdi3xmqgwarv22_4123/msg/video/2026-10/753c3aed823463a4e925e2b4a85f0516.mp4'
cap=cv2.VideoCapture(video);frames=0;sample=None;hashes=[]
while True:
 ok,bgr=cap.read()
 if not ok:break
 if frames==75:sample=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
 hashes.append(hashlib.sha256(bgr.tobytes()).hexdigest());frames+=1
cap.release();assert frames==378 and sample is not None
(build/'video_review/all_frames.json').write_text(json.dumps({'decoded_frames':frames,'frame_sha256':hashes,'replay_frame':75},indent=2))
rgb=sample;h,w=rgb.shape[:2];yy,xx=np.indices((h,w));r,g,b=(rgb[:,:,n].astype(np.int16) for n in range(3))
lum=(r+2*g+b)//4
# Known rectangle encloses the physical green cube in the supplied phone frame.
# This is a display fixture, not a claimed detector result from this recording.
x0,y0,x1,y1=800,450,1200,719
roi=(xx>=x0)&(xx<=x1)&(yy>=y0)&(yy<=y1)
mean=lum.reshape(h//8,8,w//8,8).sum(axis=(1,3))//64
left=np.concatenate((mean[:,:1],mean[:,:-1]),axis=1);above=np.concatenate((mean[:1],mean[:-1]),axis=0)
dx=np.abs(mean-left);dy=np.abs(mean-above)
smooth=(2*mean+np.where(dx<=12,left,mean)+np.where(dy<=12,above,mean))//4
rep=lambda a:np.repeat(np.repeat(a,8,axis=0),8,axis=1)
gray=rep(96+smooth//2)
ex=rep(dx>=32);ey=rep(dy>=32)
gray=(gray-np.where((ex&(xx%8==0))|(ey&(yy%8==0)),24,np.where((ex&(xx%8==1))|(ey&(yy%8==1)),12,0))).astype(np.uint8)
hud=(xx>=1008)&(xx<1264)&(yy>=16)&(yy<48)&~roi
filtered=rgb.copy();med=np.median(np.lib.stride_tricks.sliding_window_view(rgb,5,axis=1),axis=-1).astype(np.uint8)
ok_window=~np.lib.stride_tricks.sliding_window_view(hud,5,axis=1).any(axis=-1)
filtered[:,2:-2]=np.where(ok_window[:,:,None],med,rgb[:,2:-2])
cr,cg,cb=(filtered[:,:,n].astype(np.int16) for n in range(3));lo=np.minimum(cr,cb);hi=np.maximum(cr,cb);ch=cg-lo
green=(cg>=8)&(cg>=hi+2)&(ch>=6)&(ch>=cg//4)&((cg<248)|((cg-hi)>=cg//4))
out=np.stack((gray,gray,gray),axis=-1);out[roi&green]=filtered[roi&green]
font={c:[int(v,2) for v in re.findall(r"5'b([01]+)",body)] for c,body in re.findall(r'"(.)":glyph=\{([^}]+)\}',(root/'user_source/hdl_source/video/roi_background_stylize.v').read_text())}
hudrgb=np.full((32,256,3),[8,12,16],dtype=np.uint8)
for line,word in enumerate(['MODE:STYLE','MOT:00000 LOCAL']):
 for ci,char in enumerate(word):
  for row,bits in enumerate(font.get(char,[0]*7)):
   for col in range(5):
    if bits&(16>>col):hudrgb[line*16+row*2:line*16+row*2+2,ci*16+col*2:ci*16+col*2+2]=[48,232,255]
out[hud]=hudrgb[yy[hud]-16,xx[hud]-1008]
stim=(lum.astype(np.uint64)<<25)|(rgb[:,:,0].astype(np.uint64)<<16)|(rgb[:,:,1].astype(np.uint64)<<8)|rgb[:,:,2].astype(np.uint64)
gold=(hud.astype(np.uint32)<<25)|(roi.astype(np.uint32)<<24)|(out[:,:,0].astype(np.uint32)<<16)|(out[:,:,1].astype(np.uint32)<<8)|out[:,:,2].astype(np.uint32)
for name,a,width in [('replay_stim',stim,9),('replay_gold',gold,7)]:
 (build/(name+'.hex')).write_text(''.join(f'{v:0{width}x}\n' for v in a.ravel()))
Image.fromarray(rgb).save(build/'video_review/replay_input.png')
(build/'replay_reference.json').write_text(json.dumps({'source_video_frames_decoded':frames,'frame':75,'bbox':[x0,y0,x1,y1],'green_retained_pixels':int((roi&green).sum()),'not_a_board_capture':True},indent=2))
work=root/'sim/modelsim_three_fixes_replay_20261027';work.mkdir(exist_ok=True)
(work/'run_replay.do').write_text('onerror {quit -code 1 -f}\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_video_replay_20261027.sv\nvsim -c work.tb_video_replay\nrun -all\nquit -f\n')
print('Prepared full real-video frame replay; all378 frames decoded',flush=True)

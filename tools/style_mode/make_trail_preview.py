from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json
root=Path(__file__).resolve().parents[2];source=root/'sim/build/style_mode_20261025/trail_movie';dest=root/'sim/build/style_mode_20261025/preview';dest.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
frames=[];counts=[]
for k in range(60):
 im=Image.open(source/f'frame_{k:02d}.ppm').convert('RGB');assert im.size==(320,176)
 a=np.asarray(im);counts.append(int(np.all(a==[255,136,0],axis=2).sum()))
 c=Image.new('RGB',(640,436),(24,28,36));c.paste(im.resize((640,352),Image.Resampling.NEAREST),(0,84))
 d=ImageDraw.Draw(c)
 d.text((12,5),f'RTL 轨迹模块仿真｜虚拟时间 {k/10:.1f} 秒',font=font,fill=(245,245,245))
 status='绿色小球移动，橙色轨迹逐帧连接' if k<20 else ('目标已移走，旧痕迹逐段满三秒后消失' if k<51 else '最近三秒无有效点，轨迹已清空')
 d.text((12,31),status,font=font,fill=(255,180,80))
 d.text((12,57),'合成输入，非上板实拍；文字/边框/目标优先显示',font=font,fill=(190,200,212))
 frames.append(c)
assert counts[0]==0 and counts[19]>0 and counts[20]>0 and all(c==0 for c in counts[51:]),counts
frames[0].save(dest/'trajectory_demo.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=2,optimize=False)
strip=Image.new('RGB',(1920,436),(24,28,36))
for pos,k in enumerate([19,40,53]):strip.paste(frames[k],(pos*640,0))
strip.save(dest/'trajectory_strip.png')
(dest/'trajectory_pixels.json').write_text(json.dumps({'source':'actual RTL output PPM frames','virtual_ms_per_frame':100,'orange_pixels':counts},indent=2),encoding='utf-8')
print('PASS trail preview: 60 actual RTL frames; trace visible during motion/loss, completely expired by frame51')

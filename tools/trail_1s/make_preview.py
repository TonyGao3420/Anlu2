from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,numpy as np
root=Path(__file__).resolve().parents[2];b=root/'sim/build/trail_1s_20261025';dest=b/'preview';dest.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
frames=[];old_counts=[];new_counts=[]
for f in range(0,240,4):
 old=Image.open(b/f'movie/old_{f:03d}.ppm').convert('RGB');new=Image.open(b/f'movie/new_{f:03d}.ppm').convert('RGB')
 assert old.size==new.size==(256,144)
 old_counts.append(int(np.all(np.asarray(old)==[255,136,0],axis=2).sum()));new_counts.append(int(np.all(np.asarray(new)==[255,136,0],axis=2).sum()))
 canvas=Image.new('RGB',(1024,366),(24,28,36));canvas.paste(old.resize((512,288),Image.Resampling.NEAREST),(0,78));canvas.paste(new.resize((512,288),Image.Resampling.NEAREST),(512,78))
 d=ImageDraw.Draw(canvas);sec=(f*16.5+(200 if f>=95 else 0))/1000
 d.text((10,3),'原方案：3秒，逐帧记录原始中心',font=font,fill='white')
 d.text((522,3),'新方案：1秒，中值＋平滑＋约20Hz采样',font=font,fill='white')
 d.text((10,28),f'RTL模块真实输出｜合成ROI输入，非上板实拍｜虚拟时间 {sec:.2f} 秒',font=font,fill=(255,185,80))
 d.text((10,52),'包含静止抖动、运动单帧跳点、丢失后消退及模式重入',font=font,fill=(195,205,215));frames.append(canvas)
assert new_counts[54]==0 and any(new_counts) and any(old_counts)
durations=[66]*60;durations[23]=266
frames[0].save(dest/'trail_comparison.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2,optimize=False)
strip=Image.new('RGB',(1024,732),(24,28,36));strip.paste(frames[27],(0,0));strip.paste(frames[54],(0,366));strip.save(dest/'trail_comparison.png')
(dest/'trajectory_pixel_counts.json').write_text(json.dumps({'actual_RTL_output':True,'captured_every_4_frames':True,'old':old_counts,'new':new_counts},indent=2),encoding='utf-8')
print('PASS trail preview: actual old/new RTL output, 1s conditioned trace and target-loss expiry')

from pathlib import Path
import cv2
import json
from PIL import Image,ImageDraw,ImageFont

root=Path(__file__).resolve().parents[2]
build=root/'sim/build/three_fixes_20261027/video_review';build.mkdir(exist_ok=True)
path='C:/Users/11512/xwechat_files/wxid_rdi3xmqgwarv22_4123/msg/video/2026-10/753c3aed823463a4e925e2b4a85f0516.mp4'
cap=cv2.VideoCapture(path)
assert cap.isOpened()
fps=cap.get(cv2.CAP_PROP_FPS);total=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
meta={'fps':fps,'frames':total,'width':cap.get(cv2.CAP_PROP_FRAME_WIDTH),'height':cap.get(cv2.CAP_PROP_FRAME_HEIGHT),'seconds':total/fps}
print(meta);(build/'metadata.json').write_text(json.dumps(meta,indent=2))
sheet=Image.new('RGB',(1200,3*380),'#17212d');draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
for k,index in enumerate([int((total-1)*q/5) for q in range(6)]):
    cap.set(cv2.CAP_PROP_POS_FRAMES,index);ok,frame=cap.read();assert ok,index
    im=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));im.save(build/f'frame_{index:04d}.png')
    thumb=im.copy();thumb.thumbnail((580,340))
    x=(k%2)*600;y=(k//2)*380
    sheet.paste(thumb,(x,y+32));draw.text((x+8,y+4),f'{index/fps:.2f}s / 帧{index}',font=font,fill='white')
sheet.save(build/'contact_sheet.png');cap.release()

from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[2];p=root/'sim/build/style_mode_20261025/preview'
a=Image.open(p/'rtl_output.ppm').convert('RGB');b=Image.open(p/'reference.png').convert('RGB')
assert np.array_equal(np.asarray(a),np.asarray(b)),'RTL readback/reference image mismatch'
a.save(p/'rtl_output.png')
canvas=Image.new('RGB',(2560,784),(24,28,36));canvas.paste(Image.open(p/'input.png'),(0,64));canvas.paste(a,(1280,64))
d=ImageDraw.Draw(canvas);font_path=Path('C:/Windows/Fonts/msyh.ttc')
if font_path.exists():
 font=ImageFont.truetype(str(font_path),28)
 left='合成测试输入（非实拍）';right='RTL 仿真输出：彩色 ROI + 灰度池化轮廓'
else:
 font=ImageFont.load_default(size=28);left='Synthetic input (not a camera capture)';right='Actual RTL simulation: color ROI + pooled gray contours'
d.text((24,12),left,font=font,fill=(240,240,240));d.text((1304,12),right,font=font,fill=(240,240,240))
canvas.save(p/'comparison.png')
print('PASS preview: 921600 ModelSim RGB pixels exactly match the independent reference image')

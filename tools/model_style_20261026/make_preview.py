"""Present actual RTL raster dumps; these images are not camera/board captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/model_style_20261026'
dest = build / 'preview'
dest.mkdir(exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)


def panel(frame):
    im = Image.new('RGB', (1280, 454), '#17212d')
    d = ImageDraw.Draw(im)
    d.text((16, 8), 'RTL仿真输出 · 合成输入，非实机拍摄', font=font, fill='white')
    d.text((16, 40), '上一版：暗灰块面 / 运动青色提示', font=font, fill='white')
    d.text((656, 40), '当前：明亮灰色块面 / 软轮廓 / 仅目标绿色保色', font=font, fill='white')
    for x, key in [(0, 'old'), (640, 'new')]:
        p = build / f'movie/{key}_{frame:02d}.ppm'
        with Image.open(p) as raster:
            im.paste(raster.resize((640, 384), Image.Resampling.NEAREST), (x, 70))
    return im


frames = [panel(i) for i in range(20)]
frames[0].save(dest / 'motion_style_comparison.gif', save_all=True,
               append_images=frames[1:], duration=500, loop=0)
sheet = Image.new('RGB', (1280, 924), '#17212d')
d = ImageDraw.Draw(sheet)
for row, frame in enumerate([0,4]):
    y=row*462
    d.text((16,y+4), f'720p RTL输出 · 帧{frame} · 静止背景同样完整显示 · 合成输入，非实机拍摄', font=font, fill='white')
    d.text((16,y+36),'上一版',font=font,fill='white')
    d.text((656,y+36),'当前明亮模型风格',font=font,fill='white')
    for x,key in [(0,'old'),(640,'new')]:
        with Image.open(build/f'movie/full_{key}_{frame:02d}.ppm') as raster:
            sheet.paste(raster.resize((640,360),Image.Resampling.NEAREST),(x,y+70))
sheet.save(dest / 'model_style_comparison.png')
with Image.open(build/'movie/full_new_04.ppm') as raster:
    raster.save(dest/'model_style_720p.png')
print('Preview from actual RTL PPM rasters:', dest)

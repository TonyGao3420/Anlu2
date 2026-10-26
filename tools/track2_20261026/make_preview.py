"""Present actual RTL raster dumps; these images are not camera/board captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/track2_requirements_20261026'
dest = build / 'preview'
dest.mkdir(exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)


def panel(frame):
    im = Image.new('RGB', (1280, 454), '#17212d')
    d = ImageDraw.Draw(im)
    d.text((16, 8), 'RTL仿真输出 · 合成输入，非实机拍摄', font=font, fill='white')
    d.text((16, 40), '原风格化', font=font, fill='white')
    d.text((656, 40), '本次扩展：运动区域提示 + 模式/统计状态', font=font, fill='white')
    for x, key in [(0, 'old'), (640, 'new')]:
        p = build / f'movie/{key}_{frame:02d}.ppm'
        with Image.open(p) as raster:
            im.paste(raster.resize((640, 384), Image.Resampling.NEAREST), (x, 70))
    return im


frames = [panel(i) for i in range(20)]
frames[0].save(dest / 'motion_style_comparison.gif', save_all=True,
               append_images=frames[1:], duration=500, loop=0)
sheet = Image.new('RGB', (1280, 980), '#17212d')
d = ImageDraw.Draw(sheet)
d.text((16, 8), '帧4：局部运动；彩色ROI与已有保护区域保持原像素', font=font, fill='white')
sheet.paste(panel(4), (0, 36))
d.text((16, 498), '帧7：全局亮度变化，GLOBAL抑制大面积着色', font=font, fill='white')
sheet.paste(panel(7), (0, 528))
sheet.save(dest / 'motion_style_comparison.png')
print('Preview from actual RTL PPM rasters:', dest)

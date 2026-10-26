"""Independent array-based full-frame reference for motion-aware stylization."""
from pathlib import Path
import json
import re
import numpy as np

root = Path(__file__).resolve().parents[2]
dest = root / 'sim/build/track2_requirements_20261026'
dest.mkdir(exist_ok=True)
src = (root / 'user_source/hdl_source/video/roi_background_stylize.v').read_text()
# Font rows are assets; rendering, text selection and frame statistics below
# are independent of the HDL control/raster implementation.
font = {c: [int(v, 2) for v in re.findall(r"5'b([01]+)", body)]
        for c, body in re.findall(r'"(.)":glyph=\{([^}]+)\}', src)}


def make(w, h, n, prefix):
    yy, xx = np.indices((h, w));cells = (w // 16) * (h // 16)
    past_mean = np.zeros((h // 16, w // 16), dtype=np.int16)
    past_motion = np.zeros_like(past_mean, dtype=bool)
    history_valid = False;completed = 0;counts = [];visible = []
    fs = {k: (dest / f'{prefix}_{k}.hex').open('w', encoding='ascii')
          for k in ['stim', 'gold', 'old', 'meta', 'counts']}
    try:
        for f in range(n):
            en = f not in [12, 13]
            shift = 16 * max(0, min(f - 2, 3))
            left = 32 + shift;top = 64 if h >= 160 else 48
            lum = np.full((h, w), 52, dtype=np.int16)
            lum[(xx >= left) & (xx < left + 64) & (yy >= top) & (yy < top + 64)] = 180
            if f in [6, 7]:lum += 24
            if f in [9, 10, 11]:
                lum = 45 + (((xx // 16 + yy // 16 + (1 if f == 11 else 0)) & 1) * 155)
            if f in [15, 16, 17, 18, 19]:
                # A local high -> hysteresis-band -> below-low sequence.
                lum = np.full((h, w), 52, dtype=np.int16)
                level = {15: 90, 16: 82, 17: 78, 18: 78, 19: 78}[f]
                lum[(xx >= 80) & (xx < 128) & (yy >= 80) & (yy < 128)] = level
            lum=lum+((xx+2*yy)%7)
            x0, y0, x1, y1 = left + 16, top + 16, left + 47, top + 47
            if f == 10:x0,y0,x1,y1=w-96,18,w-32,45
            valid = f != 18
            if not valid:x1=w
            roi = valid & (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
            hx = w - 272 if w >= 288 else 0;hy=16
            protected = ((xx >= 16) & (xx < 112) & (yy >= 4) & (yy < 12)) | ((xx>=hx+8)&(xx<hx+22)&(yy>=20)&(yy<26))
            rgb = np.stack(((lum * 3 + f) & 255, lum, (lum * 2) & 255), axis=-1).astype(np.uint8)
            rgb[roi] = [24, 220, 72];rgb[protected] = [255, 242, 0]
            means8 = lum.reshape(h//8,8,w//8,8).sum(axis=(1,3)) // 64
            left8=np.concatenate((means8[:,:1],means8[:,:-1]),axis=1)
            above8=np.concatenate((means8[:1,:],means8[:-1,:]),axis=0)
            edges=(np.abs(means8-left8)+np.abs(means8-above8))>=40
            levels=(means8>>5)*36 + (means8>>6)
            gray=np.where(edges,0,levels).astype(np.uint8)
            bg=np.repeat(np.repeat(gray,8,axis=0),8,axis=1)
            # Four truncated 8x8 means, matching the intentionally reused
            # existing statistics, approximate a direct 16x16 mean within 1.
            means16=means8.reshape(h//16,2,w//16,2).sum(axis=(1,3))//4
            if not en:history_valid=False;completed=0
            displayed_count=completed
            global_scene=completed>=(cells+2)//3
            oldmask=past_motion.copy() if history_valid and en and not global_scene else np.zeros_like(past_motion)
            motionmask=np.repeat(np.repeat(oldmask,16,axis=0),16,axis=1)
            delta=np.abs(means16-past_mean)
            detected=history_valid & en & ((delta>=12) | (past_motion & (delta>=6)))
            new_count=int(detected.sum()) if en else 0
            counts.append(new_count);visible.append(int(oldmask.sum()))
            out=np.stack((bg,bg,bg),axis=-1)
            if en:
                out[motionmask]=np.stack((bg[motionmask]>>1,bg[motionmask],bg[motionmask]),axis=-1)
                out[motionmask & (bg==0)]=[48,200,216]
            else:out=rgb.copy()
            oldout=np.stack((bg,bg,bg),axis=-1) if en else rgb.copy()
            oldout[roi|protected]=rgb[roi|protected]
            hud=(xx>=hx)&(xx<hx+256)&(yy>=hy)&(yy<hy+32)&~roi&~protected
            lines=['MODE:'+('STYLE' if en else 'COLOR'),
                   ('MOT:'+f'{displayed_count:05d}'+' '+('GLOBAL' if global_scene else 'LOCAL')) if en else 'MOT:-----']
            hudrgb=np.full((32,256,3),[8,12,16],dtype=np.uint8)
            color=[48,232,255] if en else [255,242,0]
            for line,word in enumerate(lines):
                for ci,ch in enumerate(word):
                    for ri,bits in enumerate(font.get(ch,[0]*7)):
                        for col in range(5):
                            if bits & (16>>col):hudrgb[line*16+ri*2:line*16+ri*2+2,ci*16+col*2:ci*16+col*2+2]=color
            out[hud]=hudrgb[(yy[hud]-hy),(xx[hud]-hx)]
            out[roi|protected]=rgb[roi|protected]
            pro=protected|hud
            stim=(lum.astype(np.uint64)<<25)|(protected.astype(np.uint64)<<24)|(rgb[:,:,0].astype(np.uint64)<<16)|(rgb[:,:,1].astype(np.uint64)<<8)|rgb[:,:,2].astype(np.uint64)
            def pack(image,p):return (p.astype(np.uint32)<<25)|(roi.astype(np.uint32)<<24)|(image[:,:,0].astype(np.uint32)<<16)|(image[:,:,1].astype(np.uint32)<<8)|image[:,:,2].astype(np.uint32)
            fs['stim'].write(''.join(f'{v:09x}\n' for v in stim.ravel()))
            fs['gold'].write(''.join(f'{v:07x}\n' for v in pack(out,pro).ravel()))
            fs['old'].write(''.join(f'{v:07x}\n' for v in pack(oldout,protected).ravel()))
            fs['meta'].write(f'{(int(en)<<65)|(int(valid)<<64)|(x0<<48)|(y0<<32)|(x1<<16)|y1:017x}\n')
            fs['counts'].write(f'{new_count:04x}\n')
            if en:past_mean=means16.copy();past_motion=detected.copy();history_valid=True
            completed=new_count
    finally:
        for f in fs.values():f.close()
    if n>=20:
        assert counts[0:3]==[0,0,0]
        assert counts[6]==cells and counts[7]==0 and visible[7]==0
        assert counts[12:15]==[0,0,0]
        assert counts[16]>0 and counts[17]==0
    metrics={'geometry':[w,h,n],'motion_counts':counts,'visible_previous_frame_tiles':visible,
             'uniform_lighting_detected_as_global':n>=8,'mask_and_statistics_age_frames':1}
    (dest/f'{prefix}_metrics.json').write_text(json.dumps(metrics,indent=2))
    print('Generated',prefix,metrics)


if __name__=='__main__':
    make(320,192,20,'small')
    make(1280,720,8,'full')

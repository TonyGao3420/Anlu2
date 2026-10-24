"""Anlu2 可重复的数字视频回归；工具路径可用 --iverilog 指定。"""
from pathlib import Path
import argparse, math, os, random, subprocess, json
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/"sim/build"
def gamma(x): return int(255*(x/255)**(1/2.2)+0.5)
def detail(l,c,r):
    lap=2*c-l-r
    d=math.trunc(lap/4) if abs(lap)>8 else 0
    return max(0,min(255,c+max(-12,min(12,d))))
def vectors():
    rng=random.Random(520)
    # 独立整数/实数参考模型，按整行计算邻居，验证RTL流式边界处理。
    def line(pixels,protect,vs=0,hs=0,gap=12):
        for x,p in enumerate(pixels):
            channels=[(p>>s)&255 for s in (16,8,0)]
            left=pixels[x-1] if x and not protect[x-1] else p
            right=pixels[x+1] if x+1<len(pixels) and not protect[x+1] else p
            enhanced=0; tone=0
            for j,s in enumerate((16,8,0)):
                c=channels[j]
                e=c if protect[x] else gamma(detail((left>>s)&255,c,(right>>s)&255))
                t=c if protect[x] else gamma(c)
                enhanced=(enhanced<<8)|e;tone=(tone<<8)|t
            ctrl=(vs<<26)|(hs<<25)|(1<<24)
            yield ((vs<<27)|(hs<<26)|(1<<25)|(protect[x]<<24)|p,
                   ctrl|enhanced,ctrl|p,ctrl|tone)
        for x in range(gap):
            ctrl=(vs<<26)|((x%2)<<25)
            yield ((vs<<27)|((x%2)<<26)|rng.randrange(1<<24),ctrl,ctrl,ctrl)
    with (BUILD/"enhance_vectors.txt").open("w",encoding="ascii") as f:
        def emit(it):
            for v in it:f.write(" ".join(f"{x:07x}" for x in v)+"\n")
        emit([(0,0,0,0)]*8)
        for c in range(256):
            emit(line([c*0x010101]*5,[0]*5))
        for width in (1,2,3,4,15,16,17,1279,1280):
            for _ in range(3):
                p=[rng.randrange(1<<24) for _ in range(width)]
                emit(line(p,[int(rng.random()<.1) for _ in p],rng.randrange(2)))
        # 两帧720p：渐变、黑白边沿、逐像素序号和受保护OSD区域。
        for frame in range(2):
            emit([(1<<27,1<<26,1<<26,1<<26)]*40)
            for y in range(720):
                p=[(((x+frame*7)&255)<<16)|(((y+x//4)&255)<<8)|((x^y)&255) for x in range(1280)]
                if y%8==0:p=[0 if x%32<16 else 0xffffff for x in range(1280)]
                emit(line(p,[int(x<160 and y<160) for x in range(1280)],gap=370))
            emit([(0,0,0,0)]*100)
        emit([(0,0,0,0)]*4)
def run(args,cwd=BUILD):
    p=subprocess.run([str(x) for x in args],cwd=cwd,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    s=p.stdout.decode("utf-8",errors="replace")
    print(s,flush=True)
    if p.returncode:raise RuntimeError(f"Failed ({p.returncode}): {args[0]}")
    return s
if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--iverilog",type=Path,default=ROOT/"sim/.tools/iverilog/bin/iverilog.exe")
    ns=ap.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True)
    ENV=dict(os.environ,TMP=str(BUILD),TEMP=str(BUILD),TMPDIR=str(BUILD))
    iv=ns.iverilog.resolve(); vvp=iv.with_name("vvp.exe" if os.name=="nt" else "vvp")
    print("Generating 720p/reference vectors...",flush=True); vectors()
    jobs=[
      ("tb_video_enhance",["user_source/hdl_source/video/video_enhance.v"]),
      ("tb_display_path",["user_source/hdl_source/isp/data96_128/data96_128.v",
        "user_source/hdl_source/video_out.v","user_source/hdl_source/hdmi_mixer.v",
        "user_source/hdl_source/anlogic_logo_rom.v","user_source/hdl_source/osd_char_lib.v"]),
      ("tb_raw10",["user_source/hdl_source/isp/raw10_unpacket_2lane.v",
        "user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v"])
    ]
    results={}
    for name,srcs in jobs:
        output=BUILD/(name+".vvp")
        sources=[ROOT/"sim/tb"/(name+".sv")]+[ROOT/s for s in srcs]
        config=BUILD/(name+".conf")
        ENV["IVERILOG_ICONFIG"]=str(config)
        # 旧Windows驱动通过cmd管道调用后端；某些环境拒绝该管道。
        # 仍由驱动生成完整编译参数，必要时逐级直接调用相同的预处理器/后端。
        args=[iv,"-B",str(iv.parent.parent/"lib/ivl"),"-g2012","-s",name,"-o",output]+sources
        attempt=subprocess.run([str(x) for x in args],cwd=BUILD,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        if attempt.returncode:
            if b"Access is denied" not in attempt.stdout or not config.exists():
                raise RuntimeError(attempt.stdout.decode(errors="replace"))
            combined=BUILD/(name+"_combined.sv")
            combined.write_text("\n".join(p.read_text(encoding="utf-8") for p in sources),encoding="utf-8")
            preprocessed=BUILD/(name+"_preprocessed.sv")
            with preprocessed.open("wb") as f:
                prep=subprocess.run([str(iv.parent.parent/"lib/ivl/ivlpp.exe"),str(combined)],stdout=f,stderr=subprocess.PIPE,cwd=BUILD,env=ENV)
            if prep.returncode:raise RuntimeError(prep.stderr.decode(errors="replace"))
            run([iv.parent.parent/"lib/ivl/ivl.exe","-C",config,"-C",iv.parent.parent/"lib/ivl/vvp.conf",preprocessed])
        else:
            print(attempt.stdout.decode(errors="replace"))
        results[name]=run([vvp,output])
    (BUILD/"results.json").write_text(json.dumps(results,indent=2),encoding="utf-8")

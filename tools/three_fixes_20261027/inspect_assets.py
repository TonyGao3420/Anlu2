from pathlib import Path
import hashlib
import importlib.util
import json
import re
from pypdf import PdfReader

root = Path(__file__).resolve().parents[2]
build = root/'sim/build/three_fixes_20261027'
backup = root.parent/'recovery_backups/Anlu2_before_three_fixes_20261027'
files = [p for p in backup.rglob('*') if p.is_file()]
hashes = {p.relative_to(backup).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
if not (backup/'source_sha256.json').exists():
    (backup/'source_sha256.json').write_text(json.dumps(hashes,indent=2))
print({k:bool(importlib.util.find_spec(k)) for k in ['cv2','imageio','imageio_ffmpeg','av','numpy','PIL']})
rom=root.parent/'lab_ex3_osd_SC520/src/hdl_source/anlogic_logo_rom.v'
words={int(a):int(v,16) for a,v in re.findall(r"15'd(\d+): O_pixel = 25'h([0-9a-fA-F]+)",rom.read_text())}
print('Official logo pixels',len(words),'lastaddress',max(words),'colors',len(set(words.values())))
for filename in ['SC520CS_设计应用指南_V1.4_for-CSP.pdf','SC520CS_V1.0.pdf','SC520CS-03_数据手册_V1.6.pdf']:
    pdf=PdfReader(root.parent/filename)
    chunks=[]
    for n,page in enumerate(pdf.pages):
        text=page.extract_text() or ''
        if any(k in text.lower() for k in ['3221','mirror','flip','bayer']):
            chunks.append(f'PAGE {n+1}\n{text}')
    (build/(filename+'.txt')).write_text('\n\n'.join(chunks),encoding='utf-8')
    print(filename,[(c.splitlines()[0]) for c in chunks])

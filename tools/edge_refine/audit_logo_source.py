from pathlib import Path
import json,hashlib,re,shutil
root=Path('Anlu2');m=json.loads((root/'sim/build/SC520_edge_color_20261009_manifest.json').read_text());bad=[]
for p,h in m['source_sha256'].items():
 if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h:bad.append(p)
assert not bad,bad
bak=root/'sim/build/backup_edge_refine_20261010';(bak/'before_sha256.json').write_text(json.dumps(m['source_sha256'],indent=2)+'\n')
p=root/'user_source/hdl_source/video/display_edge_color.v';shutil.copy2(p,bak/'display_edge_color.v')
rom=(root/'user_source/hdl_source/anlogic_logo_rom.v').read_text(encoding='utf-8');pixels={int(a):int(b,16) for a,b in re.findall(r"15'd(\d+):\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)",rom)}
assert 'default: O_pixel = 25\'d0;' in rom or re.search(r'default\s*:\s*O_pixel\s*=\s*(25\'h0+|25\'d0)',rom)
active={a:v for a,v in pixels.items() if v>>24};xs=[a%160 for a in active];ys=[a//160 for a in active]
report={'logo_valid_pixels':len(active),'logo_pixel_bounds':[min(xs),min(ys),max(xs),max(ys)],'transparent_default':True,'current_source_matches_previous_bit_manifest':True}
(root/'sim/build/edge_refine_20261010/logo_source_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
# Independent expected ROM image, for exercising actual mixer timing/alpha.
(root/'sim/build/edge_refine_20261010/logo_reference.hex').write_text('\n'.join(f'{pixels.get(a,0):07x}' for a in range(25600))+'\n')

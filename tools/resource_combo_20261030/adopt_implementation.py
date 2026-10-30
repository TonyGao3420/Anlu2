"""After stopping other physical trials, adopt a completed run into main phy_1."""
from pathlib import Path
import sys,re,json,shutil,hashlib
r=Path(__file__).resolve().parents[2];b=r/'sim/build/resource_combo_20261030';seed=int(sys.argv[1]);assert seed in [0,2,3]
routability='--routability' in sys.argv[2:]
base=r/'td_project/camera_to_dsi_display_Runs';dst=base/'phy_1';src=dst if seed==0 else base/(f'phy_combo_seed{seed}_route' if routability else f'phy_combo_seed{seed}')
q=(src/'route.qor').read_text(encoding='utf-8-sig')
metric=lambda k:int(re.search(r'\|\s*'+re.escape(k)+r'\s*\|\s*(-?\d+)',q)[1])
assert metric('Setup WNS')>=0 and metric('Hold WNS')>=0 and metric('Setup TNS')==metric('Hold TNS')==0
assert metric('#slices')<=21216 and metric('#RAMs')<=108 and metric('#DSPs')<=40
gate=base/'syn_1/camera_to_dsi_display_gate.db';bit=src/'camera_to_dsi_display.bit'
assert bit.stat().st_mtime>(src/'camera_to_dsi_display_pr.db').stat().st_mtime>(src/'camera_to_dsi_display_place.db').stat().st_mtime>gate.stat().st_mtime
for log,mark in [('color_equivalence','PASS color_equivalence:'),('opt_equivalence','PASS resource_equivalence:'),('union_mask','PASS union_mask:'),('combo_coldboot_final','PASS combo_coldboot:'),('combo_integration','PASS combo_integration:')]:
 assert mark in (b/(log+'.log')).read_text(errors='replace', encoding='utf-8-sig'),log
if src!=dst:
 for p in src.iterdir():
  if p.is_file():shutil.copy2(p,dst/p.name)
cfg=dst/'settings.cfg';s=cfg.read_text(encoding='utf-8-sig');s=re.sub(r'^set phyWildParams.*\n?','',s,flags=re.M);s=s.replace('set start_step opt_route','set start_step opt_place');cfg.write_text(s+f'\nset phyWildParams {{place seed {seed}'+(' route effort routability' if routability else '')+'}\n', encoding='utf-8')
script=dst/'camera_to_dsi_display.tcl';s=script.read_text(encoding='utf-8-sig');s=s.replace('### Editable zone for opt_place ###',f'### Editable zone for opt_place ###\n  set_param place seed {seed}');script.write_text(s, encoding='utf-8')
if routability:
 s=script.read_text(encoding='utf-8-sig');s=s.replace('### Editable zone for opt_route ###','### Editable zone for opt_route ###\n  set_param route effort routability');script.write_text(s, encoding='utf-8')
al=r/'td_project/camera_to_dsi_display.al';s=al.read_text(encoding='utf-8')
s=re.sub(r'<Run Name="phy_1"[^>]*>',lambda m:re.sub(r'\suseDefaultScript="[^"]*"','',m[0][:-1])+' useDefaultScript="false">',s)
s=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+(r/'td_project').as_posix()+m[2],s,count=1)
al.write_text(s,encoding='utf-8')
shutil.copy2(b/('final_main_route.log' if seed==0 else (f'combo_route_seed{seed}_routability.log' if routability else f'combo_route_seed{seed}.log')),b/'final_route.log')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((b/'record.json').read_text(encoding='utf-8-sig'));m['selected_seed']=seed;m['selected_route_effort']='routability' if routability else 'normal';m['selected_run']=str(src)
m['optimization_color_sha256']={p:sha(b/'optimization_passed'/p) for p in ['user_source/hdl_source/video/display_color_shading.v','user_source/hdl_source/video/shading_row0.mif','user_source/hdl_source/video/shading_row1.mif','user_source/hdl_source/video/shading_row2.mif']}
m['optimization_metrics']=(b/'optimization_passed/route.qor').read_text(encoding='utf-8-sig');m['optimization_bit_sha256']=sha(b/'optimization_passed/camera_to_dsi_display.bit')
(b/'record.json').write_text(json.dumps(m,indent=2), encoding='utf-8')
print('Adopted actual main-project seed',seed,'with matching GUI custom script and CLI configuration;',metric('#slices'),'slices; bit',sha(bit))

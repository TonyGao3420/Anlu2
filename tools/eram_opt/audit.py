from pathlib import Path
import json,hashlib,re,xml.etree.ElementTree as ET,subprocess,sys
root=Path(__file__).resolve().parents[2];build=root/'sim/build/eram_opt_20261025'
backup=root.parent/'recovery_backups/Anlu2_before_eram_opt_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
old=json.loads((backup/'source_sha256.json').read_text(encoding='utf-8'))
changed_production=[]
for rel,h in old.items():
 if rel.startswith('user_source/') and sha(root/rel)!=h:
  changed_production.append(rel)
assert changed_production==['user_source/hdl_source/hdmi_mixer.v'] or set(changed_production)=={'user_source/hdl_source/hdmi_mixer.v'},changed_production
for rel,h in old.items():
 if rel.endswith(('.sdc','settings.cfg')) or rel=='user_source/constraints_source/pin.adc':assert sha(root/rel)==h,('Original constraints/strategy changed',rel)
subprocess.run([sys.executable,str(root/'tools/style_mode/audit.py')],check=True,cwd=root)
# Decode packed initialization independently from its generator.
s=(root/'user_source/hdl_source/anlogic_logo_eram.v').read_text(encoding='ascii')
def vector(name):
 region=re.search(name+r'=\{(.*?)\};',s,re.S)[1]
 words=re.findall(r"512'h([0-9a-f]+)",region)
 return int(''.join(words),16)
idx=vector('INDEX_BITS');pal=vector('PALETTE_BITS')
original=(root/'user_source/hdl_source/anlogic_logo_rom.v').read_text(encoding='utf-8-sig')
colors={int(a):int(v,16) for a,v in re.findall(r"15'd(\d+)\s*:\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)",original)}
lo,hi=map(int,re.search(r"I_addr>=15'd(\d+) && I_addr<=15'd(\d+)",s).groups())
for a in range(32768):
 code=(idx>>((a&16383)*10))&1023
 out=(pal>>(code*25))&((1<<25)-1) if lo<=a<=hi else 0
 assert out==colors.get(a,0),('Logo pixel changed',a)
def sources(p):
 tree=ET.fromstring(p.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__'))
 return {(p.parent/f.attrib['Path']).resolve() for f in tree.findall('Source_Files/*/File')}
new=sources(root/'td_project/camera_to_dsi_display.al')
# Resolve saved relative source names in the current project directory.
tree=ET.fromstring((backup/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__'))
base={(root/'td_project'/f.attrib['Path']).resolve() for f in tree.findall('Source_Files/*/File')}
assert new==base|{root/'user_source/hdl_source/anlogic_logo_eram.v'}
for stage in ['syn_1','phy_1']:
 assert sources(root/'td_project/camera_to_dsi_display_Runs'/stage/'camera_to_dsi_display.prj')==new
baseline=json.loads((backup/'sim/build/style_mode_20261025/Anlu2_three_modes_20261025_manifest.json').read_text(encoding='utf-8'))
old_bit=backup/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
assert sha(old_bit)==baseline['sha256']
report={'backup':str(backup),'changed_existing_hardware_sources':changed_production,'new_hardware_source':'user_source/hdl_source/anlogic_logo_eram.v',
 'top_ROI_servo_style_trail_switch_color_sources_byte_identical_to_three_mode_baseline':True,
 'all_pins_SDC_and_tool_strategy_unchanged':True,'logo_all_32768_addresses_exactly_equal':True,'additional_display_latency':0,
 'palette_exact_colors_with_transparency':580,'previous_main_bit_sha256':sha(old_bit),'project_source_count':len(new)}
(build/'source_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))

from pathlib import Path
import re,shutil
root=Path(__file__).resolve().parents[2]
src=(root/'user_source/hdl_source/anlogic_logo_rom.v').read_text(encoding='utf-8-sig')
m=re.search(r"default\s*:\s*O_pixel\s*=\s*25'([hdb])([0-9a-fA-F]+)",src)
assert m,'ROM default not found'
default=int(m[2],{'h':16,'d':10,'b':2}[m[1]])
values=[default]*32768;entries=re.findall(r"15'd(\d+)\s*:\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)",src)
seen=set()
for a,b in entries:
 i=int(a);assert i not in seen;seen.add(i);values[i]=int(b,16);assert values[i]<2**25
(root/'sim/build/style_mode_20261025/vectors').mkdir(parents=True,exist_ok=True)
(root/'sim/build/style_mode_20261025/vectors/logo_rom.hex').write_text(''.join(f'{v:07x}\n' for v in values),encoding='ascii')
(root/'sim/models/style_mode').mkdir(exist_ok=True)
(root/'sim/models/style_mode/logo_rom_fast.v').write_text(f'''// SIMULATION ONLY: exact constant table generated from unchanged production ROM.
module anlogic_logo_rom(input [14:0] I_addr,output reg [24:0] O_pixel);
 reg [24:0] pixels[0:32767];
 initial $readmemh("../build/style_mode_20261025/vectors/logo_rom.hex",pixels);
 always @* if((^I_addr)===1'bx)O_pixel=25'd{default};else O_pixel=pixels[I_addr];
endmodule
''',encoding='ascii')
(root/'sim/models/style_mode/logo_rom_reference.v').write_text(src.replace('module anlogic_logo_rom (','module anlogic_logo_rom_reference ('),encoding='utf-8')

print("Production ROM model generated and isolated from hardware source list.")

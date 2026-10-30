"""Regenerate exact horizontal ROMs after editing the nine gain nodes in RTL."""
from pathlib import Path
import re
r=Path(__file__).resolve().parents[2];video=r/'user_source/hdl_source/video'
s=(video/'display_color_shading.v').read_text(encoding='utf-8');values=[]
for name in ['r_gain','b_gain']:
 a=s[s.index('function [9:0] '+name):];a=a[:a.index('endfunction')]
 nodes=[int(v) for v in re.findall(name+r'=10\x27d(\d+)',a)][:9]
 assert len(nodes)==9 and min(nodes)>=0 and max(nodes)<512 and max(nodes)-min(nodes)<256,'Gain nodes exceed lossless ROM/vertical delta width'
 values.append(nodes)
for row in range(3):
 words=[]
 for addr in range(1024):
  side=addr>>9;f=min(addr&511,256);pair=[ns[row*3+side]+(((ns[row*3+side+1]-ns[row*3+side])*f+128)>>8) for ns in values]
  words.append(pair[0]|pair[1]<<9)
 (video/f'shading_row{row}.mif').write_text('WIDTH=18;\nDEPTH=1024;\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i} : {v:05X};\n' for i,v in enumerate(words))+'END;\n', encoding='utf-8')
print('Regenerated exact horizontal ROM assets from current nine-node RGB gains')

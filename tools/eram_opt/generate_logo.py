"""Lossless packed ERAM assets generated from the unchanged 25-bit logo ROM."""
from pathlib import Path
import re,json,collections
root=Path(__file__).resolve().parents[2]
s=(root/'user_source/hdl_source/anlogic_logo_rom.v').read_text(encoding='utf-8-sig')
entries=[(int(a),int(b,16)) for a,b in re.findall(r"15'd(\d+)\s*:\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)",s)]
assert len({a for a,b in entries})==len(entries)
lo=min(a for a,b in entries);hi=max(a for a,b in entries);assert hi-lo<16384
colors=[0]+[v for v,c in collections.Counter(v for a,v in entries).most_common() if v!=0]
assert len(colors)<=1024
codes={v:i for i,v in enumerate(colors)};indices=[0]*16384;palette=colors+[0]*(1024-len(colors))
for a,v in entries:indices[a&16383]=codes[v]
# Exhaustive known-address proof, including aliased addresses outside the crop.
original=dict(entries)
for a in range(32768):
 v=palette[indices[a&16383]] if lo<=a<=hi else 0
 assert v==original.get(a,0),a

def packed(name,values,width):
 value=sum(v<<(i*width) for i,v in enumerate(values));bits=len(values)*width
 assert bits%512==0
 words=[f"512'h{(value>>i)&((1<<512)-1):0128x}" for i in range(bits-512,-1,-512)]
 return f' localparam [{bits-1}:0] {name}={{\n'+',\n'.join('  '+w for w in words)+'\n };\n'
text="// Lossless logo ERAM. Generated from anlogic_logo_rom.v; do not hand-edit pixels.\n// 10-bit cropped indices + all 25-bit palette colors, including transparency.\n// Two synchronous reads reuse the mixer's existing x/y pipeline stages.\n// Packed constant initialization is self-contained: no runtime file paths.\nmodule anlogic_logo_eram(input wire I_clk,I_rst_n,input wire [14:0] I_addr,\n output wire [24:0] O_pixel);\n"
text+=packed('INDEX_BITS',indices,10)+packed('PALETTE_BITS',palette,25)
text+=' reg [9:0] index_mem[0:16383];\n reg [24:0] palette_mem[0:1023];\n integer init_i;\n initial begin\n  for(init_i=0;init_i<16384;init_i=init_i+1)index_mem[init_i]=INDEX_BITS[init_i*10+:10];\n  for(init_i=0;init_i<1024;init_i=init_i+1)palette_mem[init_i]=PALETTE_BITS[init_i*25+:25];\n end\n reg [9:0] index_q;\n reg range_q;\n reg [24:0] pixel_q;\n reg [1:0] valid_q;\n always @(posedge I_clk)begin\n  index_q<=index_mem[I_addr[13:0]];\n'
text+=f"  if(I_addr>=15'd{lo} && I_addr<=15'd{hi})range_q<=1'b1;else range_q<=1'b0;\n"
text+="  pixel_q<=palette_mem[range_q?index_q:10'd0];\n end\n always @(posedge I_clk or negedge I_rst_n)begin\n  if(!I_rst_n)valid_q<=0;else valid_q<={valid_q[0],1'b1};\n end\n assign O_pixel=valid_q[1]?pixel_q:25'd0;\nendmodule\n"
(root/'user_source/hdl_source/anlogic_logo_eram.v').write_text(text,encoding='ascii')
build=root/'sim/build/eram_opt_20261025'
(build/'logo_encoding.json').write_text(json.dumps({'source_entries':len(entries),'exact_colors_including_transparency':len(colors),'index_bits':10,'index_depth':16384,'palette_depth':1024,'address_range':[lo,hi],'exhaustive_32768_address_decode':True},indent=2),encoding='utf-8')
print('Generated lossless logo:',len(colors),'colors, 32768 addresses verified.')

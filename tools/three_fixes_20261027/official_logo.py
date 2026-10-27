"""Losslessly pack the exact lab_ex3 logo into 20-bit dual-index ERAM words."""
from pathlib import Path
import hashlib,json,re
from PIL import Image

root=Path(__file__).resolve().parents[2]
build=root/'sim/build/three_fixes_20261027';hdl=root/'user_source/hdl_source'
source=root.parent/'lab_ex3_osd_SC520/src/hdl_source/anlogic_logo_rom.v'
values=[0]*25600
for a,v in re.findall(r"15'd(\d+): O_pixel = 25'h([0-9a-fA-F]+)",source.read_text()):
    values[int(a)]=int(v,16)
palette=sorted(set(values));assert palette[0]==0 and len(palette)==580
indices={v:n for n,v in enumerate(palette)}
packed=[indices[values[a]]|(indices[values[a+1]]<<10) for a in range(0,25600,2)]
def mif(name,words,width):
    text=f'DEPTH = {len(words)};\nWIDTH = {width};\nADDRESS_RADIX = UNS;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n'
    text+=''.join(f'{n} : {v:0{(width+3)//4}X};\n' for n,v in enumerate(words))+'END;\n'
    (hdl/(name+'.mif')).write_text(text,encoding='ascii')
    (build/(name+'.hex')).write_text(''.join(f'{v:0{(width+3)//4}x}\n' for v in words))
for name,words in [('official_logo_index0',packed[:8192]),('official_logo_index1',packed[8192:12288]),('official_logo_index2',packed[12288:])]:mif(name,words,20)
mif('official_logo_palette',palette+[0]*(1024-len(palette)),25)
for a,v in enumerate(values):assert palette[(packed[a//2]>>(10*(a%2)))&1023]==v
(build/'official_logo_reference.hex').write_text(''.join(f'{v:07x}\n' for v in values+[0]*(32768-25600)))
im=Image.new('RGBA',(160,160));im.putdata([(v>>16&255,v>>8&255,v&255,255 if v>>24 else 0) for v in values]);im.save(build/'official_logo.png')

def primitive(name,width,depth,aw,addr,out):
    return f''' PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A({width}),.ADDR_WIDTH_A({aw}),.DATA_DEPTH_A({depth}),
  .DATA_WIDTH_B({width}),.ADDR_WIDTH_B({aw}),.DATA_DEPTH_B({depth}),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
  .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.INIT_FILE("{name}.mif"),.FILL_ALL("NONE")
 ) u_{name} (
  .dia({width}'d0),.addra({aw}'d0),.cea(1'b0),.ocea(1'b0),.clka(I_clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
  .dib({width}'d0),.addrb({addr}),.ceb(1'b1),.oceb(1'b1),.clkb(I_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob({out}),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
 );\n'''
helper='''// Exact official lab_ex3 160x160 logo: two lossless 10-bit palette indices
// per 20-bit ERAM word. Index stage + palette stage reuse the existing latency.
module anlogic_logo_eram(input wire I_clk,I_rst_n,input wire [16:0] I_addr,output wire [24:0] O_pixel);
 wire [13:0] wa=I_addr[14:1];
 wire [19:0] q0,q1,q2;reg [1:0] bank;reg half;
 always @(posedge I_clk)begin bank<=(wa<8192)?0:((wa<12288)?1:2);half<=I_addr[0];end
 wire [19:0] word_q=(bank==0)?q0:((bank==1)?q1:q2);
 wire [9:0] index_q=half?word_q[19:10]:word_q[9:0];
 wire [24:0] palette_q;
'''
for name,depth,aw,addr,out,width in [('official_logo_index0',8192,13,'wa[12:0]','q0',20),('official_logo_index1',4096,12,'wa[11:0]','q1',20),('official_logo_index2',512,9,'wa[8:0]','q2',20),('official_logo_palette',1024,10,'index_q','palette_q',25)]:helper+=primitive(name,width,depth,aw,addr,out)
helper+=''' reg [1:0] valid;
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)valid<=0;else valid<={valid[0],I_addr<17'd25600};
 assign O_pixel=valid[1]?palette_q:25'd0;
endmodule
'''
mixer=hdl/'hdmi_mixer.v';s=mixer.read_text(encoding='utf-8-sig')
assert "LOGO_W          = 12'd345" in s or "LOGO_W          = 12'd160" in s
s=s.replace("LOGO_W          = 12'd345","LOGO_W          = 12'd160").replace("LOGO_H          = 12'd120","LOGO_H          = 12'd160")
s=s.replace("({S_y,8'b0}+{S_y,6'b0}+{S_y,4'b0}+{S_y,3'b0}+S_y+S_x)","({S_y,7'b0}+{S_y,5'b0}+S_x)")
s=re.sub(r'// LOGO_W=345=.*?S_logo_y \+ S_logo_x;',"// 160=128+32; preserve DSP resources.\n                S_logo_addr = {S_logo_y,7'b0} + {S_logo_y,5'b0} + S_logo_x;",s,flags=re.S)
begin=s.index('// Integrated ERAM logo definition:') if '// Integrated ERAM logo definition:' in s else s.index('// Exact official lab_ex3')
s=s[:begin]+helper
mixer.write_text(s,encoding='utf-8')
print('Official logo exact pixels/alpha preserved; 580 colors, 12800 packed words')

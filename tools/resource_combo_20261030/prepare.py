from pathlib import Path
import re,json,hashlib,sys
r=Path(__file__).resolve().parents[2];tag='resource_combo_20261030'
b=r/'sim/build'/tag;b.mkdir(parents=True,exist_ok=True)
backup=r.parent/'recovery_backups/Anlu2_before_resource_combo_20261030'
for root in [r,backup]:
 for run in ['syn_1','phy_1']:
  p=root/'td_project/camera_to_dsi_display_Runs'/run/'camera_to_dsi_display.prj'
  s=p.read_text(encoding='utf-8')
  s=re.sub(r'<File Path="[^"]*display_color_shading.v">.*?</File>',lambda m:m[0].replace('<Attr Name="AutoExcluded" Val="true"/>','<Attr Name="AutoExcluded" Val="false"/>'),s,flags=re.S)
  p.write_text(s,encoding='utf-8')
if '--config-only' in sys.argv:sys.exit(0)
ref=r/'sim/reference'/tag;ref.mkdir(parents=True,exist_ok=True)
src=backup/'user_source/hdl_source/video/display_color_shading.v'
s=src.read_text(encoding='utf-8')
(ref/'shading_before.v').write_text(s.replace('module display_color_shading #(','module baseline_display_color_shading #('),encoding='utf-8')
values=[]
for name in ['r_gain','b_gain']:
 block=s[s.index('function [9:0] '+name):];block=block[:block.index('endfunction')]
 a=[int(v) for v in re.findall(name+r'=10\x27d(\d+)',block)][:9];assert len(a)==9;values.append(a)
video=r/'user_source/hdl_source/video'
for row in range(3):
 words=[]
 for addr in range(1024):
  side=addr>>9;f=min(addr&511,256);pair=[]
  for nodes in values:
   lo=nodes[row*3+side];hi=nodes[row*3+side+1]
   pair.append(lo+(((hi-lo)*f+128)>>8))
  assert all(0<=v<512 for v in pair)
  words.append(pair[0]|(pair[1]<<9))
 name=f'shading_row{row}'
 (video/(name+'.mif')).write_text('WIDTH=18;\nDEPTH=1024;\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i} : {v:05X};\n' for i,v in enumerate(words))+'END;\n', encoding='utf-8')
 (b/(name+'.hex')).write_text(''.join(f'{v:05x}\n' for v in words), encoding='utf-8')
start=s.index('    reg [9:0] r00,');end=s.index('    reg signed [20:0] r_vertical',start)
s=s[:start]+'''    // Exact pre-rounded horizontal interpolants, two channels per ERAM row.
    // Three 1024x18 ROMs replace four per-pixel horizontal multipliers.
    wire [9:0] row_addr={(x>=640),fx};
    wire [17:0] row0,row1,row2;
    shading_horizontal_rom #(.INIT_FILE("shading_row0.mif")) rom0(clk,row_addr,row0);
    shading_horizontal_rom #(.INIT_FILE("shading_row1.mif")) rom1(clk,row_addr,row1);
    shading_horizontal_rom #(.INIT_FILE("shading_row2.mif")) rom2(clk,row_addr,row2);
    reg bottom_half1;
    reg [9:0] rt_base2,rb_base2,bt_base2,bb_base2;
    reg [9:0] rt3,rb3,bt3,bb3;
    wire signed [8:0] rd=$signed({1'b0,rb3})-$signed({1'b0,rt3});
    wire signed [8:0] bd=$signed({1'b0,bb3})-$signed({1'b0,bt3});
''' + s[end:]
start=s.index('            r00<=256;');end=s.index('            rt_base2<=256;',start)
s=s[:start]+'            bottom_half1<=0;\n'+s[end:]
start=s.index('            // 1: coordinates, node gains.');end=s.index('            // 4/5:',start)
s=s[:start]+'''            // P1 ROM read; P2 row selection; P3 original horizontal boundary.
            fy1<=fy;bottom_half1<=(y>=360);
            rt_base2<=bottom_half1?{1'b0,row1[8:0]}:{1'b0,row0[8:0]};
            rb_base2<=bottom_half1?{1'b0,row2[8:0]}:{1'b0,row1[8:0]};
            bt_base2<=bottom_half1?{1'b0,row1[17:9]}:{1'b0,row0[17:9]};
            bb_base2<=bottom_half1?{1'b0,row2[17:9]}:{1'b0,row1[17:9]};
            fy2<=fy1;
            rt3<=rt_base2;rb3<=rb_base2;bt3<=bt_base2;bb3<=bb_base2;fy3<=fy2;
''' + s[end:]
s=s.replace("($signed({1'b0,rb3})-$signed({1'b0,rt3}))*$signed({1'b0,fy3})","rd*$signed({1'b0,fy3})")
s=s.replace("($signed({1'b0,bb3})-$signed({1'b0,bt3}))*$signed({1'b0,fy3})","bd*$signed({1'b0,fy3})")
s+='''
// Native single-cycle ROM. File is relative to this HDL source directory.
module shading_horizontal_rom #(parameter INIT_FILE="shading_row0.mif")(
 input clk,input [9:0] addr,output [17:0] q);
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(18),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(18),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
 .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
 .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.CLKMODE("ASYNC"),
 .SSROVERCE("DISABLE"),.INIT_FILE(INIT_FILE),.FILL_ALL("NONE")) ram(
 .dia(18'd0),.addra(10'd0),.cea(1'b0),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
 .dib(18'd0),.addrb(addr),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(q),
 .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
endmodule
'''
(video/'display_color_shading.v').write_text(s,encoding='utf-8')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=json.loads((backup/'source_sha256.json').read_text(encoding='utf-8-sig'))
record={'backup':str(backup),'before_source_sha256':before,'before_sdc_sha256':sha(backup/'td_project/camera_to_dsi_display.sdc'),
 'latest_color_nodes':values,'phase':'resource optimization only','production_sha256':{p.relative_to(r).as_posix():sha(p) for p in (r/'user_source').rglob('*') if p.is_file()}}
(b/'record.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print('Prepared exact horizontal ROMs from latest user color nodes:',values)

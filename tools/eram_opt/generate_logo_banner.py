# 将主目录的安路 10 周年 PNG 转成 345x120（原 460x160 的 75%）Logo。
# 位置仍为左上角 (0,0)；使用 64 色 palette，1 像素 = 1 个 6-bit 索引。
from pathlib import Path
from PIL import Image
import numpy as np
import re
from sklearn.cluster import MiniBatchKMeans

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT.parent / "安路10周年.png"
OUT_PNG = ROOT / "doc" / "logo_345x120.png"
W, H = 345, 120
ALPHA_THRESHOLD = 128
PALETTE_DEPTH = 64
INDEX_BITS = 6

im = Image.open(SRC).convert("RGBA")
im = im.resize((W, H), Image.LANCZOS)
im.save(OUT_PNG)

a = np.array(im)
alpha = a[:, :, 3]
rgb = a[:, :, :3].astype(np.uint8)

opaque_mask = alpha >= ALPHA_THRESHOLD
opaque_rgb = rgb[opaque_mask].astype(np.float32)
kmeans = MiniBatchKMeans(
    n_clusters=PALETTE_DEPTH - 1,
    random_state=0,
    batch_size=4096,
    n_init=3,
)
kmeans.fit(opaque_rgb)
centers = np.clip(np.rint(kmeans.cluster_centers_), 0, 255).astype(np.uint8)
labels = kmeans.predict(opaque_rgb).astype(np.uint16)

palette = [0]
for r, g, b in centers:
    palette.append((int(r) << 16) | (int(g) << 8) | int(b))
while len(palette) < PALETTE_DEPTH:
    palette.append(0)

indices = []
label_i = 0
for y in range(H):
    for x in range(W):
        if alpha[y, x] >= ALPHA_THRESHOLD:
            indices.append(int(labels[label_i]) + 1)
            label_i += 1
        else:
            indices.append(0)
assert label_i == len(labels)
assert max(indices) < PALETTE_DEPTH

n = len(indices)
BANK0_DEPTH = 16384
BANK1_DEPTH = 16384
BANK2_DEPTH = 8192
BANK3_DEPTH = 512
assert n <= BANK0_DEPTH + BANK1_DEPTH + BANK2_DEPTH + BANK3_DEPTH

bank0 = indices[:BANK0_DEPTH]
bank1 = indices[BANK0_DEPTH:BANK0_DEPTH + BANK1_DEPTH]
bank2 = indices[BANK0_DEPTH + BANK1_DEPTH:BANK0_DEPTH + BANK1_DEPTH + BANK2_DEPTH]
rest = indices[BANK0_DEPTH + BANK1_DEPTH + BANK2_DEPTH:]
bank3 = rest + [0] * (BANK3_DEPTH - len(rest))
assert len(bank0) == BANK0_DEPTH and len(bank1) == BANK1_DEPTH
assert len(bank2) == BANK2_DEPTH and len(bank3) == BANK3_DEPTH

palette25 = []
for c in palette:
    palette25.append((1 << 24) | c if c else 0)
PALETTE_STORAGE = 512
palette_padded = palette25 + [0] * (PALETTE_STORAGE - len(palette25))


def pack_values(values, width):
    bits = len(values) * width
    assert bits % 512 == 0
    value = 0
    for i, v in enumerate(values):
        value |= v << (i * width)
    mask = (1 << 512) - 1
    words_out = [f"512'h{(value >> i) & mask:0128x}" for i in range(bits - 512, -1, -512)]
    return bits, ",\n".join("  " + w for w in words_out)


def packed_block(name, values, width):
    bits, body = pack_values(values, width)
    return f" localparam [{bits-1}:0] {name}={{\n{body}\n }};\n"


def write_mif(path, depth, width, values):
    digits = (width + 3) // 4
    with path.open("w", encoding="ascii") as f:
        f.write(f"DEPTH = {depth};\nWIDTH = {width};\n")
        f.write("ADDRESS_RADIX = DEC;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n")
        for i, v in enumerate(values):
            f.write(f"{i} : {v:0{digits}x};\n")
        f.write("END;\n")


mif_dir = ROOT / "user_source/hdl_source"
mif0 = mif_dir / "logo_index0.mif"
mif1 = mif_dir / "logo_index1.mif"
mif2 = mif_dir / "logo_index2.mif"
mif3 = mif_dir / "logo_index3.mif"
mifp = mif_dir / "logo_palette.mif"
write_mif(mif0, BANK0_DEPTH, INDEX_BITS, bank0)
write_mif(mif1, BANK1_DEPTH, INDEX_BITS, bank1)
write_mif(mif2, BANK2_DEPTH, INDEX_BITS, bank2)
write_mif(mif3, BANK3_DEPTH, INDEX_BITS, bank3)
write_mif(mifp, PALETTE_DEPTH, 25, palette25)

mifs = [str(p).replace("\\", "/") for p in (mif0, mif1, mif2, mif3, mifp)]

# 行为模型使用完整 65536 深度
index_all = indices + [0] * (65536 - n)
index_bits, index_body = pack_values(index_all, INDEX_BITS)
palette_bits, palette_body = pack_values(palette_padded, 25)

header = """// 345x120 Logo，6-bit 索引 + 64 色 palette，1 像素 1 索引。
// 索引 0 为透明；palette 的 bit24=1 表示颜色有效，bit23:0=RGB888。
// 由 tools/eram_opt/generate_logo_banner.py 从 安路10周年.png 生成。
"""

rom = header + """// 本文件供仿真/参考；硬件实际使用 hdmi_mixer.v 内的 anlogic_logo_eram。
module anlogic_logo_rom (
    input  wire [16:0] I_addr,
    output reg  [24:0] O_pixel
);
"""
rom += f" localparam [{index_bits-1}:0] INDEX_BITS={{\n{index_body}\n }};\n"
rom += f" localparam [{palette_bits-1}:0] PALETTE_BITS={{\n{palette_body}\n }};\n"
rom += """    wire [5:0] index = INDEX_BITS[I_addr[15:0]*6 +: 6];
    always @(*) O_pixel = PALETTE_BITS[index*25 +: 25];
endmodule
"""
(ROOT / "user_source/hdl_source/anlogic_logo_rom.v").write_text(rom, encoding="utf-8")

eram = header + """module anlogic_logo_eram(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [16:0] I_addr,
    output wire [24:0] O_pixel
);
    wire [5:0] idx0_do, idx1_do, idx2_do, idx3_do;
    reg  [1:0] bank_sel_q;
    always @(posedge I_clk) begin
        if (I_addr < 17'd16384)       bank_sel_q <= 2'd0;
        else if (I_addr < 17'd32768)  bank_sel_q <= 2'd1;
        else if (I_addr < 17'd40960)  bank_sel_q <= 2'd2;
        else                          bank_sel_q <= 2'd3;
    end
    wire [5:0] index_do = (bank_sel_q == 2'd0) ? idx0_do :
                          (bank_sel_q == 2'd1) ? idx1_do :
                          (bank_sel_q == 2'd2) ? idx2_do : idx3_do;
    wire [24:0] palette_do;
"""

eram += f"""
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(6), .ADDR_WIDTH_A(14), .DATA_DEPTH_A(16384),
        .DATA_WIDTH_B(6), .ADDR_WIDTH_B(14), .DATA_DEPTH_B(16384),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("OUTREG"),
        .IMPLEMENT("20K(FAST)"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .INIT_FILE("{mifs[0]}"), .FILL_ALL("NONE")
    ) u_idx0 (
        .dia(6'd0), .addra(14'd0), .cea(1'b0), .ocea(1'b0),
        .clka(I_clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib(6'd0), .addrb(I_addr[13:0]), .ceb(1'b1), .oceb(1'b1), .clkb(I_clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(idx0_do),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr()
    );

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(6), .ADDR_WIDTH_A(14), .DATA_DEPTH_A(16384),
        .DATA_WIDTH_B(6), .ADDR_WIDTH_B(14), .DATA_DEPTH_B(16384),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("OUTREG"),
        .IMPLEMENT("20K(FAST)"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .INIT_FILE("{mifs[1]}"), .FILL_ALL("NONE")
    ) u_idx1 (
        .dia(6'd0), .addra(14'd0), .cea(1'b0), .ocea(1'b0),
        .clka(I_clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib(6'd0), .addrb(I_addr[13:0]), .ceb(1'b1), .oceb(1'b1), .clkb(I_clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(idx1_do),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr()
    );

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(6), .ADDR_WIDTH_A(13), .DATA_DEPTH_A(8192),
        .DATA_WIDTH_B(6), .ADDR_WIDTH_B(13), .DATA_DEPTH_B(8192),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("OUTREG"),
        .IMPLEMENT("20K(FAST)"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .INIT_FILE("{mifs[2]}"), .FILL_ALL("NONE")
    ) u_idx2 (
        .dia(6'd0), .addra(13'd0), .cea(1'b0), .ocea(1'b0),
        .clka(I_clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib(6'd0), .addrb(I_addr[12:0]), .ceb(1'b1), .oceb(1'b1), .clkb(I_clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(idx2_do),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr()
    );

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(6), .ADDR_WIDTH_A(9), .DATA_DEPTH_A(512),
        .DATA_WIDTH_B(6), .ADDR_WIDTH_B(9), .DATA_DEPTH_B(512),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("OUTREG"),
        .IMPLEMENT("20K(FAST)"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .INIT_FILE("{mifs[3]}"), .FILL_ALL("NONE")
    ) u_idx3 (
        .dia(6'd0), .addra(9'd0), .cea(1'b0), .ocea(1'b0),
        .clka(I_clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib(6'd0), .addrb(I_addr[8:0]), .ceb(1'b1), .oceb(1'b1), .clkb(I_clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(idx3_do),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr()
    );

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(25), .ADDR_WIDTH_A(6), .DATA_DEPTH_A(64),
        .DATA_WIDTH_B(25), .ADDR_WIDTH_B(6), .DATA_DEPTH_B(64),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("OUTREG"),
        .IMPLEMENT("20K(FAST)"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .INIT_FILE("{mifs[4]}"), .FILL_ALL("NONE")
    ) u_palette (
        .dia(25'd0), .addra(6'd0), .cea(1'b0), .ocea(1'b0),
        .clka(I_clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib(25'd0), .addrb(index_do), .ceb(1'b1), .oceb(1'b1), .clkb(I_clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(palette_do),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr()
    );

    reg [1:0] valid_q;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) valid_q <= 2'd0;
        else          valid_q <= {{valid_q[0], 1'b1}};
    end
    assign O_pixel = valid_q[1] ? palette_do : 25'd0;
endmodule
"""

mixer_path = ROOT / "user_source/hdl_source/hdmi_mixer.v"
mixer = mixer_path.read_text(encoding="utf-8")
pattern = re.compile(r"// Integrated ERAM logo definition.*?endmodule", re.S)
if not pattern.search(mixer):
    raise SystemExit("anlogic_logo_eram module not found")
replacement = "// Integrated ERAM logo definition: keep the mixer self-contained for TD source lists.\n" + eram.rstrip() + "\n"
mixer = pattern.sub(replacement, mixer, count=1)
mixer_path.write_text(mixer, encoding="utf-8")

print(f"logo: {W}x{H}, pixels={n}, palette={PALETTE_DEPTH}")
print(f"colors={len(set(palette))}, max_index={max(indices)}")
print("banks:", BANK0_DEPTH, BANK1_DEPTH, BANK2_DEPTH, BANK3_DEPTH)

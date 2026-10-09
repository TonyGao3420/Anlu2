"""Generate an isolated read-only diagnostic top and TD build script."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'sim' / 'diagnostic'
top = (ROOT / 'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
marker = '    // Official ISP/AWB colors followed by a uniform 17/16 display-only gain.'
assert top.count(marker) == 1
addition = '''    // Read-only diagnostic taps. Production sources and ROI input are unchanged.
    wire [359:0] diag_raw_means;
    wire [8:0] diag_raw_good, diag_raw_clip;
    wire diag_raw_toggle, diag_raw_ack;
    color_raw_probe u_diag_raw (
        .clk(S_csi_rx_clk), .rst_n(S_rst_n),
        .valid(S_raw_tvalid), .user(S_raw_tuser), .last(S_raw_tlast),
        .data(S_raw_tdata), .ack_async(diag_raw_ack),
        .publish_toggle(diag_raw_toggle), .means(diag_raw_means),
        .good(diag_raw_good), .clipped(diag_raw_clip)
    );
    // Register alongside hdmi_mixer's output: camera RGB and its x/y agree,
    // and the measurement never includes the mixer's OSD or ROI pixels.
    reg [23:0] diag_camera_rgb;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) diag_camera_rgb<=0;
        else diag_camera_rgb<=S_video_rd_data;
    wire [215:0] diag_rgb_means;
    wire [8:0] diag_rgb_good, diag_rgb_clip;
    color_rgb_probe u_diag_rgb (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n), .de(S_hdmi_out_de),
        .x(S_hdmi_out_x), .y(S_hdmi_out_y), .rgb(diag_camera_rgb),
        .means(diag_rgb_means), .good(diag_rgb_good), .clipped(diag_rgb_clip), .ready()
    );
    wire diag_vs, diag_hs, diag_de, diag_protect;
    wire [23:0] diag_rgb;
    color_diagnostic_display u_diag_display (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n),
        .vs(S_hdmi_out_vsync), .hs(S_hdmi_out_hsync), .de(S_hdmi_out_de),
        .protect(S_hdmi_out_protect), .x(S_hdmi_out_x), .y(S_hdmi_out_y),
        .rgb(S_hdmi_out_data), .raw_mailbox(diag_raw_means),
        .raw_good_mailbox(diag_raw_good), .raw_clip_mailbox(diag_raw_clip),
        .raw_toggle_async(diag_raw_toggle), .raw_ack(diag_raw_ack),
        .rgb_means(diag_rgb_means), .rgb_good(diag_rgb_good), .rgb_clip(diag_rgb_clip),
        .out_vs(diag_vs), .out_hs(diag_hs), .out_de(diag_de),
        .out_protect(diag_protect), .out_rgb(diag_rgb)
    );

'''
top = top.replace(marker, addition + marker)
for a,b in {
    '.in_vsync  (S_hdmi_out_vsync)': '.in_vsync  (diag_vs)',
    '.in_hsync  (S_hdmi_out_hsync)': '.in_hsync  (diag_hs)',
    '.in_de     (S_hdmi_out_de)': '.in_de     (diag_de)',
    '.in_protect(S_hdmi_out_protect)': '.in_protect(diag_protect)',
    '.in_rgb    (S_hdmi_out_data)': '.in_rgb    (diag_rgb)',
}.items():
    assert top.count(a)==1, a
    top=top.replace(a,b)
(OUT/'design_top_wrapper_diagnostic.v').write_text(top,encoding='utf-8')
script=(ROOT/'td_project/rebuild_validation_official_display_20261009.tcl').read_text()
script=script.replace('td_validation_official_display_20261009','td_validation_color_diagnostic_v2_20261009')
script=script.replace(str(ROOT.as_posix())+'/user_source/hdl_source/design_top_wrapper.v',
                      str((OUT/'design_top_wrapper_diagnostic.v').as_posix()))
script=script.replace('launch_runs -step gate syn_1',
    'add_files {'+str((OUT/'color_diagnostic.v').as_posix())+'}\nlaunch_runs -step gate syn_1')
target=ROOT/'td_project/rebuild_validation_color_diagnostic_20261009.tcl'
target.write_text(script,encoding='utf-8')
print('Generated:',target)
hashes=json.loads((ROOT/'sim/build/backup_color_diagnostic_20261009/production_hashes.json').read_text())
for p,h in hashes.items():
    assert hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h, p
print('All',len(hashes),'production source hashes unchanged.')

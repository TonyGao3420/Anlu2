from pathlib import Path
import hashlib,json,shutil,re
root=Path('Anlu2')
backup=root/'sim/build/backup_shared_color_roi_20261009'
paths=['user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/track2/roi_target_tracker.v','td_project/camera_to_dsi_display.al']
for p in paths:
 dst=backup/p;dst.parent.mkdir(parents=True,exist_ok=True)
 if not dst.exists():shutil.copy2(root/p,dst)
hashes=json.loads((root/'sim/build/backup_color_diagnostic_20261009/production_hashes.json').read_text())
for p,h in hashes.items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
(backup/'production_before_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
shading=(root/'sim/color_trial/display_color_shading.v').read_text()
shading=shading.replace('// Measured white-field DISPLAY-ONLY trial. Does not feed ROI, AWB or sensor.',
 '// Measured white-field correction, shared by camera display and green ROI.\n// Located after DDR, before OSD selection/brightness; ISP/AWB/sensor unchanged.')
(root/'user_source/hdl_source/video/display_color_shading.v').write_text(shading,encoding='ascii')
stream=r'''// One corrected camera stream feeds both ROI and display.
// Raster coordinates are reconstructed from VS/DE, independent of mixer's
// one-pixel SOF coordinate convention. Never modifies DDR request timing.
// Camera RGB is registered alongside mixer RGB, before OSD composition.
module scene_color_stream #(
    parameter integer W=1280,H=720
)(
    input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,
    input wire [23:0] camera_rgb,mixed_rgb,
    output wire out_vs,out_hs,out_de,out_protect,
    output wire [23:0] display_rgb,roi_rgb,
    output wire roi_de,roi_sof,roi_last
);
    reg vs_d,armed;
    reg [11:0] x,y;
    reg [7:0] protect_pipe,armed_pipe,sof_pipe,last_pipe;
    reg [23:0] mixed_pipe[0:7];
    wire [23:0] corrected;
    wire corrected_de;
    assign out_de=corrected_de;
    assign out_protect=protect_pipe[7];
    assign display_rgb=!corrected_de?24'd0:
                       (protect_pipe[7]?mixed_pipe[7]:corrected);
    assign roi_rgb=corrected;
    assign roi_de=corrected_de && armed_pipe[7];
    assign roi_sof=sof_pipe[7];
    assign roi_last=last_pipe[7];
    display_color_shading corrector(
        .clk(clk),.rst_n(rst_n),.in_vs(in_vs),.in_hs(in_hs),.in_de(in_de),
        .in_protect(1'b0),.x(x),.y(y),.in_rgb(camera_rgb),
        .out_vs(out_vs),.out_hs(out_hs),.out_de(corrected_de),
        .out_protect(),.out_rgb(corrected)
    );
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;armed<=0;x<=0;y<=0;
            protect_pipe<=0;armed_pipe<=0;sof_pipe<=0;last_pipe<=0;
            for(i=0;i<8;i=i+1) mixed_pipe[i]<=0;
        end else begin
            vs_d<=in_vs;
            // VS begins in vertical blank; all active pixels follow it.
            if(in_vs && !vs_d) begin x<=0;y<=0;armed<=1;end
            else if(in_de && armed) begin
                if(x==W-1) begin x<=0;y<=(y==H-1)?12'd0:y+1'b1;end
                else x<=x+1'b1;
            end
            protect_pipe<={protect_pipe[6:0],in_protect};
            armed_pipe<={armed_pipe[6:0],armed};
            sof_pipe<={sof_pipe[6:0],in_de && armed && x==0 && y==0};
            last_pipe<={last_pipe[6:0],in_de && armed && x==W-1};
            mixed_pipe[0]<=mixed_rgb;
            for(i=1;i<8;i=i+1) mixed_pipe[i]<=mixed_pipe[i-1];
        end
    end
endmodule
'''
(root/'user_source/hdl_source/video/scene_color_stream.v').write_text(stream,encoding='ascii')
p=root/'user_source/hdl_source/track2/roi_target_tracker.v';s=p.read_text()
s=s.replace('// 90..150 degree hue, >=25% saturation, >=12 chroma, G>=MIN_VALUE.',
 '// 90..150 degree hue, >=25% saturation, >=12 chroma, G>=MIN_VALUE.\n// Near-clipped G additionally needs >=25% separation from BOTH R and B.')
s=s.replace('parameter integer MIN_VALUE=24, MIN_AREA=128, MAX_AREA=120000',
 'parameter integer MIN_VALUE=24, MIN_AREA=128, MAX_AREA=120000,\n    parameter integer HIGHLIGHT_G=248')
marker='    wire green_match='
assert s.count(marker)==1
addition='''    wire [7:0] rb_max=(rgb_pipe[23:16]>rgb_pipe[7:0])?rgb_pipe[23:16]:rgb_pipe[7:0];
    wire [7:0] both_green_gap=(rgb_pipe[15:8]>rb_max)?rgb_pipe[15:8]-rb_max:8'd0;
    // Keep saturated pure/light greens. Reject ambiguous near-clipped whites
    // when only the lower of R/B made the old saturation test look green.
    wire highlight_ok=(rgb_pipe[15:8]<HIGHLIGHT_G) ||
                      (both_green_gap>=(rgb_pipe[15:8]>>2));
'''
s=s.replace(marker,addition+marker)
s=s.replace('(rgb_pipe[15:8]>=MIN_VALUE);','(rgb_pipe[15:8]>=MIN_VALUE) && highlight_ok;')
old=(backup/'user_source/hdl_source/track2/roi_target_tracker.v').read_text()
assert old[old.index('module green_region_tracker'):]==s[s.index('module green_region_tracker'):]
p.write_text(s,encoding='utf-8')
p=root/'user_source/hdl_source/design_top_wrapper.v';top=p.read_text(encoding='utf-8-sig')
old_comment='''    // Read-only detector tap: it observes the exact RGB/DE stream consumed by
    // the mixer and cannot stall or alter the official DDR-to-HDMI video path.
'''
assert top.count(old_comment)==1
addition='''    // One calibrated camera stream for ROI and display; overlays stay separate.
    // Register pre-OSD camera RGB on the same edge as hdmi_mixer's output.
    reg [23:0] S_camera_rgb_aligned;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) S_camera_rgb_aligned<=0;
        else S_camera_rgb_aligned<=S_video_rd_data;
    wire S_color_vs,S_color_hs,S_color_de,S_color_protect;
    wire S_color_roi_de,S_color_roi_sof,S_color_roi_last;
    wire [23:0] S_color_display_rgb,S_color_roi_rgb;
    scene_color_stream u_scene_color_stream(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_out_vsync),.in_hs(S_hdmi_out_hsync),.in_de(S_hdmi_out_de),
        .in_protect (S_hdmi_out_protect),.camera_rgb(S_camera_rgb_aligned),
        .mixed_rgb(S_hdmi_out_data),
        .out_vs(S_color_vs),.out_hs(S_color_hs),.out_de(S_color_de),
        .out_protect(S_color_protect),.display_rgb(S_color_display_rgb),
        .roi_rgb(S_color_roi_rgb),.roi_de(S_color_roi_de),
        .roi_sof(S_color_roi_sof),.roi_last(S_color_roi_last)
    );

    // Read-only ROI tap on corrected camera pixels, before OSD and brightness.
'''
top=top.replace(old_comment,addition)
for a,b in {'.in_frame_start  (S_hdmi_user)':'.in_frame_start  (S_color_roi_sof)',
 '.in_de           (S_hdmi_window_rd_en)':'.in_de           (S_color_roi_de)',
 '.in_line_last    (S_hdmi_last)':'.in_line_last    (S_color_roi_last)',
 '.in_rgb          (S_video_rd_data)':'.in_rgb          (S_color_roi_rgb)',
 '.in_vsync  (S_hdmi_out_vsync)':'.in_vsync  (S_color_vs)',
 '.in_hsync  (S_hdmi_out_hsync)':'.in_hsync  (S_color_hs)',
 '.in_de     (S_hdmi_out_de)':'.in_de     (S_color_de)',
 '.in_protect(S_hdmi_out_protect)':'.in_protect(S_color_protect)',
 '.in_rgb    (S_hdmi_out_data)':'.in_rgb    (S_color_display_rgb)'}.items():
 assert top.count(a)==1,(a,top.count(a));top=top.replace(a,b)
top=top.replace('// Official ISP/AWB colors followed by a uniform 17/16 display-only gain.',
 '// Shared measured color correction followed by uniform 17/16 display-only gain.')
p.write_text(top,encoding='utf-8')
p=root/'td_project/camera_to_dsi_display.al';al=p.read_text(encoding='utf-8-sig')
new=''
for i,name in enumerate(['display_color_shading','scene_color_stream']):
 new+=f'''            <File Path="../user_source/hdl_source/video/{name}.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{56+i}"/>
                </FileInfo>
            </File>
'''
assert al.count('        </Verilog>')==1
al=al.replace('        </Verilog>',new+'        </Verilog>')
p.write_text(al,encoding='utf-8')
script=(root/'td_project/rebuild_validation_official_display_20261009.tcl').read_text()
script=script.replace('td_validation_official_display_20261009','td_validation_shared_color_roi_20261009')
imports=''.join(f'add_files {{D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/video/{n}.v}}\n' for n in ['display_color_shading','scene_color_stream'])
script=script.replace('launch_runs -step gate syn_1',imports+'launch_runs -step gate syn_1')
(root/'td_project/rebuild_validation_shared_color_roi_20261009.tcl').write_text(script,encoding='utf-8')
print('Backed up production, added one shared correction path; region/stability module unchanged.')

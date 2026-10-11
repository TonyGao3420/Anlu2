from pathlib import Path
r=Path('Anlu2');p=r/'user_source/hdl_source/hdmi_mixer.v';s=p.read_text(encoding='utf-8-sig')
s=s.replace('parameter integer OSD_ENABLE = 1,','parameter integer OSD_ENABLE = 1,\n    parameter integer CENTER_OSD_ENABLE = 1,')
s=s.replace('Frame-level target bounds from the single-red-object tracker.', 'Frame-level target bounds from the single-green-object tracker.')
needle='    assign O_video_rd_en = I_video_de;';assert s.count(needle)==1
s=s.replace(needle,'''    // The tracker publishes at corrected-camera SOF, a few clocks after mixer SOF.
    // Capture on line 1 so both axes use that complete result, well before the HUD.
    wire S_center_hit;
    wire [23:0] S_center_rgb;
    wire S_center_valid;
    wire [15:0] S_center_x,S_center_y;
    generate if (OSD_ENABLE && CENTER_OSD_ENABLE) begin: center_hud
        roi_center_osd #(.IMG_W(IMG_WIDTH),.IMG_H(IMG_HEIGHT)) coordinates (
            .clk(I_clk),.rst_n(I_rst_n),
            .capture(I_video_de && S_x==12'd0 && S_y==12'd1),
            .bbox_valid(I_target_bbox_valid),
            .bbox_x0(I_target_bbox_x0),.bbox_y0(I_target_bbox_y0),
            .bbox_x1(I_target_bbox_x1),.bbox_y1(I_target_bbox_y1),
            .pixel_x(S_x_2d),.pixel_y(S_y_2d),
            .hit(S_center_hit),.rgb(S_center_rgb),
            .center_valid(S_center_valid),.center_x(S_center_x),.center_y(S_center_y));
    end else begin: no_center_hud
        assign S_center_hit=1'b0;assign S_center_rgb=24'd0;
        assign S_center_valid=1'b0;assign S_center_x=16'd0;assign S_center_y=16'd0;
    end endgenerate

'''+needle)
needle='        // Draw a clean two-pixel rectangular box instead of marking mask pixels.';assert s.count(needle)==1
s=s.replace(needle,'''        // Protect the complete coordinate HUD (glyph and black background) from ISP gains.
        if (S_video_de_2d && S_center_hit) begin
            S_osd_hit   = 1'b1;
            S_osd_color = S_center_rgb;
        end

'''+needle)
p.write_text(s,encoding='utf-8')
for p in [r/'td_project/camera_to_dsi_display.al']+[r/f'td_project/camera_to_dsi_display_Runs/{stage}/camera_to_dsi_display.prj' for stage in ['syn_1','phy_1']]:
 s=p.read_text(encoding='utf-8');assert 'roi_center_osd.v' not in s
 prefix='../' if p.suffix=='.al' else '../../../'
 entry='''            <File Path="'''+prefix+'''user_source/hdl_source/video/roi_center_osd.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="100"/>
                </FileInfo>
            </File>
'''
 assert s.count('        </Verilog>')==1;s=s.replace('        </Verilog>',entry+'        </Verilog>');p.write_text(s,encoding='utf-8')
print('Added frame-stable decimal center HUD; main project and both main run snapshots updated.')

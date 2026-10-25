from pathlib import Path
root=Path(__file__).resolve().parents[2]
backup=root.parent/'recovery_backups/Anlu2_before_style_mode_20261025'
old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
new=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
decl=old[old.index('    wire         S_hdmi_vsync;'):old.index('    reg          S_dbg_raw_seen;')]
parts=[]
for name,s,tail in [('baseline_display_path',old,'S_tone'),('isolated_display_path',new,'S_trail')]:
 region=s[s.index('    // One calibrated camera stream'):s.index('    hdmi_tx u_hdmi_tx (')]
 parts.append(f"""// Extracted from current original/merged top; all servo logic is real RTL.
module {name}(input clk,rst,vs,hs,de,user,last,input [23:0] camera,
 input sw1,sw2,output ov,oh,od,output [23:0] rgb);
 {decl}
 wire S_hdmi_pixel_clk=clk,S_hdmi_rst_n=rst,I_sys_clk=clk,I_rst_n=rst;
 wire I_sw1=sw1,I_sw2=sw2;
 wire O_servo_pan,O_servo_tilt;
 wire [3:0] S_hdmi_debug_status=0;
 assign S_hdmi_vsync=vs;assign S_hdmi_hsync=hs;assign S_hdmi_de=de;
 assign S_hdmi_user=user;assign S_hdmi_last=last;assign S_video_rd_data=camera;
 {region}
 assign ov={tail}_vs;assign oh={tail}_hs;assign od={tail}_de;assign rgb={tail}_rgb;
endmodule
""")
(root/'sim/tb/style_mode/extracted_display_paths.v').write_text('\n'.join(parts),encoding='utf-8')
print('Extracted latest baseline and merged actual display/ROI/SW1-servo paths.')

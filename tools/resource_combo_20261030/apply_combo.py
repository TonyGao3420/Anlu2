from pathlib import Path
import json,shutil,re,hashlib
r=Path(__file__).resolve().parents[2];b=r/'sim/build/resource_combo_20261030'
assert 'PASS resource_equivalence:' in (b/'opt_equivalence.log').read_text(errors='replace', encoding='utf-8-sig')
assert 'PASS color_equivalence:' in (b/'color_equivalence.log').read_text(errors='replace', encoding='utf-8-sig')
q=(r/'td_project/camera_to_dsi_display_Runs/phy_1/route.qor').read_text(encoding='utf-8-sig')
for label in ['Setup WNS','Hold WNS','Setup TNS','Hold TNS']:
 v=int(re.search(r'\|\s*'+label+r'\s*\|\s*(-?\d+)',q)[1]);assert v>=0
assert (r/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit').stat().st_mtime>(b/'opt_synthesis.log').stat().st_mtime
snap=b/'optimization_passed';assert not snap.exists();snap.mkdir()
for n in ['route.qor','camera_to_dsi_display.bit','camera_to_dsi_display_pr.timing']:
 shutil.copy2(r/'td_project/camera_to_dsi_display_Runs/phy_1'/n,snap/n)
shutil.copytree(r/'user_source',snap/'user_source')
shutil.copy2(b/'opt_synthesis.log',snap/'synthesis.log');shutil.copy2(b/'opt_route.log',snap/'route.log')
(snap/'before_combo_top.v').write_bytes((r/'user_source/hdl_source/design_top_wrapper.v').read_bytes())
p=r/'user_source/hdl_source/video/roi_background_stylize.v';s=p.read_text(encoding='utf-8')
s=s.replace('parameter integer CLEAN_STYLE_ENABLE=0,','parameter integer CLEAN_STYLE_ENABLE=0,MULTI_ROI_ENABLE=0,')
s=s.replace('output wire [23:0] out_rgb,output wire out_roi,output wire out_enable','output wire [23:0] out_rgb,output wire out_roi,output wire out_enable,\n input wire multi_mode,input wire [7:0] multi_valid,\n input wire [95:0] multi_x0,multi_y0,multi_x1,multi_y1')
s=s.replace('wire keep_roi=use_valid','wire keep_single=use_valid',1)
at=s.index(' // Display-only green selection')
s=s[:at]+''' // Reuse the existing one-bit ROI metadata and video RAM for the union.
 wire keep_roi;
 generate if(MULTI_ROI_ENABLE)begin: multi_roi
  reg fm;reg [7:0] fv;reg [95:0] fx0,fy0,fx1,fy1;
  wire [7:0] roi_hits,first_hits;
  genvar ri;
  for(ri=0;ri<8;ri=ri+1)begin: target
   assign roi_hits[ri]=fv[ri] && x>=fx0[ri*12+:12] && x<=fx1[ri*12+:12] && y>=fy0[ri*12+:12] && y<=fy1[ri*12+:12];
   // At first_pixel x=y=0, unsigned upper bounds always include zero.
   assign first_hits[ri]=multi_valid[ri] && multi_x0[ri*12+:12]==0 && multi_y0[ri*12+:12]==0;
  end
  always @(posedge clk or negedge rst_n)if(!rst_n)begin fm<=0;fv<=0;fx0<=0;fy0<=0;fx1<=0;fy1<=0;end
  else if(first_pixel)begin fm<=multi_mode;fv<=multi_valid;fx0<=multi_x0;fy0<=multi_y0;fx1<=multi_x1;fy1<=multi_y1;end
  assign keep_roi=first_pixel?(multi_mode?(|first_hits):keep_single):(fm?(|roi_hits):keep_single);
 end else begin: single_roi
  assign keep_roi=keep_single;
 end endgenerate
''' +s[at:];p.write_text(s,encoding='utf-8')
p=r/'user_source/hdl_source/design_top_wrapper.v';s=p.read_text(encoding='utf-8')
s=s.replace('fourth mode overrides SW2.','multi-target enable; independent of SW2.')
s=s.replace('.CLEAN_STYLE_ENABLE(1),.MODEL_EDGE_THRESHOLD(32)', '.CLEAN_STYLE_ENABLE(1),.MULTI_ROI_ENABLE(1),.MODEL_EDGE_THRESHOLD(32)')
s=s.replace('S_style_request && !S_multi_frame && !CALIBRATION_MODE','S_style_request && !CALIBRATION_MODE')
s=s.replace('.bbox_valid(S_track2_valid),.bbox_x0(S_track2_bbox_x0)', '.multi_mode(S_multi_frame),.multi_valid(S_multi_valid),.multi_x0(S_multi_x0),.multi_y0(S_multi_y0),.multi_x1(S_multi_x1),.multi_y1(S_multi_y1),\n        .bbox_valid(S_track2_valid),.bbox_x0(S_track2_bbox_x0)')
s=s.replace('multi_target_overlay u_multi_overlay(', 'multi_target_overlay #(.COMBO_STATUS(1)) u_multi_overlay(')
s=s.replace('.enable(CALIBRATION_MODE ?', '.style_active(S_style_enable),.enable(CALIBRATION_MODE ?')
p.write_text(s,encoding='utf-8')
p=r/'user_source/hdl_source/hdmi_mixer.v';s=p.read_text(encoding='utf-8')
s=s.replace('module multi_target_overlay #(parameter integer W=1280,H=720,N=8)', 'module multi_target_overlay #(parameter integer W=1280,H=720,N=8,COMBO_STATUS=0)')
s=s.replace('input wire enable,input wire [N-1:0] valid', 'input wire style_active,input wire enable,input wire [N-1:0] valid')
s=s.replace('reg mode;reg [N-1:0] fv;', 'reg mode,style_mode;reg [N-1:0] fv;')
s=s.replace('y<=0;mode<=0;fv<=0;', 'y<=0;mode<=0;style_mode<=0;fv<=0;')
s=s.replace('mode<=enable;fv<=valid;', 'mode<=enable;style_mode<=COMBO_STATUS?style_active:1\x27b0;fv<=valid;')
s=s.replace('9:ch="I";endcase', '9:ch="I";10:ch=style_mode?"+":" ";11:ch=style_mode?"S":" ";12:ch=style_mode?"T":" ";13:ch=style_mode?"Y":" ";14:ch=style_mode?"L":" ";15:ch=style_mode?"E":" ";endcase')
p.write_text(s,encoding='utf-8')
m=json.loads((b/'record.json').read_text(encoding='utf-8-sig'));m['phase']='combination mode';m['production_sha256']={p.relative_to(r).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (r/'user_source').rglob('*') if p.is_file()}
(b/'record.json').write_text(json.dumps(m,indent=2), encoding='utf-8')
print('Optimization passed all checks. Applied independent SW2/SW3 union-ROI combination without new video RAM or detector.')

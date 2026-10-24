from pathlib import Path
import json
root=Path('Anlu2')
rgb=[(0x44,0x41,0x42),(0x46,0x4c,0x45),(0x3a,0x3a,0x3d),
     (0x49,0x44,0x47),(0x49,0x55,0x4a),(0x3f,0x3e,0x42),
     (0x44,0x3e,0x43),(0x46,0x4d,0x47),(0x39,0x38,0x3e)]
points=[]
for n,(r,g,b) in enumerate(rgb):
 rg=round(256*(g-14)/(r-14));bg=round(256*(g-14)/(b-14))
 assert 224<=rg<=310 and 224<=bg<=310
 points.append(dict(node=n,x=[128,640,1152][n%3],y=[90,360,630][n//3],rgb=[r,g,b],r_gain_q8=rg,b_gain_q8=bg))
report=dict(purpose='provisional_display_only_flat_field_trial',photo='0cd0cb898d378aefd5260e57609c96b7.jpg',
 user_confirmed_full_field_neutral=True,raw_black_reported_hex=['040','041'],rgb_black_reported_hex=['0E','0F'],
 rgb_pivot=14,green_gain_q8=256,brightness_gain_all_channels_q8=272,
 rgb_q_caveat='Q=1000. Actual VTC+mixer simulation reproduces 921600 DE samples, nine complete 2048-sample windows, but diagnostic coordinate-based frame count 921599. RGB means used provisionally only in isolated trial; no production correction enabled.',
 interpolation='bilinear, clamp outside measured rectangle; vertical fractional weight rounded to 1/256',points=points)
(root/'sim/build/color_trial_20261009/calibration.json').write_text(json.dumps(report,indent=2)+'\n')
case_r='\n'.join(f"            4'd{p['node']}: r_gain=10'd{p['r_gain_q8']};" for p in points)
case_b='\n'.join(f"            4'd{p['node']}: b_gain=10'd{p['b_gain_q8']};" for p in points)
rtl=r'''// Measured white-field DISPLAY-ONLY trial. Does not feed ROI, AWB or sensor.
// Eight pipeline clocks. Same latency for RGB/VS/HS/DE/protection.
// Nine measured nodes, continuous bilinear gain, clamped beyond outer nodes.
// G is unchanged here; the existing downstream 17/16 RGB gain remains uniform.
module display_color_shading #(
    parameter integer ENABLE=1,
    parameter integer BLACK_PIVOT=14
)(
    input wire clk,rst_n,
    input wire in_vs,in_hs,in_de,in_protect,
    input wire [11:0] x,y,
    input wire [23:0] in_rgb,
    output wire out_vs,out_hs,out_de,out_protect,
    output reg [23:0] out_rgb
);
    function [9:0] r_gain;
        input [3:0] node;
        begin case(node)
@R@
            default:r_gain=10'd256;
        endcase end
    endfunction
    function [9:0] b_gain;
        input [3:0] node;
        begin case(node)
@B@
            default:b_gain=10'd256;
        endcase end
    endfunction
    reg [3:0] tl;
    reg [8:0] fx,fy;
    reg [8:0] dy;
    reg [17:0] scaled_y;
    always @* begin
        tl=((y<360)?4'd0:4'd3)+((x<640)?4'd0:4'd1);
        if(x<=128) fx=0;
        else if(x>=1152) fx=256;
        else if(x<640) fx=(x-128)>>1;
        else fx=(x-640)>>1;
        dy=0;scaled_y=0;
        if(y<=90) fy=0;
        else if(y>=630) fy=256;
        else begin
            dy=(y<360)?y-90:y-360;
            // 243/256 approximates 256/270; max error < one weight step.
            scaled_y=dy*8'd243+18'd128;
            fy=scaled_y[16:8];
        end
    end
    reg [7:0] vp,hp,dp,pp;
    reg [23:0] raw[0:6];
    assign out_vs=vp[7];assign out_hs=hp[7];
    assign out_de=dp[7];assign out_protect=pp[7];
    reg [8:0] fx1,fy1,fy2,fy3;
    reg [9:0] r00,r01,r10,r11,b00,b01,b10,b11;
    reg signed [20:0] rt_product,rb_product,bt_product,bb_product;
    reg [9:0] rt_base2,rb_base2,bt_base2,bb_base2;
    reg [9:0] rt3,rb3,bt3,bb3;
    reg signed [20:0] r_vertical,b_vertical;
    reg [9:0] r_base4,b_base4;
    reg [9:0] r5,b5,r6,b6;
    reg [7:0] red_delta,blue_delta;
    reg [17:0] red_product,blue_product;
    function [7:0] finish_channel;
        input [7:0] original;
        input [17:0] product;
        reg [18:0] lifted;
        begin
            lifted=BLACK_PIVOT+((product+19'd128)>>8);
            if(original<=BLACK_PIVOT) finish_channel=original;
            else if(lifted>255) finish_channel=255;
            else finish_channel=lifted[7:0];
        end
    endfunction
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vp<=0;hp<=0;dp<=0;pp<=0;out_rgb<=0;
            for(i=0;i<7;i=i+1) raw[i]<=0;
            fx1<=0;fy1<=0;fy2<=0;fy3<=0;
            r00<=256;r01<=256;r10<=256;r11<=256;
            b00<=256;b01<=256;b10<=256;b11<=256;
            rt_product<=0;rb_product<=0;bt_product<=0;bb_product<=0;
            rt_base2<=256;rb_base2<=256;bt_base2<=256;bb_base2<=256;
            rt3<=256;rb3<=256;bt3<=256;bb3<=256;
            r_vertical<=0;b_vertical<=0;r_base4<=256;b_base4<=256;
            r5<=256;b5<=256;r6<=256;b6<=256;
            red_delta<=0;blue_delta<=0;red_product<=0;blue_product<=0;
        end else begin
            vp<={vp[6:0],in_vs};hp<={hp[6:0],in_hs};
            dp<={dp[6:0],in_de};pp<={pp[6:0],in_protect};
            raw[0]<=in_rgb;for(i=1;i<7;i=i+1) raw[i]<=raw[i-1];
            // 1: coordinates, node gains.
            fx1<=fx;fy1<=fy;
            r00<=r_gain(tl);r01<=r_gain(tl+4'd1);
            r10<=r_gain(tl+4'd3);r11<=r_gain(tl+4'd4);
            b00<=b_gain(tl);b01<=b_gain(tl+4'd1);
            b10<=b_gain(tl+4'd3);b11<=b_gain(tl+4'd4);
            // 2: horizontal products, signed to allow lower edge gains.
            rt_product<=($signed({1'b0,r01})-$signed({1'b0,r00}))*$signed({1'b0,fx1});
            rb_product<=($signed({1'b0,r11})-$signed({1'b0,r10}))*$signed({1'b0,fx1});
            bt_product<=($signed({1'b0,b01})-$signed({1'b0,b00}))*$signed({1'b0,fx1});
            bb_product<=($signed({1'b0,b11})-$signed({1'b0,b10}))*$signed({1'b0,fx1});
            rt_base2<=r00;rb_base2<=r10;bt_base2<=b00;bb_base2<=b10;fy2<=fy1;
            // 3: two horizontally interpolated rows.
            rt3<=$signed({1'b0,rt_base2})+((rt_product+21'sd128)>>>8);
            rb3<=$signed({1'b0,rb_base2})+((rb_product+21'sd128)>>>8);
            bt3<=$signed({1'b0,bt_base2})+((bt_product+21'sd128)>>>8);
            bb3<=$signed({1'b0,bb_base2})+((bb_product+21'sd128)>>>8);fy3<=fy2;
            // 4/5: vertical interpolation.
            r_vertical<=($signed({1'b0,rb3})-$signed({1'b0,rt3}))*$signed({1'b0,fy3});
            b_vertical<=($signed({1'b0,bb3})-$signed({1'b0,bt3}))*$signed({1'b0,fy3});
            r_base4<=rt3;b_base4<=bt3;
            r5<=$signed({1'b0,r_base4})+((r_vertical+21'sd128)>>>8);
            b5<=$signed({1'b0,b_base4})+((b_vertical+21'sd128)>>>8);
            // 6/7: subtract measured dark pivot, multiply signal, preserve G.
            red_delta<=(raw[4][23:16]>BLACK_PIVOT)?raw[4][23:16]-BLACK_PIVOT:0;
            blue_delta<=(raw[4][7:0]>BLACK_PIVOT)?raw[4][7:0]-BLACK_PIVOT:0;
            r6<=r5;b6<=b5;
            red_product<=red_delta*r6;blue_product<=blue_delta*b6;
            // 8: bounded output; protected OSD/ROI and darks are exact.
            if(!dp[6]) out_rgb<=0;
            else if(!ENABLE || pp[6]) out_rgb<=raw[6];
            else out_rgb<={finish_channel(raw[6][23:16],red_product),raw[6][15:8],
                           finish_channel(raw[6][7:0],blue_product)};
        end
    end
endmodule
'''.replace('@R@',case_r).replace('@B@',case_b)
(root/'sim/color_trial/display_color_shading.v').write_text(rtl,encoding='ascii')
top=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
marker='    // Official ISP/AWB colors followed by a uniform 17/16 display-only gain.'
addition='''    // Isolated trial: 30 seconds of true gray for slow HDMI acquisition.
    reg trial_vs_d;
    reg [10:0] trial_gray_frames;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) begin trial_vs_d<=0;trial_gray_frames<=0;end
        else begin
            trial_vs_d<=S_hdmi_out_vsync;
            if(S_hdmi_out_vsync && !trial_vs_d && trial_gray_frames<1800)
                trial_gray_frames<=trial_gray_frames+1'b1;
        end
    wire trial_gray=(trial_gray_frames<1800);
    wire trial_vs,trial_hs,trial_de,trial_protect;
    wire [23:0] trial_rgb;
    display_color_shading u_display_color_shading (
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_out_vsync),.in_hs(S_hdmi_out_hsync),.in_de(S_hdmi_out_de),
        .in_protect(trial_gray || S_hdmi_out_protect),
        .x(S_hdmi_out_x),.y(S_hdmi_out_y),
        .in_rgb(trial_gray?24'h808080:S_hdmi_out_data),
        .out_vs(trial_vs),.out_hs(trial_hs),.out_de(trial_de),
        .out_protect(trial_protect),.out_rgb(trial_rgb)
    );

'''
assert top.count(marker)==1
top=top.replace(marker,addition+marker)
for a,b in {'.in_vsync  (S_hdmi_out_vsync)':'.in_vsync  (trial_vs)',
 '.in_hsync  (S_hdmi_out_hsync)':'.in_hsync  (trial_hs)',
 '.in_de     (S_hdmi_out_de)':'.in_de     (trial_de)',
 '.in_protect(S_hdmi_out_protect)':'.in_protect(trial_protect)',
 '.in_rgb    (S_hdmi_out_data)':'.in_rgb    (trial_rgb)'}.items():
 assert top.count(a)==1;top=top.replace(a,b)
(root/'sim/color_trial/design_top_wrapper_color_trial.v').write_text(top,encoding='utf-8')
script=(root/'td_project/rebuild_validation_official_display_20261009.tcl').read_text()
script=script.replace('td_validation_official_display_20261009','td_validation_color_trial_20261009')
script=script.replace('user_source/hdl_source/design_top_wrapper.v','sim/color_trial/design_top_wrapper_color_trial.v')
script=script.replace('launch_runs -step gate syn_1','add_files {D:/HX1P35A_Contest_202606/Anlu2/sim/color_trial/display_color_shading.v}\nlaunch_runs -step gate syn_1')
(root/'td_project/rebuild_validation_color_trial_20261009.tcl').write_text(script,encoding='utf-8')
print('Generated isolated display correction trial, gray 1800 frames. Production unchanged.')
print([(p['r_gain_q8'],p['b_gain_q8']) for p in points])

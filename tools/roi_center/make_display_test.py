from pathlib import Path
r=Path('Anlu2')
s=r'''`timescale 1ns/1ps
module tb_roi_center_display;
reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,user=0,last=0,bvalid=0;
reg [15:0] x0=0,y0=0,x1=0,y1=0;reg[23:0] camera=0,camera_q=0;
always @(posedge clk)camera_q<=camera;
wire[1:0] mv,mh,md,mp,rd,sv,sh,sd,sp,rv,rs,rl,ev,eh,ed,ep,vv,vh,vd,tv,th,td;
wire[23:0] mixed[0:1],scene[0:1],roi[0:1],edge_rgb[0:1],enhanced[0:1],final_rgb[0:1];wire[11:0] mx[0:1],my[0:1];
hdmi_mixer_baseline old_mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),
 .I_target_bbox_valid(bvalid),.I_target_bbox_x0(x0),.I_target_bbox_y0(y0),.I_target_bbox_x1(x1),.I_target_bbox_y1(y1),.O_video_rd_en(rd[0]),.I_video_rd_data(camera),
 .O_hdmi_vsync(mv[0]),.O_hdmi_hsync(mh[0]),.O_hdmi_de(md[0]),.O_hdmi_protect(mp[0]),.O_hdmi_data(mixed[0]),.O_hdmi_x(mx[0]),.O_hdmi_y(my[0]));
hdmi_mixer new_mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),
 .I_target_bbox_valid(bvalid),.I_target_bbox_x0(x0),.I_target_bbox_y0(y0),.I_target_bbox_x1(x1),.I_target_bbox_y1(y1),.O_video_rd_en(rd[1]),.I_video_rd_data(camera),
 .O_hdmi_vsync(mv[1]),.O_hdmi_hsync(mh[1]),.O_hdmi_de(md[1]),.O_hdmi_protect(mp[1]),.O_hdmi_data(mixed[1]),.O_hdmi_x(mx[1]),.O_hdmi_y(my[1]));
genvar k;
generate for(k=0;k<2;k=k+1)begin: chain
 scene_color_stream #(.RGB_SHADING_ENABLE(0)) stream(clk,rst,mv[k],mh[k],md[k],mp[k],camera_q,mixed[k],sv[k],sh[k],sd[k],sp[k],scene[k],roi[k],rv[k],rs[k],rl[k]);
 display_edge_color edge_stage(clk,rst,sv[k],sh[k],sd[k],sp[k],scene[k],ev[k],eh[k],ed[k],ep[k],edge_rgb[k]);
 reg[5:0] protect6=0;always @(posedge clk)if(!rst)protect6<=0;else protect6<={protect6[4:0],ep[k]};
 video_enhance #(.ENABLE(0),.GAMMA_ENABLE(0),.SHARPEN_ENABLE(0),.CONTRAST_ENABLE(0),.SATURATION_ENABLE(0),.RGB_GAIN_Q8(256))
 enhance(clk,rst,ev[k],eh[k],ed[k],ep[k],edge_rgb[k],vv[k],vh[k],vd[k],enhanced[k]);
 display_common_tone tone(clk,rst,vv[k],vh[k],vd[k],protect6[5],enhanced[k],tv[k],th[k],td[k],final_rgb[k]);
end endgenerate
integer frame=0,x,y,j,pixels=0,hudpixels=0,postpixels=0,posthud=0,roi_pixels=0,ex=0,ey=0;reg hud;reg[22:0] hud_pipe=0;reg[23:0] rgb_pipe[0:22];
always @(posedge clk)begin
 if(!rst)begin hud_pipe=0;for(j=0;j<23;j=j+1)rgb_pipe[j]=0;end
 else begin
 hud_pipe={hud_pipe[21:0],md[1] && mx[1]>=375 && mx[1]<919 && my[1]>=160 && my[1]<192};
 for(j=22;j>0;j=j-1)rgb_pipe[j]=rgb_pipe[j-1];rgb_pipe[0]=mixed[1];
 #1;
 if({mv[0],mh[0],md[0],rd[0],mx[0],my[0]}!=={mv[1],mh[1],md[1],rd[1],mx[1],my[1]})$fatal(1,"HUD changed DDR/raster alignment");
 if(md[1])begin
 pixels=pixels+1;hud=mx[1]>=375 && mx[1]<919 && my[1]>=160 && my[1]<192;
 if(!hud)begin
 if({mp[0],mixed[0]}!=={mp[1],mixed[1]})$fatal(1,"HUD changed existing logo, box or camera outside panel at %0d,%0d",mx[1],my[1]);
 end else begin
 hudpixels=hudpixels+1;
 if(!mp[1])$fatal(1,"HUD not protected from color/brightness correction");
 if(frame==2)begin if(new_mixer.S_center_valid)$fatal(1,"Lost target still valid");end
 else if(!new_mixer.S_center_valid || $signed(new_mixer.S_center_x)!=ex || $signed(new_mixer.S_center_y)!=ey)$fatal(1,"Integrated HUD center mismatch frame%0d got%0d,%0d want%0d,%0d",frame,new_mixer.S_center_x,new_mixer.S_center_y,ex,ey);
 if(mp[0] && mixed[0]==24'h00ffff && mixed[1]!==mixed[0])$fatal(1,"HUD erased ROI box border");
 end
 end
 if({rv[0],rs[0],rl[0],roi[0]}!=={rv[1],rs[1],rl[1],roi[1]})$fatal(1,"HUD contaminated ROI camera pixels");
 if(rv[1])roi_pixels=roi_pixels+1;
 if({tv[0],th[0],td[0]}!=={tv[1],th[1],td[1]})$fatal(1,"HUD altered final HDMI timing");
 if(td[1])begin
 postpixels=postpixels+1;
 if(hud_pipe[22])begin
 posthud=posthud+1;if(final_rgb[1]!==rgb_pipe[22])$fatal(1,"HUD altered by downstream color correction or misaligned");
 end else if(final_rgb[1]!==final_rgb[0])$fatal(1,"Existing camera color changed outside HUD");
 end
 end
end
initial begin
 repeat(6)@(negedge clk);rst=1;
 for(frame=0;frame<5;frame=frame+1)begin
 @(negedge clk);vs=1;repeat(8)@(negedge clk);vs=0;repeat(60)@(negedge clk);
 for(y=0;y<720;y=y+1)begin
 for(x=0;x<1280;x=x+1)begin
 @(negedge clk);de=1;user=(x==0&&y==0);last=(x==1279);camera={x[7:0],y[7:0],x[7:0]^y[7:0]};
 // Emulate actual tracker publishing after corrected-camera SOF, not at mixer SOF.
 if(x==20 && y==0)begin
 case(frame)
 0:begin bvalid=1;x0=180;y0=260;x1=540;y1=620;ex=-280;ey=80;end
 1:begin bvalid=1;x0=1000;y0=0;x1=1279;y1=719;ex=499;ey=-1;end
 2:begin bvalid=0;x0=0;y0=0;x1=0;y1=0;ex=0;ey=0;end
 3:begin bvalid=1;x0=500;y0=150;x1=600;y1=210;ex=-90;ey=-180;end
 4:begin bvalid=1;x0=620;y0=340;x1=660;y1=380;ex=0;ey=0;end
 endcase
 end
 end
 @(negedge clk);de=0;user=0;last=0;hs=1;repeat(20)@(negedge clk);hs=0;repeat(4)@(negedge clk);
 end
 repeat(64)@(negedge clk);
 end
 if(pixels!=4608000 || postpixels!=pixels || roi_pixels!=pixels || hudpixels!=87040 || posthud!=hudpixels)$fatal(1,"Integration coverage %0d/%0d/%0d HUD%0d/%0d",pixels,postpixels,roi_pixels,hudpixels,posthud);
 $display("PASS roi_center_display: five complete 720p frames with signed screen-center coordinates, delayed SOF publication, movement/loss/reacquire, ROI border priority; 4608000 ROI pixels and every final HDMI pixel outside HUD identical to user-tested color baseline; HUD protected through full color/tone chain");$finish;
end
initial begin #55000000;$fatal(1,"Center integration timeout");end
endmodule
'''
(r/'sim/tb/tb_roi_center_display.sv').write_text(s)
s='''transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/hdmi_mixer.v ../build/roi_origin_center_20261011/hdmi_mixer_baseline.v ../../user_source/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/tb_roi_center_display.sv
vsim -c work.tb_roi_center_display
run -all
quit -f
''';(r/'sim/modelsim/run_roi_center_display.do').write_text(s)
print('Generated five-frame old/new actual mixer + full color/tone comparison.')

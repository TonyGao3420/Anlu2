`timescale 1ns/1ps
module tb_mixer_eram_equivalence;
 localparam W=1280,H=720,HT=1650,VT=750,N=3;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,user=0,last=0;
 reg[23:0] rgb=0;reg valid=0;reg[15:0] x0=0,y0=0,x1=0,y1=0;
 wire[52:0] before_data,after_data;
 wire old_req,old_v,old_h,old_d,old_p;wire[23:0] old_rgb;wire[11:0] old_x,old_y;
 baseline_hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(W),.IMG_HEIGHT(H)) old(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_target_bbox_valid(valid),.I_target_bbox_x0(x0),.I_target_bbox_y0(y0),.I_target_bbox_x1(x1),.I_target_bbox_y1(y1),
 .O_video_rd_en(old_req),.I_video_rd_data(rgb),.O_hdmi_vsync(old_v),.O_hdmi_hsync(old_h),.O_hdmi_de(old_d),
 .O_hdmi_protect(old_p),.O_hdmi_data(old_rgb),.O_hdmi_x(old_x),.O_hdmi_y(old_y));
 assign before_data={old_req,old_v,old_h,old_d,old_p,old_rgb,old_x,old_y};
 wire optimized_req,optimized_v,optimized_h,optimized_d,optimized_p;wire[23:0] optimized_rgb;wire[11:0] optimized_x,optimized_y;
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(W),.IMG_HEIGHT(H)) optimized(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_target_bbox_valid(valid),.I_target_bbox_x0(x0),.I_target_bbox_y0(y0),.I_target_bbox_x1(x1),.I_target_bbox_y1(y1),
 .O_video_rd_en(optimized_req),.I_video_rd_data(rgb),.O_hdmi_vsync(optimized_v),.O_hdmi_hsync(optimized_h),.O_hdmi_de(optimized_d),
 .O_hdmi_protect(optimized_p),.O_hdmi_data(optimized_rgb),.O_hdmi_x(optimized_x),.O_hdmi_y(optimized_y));
 assign after_data={optimized_req,optimized_v,optimized_h,optimized_d,optimized_p,optimized_rgb,optimized_x,optimized_y};
 reg measure=1;integer pixels=0,opaque=0,transparent=0;
 always @(posedge clk)begin #1;if(rst)begin
  if(before_data!==after_data)$fatal(1,"Mixer behavior/latency changed pixel%0d x%0d y%0d got%h want%h",pixels,old_x,old_y,after_data,before_data);
  if(old_d && measure)begin
   pixels=pixels+1;
   if(old_x<160 && old_y<160)begin
    if(old.S_logo_pixel[24])opaque=opaque+1;else transparent=transparent+1;
   end
  end
 end end
 integer f,line,col;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)begin
   valid=(f!=2);x0=(f==0)?40:1120;y0=(f==0)?40:600;x1=x0+80;y1=y0+100;
   for(line=0;line<VT;line=line+1)for(col=0;col<HT;col=col+1)begin
    @(negedge clk);vs=(line<3);hs=(col>=1390 && col<1430);
    de=(line>=6 && line<6+H && col<W);user=de && line==6 && col==0;last=de && col==W-1;
    rgb={8'(col+f*23),8'(line+f*37),8'(col^line)};
   end
  end
  @(negedge clk);vs=0;hs=0;de=0;user=0;last=0;repeat(8)@(negedge clk);
  if(pixels!=N*W*H || opaque<19000 || transparent<50000)$fatal(1,"Mixer coverage missing %0d %0d %0d",pixels,opaque,transparent);
  measure=0;
  de=1;repeat(30)@(negedge clk);rst=0;
  repeat(3)@(negedge clk);de=0;rst=1;
  for(line=0;line<64;line=line+1)for(col=0;col<HT;col=col+1)begin
   @(negedge clk);de=(col<W);user=(line==0 && col==0);last=de && col==W-1;
   rgb={8'(col),8'(line),8'(col^line)};
  end
  @(negedge clk);de=0;user=0;last=0;repeat(8)@(negedge clk);
  $display("PASS mixer_eram_equivalence: %0d full 720p pixels, opaque%0d transparent%0d; RGB/OSD/ROI/coordinates/DDR request/sync cycle-exact, active-raster reset recovery",pixels,opaque,transparent);$finish;
 end
endmodule

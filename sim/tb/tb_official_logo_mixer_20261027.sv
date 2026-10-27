`timescale 1ns/1ps
module tb_official_logo_mixer;
 reg clk=0;always #5 clk=~clk;reg rst=0,de=0,user=0,last=0;
 wire od,protect;wire [23:0] rgb;wire [11:0] ox,oy;
 reg [11:0] raster_x=0,raster_y=0;
 wire [14:0] address=raster_y*160+raster_x;wire [24:0] reference;
 anlogic_logo_rom official(address,reference);
 hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.CENTER_OSD_ENABLE(0)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'd0),.I_target_bbox_valid(1'b0),.I_target_bbox_x0(16'd0),.I_target_bbox_y0(16'd0),.I_target_bbox_x1(16'd0),.I_target_bbox_y1(16'd0),
 .O_video_rd_en(),.I_video_rd_data(24'h405060),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(od),.O_hdmi_protect(protect),.O_hdmi_data(rgb),.O_hdmi_x(ox),.O_hdmi_y(oy));
 integer pixels=0,opaque=0,x,y;
 // Count the physical DE raster independently. The inherited mixer debug
 // coordinate has a duplicated (0,0) at SOF; the logo's first row is transparent.
 always @(posedge clk)begin #1;if(rst && od)begin
  if(raster_x<160 && raster_y<160)begin
   if(rgb!==(reference[24]?reference[23:0]:24'h405060) || protect!==reference[24])$fatal(1,"Official mixer logo pixel mismatch x%0d y%0d got%h expected%h",raster_x,raster_y,rgb,reference);
   pixels=pixels+1;if(reference[24])opaque=opaque+1;
  end
  if(raster_x==1279)begin raster_x=0;raster_y=raster_y+1;end else raster_x=raster_x+1;
 end end
 initial begin
  repeat(6)@(negedge clk);rst=1;
  for(y=0;y<160;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge clk);de=1;user=(x==0 && y==0);last=x==1279;end
   @(negedge clk);de=0;user=0;last=0;repeat(30)@(negedge clk);
  end
  repeat(10)@(negedge clk);
  if(pixels!=25600 || opaque!=6387)$fatal(1,"Logo mixer coverage pixels%0d opaque%0d",pixels,opaque);
  $display("PASS official_logo_mixer: 25600 raster pixels, 6387 opaque official pixels, exact position/RGB/alpha/protect, real two-stage prefetch alignment");$finish;
 end
endmodule

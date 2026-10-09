`timescale 1ns/1ps
module tb_color_probe_vtc;
reg clk=0;always #5 clk=~clk;
reg rst=0;
wire vs,hs,de,user,last,ov,oh,od;
wire [23:0] rgb;
wire [11:0] x,y;
wire [215:0] means;
wire [8:0] good,clip;
wire ready;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
 .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc
 (.I_vtc_rstn(rst),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),
 .O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
hdmi_mixer #(.OSD_ENABLE(0)) mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),
 .I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_target_bbox_valid(1'b0),
 .I_target_bbox_x0(16'd0),.I_target_bbox_y0(16'd0),
 .I_target_bbox_x1(16'd0),.I_target_bbox_y1(16'd0),
 .O_video_rd_en(),.I_video_rd_data(24'h285078),.O_hdmi_vsync(ov),.O_hdmi_hsync(oh),
 .O_hdmi_de(od),.O_hdmi_data(rgb),.O_hdmi_protect(),.O_hdmi_x(x),.O_hdmi_y(y));
color_rgb_probe probe(.clk(clk),.rst_n(rst),.de(od),.x(x),.y(y),.rgb(rgb),
 .means(means),.good(good),.clipped(clip),.ready(ready));
integer f=0,i,de_pixels=0;reg vd=0;
always @(posedge clk) if(rst) begin
 if(od) de_pixels=de_pixels+1;
 if(od && y==0 && x<3 && f>0) $display("FIRST frame=%0d x=%0d y=%0d active=%0d pixels=%0d",f,x,y,probe.active,probe.pixels);
 if(ov && !vd) begin
   f=f+1;
   $display("FRAME %0d ready=%b pixels=%0d good=%h means0=%h",f,ready,probe.pixels,good,means[23:0]);
   for(i=0;i<9;i=i+1) $display("NODE %0d count=%0d mean=%h",i,probe.counts[i],means[i*24+:24]);
   if(f>=2) begin
     if(de_pixels!=1280*720) $fatal(1,"Actual DE frame incomplete: %0d",de_pixels);
     if(probe.pixels!=1280*720-1 || good!==9'b0)
       $fatal(1,"Expected diagnostic coordinate/count mismatch not reproduced");
     for(i=0;i<9;i=i+1)
       if(probe.counts[i]!=2048 || means[i*24+:24]!==24'h785028)
         $fatal(1,"Region %0d samples or measured means incorrect",i);
   end
   de_pixels=0;
   if(f==3) begin
     $display("PASS reproduction: full 921600 DE pixels, nine correct window means, diagnostic count one short -> Q RGB invalid");
     $finish;
   end
 end
 vd=ov;
end
initial begin repeat(10) @(negedge clk);rst=1;end
initial begin #50000000; $fatal(1,"Timeout");end
endmodule

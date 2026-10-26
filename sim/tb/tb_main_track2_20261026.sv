`timescale 1ns/1ps
module tb_main_track2;
 localparam W=1280,H=720,HT=1650,VT=750,N=8,TOTAL=W*H*N;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,user=0,last=0,sw1=0,sw2=0;
 reg [23:0] camera=0,pixels[0:TOTAL-1];
 wire bv,bh,bd,nv,nh,nd;wire [23:0] brgb,nrgb;
 baseline_current_path base(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,bv,bh,bd,brgb);
 extended_current_path experimental(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,nv,nh,nd,nrgb);
 reg roi_d1=0,roi_d2=0,vs_d=0,style_mode=0,last_mode=0;
 integer ox=0,oy=0,checked=0,normal=0,foreground=0,osd=0,hud=0,motion=0,trail=0,frames=0,enter=0,leave=0;
 integer f,l,x;reg hud_region;
 always @(posedge clk)begin
  if(!rst)begin roi_d1<=0;roi_d2<=0;end
  else begin
   roi_d1<=base.S_style_roi;roi_d2<=roi_d1;
   if({experimental.S_hdmi_window_rd_en,experimental.S_color_roi_de,experimental.S_color_roi_sof,experimental.S_color_roi_last,experimental.S_color_roi_rgb}!==
      {base.S_hdmi_window_rd_en,base.S_color_roi_de,base.S_color_roi_sof,base.S_color_roi_last,base.S_color_roi_rgb})$fatal(1,"DDR request/detector input changed");
   if({experimental.S_track2_valid,experimental.S_track2_bbox_x0,experimental.S_track2_bbox_y0,experimental.S_track2_bbox_x1,experimental.S_track2_bbox_y1,experimental.S_track2_cx,experimental.S_track2_cy,experimental.O_servo_pan,experimental.O_servo_tilt}!==
      {base.S_track2_valid,base.S_track2_bbox_x0,base.S_track2_bbox_y0,base.S_track2_bbox_x1,base.S_track2_bbox_y1,base.S_track2_cx,base.S_track2_cy,base.O_servo_pan,base.O_servo_tilt})$fatal(1,"Existing ROI/servo behavior changed");
  end
  #1;
  if(rst)begin
   if({nv,nh,nd}!=={bv,bh,bd})$fatal(1,"Extension added display timing delay");
   if(nv && !vs_d)begin ox=0;oy=0;end
   vs_d=nv;
   if(nd)begin
    if(ox==0 && oy==0)begin
     style_mode=experimental.S_style_enable;
     if(style_mode!==(frames==2 || frames==3 || frames==4 || frames==7))$fatal(1,"Mode switch was not frame-atomic");
     if(style_mode && !last_mode)enter=enter+1;if(!style_mode && last_mode)leave=leave+1;
     last_mode=style_mode;frames=frames+1;
     $display("TRACE main output frame%0d style%0d motion_count%0d",frames,style_mode,experimental.u_background_stylize.completed_motion_count);
    end
    hud_region=ox>=1008 && ox<1264 && oy>=16 && oy<48;
    if(experimental.S_trail_hit!==base.S_trail_hit)$fatal(1,"Existing 1s trajectory changed");
    if(base.S_trail_protect || roi_d2)begin
     if(nrgb!==brgb)$fatal(1,"Existing ROI/logo/coordinate/OSD/trail RGB changed at %0d,%0d",ox,oy);
     if(base.S_trail_protect)osd=osd+1;else foreground=foreground+1;
    end else if(hud_region)begin
     if(!experimental.S_trail_protect)$fatal(1,"New status HUD not protected from trail");
     if(nrgb!==24'h080c10 && nrgb!==(style_mode?24'h30e8ff:24'hfff200))$fatal(1,"HUD style metadata/color misaligned");
     hud=hud+1;
    end else if(!style_mode)begin
     if(nrgb!==brgb)$fatal(1,"Normal mode changed outside new HUD");normal=normal+1;
    end else if(nrgb!==brgb)begin
     if(nrgb!==24'h30c8d8 && !(nrgb[23:16]==(nrgb[15:8]>>1) && nrgb[15:8]==nrgb[7:0]))$fatal(1,"Unexpected motion palette");
     motion=motion+1;
    end
    if(experimental.S_trail_hit)trail=trail+1;
    checked=checked+1;if(ox==W-1)begin ox=0;oy=(oy==H-1)?0:oy+1;end else ox=ox+1;
   end else if(nrgb!==0)$fatal(1,"Blanking RGB changed");
  end
 end
 initial begin
  $readmemh("../build/style_mode_20261025/vectors/trajectory_camera.hex",pixels);
  repeat(6)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)for(l=0;l<VT;l=l+1)for(x=0;x<HT;x=x+1)begin
   @(negedge clk);
   if(f==0 && l==50 && x==2)sw2=1;if(f==0 && l==50 && x==22)sw2=0;
   if(f==1 && l==10 && x==0)sw2=1;if(f==4 && l==100 && x==0)sw2=0;if(f==6 && l==100 && x==0)sw2=1;
   if(f==1 && l==200 && x==0)sw1=1;if(f==6 && l==300 && x==0)sw1=0;
   vs=l<3;hs=x>=1390 && x<1430;de=l>=6 && l<6+H && x<W;
   user=de && l==6 && x==0;last=de && x==W-1;
   camera=de?pixels[f*W*H+(l-6)*W+x]:0;
  end
  @(negedge clk);de=0;vs=0;hs=0;user=0;last=0;camera=0;
  repeat(13304)@(negedge clk);
  if(checked!=TOTAL || normal<3000000 || foreground<5000 || osd<20000 || hud!=65536 || trail!=32 || frames!=N || enter!=2 || leave!=1 || motion==0)$fatal(1,"Coverage incomplete checked%0d normal%0d fg%0d osd%0d hud%0d trail%0d motion%0d frames%0d",checked,normal,foreground,osd,hud,trail,motion,frames);
  $display("PASS main_track2: %0d full 720p pixels; original DDR/ROI/servo/PWM/coordinates/logo/1s trail unchanged; normal%0d ROI%0d OSD%0d HUD%0d motion%0d trail%0d; 2 style entries/1 exit with switch bounce",checked,normal,foreground,osd,hud,motion,trail);$finish;
 end
 initial begin #150000000;$fatal(1,"Main integration timeout");end
endmodule

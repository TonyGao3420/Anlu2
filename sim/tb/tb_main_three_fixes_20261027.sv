`timescale 1ns/1ps
module tb_main_track2;
 localparam W=1280,H=720,HT=1650,VT=750,N=8,TOTAL=W*H*N;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,user=0,last=0,sw1=0,sw2=0;
 reg [23:0] camera=0,pixels[0:W*H-1];
 wire bv,bh,bd,nv,nh,nd;wire [23:0] brgb,nrgb;
 baseline_current_path base(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,bv,bh,bd,brgb);
 extended_current_path experimental(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,nv,nh,nd,nrgb);
 reg roi_d1=0,roi_d2=0,vs_d=0,style_mode=0,last_mode=0;
 reg [29:0] reference_delay[0:5];integer d;
 wire rv,rh,rd,rp,rt,rr;wire [23:0] reference_rgb;
 assign {rv,rh,rd,rp,rt,rr,reference_rgb}=reference_delay[5];
 integer ox=0,oy=0,checked=0,normal=0,foreground=0,osd=0,hud=0,background=0,trail=0,frames=0,enter=0,leave=0;
 integer f,l,x;reg hud_region;
 always @(posedge clk)begin
  if(!rst)begin roi_d1<=0;roi_d2<=0;for(d=0;d<6;d=d+1)reference_delay[d]<=0;end
  else begin
   roi_d1<=base.S_style_roi;roi_d2<=roi_d1;
   reference_delay[0]<={bv,bh,bd,base.S_trail_protect,base.S_trail_hit,roi_d2,brgb};
   for(d=1;d<6;d=d+1)reference_delay[d]<=reference_delay[d-1];
   if({experimental.S_hdmi_window_rd_en,experimental.S_color_roi_de,experimental.S_color_roi_sof,experimental.S_color_roi_last,experimental.S_color_roi_rgb}!==
      {base.S_hdmi_window_rd_en,base.S_color_roi_de,base.S_color_roi_sof,base.S_color_roi_last,base.S_color_roi_rgb})$fatal(1,"Detector/request input changed by style cleaning");
   if({experimental.S_track2_valid,experimental.S_track2_bbox_x0,experimental.S_track2_bbox_y0,experimental.S_track2_bbox_x1,experimental.S_track2_bbox_y1,experimental.S_track2_cx,experimental.S_track2_cy,experimental.O_servo_pan,experimental.O_servo_tilt}!==
      {base.S_track2_valid,base.S_track2_bbox_x0,base.S_track2_bbox_y0,base.S_track2_bbox_x1,base.S_track2_bbox_y1,base.S_track2_cx,base.S_track2_cy,base.O_servo_pan,base.O_servo_tilt})$fatal(1,"ROI/servo changed by style cleaning");
  end
  #1;if(rst)begin
   if({nv,nh,nd}!=={rv,rh,rd})$fatal(1,"Expected exactly six extra clean-filter clocks");
   if(nv && !vs_d)begin ox=0;oy=0;end vs_d=nv;
   if(nd)begin
    if(ox==0 && oy==0)begin
     style_mode=experimental.S_style_enable;
     if(style_mode!==(frames==2 || frames==3 || frames==4 || frames==7))$fatal(1,"Frame-atomic mode switching");
     if(style_mode && !last_mode)enter=enter+1;if(!style_mode && last_mode)leave=leave+1;
     last_mode=style_mode;frames=frames+1;$display("TRACE final main frame%0d style%0d",frames,style_mode);
    end
    hud_region=ox>=1008 && ox<1264 && oy>=16 && oy<48;
    if(experimental.S_trail_hit!==rt)$fatal(1,"One-second trajectory changed");
    if(hud_region && !rr)begin
     if(nrgb!==reference_rgb || !experimental.S_trail_protect)$fatal(1,"HUD RGB/protection changed");hud=hud+1;
    end else if(rp || rt)begin
     if(nrgb!==reference_rgb)$fatal(1,"Official logo/OSD/coordinate/trail pixels changed");osd=osd+1;
    end else if(!style_mode)begin
     if(nrgb!==reference_rgb)$fatal(1,"Normal-mode RGB changed");normal=normal+1;
    end else if(rr)begin
     if(nrgb[23:16]!=nrgb[15:8] || nrgb[15:8]!=nrgb[7:0])begin
      if(!(nrgb[15:8]>nrgb[23:16] && nrgb[15:8]>nrgb[7:0] && nrgb[15:8]>=8))$fatal(1,"Unwanted target color");
     end else if(nrgb[7:0]<72 || nrgb[7:0]>223)$fatal(1,"Target background gray outside range");
     foreground=foreground+1;
    end else begin
     if(nrgb[23:16]!==nrgb[15:8] || nrgb[15:8]!==nrgb[7:0] || nrgb[7:0]<72 || nrgb[7:0]>223)$fatal(1,"Background not clean neutral gray");background=background+1;
    end
    if(rt)trail=trail+1;checked=checked+1;
    if(ox==W-1)begin ox=0;oy=(oy==H-1)?0:oy+1;end else ox=ox+1;
   end else if(nrgb!==0)$fatal(1,"Blanking RGB");
  end
 end
 initial begin
  repeat(6)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)begin
   $readmemh($sformatf("../build/three_fixes_20261027/main_camera_%0d.hex",f),pixels);
   for(l=0;l<VT;l=l+1)for(x=0;x<HT;x=x+1)begin
   @(negedge clk);
   if(f==0 && l==50 && x==2)sw2=1;if(f==0 && l==50 && x==22)sw2=0;
   if(f==1 && l==10 && x==0)sw2=1;if(f==4 && l==100 && x==0)sw2=0;if(f==6 && l==100 && x==0)sw2=1;
   if(f==1 && l==200 && x==0)sw1=1;if(f==6 && l==300 && x==0)sw1=0;
   vs=l<3;hs=x>=1390 && x<1430;de=l>=6 && l<6+H && x<W;user=de && l==6 && x==0;last=de && x==W-1;
   camera=de?pixels[(l-6)*W+x]:0;
   end
  end
  @(negedge clk);de=0;vs=0;hs=0;user=0;last=0;camera=0;repeat(13310)@(negedge clk);
  if(checked!=TOTAL || normal<3000000 || foreground<5000 || osd<20000 || hud!=65536 || trail!=32 || frames!=N || enter!=2 || leave!=1 || background<3000000)$fatal(1,"Final main coverage checked%0d normal%0d ROI%0d OSD%0d HUD%0d trail%0d background%0d",checked,normal,foreground,osd,hud,trail,background);
  $display("PASS final_main: %0d full 720p pixels; ROI/coordinates/upright servo input/PWM unchanged by denoising; normal%0d ROI%0d OSD%0d HUD%0d background%0d trail%0d; 2 entries/1 exit with switch bounce; +6 aligned video clocks",checked,normal,foreground,osd,hud,background,trail);$finish;
 end
 initial begin #150000000;$fatal(1,"Final integration timeout");end
endmodule

`timescale 1ns/1ps
module tb_style_integration;
 localparam W=1280,H=720,HT=1650,VT=750,N=8,LAT=13204,TOTAL=W*H*N;
 reg sw1=0,sw2=0;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,user=0,last=0;
 reg[23:0] camera=0;reg[23:0] pixels[0:TOTAL-1];
 wire bv,bh,bd,nv,nh,nd;wire[23:0] brgb,nrgb;
 baseline_display_path base(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,bv,bh,bd,brgb);
 isolated_display_path experimental(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,nv,nh,nd,nrgb);
 reg[29:0] history[0:LAT-1];reg[29:0] want;
 reg[7:0] luma[0:14];reg[14:0] protection=0;
 reg [15:0] fx0=0,fy0=0,fx1=0,fy1=0;reg fv=0,seen_vs=0;
 integer rx=0,ry=0,j,ptr=0,checked=0,fg=0,osd=0,bg=0,trail=0;
 integer out_frames=0,normal=0,style=0,enter=0,leave=0;reg ref_mode=0,last_mode=0;
 reg keep,expected_tone_protect;integer gref;
 always @(posedge clk)begin
  if(!rst)begin
   for(j=0;j<LAT;j=j+1)history[j]=0;
   for(j=0;j<15;j=j+1)luma[j]=0;
   protection=0;ptr=0;rx=0;ry=0;seen_vs=0;fv=0;checked=0;fg=0;osd=0;bg=0;trail=0;
  end else begin
   expected_tone_protect=protection[14];
   if({experimental.S_hdmi_window_rd_en,experimental.S_color_roi_de,experimental.S_color_roi_sof,experimental.S_color_roi_last,experimental.S_color_roi_rgb}!==
      {base.S_hdmi_window_rd_en,base.S_color_roi_de,base.S_color_roi_sof,base.S_color_roi_last,base.S_color_roi_rgb})$fatal(1,"Display styling changed DDR request or detector input");
   if({experimental.S_track2_valid,experimental.S_track2_bbox_x0,experimental.S_track2_bbox_y0,experimental.S_track2_bbox_x1,experimental.S_track2_bbox_y1,experimental.S_track2_cx,experimental.S_track2_cy,experimental.O_servo_pan,experimental.O_servo_tilt}!==
      {base.S_track2_valid,base.S_track2_bbox_x0,base.S_track2_bbox_y0,base.S_track2_bbox_x1,base.S_track2_bbox_y1,base.S_track2_cx,base.S_track2_cy,base.O_servo_pan,base.O_servo_tilt})$fatal(1,"Display styling changed real ROI/servo results");
   if(bd)begin
    if(experimental.S_style_luma_delay[14]!==luma[14] || experimental.S_style_protect_delay[14]!==protection[14])$fatal(1,"Actual top luma/OSD bridge misaligned");
   end
   gref=(int'(base.S_color_roi_rgb[23:16])+2*int'(base.S_color_roi_rgb[15:8])+int'(base.S_color_roi_rgb[7:0]))/4;
   for(j=14;j>0;j=j-1)luma[j]=luma[j-1];luma[0]=gref;
   protection={protection[13:0],base.S_color_protect};
   if(bv && !seen_vs)begin rx=0;ry=0;end
   seen_vs=bv;keep=0;
   if(bd)begin
    if(rx==0 && ry==0)begin
     ref_mode=experimental.S_style_request;
     if(ref_mode!==(out_frames==2 || out_frames==3 || out_frames==4 || out_frames==7))$fatal(1,"Unexpected mode at frame%0d",out_frames);
     if(ref_mode && !last_mode)enter=enter+1;if(!ref_mode && last_mode)leave=leave+1;
     last_mode=ref_mode;out_frames=out_frames+1;
     fv=base.S_track2_valid;fx0=base.S_track2_bbox_x0;fy0=base.S_track2_bbox_y0;
     fx1=base.S_track2_bbox_x1;fy1=base.S_track2_bbox_y1;
    end
    keep=fv && rx>=fx0 && rx<=fx1 && ry>=fy0 && ry<=fy1;
    if(rx==W-1)begin rx=0;ry=(ry==H-1)?0:ry+1;end else rx=rx+1;
   end
   want=history[ptr];history[ptr]={ref_mode,bv,bh,bd,expected_tone_protect,keep,brgb};
   ptr=(ptr==LAT-1)?0:ptr+1;
   #1;
   if({nv,nh,nd}!==want[28:26])$fatal(1,"Whole-chain HDMI timing changed beyond documented line delay");
   if(experimental.S_trail_protect!==(want[25] || experimental.S_trail_hit))$fatal(1,"Final OSD protect mismatch");
   if(nd)begin
    checked=checked+1;
    if(!want[29])begin
     normal=normal+1;
     if(nrgb!==want[23:0] || experimental.S_trail_hit)$fatal(1,"Mode1/2 must preserve original full RGB exactly");
    end else if(want[25] || want[24])begin
     if(nrgb!==want[23:0])$fatal(1,"Original OSD/ROI color changed at output pixel%0d",checked);
     if(want[25])osd=osd+1;else fg=fg+1;
    end else begin
     bg=bg+1;style=style+1;
     if(experimental.S_trail_hit)begin
      trail=trail+1;if(nrgb!==24'hff8800)$fatal(1,"Trail color altered");
     end else begin
     if(nrgb[23:16]!==nrgb[15:8] || nrgb[15:8]!==nrgb[7:0])$fatal(1,"Background is not neutral gray");
     case(nrgb[7:0])0,36,73,109,146,182,219,255:;default:$fatal(1,"Unexpected quantized gray level");endcase
     end
    end
   end else if(nrgb!==0)$fatal(1,"Blanking RGB must be zero");
  end
 end
 integer f,line,col;
 integer moved=0,last_cx=-1,last_cy=-1;
 always @(posedge clk) if(rst && experimental.u_motion_trail.sof)begin
  if(experimental.u_motion_trail.in_enable && !experimental.u_motion_trail.frame_enable && experimental.u_motion_trail.point_count!=0)$fatal(1,"Old trace reappeared on style re-entry");
  $display("TRACE input valid%0d center(%0d,%0d) history%0d bank%0d mode%0d",experimental.S_track2_valid,experimental.S_track2_cx,experimental.S_track2_cy,experimental.u_motion_trail.point_count,experimental.u_motion_trail.bank_valid,experimental.S_style_enable);
  if(experimental.S_track2_valid)begin
   if(last_cx>=0 && (last_cx!=experimental.S_track2_cx || last_cy!=experimental.S_track2_cy))moved=moved+1;
   last_cx=experimental.S_track2_cx;last_cy=experimental.S_track2_cy;
  end
 end
 initial begin
  $readmemh("../build/style_mode_20261025/vectors/trajectory_camera.hex",pixels);
  repeat(6)@(negedge clk);rst=1;
  for(f=0;f<N;f=f+1)for(line=0;line<VT;line=line+1)for(col=0;col<HT;col=col+1)begin
   @(negedge clk);
   if(f==0 && line==50 && col==2)sw2=1;
   if(f==0 && line==50 && col==22)sw2=0;
   if(f==1 && line==10 && col==0)sw2=1;
   if(f==4 && line==100 && col==0)sw2=0;
   if(f==6 && line==100 && col==0)sw2=1;
   if(f==1 && line==200 && col==0)sw1=1;
   if(f==6 && line==300 && col==0)sw1=0;
   vs=(line<3);hs=(col>=1390 && col<1430);
   de=(line>=6 && line<6+H && col<W);user=de && line==6 && col==0;last=de && col==W-1;
   camera=de?pixels[f*W*H+(line-6)*W+col]:0;
  end
  @(negedge clk);de=0;vs=0;hs=0;user=0;last=0;camera=0;
  repeat(LAT+100)@(negedge clk);
  if(checked!=TOTAL || fg<5000 || osd<20000 || bg<2000000 || trail<100 || moved<2 || normal!=4*W*H || enter!=2 || leave!=1 || out_frames!=N)$fatal(1,"Incomplete whole-chain coverage %0d fg%0d osd%0d bg%0d trail%0d moved%0d",checked,fg,osd,bg,trail,moved);
  $display("PASS mode_integration: %0d actual 720p output pixels; ROI %0d OSD %0d background %0d trail %0d; extracted real top, DDR/ROI/servo unchanged, calibrated luma alignment, foreground/anniversary-logo/HUD/border bit exact",checked,fg,osd,bg,trail);$display("PASS mode_switches: normal RGB pixels%0d, style pixels%0d, enter%0d leave%0d; SW1 servo outputs cycle-exact; no partial-frame mode",normal,style,enter,leave);$finish;
 end
 initial begin #150000000;$fatal(1,"Integration timeout");end
endmodule

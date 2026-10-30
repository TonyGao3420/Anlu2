`timescale 1ns/1ps
module tb_four_modes_vtc;
 localparam W=1280,H=720,HT=1650,VT=750,N=7;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,sw1=0,sw2=0,sw3=0;wire vs,hs,de,user,last;
 uivtc #(.H_ActiveSize(W),.H_FrameSize(HT),.H_SyncStart(1390),.H_SyncEnd(1430),.V_ActiveSize(H),.V_FrameSize(VT),.V_SyncStart(725),.V_SyncEnd(730)) vtc(rst,clk,vs,hs,de,user,last);
 reg [23:0] camera=0;wire bv,bh,bd,nv,nh,nd;wire [23:0] brgb,nrgb;
 baseline_path base(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,sw3,bv,bh,bd,brgb);
 multi_path dut(clk,rst,vs,hs,de,user,last,camera,sw1,sw2,sw3,nv,nh,nd,nrgb);
 reg [26:0] delayed[0:0];integer i;
 reg [2:0] multi_delay=0;reg seen_vs=0;reg vsd=0;integer ox=0,oy=0,checked=0,ordinary=0,multiple=0,frames=0,styleframes=0,entries=0,exits=0;reg oldmode=0;
 integer f,l,x,j,fx,fy,t;reg inside_any;integer combo_pixels=0,gray_samples=0;
 always @(posedge clk)begin
  if(!rst)begin for(i=0;i<1;i=i+1)delayed[i]<=0;multi_delay<=0;end
  else begin
   delayed[0]<={bv,bh,bd,brgb};for(i=1;i<1;i=i+1)delayed[i]<=delayed[i-1];
   multi_delay<={multi_delay[1:0],dut.S_multi_frame};
   if({dut.S_hdmi_window_rd_en,dut.S_color_roi_de,dut.S_color_roi_sof,dut.S_color_roi_last,dut.S_color_roi_rgb}!==
      {base.S_hdmi_window_rd_en,base.S_color_roi_de,base.S_color_roi_sof,base.S_color_roi_last,base.S_color_roi_rgb})$fatal(1,"Original detector input changed");
   if({dut.S_track2_valid,dut.S_track2_bbox_x0,dut.S_track2_bbox_y0,dut.S_track2_bbox_x1,dut.S_track2_bbox_y1,dut.S_track2_cx,dut.S_track2_cy,dut.O_servo_pan,dut.O_servo_tilt}!==
      {base.S_track2_valid,base.S_track2_bbox_x0,base.S_track2_bbox_y0,base.S_track2_bbox_x1,base.S_track2_bbox_y1,base.S_track2_cx,base.S_track2_cy,base.O_servo_pan,base.O_servo_tilt})$fatal(1,"Original ROI/coordinate/servo/PWM changed");
  end
  #1;if(rst)begin
   if({nv,nh,nd}!=={bv,bh,bd})$fatal(1,"VS/HS/DE not aligned by zero extra clocks");
   if(nv && !vsd)begin seen_vs=1;ox=0;oy=0;end vsd=nv;
   if(nd && seen_vs)begin
    if(ox==0 && oy==0)begin
     if(dut.u_multi_overlay.mode!=oldmode)begin if(dut.u_multi_overlay.mode)entries=entries+1;else exits=exits+1;end oldmode=dut.u_multi_overlay.mode;
     if(dut.S_style_enable)styleframes=styleframes+1;
     $display("TRACE four_modes frame%0d multi%0d style%0d count%0d",frames,dut.u_multi_overlay.mode,dut.S_style_enable,dut.S_multi_count);frames=frames+1;
    end
    if(!(dut.u_multi_overlay.mode && dut.S_style_enable) && nrgb!==brgb)$fatal(1,"Original independent mode RGB differs");
    if(!dut.u_multi_overlay.mode)begin
     if(nrgb!==brgb)$fatal(1,"Original three modes RGB changed at frame%0d x%0d y%0d",frames,ox,oy);ordinary=ordinary+1;
    end else begin
     if(dut.S_style_enable && !dut.u_multi_overlay.style_mode)$fatal(1,"Combined mode HUD missing");
     if(dut.u_multi_overlay.fc!=4)$fatal(1,"Four boxes not visible");multiple=multiple+1;
    end
    if(dut.u_multi_overlay.mode && dut.S_style_enable)begin
     combo_pixels=combo_pixels+1;inside_any=0;
     for(t=0;t<8;t=t+1)if(dut.S_multi_valid[t] && ox>=dut.S_multi_x0[t*12+:12] && ox<=dut.S_multi_x1[t*12+:12] && oy>=dut.S_multi_y0[t*12+:12] && oy<=dut.S_multi_y1[t*12+:12])inside_any=1;
     if(inside_any && nrgb!==brgb)$fatal(1,"Combined ROI original color lost x%0d y%0d %h %h",ox,oy,nrgb,brgb);
     if(ox==950 && oy==650)begin if(nrgb[23:16]!==nrgb[15:8] || nrgb[7:0]!==nrgb[15:8] || nrgb==0)$fatal(1,"Combined background not bright grayscale");gray_samples=gray_samples+1;end
    end
    checked=checked+1;
    if(checked==N*W*H)begin
     if(combo_pixels!=W*H || gray_samples!=1)$fatal(1,"Combination coverage missing");
     if(ordinary!=5*W*H || multiple!=2*W*H || styleframes!=3 || entries!=1 || exits!=1)$fatal(1,"VTC coverage %d %d %d %d %d",ordinary,multiple,styleframes,entries,exits);
     $display("PASS combo_integration: 6451200 actual VTC pixels; late VS at 725, 30 blank lines; normal/servo/style/multi/return; unchanged primary ROI/PWM/read requests; latest calibration/ROI/PWM/read requests preserved; independent modes exact; multi-only and combined style both entered");$finish;
    end
    if(ox==W-1)begin ox=0;oy=oy==H-1?0:oy+1;end else ox=ox+1;
   end
  end
 end
 integer input_frame=0,ix=0,iy=0;reg input_vs_d=0;
 always @(negedge clk)if(rst)begin
  if(user)input_frame=input_frame+1;
  if(vs && !input_vs_d)begin ix=0;iy=0;end input_vs_d=vs;
  if(input_frame==0 && vtc.vcnt==50 && vtc.hcnt==200)sw1=1;
  if(input_frame==1 && vtc.vcnt==30 && vtc.hcnt==200)sw2=1;
  if(input_frame==2 && vtc.vcnt==20 && vtc.hcnt==200)sw3=1;
  if(input_frame==2 && vtc.vcnt==20 && vtc.hcnt==220)sw3=0;
  if(input_frame==2 && vtc.vcnt==40 && vtc.hcnt==200)sw3=1;
  if(input_frame==3 && vtc.vcnt==40 && vtc.hcnt==200)sw2=0;
  if(input_frame==4 && vtc.vcnt==40 && vtc.hcnt==200)begin sw3=0;sw2=1;end
  if(input_frame==5 && vtc.vcnt==40 && vtc.hcnt==200)begin sw2=0;sw1=0;end
  camera=de?24'h707070:0;
  for(j=0;j<4;j=j+1)begin fx=240+(j%2)*550;fy=170+(j/2)*300;
   if(de && ix>=fx && ix<fx+64 && iy>=fy && iy<fy+80)camera=24'h20a030;
  end
  if(de)if(ix==W-1)begin ix=0;iy=iy==H-1?0:iy+1;end else ix=ix+1;
 end
 initial begin repeat(6)@(negedge clk);rst=1;end
 initial begin #170000000;$fatal(1,"Actual VTC integration timeout");end
endmodule

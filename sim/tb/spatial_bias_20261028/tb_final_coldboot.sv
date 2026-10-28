`timescale 1ns/1ps
module tb_sw3_coldboot;
 reg clk=0;always #5 clk=~clk;reg rst=0;
 wire vs,hs,de,user,last,ov,oh,od;reg [23:0] camera=0;wire [23:0] rgb;
 uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),.V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(rst,clk,vs,hs,de,user,last);
 // SW2 is LOW throughout. SW3 is HIGH from power-up: no prior style mode.
 multi_path dut(clk,rst,vs,hs,de,user,last,camera,1'b0,1'b0,1'b1,ov,oh,od,rgb);
 integer ix=0,iy=0,j,bx,by;reg ivd=0,ovd=0,seen=0;integer ox=0,oy=0,frames=0,pixels=0;
 always @(negedge clk)if(rst)begin
  if(vs && !ivd)begin ix=0;iy=0;end ivd=vs;camera=de?24'h808080:0;
  for(j=0;j<8;j=j+1)begin bx=32+(j%4)*300;by=180+(j/4)*280;
   if(de && ix>=bx && ix<bx+80 && iy>=by && iy<by+80)camera=24'h20a030;
  end
  if(de)if(ix==1279)begin ix=0;iy=iy==719?0:iy+1;end else ix=ix+1;
 end
 always @(posedge clk)begin #1;if(rst)begin
  if(ov && !ovd)begin seen=1;ox=0;oy=0;end ovd=ov;
  if(od && seen)begin
   if(ox==0 && oy==0)begin
    frames=frames+1;
    if(!dut.u_multi_overlay.mode || !dut.S_multi_frame || !dut.S_multi_request || dut.S_style_enable)$fatal(1,"Cold boot did not enter multi directly with SW2 low");
    if(frames==2 && dut.u_multi_overlay.fc!=8)$fatal(1,"Cold boot native VTC lost 8 targets %d",dut.u_multi_overlay.fc);
    $display("TRACE coldboot frame%0d M%0d N%0d",frames,dut.u_multi_overlay.mode,dut.u_multi_overlay.fc);
   end
   pixels=pixels+1;
   if(pixels==2*1280*720)begin $display("PASS spatial_coldboot: SW3 high from reset, SW2 always low, native VTC, direct multi before any ROI result, eight independent targets, 1843200 active pixels");$finish;end
   if(ox==1279)begin ox=0;oy=oy==719?0:oy+1;end else ox=ox+1;
  end
 end end
 initial begin repeat(6)@(negedge clk);rst=1;end
 initial begin #50000000;$fatal(1,"Cold boot timeout");end
endmodule

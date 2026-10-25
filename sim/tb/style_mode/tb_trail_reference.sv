`timescale 1ns/1ps
// Complete-frame software bitmap reference, independent of renderer FSM/RAM.
module tb_trail_reference #(parameter W=64,H=48,HT=80,N=52,HIST=16,MOVIE=0,JUMP=32);
 localparam GW=(W+3)/4,GH=(H+3)/4,CELLS=GW*GH;
 reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,prot=0,roi=0,en=1,clear=0;
 reg[23:0] rgb=0;reg[15:0] now_ms=0,px=0,py=0;reg pv=0;
 wire ov,oh,od,op,hit,busy,bank_valid;wire[23:0] out;wire[8:0] count;
 roi_motion_trail #(.IMG_W(W),.IMG_H(H),.HISTORY_DEPTH(HIST),.MAX_JUMP_PIXELS(JUMP),.FRAME_TIMEOUT_MS(MOVIE?250:0)) dut(
  .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.in_roi(roi),
  .in_enable(en),.in_clear(clear),.in_rgb(rgb),.ms_now(now_ms),.point_valid(pv),.point_x(px),.point_y(py),
  .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.out_hit(hit),.out_rgb(out),
  .render_busy(busy),.point_count(count),.bank_valid(bank_valid));
 reg front[0:CELLS-1],back[0:CELLS-1];reg hv[0:HIST-1],hl[0:HIST-1];
 integer hx[0:HIST-1],hy[0:HIST-1],htime[0:HIST-1];
 integer mh=0,mc=0,prev_x=0,prev_y=0,prev_ms=0;reg prev_valid=0,front_valid=0,back_ready=0;
 reg[28:0] current_expected=0,delayed_expected=0,want=0;
 integer out_pixels=0,trace_pixels=0,all_checked=0,frames=0,ppm=0;
 integer f,x,y,j,idx,age,dx,dy,linkgap,qx,qy,xx,yy,model_count,epoch;
 reg enabled_frame,point_good,expected_hit,first_frame_reset=0;
 reg old_bank;
 always @(posedge clk)begin
  if(!rst)begin delayed_expected=0;old_bank=0;out_pixels=0;trace_pixels=0;end
  else begin
   want=delayed_expected;delayed_expected=current_expected;
   if(de && dut.front_bank!==old_bank)$fatal(1,"Front cache changed during active video");
   old_bank=dut.front_bank;
   #1;
   if({ov,oh,od,op,hit,out}!==want)$fatal(1,"Trail reference mismatch movie%0d frame%0d pixel%0d got%h expected%h",MOVIE,frames,out_pixels,{ov,oh,od,op,hit,out},want);
   if(od)begin
    out_pixels=out_pixels+1;all_checked=all_checked+1;
    if(hit)trace_pixels=trace_pixels+1;
    if(MOVIE && ppm)$fwrite(ppm,"%c%c%c",out[23:16],out[15:8],out[7:0]);
   end
  end
 end
 task software_line(input integer ax,input integer ay,input integer bx,input integer by);
 integer cx,cy,ddx,ddy,sx,sy,err,e2,done,steps;
 begin
  cx=ax;cy=ay;ddx=(bx>=ax)?bx-ax:ax-bx;ddy=(by>=ay)?by-ay:ay-by;
  sx=(ax<bx)?1:-1;sy=(ay<by)?1:-1;err=ddx-ddy;done=0;steps=0;
  while(!done)begin
   if(cx<0 || cx>=GW || cy<0 || cy>=GH)$fatal(1,"Reference line outside bitmap");
   back[cy*GW+cx]=1;steps=steps+1;
   if(cx==bx && cy==by)done=1;
   else begin e2=2*err;if(e2>=-ddy)begin err=err-ddy;cx=cx+sx;end if(e2<=ddx)begin err=err+ddx;cy=cy+sy;end end
   if(steps>GW+GH+2)$fatal(1,"Software line did not terminate");
  end
 end endtask
 task rebuild_reference;
 integer i,p,have,lastx,lasty;
 begin
  for(i=0;i<CELLS;i=i+1)back[i]=0;
  have=0;
  for(i=0;i<mc;i=i+1)begin
   p=(mh+HIST-mc+i)%HIST;age=(int'(now_ms)-htime[p])&65535;
   if(hv[p] && age>=3000)hv[p]=0;
   if(hv[p])begin
    if(have && hl[p])software_line(lastx,lasty,hx[p],hy[p]);else software_line(hx[p],hy[p],hx[p],hy[p]);
    lastx=hx[p];lasty=hy[p];have=1;
   end else have=0;
  end
  back_ready=1;
 end endtask
 task set_case(input integer k);
 begin
  en=1;clear=0;pv=1;now_ms=k*16;px=32;py=24;
  case(k)
   0:begin px=8;py=8;end
   1:begin px=20;py=8;end
   2:begin px=20;py=20;end
   3:begin px=8;py=20;end
   4:begin px=8;py=8;end
   5:begin px=20;py=20;end
   6:begin px=8;py=20;end
   7:begin px=20;py=8;end
   8:begin now_ms=2999;pv=0;end
   9:begin now_ms=3000;pv=0;end
   10:begin now_ms=3016;pv=0;end
   11:begin now_ms=3112;pv=0;end
   12:begin now_ms=3128;px=40;py=24;end
   13:begin now_ms=3144;px=52;py=24;end
   14:begin now_ms=65530;px=8;py=8;end
   15:begin now_ms=4;px=20;py=8;end
   16:begin now_ms=3004;pv=0;end
   17:begin now_ms=4;pv=0;end // full counter wrap must not resurrect invalidated points
   18:begin now_ms=20;en=0;end
   19:begin now_ms=36;px=32;py=24;end
   20:begin now_ms=52;clear=1;end
   21:begin now_ms=68;px=0;py=0;end
   22:begin now_ms=84;px=W-1;py=H-1;end
   23:begin now_ms=100;px=W;py=H-1;end
   24:begin now_ms=116;px=0;py=H-1;end
   25:begin now_ms=132;px=W-1;py=0;end
   26:begin now_ms=148;px=32;py=24;end
   27:begin now_ms=164;px=44;py=12;end
   28:begin now_ms=180;px=32;py=24;end
   29:begin now_ms=196;px=20;py=12;end
   30:begin now_ms=212;px=32;py=24;end
   31:begin now_ms=228;px=32;py=24;end
  endcase
  if(k>=32)begin now_ms=244+(k-32)*16;px=8+(k%8)*4;py=12+((k/8)%2)*8;end
  if(MOVIE)begin
   en=1;clear=0;now_ms=k*100;pv=(k<20);px=28+(k%20)*13;py=H/2+((k%10)<5?(k%5)*7:(9-k%10)*7)-14;
  end
 end endtask
 initial begin
  for(j=0;j<CELLS;j=j+1)begin front[j]=0;back[j]=0;end
  for(j=0;j<HIST;j=j+1)begin hv[j]=0;hl[j]=0;hx[j]=0;hy[j]=0;htime[j]=0;end
  repeat(6)@(negedge clk);rst=1;
  for(epoch=0;epoch<(MOVIE?1:2);epoch=epoch+1)begin
  for(f=0;f<N;f=f+1)begin
   frames=f;
   if(busy)$fatal(1,"Renderer exceeded frame budget");
   if(back_ready)begin for(j=0;j<CELLS;j=j+1)front[j]=back[j];front_valid=1;back_ready=0;end
   @(negedge clk);set_case(f);vs=1;hs=0;de=0;prot=0;roi=0;rgb=0;current_expected={1'b1,1'b0,1'b0,1'b0,1'b0,24'd0};
   repeat(6)@(negedge clk);vs=0;current_expected=0;
   if(MOVIE)begin ppm=$fopen($sformatf("../build/style_mode_20261025/trail_movie/frame_%02d.ppm",f),"wb");$fwrite(ppm,"P6\n%0d %0d\n255\n",W,H);end
   enabled_frame=en;
   if(!en || clear)begin mh=0;mc=0;prev_valid=0;front_valid=0;back_ready=0;end
   else begin
    point_good=pv && px<W && py<H;qx=px/4;qy=py/4;linkgap=(int'(now_ms)-prev_ms)&65535;
    hx[mh]=qx;hy[mh]=qy;htime[mh]=now_ms;hv[mh]=point_good;
    hl[mh]=prev_valid && point_good && linkgap<=150 && ((qx>=prev_x?qx-prev_x:prev_x-qx)<=JUMP/4) && ((qy>=prev_y?qy-prev_y:prev_y-qy)<=JUMP/4);
    mh=(mh+1)%HIST;if(mc<HIST)mc=mc+1;
    prev_valid=point_good;prev_ms=now_ms;if(point_good)begin prev_x=qx;prev_y=qy;end
    rebuild_reference;
   end
   model_count=mc;
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<HT;x=x+1)begin
     @(negedge clk);de=(x<W);hs=(x>=W+2 && x<W+6);prot=de && (y==H/2 && x>=W/4 && x<3*W/4);
     roi=de && pv && px<W && py<H && x>=int'(px)-4 && x<=int'(px)+4 && y>=int'(py)-4 && y<=int'(py)+4;
     dx=x-int'(px);dy=y-int'(py);
     rgb=(roi && (!MOVIE || dx*dx+dy*dy<=16))?24'h20dc60:{3{8'h80}};
     if(prot)rgb=24'hffff20;
     if(MOVIE && de && pv && ((dx>=-6 && dx<=6 && (dy==-6 || dy==6)) || (dy>=-6 && dy<=6 && (dx==-6 || dx==6))))begin
      prot=1;rgb=24'h00ffff;
     end
     expected_hit=de && enabled_frame && front_valid && !roi && !prot && front[(y/4)*GW+(x/4)];
     current_expected={vs,hs,de,(prot || expected_hit),expected_hit,(de?(expected_hit?24'hff8800:rgb):24'd0)};
     if(!MOVIE && f==26 && y==H/2 && x==W/2)begin en=~en;pv=0;px=65535;py=65535;end
    end
   end
   @(negedge clk);de=0;hs=0;prot=0;roi=0;current_expected=0;
   repeat(4)@(negedge clk);
   if(count!=model_count)$fatal(1,"Circular history count mismatch %0d/%0d",count,model_count);
   if(MOVIE)begin $fclose(ppm);ppm=0;end
  end
  if(out_pixels!=W*H*N)$fatal(1,"Missing pixels in complete reference run");
  if(!MOVIE && epoch==0)begin
   @(negedge clk);vs=1;de=0;hs=0;prot=0;roi=0;current_expected={1'b1,1'b0,1'b0,1'b0,1'b0,24'd0};
   repeat(6)@(negedge clk);vs=0;de=1;prot=1;roi=0;rgb=24'habcdef;
   current_expected={1'b0,1'b0,1'b1,1'b1,1'b0,24'habcdef};
   repeat(37)@(negedge clk);rst=0;de=0;vs=0;hs=0;prot=0;roi=0;current_expected=0;
   mh=0;mc=0;prev_valid=0;prev_ms=0;prev_x=0;prev_y=0;front_valid=0;back_ready=0;
   for(j=0;j<CELLS;j=j+1)begin front[j]=0;back[j]=0;end
   for(j=0;j<HIST;j=j+1)begin hv[j]=0;hl[j]=0;end
   repeat(5)@(negedge clk);rst=1;
  end
  end
  if(trace_pixels==0 || out_pixels!=W*H*N)$fatal(1,"Incomplete trajectory coverage %0d trace%0d",all_checked,trace_pixels);
  if(MOVIE)$display("PASS trail_movie: %0d RGB pixels, 60 accelerated-time frames, live target then loss, three-second expiry and protected ROI/OSD",out_pixels);
  else $display("PASS trail_reference: %0d pixels per reset run; TTL2999/3000, crossings/expiry, loss/reacquire/jumps, 16-bit wrap/no resurrection, live ring overflow, mode/clear, raster edges, OSD/ROI priority, registered raster alignment and active-reset recovery",out_pixels);
  $finish;
 end
 initial begin #150000000;$fatal(1,"Trajectory reference timeout");end
endmodule
module tb_trail_small;tb_trail_reference test();endmodule
module tb_trail_movie;tb_trail_reference #(.W(320),.H(176),.HT(400),.N(60),.HIST(64),.MOVIE(1),.JUMP(320)) test();endmodule

module tb_trail_clock;
 reg clk=0;always #5 clk=~clk;reg rst=0;wire[15:0] normal_ms,fast_ms;
 video_ms_clock normal(clk,rst,normal_ms);
 video_ms_clock #(.CLK_HZ(1000)) fast(clk,rst,fast_ms);
 integer n;
 initial begin
  repeat(3)@(negedge clk);rst=1;
  for(n=1;n<=225005;n=n+1)begin
   @(posedge clk);#1;
   if(normal_ms!==n/75000 || fast_ms!==(n&65535))$fatal(1,"Millisecond divider or counter wrap mismatch %0d",n);
  end
  @(negedge clk);rst=0;@(posedge clk);#1;if(normal_ms!==0 || fast_ms!==0)$fatal(1,"Clock reset failed");
  $display("PASS trail_clock: exact 75000-cycle milliseconds, counter wrap and reset");$finish;
 end
endmodule

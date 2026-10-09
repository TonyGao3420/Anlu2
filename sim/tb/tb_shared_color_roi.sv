`timescale 1ns/1ps
module tb_shared_color_roi;
reg clk=0;always #5 clk=~clk;
reg rst=0,vs=0,hs=0,de=0,protect=0;
reg [23:0] camera=0,mixed=0,wanted=0;
integer frame_id=0,dx=0,dy=0;
wire ov,oh,od,op,rd,rs,rl;
wire [23:0] display_rgb,roi_rgb;
scene_color_stream stream(.clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),
 .in_protect(protect),.camera_rgb(camera),.mixed_rgb(mixed),
 .out_vs(ov),.out_hs(oh),.out_de(od),.out_protect(op),.display_rgb(display_rgb),
 .roi_rgb(roi_rgb),.roi_de(rd),.roi_sof(rs),.roi_last(rl));
wire valid,update;
wire [15:0] x0,y0,x1,y1;
roi_target_tracker #(.IMG_W(1280),.IMG_H(720),.MIN_AREA(64),.MAX_AREA(120000)) tracker
 (.clk(clk),.rst_n(rst),.in_frame_start(rs),.in_de(rd),.in_line_last(rl),.in_rgb(roi_rgb),
 .target_valid(valid),.bbox_x0(x0),.bbox_y0(y0),.bbox_x1(x1),.bbox_y1(y1),
 .centroid_x(),.centroid_y(),.target_area(),.frame_done(),.result_update(update),
 .mask_valid(),.green_mask(),.mask_x(),.mask_y(),.dbg_roi_valid(),.dbg_color_match());
function integer rg(input integer n);begin case(n) 0: rg=242; 1: rg=283; 2: rg=256; 3: rg=234; 4: rg=308; 5: rg=251; 6: rg=228; 7: rg=288; 8: rg=250; default:rg=256;endcase end endfunction
function integer bg(input integer n);begin case(n) 0: bg=251; 1: bg=289; 2: bg=240; 3: bg=243; 4: bg=303; 5: bg=236; 6: bg=232; 7: bg=283; 8: bg=224; default:bg=256;endcase end endfunction
function integer gain(input integer x,y,input bit blue);
 integer n,fx,fy,a,b,c,d,t,bt;begin
 n=((y<360)?0:3)+((x<640)?0:1);
 fx=(x<=128)?0:((x>=1152)?256:((x-((x<640)?128:640))/2));
 fy=(y<=90)?0:((y>=630)?256:(((y-((y<360)?90:360))*243+128)/256));
 if(blue)begin a=bg(n);b=bg(n+1);c=bg(n+3);d=bg(n+4);end
 else begin a=rg(n);b=rg(n+1);c=rg(n+3);d=rg(n+4);end
 // Signed arithmetic shift matches rounded fixed-point gain interpolation.
 t=a+(((b-a)*fx+128)>>>8);bt=c+(((d-c)*fx+128)>>>8);
 gain=t+(((bt-t)*fy+128)>>>8);
 end endfunction
function [7:0] inverse(input [7:0] c,input integer g);
 integer a;begin
 a=(c<=14)?c:14+((c-14)*256+g/2)/g;
 inverse=(a>255)?255:a;
 end endfunction
function [23:0] shade_camera(input integer x,y,input [23:0] desired);
 begin shade_camera={inverse(desired[23:16],gain(x,y,0)),desired[15:8],inverse(desired[7:0],gain(x,y,1))};end
endfunction
reg [23:0] wantedq[0:7],mixedq[0:7];
reg [5:0] controls[0:7];integer fq[0:7];
integer i,pixels=0,sofs=0,lines=0,checks=0,prior_frame=0;
reg do_result_check;
reg [23:0] expected_display;
function integer delta(input [7:0] a,b);begin delta=(a>b)?a-b:b-a;end endfunction
always @(posedge clk) begin
 if(!rst) begin
  for(i=0;i<8;i=i+1)begin wantedq[i]=0;mixedq[i]=0;controls[i]=0;fq[i]=0;end
 end else begin
  do_result_check=rs;prior_frame=fq[7];
  if(rd)begin pixels=pixels+1;if(rs)sofs=sofs+1;if(rl)lines=lines+1;end
  for(i=7;i>0;i=i-1)begin wantedq[i]=wantedq[i-1];mixedq[i]=mixedq[i-1];controls[i]=controls[i-1];fq[i]=fq[i-1];end
  wantedq[0]=de?wanted:0;mixedq[0]=mixed;
  controls[0]={vs,hs,de,protect,de && dx==0 && dy==0,de && dx==1279};fq[0]=frame_id;
  #1;
  if({ov,oh,od,op,rs,rl}!==controls[7])$fatal(1,"Shared stream timing mismatch");
  if(rd!==od)$fatal(1,"ROI/display active pixels disagree after initial VS");
  if(od) begin
   if(delta(roi_rgb[23:16],wantedq[7][23:16])>1 || roi_rgb[15:8]!==wantedq[7][15:8] ||
      delta(roi_rgb[7:0],wantedq[7][7:0])>1)
     $fatal(1,"Calibrated camera mismatch f=%0d got=%h wanted=%h",fq[7],roi_rgb,wantedq[7]);
  end else if(roi_rgb!==0)$fatal(1,"Camera blank not black");
  expected_display=od?(op?mixedq[7]:roi_rgb):0;
  if(display_rgb!==expected_display)$fatal(1,"Overlay leaks into shared camera or display mismatch");
  if(do_result_check && prior_frame>=2)begin
   if(!update)$fatal(1,"Missing result update");
   if(prior_frame<=2 && valid)$fatal(1,"Biased bright white or protected green overlay acquired ROI");
   if(prior_frame>=3 && (!valid || x0!=700 || x1!=891 || y0!=160 || y1!=607))
    $fatal(1,"Light/dark true-green full-height box failed f=%0d bbox=%0d,%0d,%0d,%0d valid=%b",prior_frame,x0,y0,x1,y1,valid);
  end
  checks=checks+1;
 end
end
integer a,b,f;
task start_frame(input integer id);
 begin
  de=0;protect=0;vs=1;frame_id=id;dx=0;dy=0;
  repeat(8)@(negedge clk);vs=0;repeat(16)@(negedge clk);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 // Align controls before arming; no DE until VS.
 repeat(5000)@(negedge clk);
 for(f=1;f<=3;f=f+1)begin
  start_frame(f);
  for(b=0;b<720;b=b+1)begin
   for(a=0;a<1280;a=a+1)begin
    dx=a;dy=b;de=1;wanted=24'h303030;
    if(a>=512 && a<=767 && b>=180 && b<=539)wanted=24'hBEFFC6;
    if(f>=2 && a>=700 && a<=891 && b>=160 && b<=607)
      wanted=(f==2)?24'hA0E0A8:24'h103820;
    camera=shade_camera(a,b,wanted);
    // A deliberately pure-green protected OSD region must never become ROI.
    protect=(a>=32 && a<=287 && b>=32 && b<=255);
    mixed=protect?24'h00FF00:camera;
    @(negedge clk);
   end
   de=0;protect=0;mixed=0;camera=0;wanted=0;repeat(370)@(negedge clk);
  end
  repeat(55000)@(negedge clk);
  if(!tracker.regions.ready)$fatal(1,"ROI blank budget exceeded");
 end
 start_frame(4);dx=0;dy=0;de=1;wanted=24'h303030;camera=shade_camera(0,0,wanted);mixed=camera;
 @(negedge clk);de=0;camera=0;mixed=0;wanted=0;
 repeat(20)@(negedge clk);
 if(pixels!=3*921600+1 || sofs!=4 || lines!=3*720)
  $fatal(1,"Frame geometry: pixels=%0d sofs=%0d lines=%0d",pixels,sofs,lines);
 $display("PASS shared_color_roi: 3 complete 720p frames; biased highlight + green OSD rejected, calibrated light/dark greens preserve 448px height, shared pixels/metadata aligned");
 $finish;
end
initial begin #100000000;$fatal(1,"Timeout");end
endmodule


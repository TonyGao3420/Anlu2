`timescale 1ns/1ps
module tb_spatial_bias;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,hs=0,de=0,prot=0;reg [23:0] camera=0;
 wire [23:0] mixed=prot?24'hff0055:camera;
 wire v0,h0,d0,p0,v1,h1,d1,p1,rd0,rs0,rl0,rd1,rs1,rl1;
 wire [23:0] rgb0,roi0,rgb1,roi1;
 scene_color_stream #(.RGB_SHADING_ENABLE(0),.POSITION_BIAS_ENABLE(1),.SOURCE_ROTATE_180(0)) a(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.camera_rgb(camera),.mixed_rgb(mixed),
 .out_vs(v0),.out_hs(h0),.out_de(d0),.out_protect(p0),.display_rgb(rgb0),.roi_rgb(roi0),.roi_de(rd0),.roi_sof(rs0),.roi_last(rl0));
 scene_color_stream #(.RGB_SHADING_ENABLE(0),.POSITION_BIAS_ENABLE(1),.SOURCE_ROTATE_180(1)) b(
 .clk(clk),.rst_n(rst),.in_vs(vs),.in_hs(hs),.in_de(de),.in_protect(prot),.camera_rgb(camera),.mixed_rgb(mixed),
 .out_vs(v1),.out_hs(h1),.out_de(d1),.out_protect(p1),.display_rgb(rgb1),.roi_rgb(roi1),.roi_de(rd1),.roi_sof(rs1),.roi_last(rl1));
 function integer maximum(input integer a,b);maximum=a>b?a:b;endfunction
 function integer minimum(input integer a,b);minimum=a<b?a:b;endfunction
 function integer finish_old(input integer v,g);
 integer t;begin t=14+(((v-14)*g+512)/1024);finish_old=v<=14?v:minimum(255,t);end endfunction
 function integer trim(input integer v,bias);
 begin trim=v<=14?v:maximum(14,v-bias);end endfunction
 // Scalar golden model: integer coordinate/gain equations, no RTL functions used.
 function [23:0] reference(input [23:0] pixel,input integer x,y,rotate);
 integer sx,sy,l,r,t,b,rloss,bloss,red,green,blue,er,eb,top,wx,wy,c,hi,lo;
 begin
  sx=rotate?1279-x:x;sy=rotate?719-y:y;
  l=minimum(256,(maximum(0,384-sx)*171+128)/256);
  r=minimum(256,(maximum(0,sx-896)*171+128)/256);
  t=(maximum(0,216-sy)*303+128)/256;b=(maximum(0,sy-504)*303+128)/256;
  rloss=(l*(160+t/4-(3*b)/8)+r*(80-t/8+b/16)+t*96+b*64+128)/256;
  bloss=(l*32+t*32+b*16-r*64+128)>>>8;
  red=pixel[23:16];green=pixel[15:8];blue=pixel[7:0];
  er=finish_old(red,1024-rloss);eb=finish_old(blue,1024-bloss);
  top=maximum(0,256-y);wx=minimum(256,maximum(0,x-640)/2);wy=minimum(256,maximum(0,y-360));c=minimum(wx,wy);
  er=trim(er,top/16+(3*c)/64);eb=trim(eb,(3*c)/32);
  hi=maximum(maximum(red,green),blue);lo=minimum(minimum(red,green),blue);
  if(hi-lo<=hi/4)begin er=maximum(er,minimum(red,green));eb=maximum(eb,minimum(blue,green));end
  reference={8'(er),8'(green),8'(eb)};
 end endfunction
 function bit isgreen(input [23:0] p);
 integer r,g,b,lo,hi,c,d;begin
  r=p[23:16];g=p[15:8];b=p[7:0];lo=minimum(r,b);hi=maximum(r,b);c=maximum(0,g-lo);d=maximum(r,b)-minimum(r,b);
  isgreen=(g>=r && g>=b && 2*d<=c && c>=12 && c>=g/4 && g>=24 && (g<248 || g-hi>=g/4));
 end endfunction
 reg [23:0] expect0[0:7],expect1[0:7],mixpipe[0:7];
 reg [6:0] flags[0:7];
 integer xx=0,yy=0,seen=0,i,pixels=0,white=0,green=0,top_checks=0,corner_checks=0;
 reg vsd=0;reg [23:0] c0,c1;
 always @(posedge clk)begin
  if(!rst)begin xx=0;yy=0;seen=0;vsd=0;for(i=0;i<8;i=i+1)begin expect0[i]=0;expect1[i]=0;mixpipe[i]=0;flags[i]=0;end end
  else begin
   for(i=7;i>0;i=i-1)begin expect0[i]=expect0[i-1];expect1[i]=expect1[i-1];mixpipe[i]=mixpipe[i-1];flags[i]=flags[i-1];end
   c0=reference(camera,xx,yy,0);c1=reference(camera,xx,yy,1);
   expect0[0]=de?c0:0;expect1[0]=de?c1:0;mixpipe[0]=mixed;
   flags[0]={vs,hs,de,prot,de && seen,de && seen && xx==0 && yy==0,de && seen && xx==1279};
   if(de && seen)begin
    pixels=pixels+1;
    if(xx<900 && yy<256)top_checks=top_checks+1;
    if(xx>=1152 && yy>=616)corner_checks=corner_checks+1;
    if(camera==24'h808080 || camera==24'hffffFF || camera==24'h908090 || camera==24'h988098)begin
     if(isgreen(c0)||isgreen(c1))$fatal(1,"Neutral/white manufactured green x%0d y%0d",xx,yy);white=white+1;
    end
    if(camera==24'h00a000 || camera==24'h00ff00)begin
     if(!isgreen(c0)||!isgreen(c1))$fatal(1,"Saturated green lost");green=green+1;
    end
    if(xx>=1152 && yy>=616 && camera==24'h507870 && !isgreen(c1))$fatal(1,"Rotated corner casted target not recovered");
   end
   if(vs && !vsd)begin xx=0;yy=0;seen=1;end
   else if(de && seen)if(xx==1279)begin xx=0;yy=yy==719?0:yy+1;end else xx=xx+1;
   vsd=vs;
  end
  #1;if(rst)begin
   if({v0,h0,d0,p0,rd0,rs0,rl0}!==flags[7] || {v1,h1,d1,p1,rd1,rs1,rl1}!==flags[7])$fatal(1,"Eight-clock metadata/ROI alignment");
   if(roi0!==expect0[7] || roi1!==expect1[7])$fatal(1,"Golden RGB mismatch input pixels%0d got %h/%h expected %h/%h",pixels,roi0,roi1,expect0[7],expect1[7]);
   if(rgb0!==(flags[7][4]?(flags[7][3]?mixpipe[7]:expect0[7]):24'd0) || rgb1!==(flags[7][4]?(flags[7][3]?mixpipe[7]:expect1[7]):24'd0))$fatal(1,"OSD protection/shared ROI vs display mismatch");
  end
 end
 integer f,y,x,j,k;reg [23:0] samples[0:15];
 initial begin
  samples[0]=24'h808080;samples[1]=24'hffffff;samples[2]=24'h908090;samples[3]=24'h988098;
  samples[4]=24'h00a000;samples[5]=24'h00ff00;samples[6]=24'h000000;samples[7]=24'h0e0e0e;
  samples[8]=24'h507870;samples[9]=24'hf02020;samples[10]=24'h2040e0;samples[11]=24'h16110f;
  samples[12]=24'h101010;samples[13]=24'hf0f8f0;samples[14]=24'ha0b090;samples[15]=24'h202020;
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<2;f=f+1)begin
   @(negedge clk);vs=1;repeat(5)@(negedge clk);vs=0;repeat(25)@(negedge clk);
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin
     @(negedge clk);de=1;camera=samples[((x/80)+(y/45)+f)%16];
     if(f==1)begin
      camera=(y<256)?24'h908080:24'h808080;
      if(x>=800 && y>=480)camera=24'h988098;
      if(x>=1152 && y>=616 && x<1232 && y<696)camera=24'h507870;
     end
     prot=(x%128<7 && y%64<5);
    end
    @(negedge clk);de=0;prot=0;camera=0;hs=1;repeat(40)@(negedge clk);hs=0;repeat(329)@(negedge clk);
   end
  end
  repeat(20)@(negedge clk);
  if(pixels!=1843200 || white<100000 || green<100000 || top_checks<100000 || corner_checks<10000)$fatal(1,"Coverage counts");
  if(reference(24'h988098,1279,719,1)!==24'h808080)$fatal(1,"Bottom-right purple neutralization");
  if(reference(24'h908080,640,0,1)!==24'h808080)$fatal(1,"Top red neutralization");
  if(!isgreen(reference(24'h507870,1279,719,1)))$fatal(1,"Corner casted green was not recovered");
  $display("PASS spatial_bias: 1843200 pixels x both rotation mappings; scalar golden RGB; upright top and bottom-right offsets; original 8-clock metadata; OSD exact; shared display/ROI; whites not green; green targets retained and corner cast recovered");$finish;
 end
 initial begin #40000000;$fatal(1,"Color regression timeout");end
endmodule

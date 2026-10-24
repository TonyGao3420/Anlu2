`timescale 1ns/1ps
module tb_roi_center_osd;
reg clk=0;always #5 clk=~clk;reg rst=0,capture=0,valid=0;reg[15:0] x0=0,y0=0,x1=0,y1=0;reg[11:0] px=0,py=0;
wire hit,cv;wire[23:0] rgb;wire signed[15:0] cx,cy;
roi_center_osd dut(clk,rst,capture,valid,x0,y0,x1,y1,px,py,hit,rgb,cv,cx,cy);
function integer decimal_value;input[15:0] b;begin decimal_value=b[15:12]*1000+b[11:8]*100+b[7:4]*10+b[3:0];end endfunction
integer checked=0,k,ex,ey,a,b,c,d;reg[31:0] seed=32'h520c0;
task sample_box;input integer ax,ay,bx,by,v;
reg[15:0] oldx,oldy,olddx,olddy;reg oldvalid;integer j;
begin
 @(negedge clk);oldx=cx;oldy=cy;olddx=dut.digits_x;olddy=dut.digits_y;oldvalid=cv;
 x0=ax;y0=ay;x1=bx;y1=by;valid=v;capture=1;
 @(negedge clk);capture=0;
 if(v && ax<=bx && ay<=by && bx<1280 && by<720)begin
 for(j=0;j<15;j=j+1)begin
 if({cx,cy,cv,dut.digits_x,dut.digits_y}!=={oldx,oldy,oldvalid,olddx,olddy})$fatal(1,"Non-atomic coordinate conversion");
 // Changes on the live tracker wires cannot change this captured result.
 x0=0;y0=0;x1=0;y1=0;valid=0;@(negedge clk);
 end
 @(negedge clk);ex=(ax+bx)/2-640;ey=(ay+by)/2-360;
 if(!cv || cx!=ex || cy!=ey || decimal_value(dut.digits_x)!=(ex<0?-ex:ex) || decimal_value(dut.digits_y)!=(ey<0?-ey:ey))$fatal(1,"Center/decimal mismatch bounds %0d,%0d..%0d,%0d got %0d,%0d",ax,ay,bx,by,cx,cy);
 end else begin
 repeat(18)@(negedge clk);
 if(cv || cx!=0 || cy!=0)$fatal(1,"Invalid box retained coordinates");
 end
 checked=checked+1;
end endtask
reg[7:0] refchar;reg[3:0] refrow,refcol;wire[15:0] font;
osd_char_lib expected_font(refchar,refrow,font);
integer ci,xx,yy,digit,n,rendered=0;reg expected_glyph;
initial begin
 repeat(5)@(negedge clk);rst=1;
 sample_box(0,0,0,0,0);
 for(k=0;k<1280;k=k+1)sample_box(k,k%720,k,k%720,1);
 for(k=0;k<1000;k=k+1)begin
 a=$urandom(seed)%1280;b=$urandom(seed)%1280;c=$urandom(seed)%720;d=$urandom(seed)%720;
 sample_box(a<b?a:b,c<d?c:d,a>b?a:b,c>d?c:d,1);
 end
 sample_box(0,0,1279,719,1);sample_box(1278,718,1279,719,1);
 sample_box(800,100,100,200,1);sample_box(0,0,1280,719,1);sample_box(0,0,1279,720,1);sample_box(65535,65535,65535,65535,1);
 for(n=0;n<4;n=n+1)begin
 case(n)
 0:sample_box(180,260,540,620,1);
 1:sample_box(1000,300,1279,719,1);
 2:sample_box(620,340,660,380,1);
 3:sample_box(0,0,0,0,0);
 endcase
 for(ci=0;ci<17;ci=ci+1)begin
 refchar=" ";
 case(ci)
 0:refchar="R";1:refchar="O";2:refchar="I";4:refchar="X";5,12:refchar=":";11:refchar="Y";
 6,13:refchar=(n==3)?"-":((ci==6?ex:ey)<0?"-":"+");
 7,8,9,14,15,16:begin
 if(n==3)refchar="-";
 else begin
 digit=(ci<10)?ex:ey;if(digit<0)digit=-digit;
 case(ci)7,14:digit=(digit/100)%10;8,15:digit=(digit/10)%10;default:digit=digit%10;endcase
 refchar=48+digit;
 end end
 endcase
 for(yy=0;yy<32;yy=yy+1)for(xx=0;xx<32;xx=xx+1)begin
 @(negedge clk);px=375+ci*32+xx;py=160+yy;refrow=yy/2;refcol=xx/2;#1;
 expected_glyph=font[15-refcol];
 if(refchar=="-" || refchar=="+")expected_glyph=((refrow==7 || refrow==8) && refcol>=6 && refcol<=9);
 if(refchar=="+" && (refcol==7 || refcol==8) && refrow>=6 && refrow<=9)expected_glyph=1;
 if(!hit || rgb!==(expected_glyph?24'hfff200:24'h000000))$fatal(1,"Glyph/decimal/axis rendering mismatch cell %0d pixel %0d,%0d",ci,xx,yy);
 rendered=rendered+1;
 end
 end
 end
 @(negedge clk);px=374;py=160;#1;if(hit)$fatal(1,"HUD escaped left");
 px=919;#1;if(hit)$fatal(1,"HUD escaped right");px=375;py=192;#1;if(hit)$fatal(1,"HUD escaped bottom");
 rst=0;#1;if(cv || cx || cy)$fatal(1,"Reset did not clear coordinates");
 $display("PASS roi_center_osd: %0d boxes, full signed coordinate range, negative/positive/zero, odd midpoint, decimal carry, atomic capture, invalid/reset and %0d glyph pixels",checked,rendered);$finish;
end
initial begin #10000000;$fatal(1,"ROI center timeout");end
endmodule

`timescale 1ns/1ps
module tb_multi_slots;
 reg clk=0;always #5 clk=~clk;reg rst=0,sof=0,start=0,finish=0,cv=0;
 reg [11:0] ix0=0,iy0=0,ix1=0,iy1=0;reg [19:0] area=0;
 wire [7:0] v;wire [95:0] x0,y0,x1,y1;wire [3:0] count;wire [15:0] total,us;wire ov,late;
 multi_target_slots dut(clk,rst,sof,start,finish,cv,ix0,iy0,ix1,iy1,area,v,x0,y0,x1,y1,count,total,us,ov,late);
 task begin_scan;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task component(input integer x,y,w,h,a);begin
  @(negedge clk);ix0=x;iy0=y;ix1=x+w-1;iy1=y+h-1;area=a;cv=1;
  @(negedge clk);cv=0;repeat(11)@(negedge clk);
 end endtask
 task end_scan;begin @(negedge clk);finish=1;@(negedge clk);finish=0;
  repeat(300)@(negedge clk);if(!dut.ready)$fatal(1,"Association not complete");
  sof=1;@(negedge clk);sof=0;
 end endtask
 integer i;reg [391:0] previous;integer replacements;
 initial begin
  repeat(5)@(negedge clk);rst=1;begin_scan();
  for(i=0;i<8;i=i+1)component(50+i*140,100,24,30,100+i);
  end_scan();if(count!=8 || total!=8 || ov)$fatal(1,"Initial slots");
  previous={v,x0,y0,x1,y1};begin_scan();
  // Reversed component discovery order must not reverse established IDs.
  for(i=7;i>=0;i=i-1)component(53+i*140,103,24,30,100+i);
  repeat(20)@(negedge clk);if({v,x0,y0,x1,y1}!==previous)$fatal(1,"Uncommitted work leaked");
  end_scan();for(i=0;i<8;i=i+1)if(x0[i*12+:12]>53+i*140 || x1[i*12+:12]<76+i*140)$fatal(1,"ID or containment changed");
  begin_scan();for(i=0;i<8;i=i+1)component(50+i*140,100,24,30,100+i);
  component(0,600,100,40,4000);component(1150,600,100,40,5000);end_scan();
  if(count!=8 || total!=10 || !ov)$fatal(1,"Overflow count not reported");
  replacements=0;for(i=0;i<8;i=i+1)if(y0[i*12+:12]==598)replacements=replacements+1;
  if(replacements!=2)$fatal(1,"Top8 did not retain largest candidates");
  // Deliberately abort work before publish: no partially updated output.
  previous={v,x0,y0,x1,y1};begin_scan();component(400,400,30,30,900);
  @(negedge clk);sof=1;@(negedge clk);sof=0;
  if(!late || {v,x0,y0,x1,y1}!==previous)$fatal(1,"Late scan corrupted published boxes");
  end_scan();if(late)$fatal(1,"Late flag failed to clear on complete publication");
  begin_scan();end_scan();begin_scan();end_scan();if(count!=0)$fatal(1,"Old tracks failed to expire");
  // A new object cannot overwrite an old slot already matched this frame.
  begin_scan();component(100,100,30,40,1200);component(900,100,30,40,1200);end_scan();
  begin_scan();component(500,500,30,40,1200);component(903,103,30,40,1200);end_scan();
  if(x0[12+:12]>903 || x1[12+:12]<932 || y0[12+:12]>103)$fatal(1,"New target stole existing ID");
  $display("PASS multi_slots: reverse scan stable IDs, top8 largest, overflow count, atomic late hold/recovery, clipped margins, coasting expiry, independent reassignment");$finish;
 end
endmodule

`timescale 1ns/1ps
module tb_multi_tracker;
 localparam W=1280,H=720;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,sof=0,de=0,last=0;reg [23:0] rgb=0;
 wire [7:0] mv;wire [95:0] mx0,my0,mx1,my1;wire [3:0] count;wire [15:0] total,us;wire ov,late;
 wire [140:0] primary,baseline;
 roi_target_tracker #(.IMG_W(W),.IMG_H(H),.MIN_AREA(64),.MULTI_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst),.in_frame_start(sof),.in_de(de),.in_line_last(last),.in_rgb(rgb),
  .target_valid(primary[140]),.bbox_x0(primary[139:124]),.bbox_y0(primary[123:108]),.bbox_x1(primary[107:92]),.bbox_y1(primary[91:76]),
  .centroid_x(primary[75:60]),.centroid_y(primary[59:44]),.target_area(primary[43:24]),.frame_done(primary[23]),.result_update(primary[22]),
  .mask_valid(primary[21]),.green_mask(primary[20]),.mask_x(primary[19:8]),.mask_y(),.dbg_roi_valid(primary[7]),.dbg_color_match(primary[6]),
  .multi_valid(mv),.multi_x0(mx0),.multi_y0(my0),.multi_x1(mx1),.multi_y1(my1),.multi_count(count),.multi_total(total),.multi_us(us),.multi_overflow(ov),.multi_late(late));
 baseline_roi_target_tracker #(.IMG_W(W),.IMG_H(H),.MIN_AREA(64)) old(
  .clk(clk),.rst_n(rst),.in_frame_start(sof),.in_de(de),.in_line_last(last),.in_rgb(rgb),
  .target_valid(baseline[140]),.bbox_x0(baseline[139:124]),.bbox_y0(baseline[123:108]),.bbox_x1(baseline[107:92]),.bbox_y1(baseline[91:76]),
  .centroid_x(baseline[75:60]),.centroid_y(baseline[59:44]),.target_area(baseline[43:24]),.frame_done(baseline[23]),.result_update(baseline[22]),
  .mask_valid(baseline[21]),.green_mask(baseline[20]),.mask_x(baseline[19:8]),.mask_y(),.dbg_roi_valid(baseline[7]),.dbg_color_match(baseline[6]));
 assign primary[5:0]=0;assign baseline[5:0]=0;
 integer cycles=0;
 always @(negedge clk)if(rst)begin
  cycles=cycles+1;if(primary!==baseline)$fatal(1,"Original primary detector changed at %d",cycles);
 end
 task start;begin @(negedge clk);sof=1;@(negedge clk);sof=0;end endtask
 integer x,y,j,fx,fy,n,shift,mode;integer age,maxage=0;reg [391:0] held;
 task frame(input integer objects,offset,kind);
 begin
  held={mv,mx0,my0,mx1,my1};
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<W;x=x+1)begin
    @(negedge clk);de=1;last=x==W-1;rgb=24'hfafafa;
    for(j=0;j<objects;j=j+1)begin
     fx=32+(j%4)*300+offset;fy=32+(j/4)*220;
     if(x>=fx && x<fx+32 && y>=fy && y<fy+48)rgb=24'h20a030;
    end
    if(kind==1)rgb=24'h20a030;
    if(kind==2)rgb=((x%16)>=4 && (x%16)<=11 && (y%16)>=4 && (y%16)<=11)?24'h20a030:24'hfafafa;
    if({mv,mx0,my0,mx1,my1}!==held)$fatal(1,"Multi result changed mid-frame");
   end
   @(negedge clk);de=0;last=0;repeat(369)@(negedge clk);
  end
  age=0;while(!dut.regions.g_multi.slots.ready && age<49500)begin @(negedge clk);age=age+1;end
  if(age>=49500)$fatal(1,"Blanking deadline missed");if(age>maxage)maxage=age;
  repeat(49500-age)@(negedge clk);start();#1;
  if(late)$fatal(1,"Unexpected late flag");
 end endtask
 reg [95:0] saved;
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(4000)@(negedge clk);start();
  frame(8,0,0);if(count!=8 || total!=8 || ov)$fatal(1,"Eight independent objects: count %d total %d ov %b",count,total,ov);
  for(j=0;j<8;j=j+1)if(mx1[j*12+:12]-mx0[j*12+:12]>40 || my1[j*12+:12]-my0[j*12+:12]>56)$fatal(1,"Objects merged");
  saved=mx0;
  frame(8,4,0);if(count!=8 || total!=8)$fatal(1,"Moving targets lost");
  for(j=0;j<8;j=j+1)if(mx0[j*12+:12]<saved[j*12+:12] || mx0[j*12+:12]>saved[j*12+:12]+4)$fatal(1,"IDs switched");
  frame(0,0,0);if(count!=8 || total!=0)$fatal(1,"One-frame hold missing");
  frame(0,0,0);if(count!=0)$fatal(1,"Stale targets not released");
  frame(10,0,0);if(count!=8 || total!=10 || !ov)$fatal(1,"Capacity overflow not reported %d %d",count,total);
  frame(0,0,1);if(total!=1)$fatal(1,"Large target split");
  frame(0,0,2);if(total!=3600 || count!=8 || !ov)$fatal(1,"Worst case isolated cells count %d",total);
  $display("PASS multi_tracker: 8 independent/moving IDs, white rejection, empty hold/release, overflow, full-height/dense/3600 components, original primary cycle exact, worst tail %d/49500 clocks",maxage);$finish;
 end
 initial begin #200000000;$fatal(1,"Timeout");end
endmodule

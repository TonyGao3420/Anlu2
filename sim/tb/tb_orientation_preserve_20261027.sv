`timescale 1ns/1ps
module tb_orientation_preserve;
 reg clk=0;always #5 clk=~clk;reg rst=0,de=0,protect=0;reg [23:0] rgb=0;
 wire [23:0] old_rgb,new_rgb;integer sx=0,sy=0,rx=1279,ry=719;
 display_edge_color original(clk,rst,1'b0,1'b0,de,protect,rgb,,,,,old_rgb);
 display_edge_color #(.SOURCE_ROTATE_180(1)) rotated(clk,rst,1'b0,1'b0,de,protect,rgb,,,,,new_rgb);
 reg toggle=0,target_valid=0;reg [15:0] tx=640,ty=360;
 wire [15:0] turned_x=16'd1279-tx,turned_y=16'd719-ty;
 wire [15:0] adapted_x=16'd1279-turned_x,adapted_y=16'd719-turned_y;
 wire op,ot,np,nt;
 visual_servo_pwm #(.PWM_PERIOD_CYCLES(10000),.MIN_PULSE_CYCLES(250),.MAX_PULSE_CYCLES(1250),.PAN_STEP_PERIOD_MS(1),.TILT_STEP_PERIOD_MS(1))
  old_servo(clk,rst,toggle,target_valid,tx,ty,op,ot);
 visual_servo_pwm #(.PWM_PERIOD_CYCLES(10000),.MIN_PULSE_CYCLES(250),.MAX_PULSE_CYCLES(1250),.PAN_STEP_PERIOD_MS(1),.TILT_STEP_PERIOD_MS(1))
  new_servo(clk,rst,toggle,target_valid,adapted_x,adapted_y,np,nt);
 integer n,x,y,c,positions=0,checked=0;
 always @(posedge clk)begin #1;if(rst && {op,ot}!=={np,nt})$fatal(1,"Physical servo direction/step/PWM changed");checked=checked+1;end
 initial begin
  force original.x=sx;force original.y=sy;force rotated.x=rx;force rotated.y=ry;
  repeat(6)@(negedge clk);rst=1;de=1;
  for(y=0;y<5;y=y+1)for(x=0;x<5;x=x+1)for(c=0;c<4;c=c+1)begin
   sx=x*319;sy=y*179;rx=1279-sx;ry=719-sy;
   case(c)0:rgb=24'hb47846;1:rgb=24'hffffff;2:rgb=24'h0e0e0e;3:rgb=24'ha51fea;endcase
   protect=c==3;repeat(12)@(negedge clk);
   if(old_rgb!==new_rgb)$fatal(1,"Color correction did not follow rotation at source%0d,%0d",sx,sy);positions=positions+1;
  end
  for(n=0;n<8;n=n+1)begin
   tx=(n%4)*400;ty=(n%3)*330;target_valid=n!=5;toggle=~toggle;
   repeat(110000)@(negedge clk);
  end
  $display("PASS orientation_preserve: %0d spatial/color/protect cases, %0d servo clocks, rotated center adapter retains original physical PWM directions/steps/limits",positions,checked);$finish;
 end
endmodule

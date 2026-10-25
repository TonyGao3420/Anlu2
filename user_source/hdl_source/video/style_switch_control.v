// SW2 only: keep SW1 servo behavior entirely in the original top-level logic.
// Two synchronizer stages followed by 10 ms stable-level filtering at 75 MHz.
// The stylizer samples style_request at its first active pixel; its out_enable
// carries that selection through the video delay to the trajectory overlay.
module style_switch_control #(
 parameter integer CLK_HZ=75000000,DEBOUNCE_MS=10
)(input wire clk,rst_n,sw2_async,output reg style_request);
 localparam integer N=(CLK_HZ/1000)*DEBOUNCE_MS;
 localparam integer CW=(N<2)?1:$clog2(N);
 (* async_reg="true" *) reg [1:0] sw2_sync;
 reg [CW-1:0] stable_cycles;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sw2_sync<=0;stable_cycles<=0;style_request<=0;end
  else begin
   sw2_sync<={sw2_sync[0],sw2_async};
   if(sw2_sync[1]==style_request)stable_cycles<=0;
   else if(stable_cycles==N-1)begin style_request<=sw2_sync[1];stable_cycles<=0;end
   else stable_cycles<=stable_cycles+1'b1;
  end
 end
endmodule

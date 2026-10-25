// SIMULATION ONLY: exact constant table generated from unchanged production ROM.
module anlogic_logo_rom(input [14:0] I_addr,output reg [24:0] O_pixel);
 reg [24:0] pixels[0:32767];
 initial $readmemh("../build/style_mode_20261025/vectors/logo_rom.hex",pixels);
 always @* if((^I_addr)===1'bx)O_pixel=25'd0;else O_pixel=pixels[I_addr];
endmodule

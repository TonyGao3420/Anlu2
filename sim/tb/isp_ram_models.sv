module blk_mem_gen_zhenghe(input [31:0] dia,input [10:0] addra,input wea,clka,input [10:0] addrb,input clkb,input [31:0] dib,input web,output [31:0] doa,output reg [31:0] dob);
reg [31:0] mem[0:2047];integer j;initial for(j=0;j<2048;j=j+1)mem[j]=0;
always @(posedge clka)if(wea)mem[addra]<=dia;
always @(posedge clkb)begin dob<=mem[addrb];if(web)mem[addrb]<=dib;end
assign doa=0;
endmodule
module blk_mem_gen_demosaic(input [32:0] dia,input [10:0] addra,input wea,clka,input [10:0] addrb,input clkb,input [32:0] dib,input web,output [32:0] doa,output reg [32:0] dob);
reg [32:0] mem[0:2047];integer j;initial for(j=0;j<2048;j=j+1)mem[j]=0;
always @(posedge clka)if(wea)mem[addra]<=dia;
always @(posedge clkb)begin dob<=mem[addrb];if(web)mem[addrb]<=dib;end
assign doa=0;
endmodule

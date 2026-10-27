module PH1P_LOGIC_ERAM (
  dia,
  addra, cea, ocea, clka, wea, rsta, bea,
  dib,
  addrb, ceb, oceb, clkb, web, rstb, beb,
  ecc_sbiterrinj, ecc_dbiterrinj,
  doa,
  dob,
  ecc_sbiterr,
  ecc_dbiterr
  );
  parameter DATA_WIDTH_A = 20;                                              
  parameter DATA_WIDTH_B = DATA_WIDTH_A;                                    
  parameter ADDR_WIDTH_A = 10;                                              
  parameter ADDR_WIDTH_B = ADDR_WIDTH_A;                                    
  parameter DATA_DEPTH_A = 2 ** ADDR_WIDTH_A;                               
  parameter DATA_DEPTH_B = 2 ** ADDR_WIDTH_B;                               
  parameter BYTE_ENABLE = 0;                                                
  parameter BYTE_A = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_A / BYTE_ENABLE;     
  parameter BYTE_B = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_B / BYTE_ENABLE;     
  output  ecc_sbiterr;                                                      
  output  ecc_dbiterr;                                                      
  output  [DATA_WIDTH_A-1:0] doa;                                           
  output  [DATA_WIDTH_B-1:0] dob;                                           
  input   [DATA_WIDTH_A-1:0] dia;                                           
  input   [DATA_WIDTH_B-1:0] dib;                                           
  input   ecc_sbiterrinj, ecc_dbiterrinj;                                   
  input   cea;                                                              
  input   ocea;                                                             
  input   clka;                                                             
  input   wea;                                                              
  input   rsta;                                                             
  input   ceb;                                                              
  input   oceb;                                                             
  input   clkb;                                                             
  input   web;                                                              
  input   rstb;                                                             
  input [BYTE_A - 1 : 0] bea;                                               
  input [BYTE_B - 1 : 0] beb;                                               
  input   [ADDR_WIDTH_A-1:0] addra;                                         
  input   [ADDR_WIDTH_B-1:0] addrb;                                         
  parameter MODE = "DP";                     // "DP", "SP", "PDPW", "FIFO".
  parameter REGMODE_A = "NOREG";             // "NOREG", "OUTREG".
  parameter REGMODE_B = "NOREG";             // "NOREG", "OUTREG".
  parameter WRITEMODE_A = "NORMAL";          // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH".
  parameter WRITEMODE_B = "NORMAL";          // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH".
  parameter RESETMODE_A = "ASYNC";           // "SYNC", "ASYNC".
  parameter RESETMODE_B = "ASYNC";           // "SYNC", "ASYNC".
  parameter OREGSET_A = "SET";               // "SET", "RESET".
  parameter OREGSET_B = "SET";               // "SET", "RESET".
  parameter SSROVERCE = "ENABLE";            // "DISABLE", "ENABLE".
  parameter ECC_DECODE = "DISABLE";          // "DISABLE", "ENABLE".
  parameter ECC_ENCODE = "DISABLE";          // "DISABLE", "ENABLE".
  parameter ASYNC_RESET_RELEASE_A = "SYNC";  // "SYNC", "ASYNC".
  parameter ASYNC_RESET_RELEASE_B = "SYNC";  // "SYNC", "ASYNC".
  parameter CLKMODE = "ASYNC";               // "ASYNC", "SYNC".
  parameter DEBUGGABLE = "NO";               // "YES", "NO".
  parameter PACKABLE = "NO";                 // "YES", "NO".
  parameter FORCE_KEEP = "OFF";              // "ON", "OFF".
  parameter INIT_FILE = "NONE";              
  parameter FILL_ALL = "NONE";               
  parameter IMPLEMENT = "20K";               // "20K", "20K(FAST)".
reg [DATA_WIDTH_B-1:0] mem[0:DATA_DEPTH_B-1];
reg [DATA_WIDTH_B-1:0] b_out;
assign dob=b_out;assign doa=0;assign ecc_sbiterr=0;assign ecc_dbiterr=0;
initial begin
if(MODE!="DP" || REGMODE_B!="OUTREG")$fatal(1,"Unsupported ROM mode");
if(INIT_FILE=="logo_index0.mif")$readmemh("../build/final_four_modes_20261028/logo_index0.hex",mem);
else if(INIT_FILE=="logo_index1.mif")$readmemh("../build/final_four_modes_20261028/logo_index1.hex",mem);
else if(INIT_FILE=="logo_index2.mif")$readmemh("../build/final_four_modes_20261028/logo_index2.hex",mem);
else if(INIT_FILE=="logo_index3.mif")$readmemh("../build/final_four_modes_20261028/logo_index3.hex",mem);
else if(INIT_FILE=="logo_palette.mif")$readmemh("../build/final_four_modes_20261028/logo_palette.hex",mem);
else if(INIT_FILE=="official_logo_index0.mif")$readmemh("../build/final_four_modes_20261028/official_logo_index0.hex",mem);
else if(INIT_FILE=="official_logo_index1.mif")$readmemh("../build/final_four_modes_20261028/official_logo_index1.hex",mem);
else if(INIT_FILE=="official_logo_index2.mif")$readmemh("../build/final_four_modes_20261028/official_logo_index2.hex",mem);
else if(INIT_FILE=="official_logo_palette.mif")$readmemh("../build/final_four_modes_20261028/official_logo_palette.hex",mem);
else $fatal(1,"Unknown logo MIF %s",INIT_FILE);
end
always @(posedge clkb)begin
if(web || wea)$fatal(1,"Unexpected logo write");
if(ceb && oceb)b_out<=mem[addrb];
end
endmodule

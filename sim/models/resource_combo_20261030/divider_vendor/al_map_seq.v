///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//               seq
//   Filename : al_map_seq.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////
module AL_MAP_SEQ (ce, clk, sr, d, q);
input ce, clk, sr, d;
output q;

parameter DFFMODE = "FF"; //FF,LATCH
parameter REGSET = "RESET"; //RESET/SET
parameter SRMUX = "SR"; //SR/INV
parameter SRMODE = "SYNC"; //SYNC/ASYNC
parameter INI = "0"; //1(SET)/0(RESET)
parameter CEMUX = "CE";
parameter CLKMUX = "CLK";
parameter GSR = "DISABLE";

tri1 ce;
tri0 d,sr,clk;

`ifdef FORMAL_VERIFICATION
reg q_reg, q_latch;
parameter INIT = REGSET=="RESET" ? 1'b0 : 1'b1;
reg q=INIT;
wire gsr = 0;
`else
reg q, q_reg, q_latch;
reg INIT = REGSET=="RESET" ? 1'b0 : 1'b1;
reg mc1_gsr;

initial begin
  case (GSR)
   	"DISABLE"   : mc1_gsr = 0;
   	"ENABLE"    : mc1_gsr = 1;
   	default : begin
    //mc1_gsr = 0;
      $display("Parameter Error : The attribute GSR in AL_MAP_SEQ instance is set to %s. It's not Legal value.\n", GSR);
      $finish;
    end
  endcase
end

tri0 gsrn = glbl.gsrn;
wire done_gwe = glbl.done_gwe;
wire gsr  = !(done_gwe & (!mc1_gsr) | gsrn);
always @(gsr) 
  begin
    if (gsr) 
      assign q = INIT;
    else 
      deassign q;
  end
`endif


reg clk_in, ce_in, sr_s,sr_a;

always @(*) begin
`ifndef FORMAL_VERIFICATION
  case (INI)
    "1"        : INIT = 1'b1;
    "0"        : INIT = 1'b0;
    default     : INIT = 1'b0;
  endcase
`endif
  case(CLKMUX)
    "CLK"  	   : clk_in = clk;
    "SIG"  	   : clk_in = clk;
    "INV"      : clk_in = ~clk;
    "1"        : clk_in = 1'b1;
    "0"        : clk_in = 1'b0;
    default    : clk_in = clk;
  endcase

  case(CEMUX)
    "CE"       : ce_in = ce;
    "SIG"      : ce_in = ce;
    "INV"      : ce_in = ~ce;
    "1"        : ce_in = 1'b1;
    "0"        : ce_in = 1'b0;
    default    : ce_in = 1'b1;
  endcase

  case (SRMUX)
    "SR"       : sr_s = sr;
    "SIG"      : sr_s = sr;
    "INV"      : sr_s = ~sr;
    default     : sr_s = sr;
  endcase
`ifndef FORMAL_VERIFICATION
  case (REGSET)
    "SET"      : INIT = 1'b1;
    "RESET"    : INIT = 1'b0;
    default     : INIT = 1'b0;
  endcase
`endif
  case (SRMODE)
    "SYNC"     :   sr_a = gsr;
    "ASYNC"    :   sr_a = gsr | sr_s;
     default    :   sr_a = gsr;
  endcase

  case (DFFMODE)
    "FF"      : begin
                     q <= q_reg;
                end
    "LATCH"   : begin
                     q <= q_latch;
                end
    default    : begin
                     q <= q_reg;
                  end
  endcase

end

always @(posedge clk_in or posedge sr_a) begin
  if (sr_a)
    q_reg <= INIT;
  else if(sr_s)
	 q_reg <= INIT;
  else if (ce_in)
    q_reg <= d;
end

always @(*) begin
  if (sr_a)
    q_latch <= INIT;
  else if (clk_in)
    if (sr_s)
      q_latch <= INIT;
    else if (ce_in)
      q_latch <= d;
end

specify
  (clk => q) = (0:0:0, 0:0:0);

  // recovery,removal
  $recovery (sr, posedge clk, 0:0:0);
  $removal  (sr, posedge clk, 0:0:0);
  $recovery (sr, negedge clk, 0:0:0);
  $removal  (sr, negedge clk, 0:0:0);

  // posedge
  $setuphold (posedge clk, posedge d , 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge ce, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge d , 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge ce, 0:0:0, 0:0:0);

  // negedge
  $setuphold (posedge clk, negedge d,  0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge ce, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge d,  0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge ce, 0:0:0, 0:0:0);
endspecify
endmodule

module AL_MAP_SEQ_GSR (ce, clk, sr, d, q);
input ce, clk, sr, d;
output q;

parameter DFFMODE = "FF"; //FF,LATCH
parameter REGSET = "RESET"; //RESET/SET
parameter SRMUX = "SR"; //SR/INV
parameter SRMODE = "SYNC"; //SYNC/ASYNC
parameter INI = "0"; //1(SET)/0(RESET)
parameter CEMUX = "CE";
parameter CLKMUX = "CLK";
parameter GSR = "DISABLE";

tri1 ce;
tri0 d,sr,clk;

`ifdef FORMAL_VERIFICATION
reg q_reg, q_latch;
parameter INIT = REGSET=="RESET" ? 1'b0 : 1'b1;
reg q=INIT;
wire gsr = 0;
`else
reg q, q_reg, q_latch;
reg INIT = REGSET=="RESET" ? 1'b0 : 1'b1;
reg mc1_gsr;

initial begin
  case (GSR)
   	"DISABLE"   : mc1_gsr = 0;
   	"ENABLE"    : mc1_gsr = 1;
   	default : begin
    //mc1_gsr = 0;
      $display("Parameter Error : The attribute GSR in AL_MAP_SEQ_GSR instance is set to %s. It's not Legal value.\n", GSR);
      $finish;
    end
  endcase
end

tri0 gsrn = glbl.gsrn;
wire done_gwe = glbl.done_gwe;
wire gsr  = !(done_gwe & (!mc1_gsr) | gsrn);
always @(gsr) 
  begin
    if (gsr) 
      assign q = INIT;
    else 
      deassign q;
  end
`endif
reg clk_in, ce_in, sr_s,sr_a;

always @(*) begin
`ifndef FORMAL_VERIFICATION
  case (INI)
    "1"        : INIT = 1'b1;
    "0"        : INIT = 1'b0;
    default     : INIT = 1'b0;
  endcase
`endif
  case(CLKMUX)
    "CLK"  	   : clk_in = clk;
    "SIG"  	   : clk_in = clk;
    "INV"      : clk_in = ~clk;
    "1"        : clk_in = 1'b1;
    "0"        : clk_in = 1'b0;
    default    : clk_in = clk;
  endcase

  case(CEMUX)
    "CE"       : ce_in = ce;
    "SIG"      : ce_in = ce;
    "INV"      : ce_in = ~ce;
    "1"        : ce_in = 1'b1;
    "0"        : ce_in = 1'b0;
    default    : ce_in = 1'b1;
  endcase

  case (SRMUX)
    "SR"       : sr_s = sr;
    "SIG"      : sr_s = sr;
    "INV"      : sr_s = ~sr;
    default     : sr_s = sr;
  endcase
`ifndef FORMAL_VERIFICATION
  case (REGSET)
    "SET"      : INIT = 1'b1;
    "RESET"    : INIT = 1'b0;
    default     : INIT = 1'b0;
  endcase
`endif
  case (SRMODE)
    "SYNC"     :   sr_a = gsr;
    "ASYNC"    :   sr_a = gsr | sr_s;
     default    :   sr_a = gsr;
  endcase

  case (DFFMODE)
    "FF"      : begin
                     q <= q_reg;
                end
    "LATCH"   : begin
                     q <= q_latch;
                end
    default    : begin
                     q <= q_reg;
                  end
  endcase

end

always @(posedge clk_in or posedge sr_a) begin
  if (sr_a)
    q_reg <= INIT;
  else if(sr_s)
	q_reg <= INIT;
  else if (ce_in)
    q_reg <= d;
end

always @(*) begin
  if (sr_a)
    q_latch <= INIT;
  else if (clk_in)
    if (sr_s)
      q_latch <= INIT;
    else if (ce_in)
      q_latch <= d;
end
   
specify
  (clk => q) = (0:0:0, 0:0:0);

  // recovery, removal
  $recovery (sr, posedge clk, 0:0:0);
  $removal  (sr, posedge clk, 0:0:0);
  $recovery (sr, negedge clk, 0:0:0);
  $removal  (sr, negedge clk, 0:0:0);

  // posedge
  $setuphold (posedge clk, posedge d , 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge ce, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge d , 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge ce, 0:0:0, 0:0:0);

  // negedge
  $setuphold (posedge clk, negedge d,  0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge ce, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge d,  0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge ce, 0:0:0, 0:0:0);
endspecify
endmodule

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
su4MlKU8+402CR6LDS9cxwTZKAbsI23atz+mD9jtwCUG7eacE+xXQkUYzN0yJjpg
FFAj5jbDdCzvJvxmkkIGXG8s1C/fENg6HHyaaITD11bUqngugvF+okTDH7FAqFB5
YcKHb8Vlz1iGqKMJ3RZGyeFvWPNf6wusp0y+o8Zh3j4=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
f52n19Q4urMvPA1qKx/AvVPCfJ0yZuzrsm98WHnkcOQlG/glV16QDR7S37iyPxbK
qJ6Mq4qZS8TFMon9XwQ5mamrKQ2wYYqeX1G9oi3C8D/wETXUNLVWLbJGs57SByCP
eMsvjeZ4BAgumHa+5qZA/ByP+5ynklqMFAOXYRoArX4=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
pTJ+eXstmGdQcwTO/QGESBpnJ7eRVHKjZvnAOtjDi/AC7c0RzAGnWaRBPSm/UqND
2TpgsuvccOorAUHyIhor3qkv8jtWIr3y9W36nRj4JEO9ijXdvhJXpOQ0+vgo/Tbg
rr3+x9jIzDf4T7CUSpuIqsQW1Fdg7vweZ12PaKHSTU/JTvbSca8jO7tOPwV5KUg3
cutVLwqPAK7sCeAf72D1+eBArtDqZgGSht+D7UxxYrv8RmXUsCGbpO/j8F48U++U
rXTNWYNTJMq0w1/VpcESphLsb8b2TqhkoomVtTmG7YcunwKJpsKaKTl6l48EQvHD
J4DLqYP+wYbFrcnEyEewZg==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
ZvfzAf7PRkuRm6nsiXQV6BdDpJobl4DYrcQzc86UOyrt/gUme+6RKKiIUiggiGnx
YRvC9KUC4xQI12YYNCPT1rMkcbc3QFfoSbLaVElJDxrf9FahbvTuy/efU/5aIEsa
RBKnW012FMo3+OlUcoKdNOD5K11yix0Y1iIuP0s+xF8=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Mq9t6Xrtikv4COKcSVZ3ZshBLHqoVAYuf0jbOug5+ExESnVQkpWhHqHpk9+wI2rg
3/9ZTT8FD4KJVL0+RRUB1UxCVUsCOqDa2+zg1V4Hk0m2ZEBH8Kw4rIT+Y3kBaDWz
wQ5YekxLURcV34ut6OmK7AT5k7UHM2gwt0NSqphPsF0gkGGM1AY8BdLS0T7r/L8j
vnB4ld5WCHGFeLa98WfUte5AiT0TK7XYVf6Dm3HRBziFq9H3oasVOyXvPXvw9BN5
MO37YZq2r2EzGnULbpbUJV9jmpFdgFxNajhKOs5fXSn/Ku/6KbpR6Ty+UKH4ZSUV
9w+dZZBBSQABuSqj0RoDcw==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
d2lnGYQDieLPRG+78shxbu3QjfNQDUwoe8TYcHXlDthRQgqRCTTGtfNi0HPFs/zh
iaCLIbHbkdc5jWR2W0IXvxJ/OqLBK765y+MvasdyxnAAjn9u4e6SvBpRvjnbUwZT
byEhK5VtRAygzKFgg10UP9kWEmgf3gY3uB3LsilDqkg1xW1LpMCZBW80SNkwpDGy
hTHkLC9pt1MR/BNZiEKy6X0p0nuDQXdBZW8GBg5Mx8SH7nQia/n/2czlE31680lJ
opneOj5gWawQHxg4GEd6YMiqYoPKwWTXH79KFfVFuge8OSevh1nylBWqUMnP89Hs
uDqv1GxFTlUVmR5hQ0ddKw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 48)
`pragma protect data_block
x8CRoYDY1tGjhtOIgQ9QdhJG7AyClCYRNVYsYgZuuXzlxwgg9X7WDtYnFu8Fp13u
`pragma protect end_protected

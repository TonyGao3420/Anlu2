// Measured white-field correction, shared by camera display and green ROI.
// Located after DDR, before OSD selection/brightness; ISP/AWB/sensor unchanged.
// Eight pipeline clocks. Same latency for RGB/VS/HS/DE/protection.
// Nine measured nodes, continuous bilinear gain, clamped beyond outer nodes.
// G is unchanged here; the existing downstream 17/16 RGB gain remains uniform.
module display_color_shading #(
    parameter integer ENABLE=1,
    parameter integer BLACK_PIVOT=14
)(
    input wire clk,rst_n,
    input wire in_vs,in_hs,in_de,in_protect,
    input wire [11:0] x,y,
    input wire [23:0] in_rgb,
    output wire out_vs,out_hs,out_de,out_protect,
    output reg [23:0] out_rgb
);
    function [9:0] r_gain;
        input [3:0] node;
        begin case(node)
            4'd0: r_gain=10'd204;
            4'd1: r_gain=10'd282;
            4'd2: r_gain=10'd192;
            4'd3: r_gain=10'd197;
            4'd4: r_gain=10'd327;
            4'd5: r_gain=10'd185;
            4'd6: r_gain=10'd185;
            4'd7: r_gain=10'd249;
            4'd8: r_gain=10'd183;
            default:r_gain=10'd256;
        endcase end
    endfunction
    function [9:0] b_gain;
        input [3:0] node;
        begin case(node)
            4'd0: b_gain=10'd228;
            4'd1: b_gain=10'd257;
            4'd2: b_gain=10'd240;
            4'd3: b_gain=10'd229;
            4'd4: b_gain=10'd281;
            4'd5: b_gain=10'd237;
            4'd6: b_gain=10'd227;
            4'd7: b_gain=10'd251;
            4'd8: b_gain=10'd243;
            default:b_gain=10'd256;
        endcase end
    endfunction
    reg [3:0] tl;
    reg [8:0] fx,fy;
    reg [8:0] dy;
    reg [17:0] scaled_y;
    always @* begin
        tl=((y<360)?4'd0:4'd3)+((x<640)?4'd0:4'd1);
        if(x<=64) fx=0;
        else if(x>=1216) fx=256;
        else if(x<640) fx=((x-64)*57)>>7;
        else fx=((x-640)*57)>>7;
        dy=0;scaled_y=0;
        if(y<=32) fy=0;
        else if(y>=688) fy=256;
        else begin
            dy=(y<360)?y-32:y-360;
            // 200/256 maps the 328-pixel half-span to full weight.
            scaled_y=dy*8'd200+18'd128;
            fy=scaled_y[16:8];
        end
    end
    reg [7:0] vp,hp,dp,pp;
    reg [23:0] raw[0:6];
    assign out_vs=vp[7];assign out_hs=hp[7];
    assign out_de=dp[7];assign out_protect=pp[7];
    reg [8:0] fx1,fy1,fy2,fy3;
    // Exact pre-rounded horizontal interpolants, two channels per ERAM row.
    // Three 1024x18 ROMs replace four per-pixel horizontal multipliers.
    wire [9:0] row_addr={(x>=640),fx};
    wire [17:0] row0,row1,row2;
    shading_horizontal_rom #(.INIT_FILE("shading_row0.mif")) rom0(clk,row_addr,row0);
    shading_horizontal_rom #(.INIT_FILE("shading_row1.mif")) rom1(clk,row_addr,row1);
    shading_horizontal_rom #(.INIT_FILE("shading_row2.mif")) rom2(clk,row_addr,row2);
    reg bottom_half1;
    reg [9:0] rt_base2,rb_base2,bt_base2,bb_base2;
    reg [9:0] rt3,rb3,bt3,bb3;
    wire signed [8:0] rd=$signed({1'b0,rb3})-$signed({1'b0,rt3});
    wire signed [8:0] bd=$signed({1'b0,bb3})-$signed({1'b0,bt3});
    reg signed [20:0] r_vertical,b_vertical;
    reg [9:0] r_base4,b_base4;
    reg [9:0] r5,b5,r6,b6;
    reg [7:0] red_delta,blue_delta;
    reg [17:0] red_product,blue_product;
    function [7:0] finish_channel;
        input [7:0] original;
        input [17:0] product;
        reg [18:0] lifted;
        begin
            lifted=BLACK_PIVOT+((product+19'd128)>>8);
            if(original<=BLACK_PIVOT) finish_channel=original;
            else if(lifted>255) finish_channel=255;
            else finish_channel=lifted[7:0];
        end
    endfunction
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vp<=0;hp<=0;dp<=0;pp<=0;out_rgb<=0;
            for(i=0;i<7;i=i+1) raw[i]<=0;
            fx1<=0;fy1<=0;fy2<=0;fy3<=0;
            bottom_half1<=0;
            rt_base2<=256;rb_base2<=256;bt_base2<=256;bb_base2<=256;
            rt3<=256;rb3<=256;bt3<=256;bb3<=256;
            r_vertical<=0;b_vertical<=0;r_base4<=256;b_base4<=256;
            r5<=256;b5<=256;r6<=256;b6<=256;
            red_delta<=0;blue_delta<=0;red_product<=0;blue_product<=0;
        end else begin
            vp<={vp[6:0],in_vs};hp<={hp[6:0],in_hs};
            dp<={dp[6:0],in_de};pp<={pp[6:0],in_protect};
            raw[0]<=in_rgb;for(i=1;i<7;i=i+1) raw[i]<=raw[i-1];
            // P1 ROM read; P2 row selection; P3 original horizontal boundary.
            fy1<=fy;bottom_half1<=(y>=360);
            rt_base2<=bottom_half1?{1'b0,row1[8:0]}:{1'b0,row0[8:0]};
            rb_base2<=bottom_half1?{1'b0,row2[8:0]}:{1'b0,row1[8:0]};
            bt_base2<=bottom_half1?{1'b0,row1[17:9]}:{1'b0,row0[17:9]};
            bb_base2<=bottom_half1?{1'b0,row2[17:9]}:{1'b0,row1[17:9]};
            fy2<=fy1;
            rt3<=rt_base2;rb3<=rb_base2;bt3<=bt_base2;bb3<=bb_base2;fy3<=fy2;
            // 4/5: vertical interpolation.
            r_vertical<=rd*$signed({1'b0,fy3});
            b_vertical<=bd*$signed({1'b0,fy3});
            r_base4<=rt3;b_base4<=bt3;
            r5<=$signed({1'b0,r_base4})+((r_vertical+21'sd128)>>>8);
            b5<=$signed({1'b0,b_base4})+((b_vertical+21'sd128)>>>8);
            // 6/7: subtract measured dark pivot, multiply signal, preserve G.
            red_delta<=(raw[4][23:16]>BLACK_PIVOT)?raw[4][23:16]-BLACK_PIVOT:0;
            blue_delta<=(raw[4][7:0]>BLACK_PIVOT)?raw[4][7:0]-BLACK_PIVOT:0;
            r6<=r5;b6<=b5;
            red_product<=red_delta*r6;blue_product<=blue_delta*b6;
            // 8: bounded output; protected OSD/ROI and darks are exact.
            if(!dp[6]) out_rgb<=0;
            else if(!ENABLE || pp[6]) out_rgb<=raw[6];
            else out_rgb<={finish_channel(raw[6][23:16],red_product),raw[6][15:8],
                           finish_channel(raw[6][7:0],blue_product)};
        end
    end
endmodule

// Native single-cycle ROM. File is relative to this HDL source directory.
module shading_horizontal_rom #(parameter INIT_FILE="shading_row0.mif")(
 input clk,input [9:0] addr,output [17:0] q);
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(18),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(18),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("OUTREG"),.IMPLEMENT("20K(FAST)"),
 .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
 .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.CLKMODE("ASYNC"),
 .SSROVERCE("DISABLE"),.INIT_FILE(INIT_FILE),.FILL_ALL("NONE")) ram(
 .dia(18'd0),.addra(10'd0),.cea(1'b0),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),
 .dib(18'd0),.addrb(addr),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(q),
 .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
endmodule

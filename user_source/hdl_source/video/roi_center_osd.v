// Frame-stable signed ROI midpoint relative to (IMG_W/2, IMG_H/2); no pixel/ROI feedback path.
// Capture after the tracker's SOF publication, then convert both axes together.
// Decimal conversion uses shift/add only (16 clocks, no divider or multiplier).
module roi_center_osd #(
 parameter integer IMG_W=1280,IMG_H=720,HUD_X=375,HUD_Y=160
)(
 input wire clk,rst_n,capture,bbox_valid,
 input wire [15:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1,
 input wire [11:0] pixel_x,pixel_y,
 output wire hit,output wire [23:0] rgb,
 output reg center_valid,output reg signed [15:0] center_x,center_y
);
 wire [16:0] x_sum={1'b0,bbox_x0}+{1'b0,bbox_x1};
 wire [16:0] y_sum={1'b0,bbox_y0}+{1'b0,bbox_y1};
 // Keep tracker/servo coordinates absolute; only this HUD uses the image center.
 localparam [15:0] ORIGIN_X=IMG_W/2,ORIGIN_Y=IMG_H/2;
 wire [15:0] absolute_x=x_sum[16:1],absolute_y=y_sum[16:1];
 wire signed [15:0] relative_x=$signed(absolute_x)-$signed(ORIGIN_X);
 wire signed [15:0] relative_y=$signed(absolute_y)-$signed(ORIGIN_Y);
 wire [15:0] magnitude_x=absolute_x<ORIGIN_X?ORIGIN_X-absolute_x:absolute_x-ORIGIN_X;
 wire [15:0] magnitude_y=absolute_y<ORIGIN_Y?ORIGIN_Y-absolute_y:absolute_y-ORIGIN_Y;
 wire bounds_ok=bbox_valid && bbox_x0<=bbox_x1 && bbox_y0<=bbox_y1 &&
                bbox_x1<IMG_W && bbox_y1<IMG_H;
 reg [15:0] binary_x,binary_y,pending_x,pending_y,bcd_x,bcd_y,digits_x,digits_y;
 reg [4:0] remaining;
 function [15:0] adjust_bcd;
 input [15:0] bcd;integer n;reg [15:0] adjusted;
 begin
 adjusted=bcd;
 for(n=0;n<4;n=n+1)if(bcd[n*4+:4]>=5)adjusted[n*4+:4]=bcd[n*4+:4]+4'd3;
 adjust_bcd=adjusted;
 end endfunction
 wire [15:0] next_bcd_x=(adjust_bcd(bcd_x)<<1)|{15'd0,binary_x[15]};
 wire [15:0] next_bcd_y=(adjust_bcd(bcd_y)<<1)|{15'd0,binary_y[15]};
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 binary_x<=0;binary_y<=0;pending_x<=0;pending_y<=0;bcd_x<=0;bcd_y<=0;
 digits_x<=0;digits_y<=0;remaining<=0;center_valid<=0;center_x<=0;center_y<=0;
 end else if(capture)begin
 if(bounds_ok)begin
 pending_x<=relative_x;pending_y<=relative_y;
 binary_x<=magnitude_x;binary_y<=magnitude_y;bcd_x<=0;bcd_y<=0;remaining<=16;
 end else begin
 remaining<=0;center_valid<=0;center_x<=0;center_y<=0;digits_x<=0;digits_y<=0;
 end
 end else if(remaining!=0)begin
 bcd_x<=next_bcd_x;bcd_y<=next_bcd_y;
 binary_x<=binary_x<<1;binary_y<=binary_y<<1;remaining<=remaining-1'b1;
 if(remaining==1)begin
 digits_x<=next_bcd_x;digits_y<=next_bcd_y;
 center_x<=pending_x;center_y<=pending_y;center_valid<=1;
 end
 end
 end
 wire [11:0] local_x=pixel_x-HUD_X,local_y=pixel_y-HUD_Y;
 wire [4:0] character_index=local_x[9:5];
 wire [3:0] glyph_col=local_x[4:1],glyph_row=local_y[4:1];
 reg [7:0] character;
 always @*begin
 character=8'h20;
 case(character_index)
 0:character="R";1:character="O";2:character="I";
 4:character="X";5:character=":";
 6:character=center_valid?(center_x[15]?"-":"+"):"-";
 7:character=center_valid?{4'h3,digits_x[11:8]}:"-";
 8:character=center_valid?{4'h3,digits_x[7:4]}:"-";
 9:character=center_valid?{4'h3,digits_x[3:0]}:"-";
 11:character="Y";12:character=":";
 13:character=center_valid?(center_y[15]?"-":"+"):"-";
 14:character=center_valid?{4'h3,digits_y[11:8]}:"-";
 15:character=center_valid?{4'h3,digits_y[7:4]}:"-";
 16:character=center_valid?{4'h3,digits_y[3:0]}:"-";
 default:character=8'h20;
 endcase
 end
 wire [15:0] row_bits;
 osd_char_lib font(.I_char(character),.I_row(glyph_row),.O_row_bits(row_bits));
 wire horizontal_sign=(glyph_row==7 || glyph_row==8) && glyph_col>=6 && glyph_col<=9;
 wire vertical_sign=(glyph_col==7 || glyph_col==8) && glyph_row>=6 && glyph_row<=9;
 wire glyph_on=(character=="-")?horizontal_sign:
               (character=="+")?(horizontal_sign || vertical_sign):row_bits[15-glyph_col];
 // Transparent ROI HUD background: only glyph pixels inside the HUD area.
 wire hud_area=(pixel_x>=HUD_X && pixel_x<HUD_X+544 && pixel_y>=HUD_Y && pixel_y<HUD_Y+32);
 assign hit=hud_area && glyph_on;
 assign rgb=glyph_on?24'hfff200:24'h000000;
endmodule

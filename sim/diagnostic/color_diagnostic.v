// Read-only flat-field diagnostics. Not part of the production project.
// RAW words have pixel 0 in [9:0], matching the SC520 reference converter.
// Each window has power-of-two area: means use exact shifts, no divider.
module color_raw_probe #(
    parameter integer W=1280, H=720, HX=32, HY=16
)(
    input wire clk, rst_n, valid, user, last,
    input wire [39:0] data,
    input wire ack_async,
    output reg publish_toggle,
    output reg [359:0] means,
    output reg [8:0] good, clipped
);
    localparam integer X0=(W/10/4)*4, X1=W/2, X2=W-X0;
    localparam integer Y0=(H/8/2)*2, Y1=H/2, Y2=H-Y0;
    localparam integer SHIFT=$clog2(HX*HY);
    reg [11:0] x,y;
    wire [11:0] px=user?12'd0:x, py=user?12'd0:y;
    reg [18:0] sums[0:35];
    reg [11:0] counts[0:8];
    reg [8:0] clip_acc;
    reg [19:0] words;
    reg active;
    (* async_reg="true" *) reg ack1,ack2;
    wire [10:0] ev={1'b0,data[9:0]}+{1'b0,data[29:20]};
    wire [10:0] od={1'b0,data[19:10]}+{1'b0,data[39:30]};
    wire clip_word=(data[9:0]>=1000)||(data[19:10]>=1000)||
                   (data[29:20]>=1000)||(data[39:30]>=1000);
    integer n,i,cx,cy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;words<=0;active<=0;ack1<=0;ack2<=0;
            publish_toggle<=0;means<=0;good<=0;clipped<=0;clip_acc<=0;
            for(i=0;i<36;i=i+1) sums[i]<=0;
            for(i=0;i<9;i=i+1) counts[i]<=0;
        end else begin
            ack1<=ack_async;ack2<=ack1;
            if(user) begin
                x<=0;y<=0;words<=0;active<=1;clip_acc<=0;
                for(i=0;i<36;i=i+1) sums[i]<=0;
                for(i=0;i<9;i=i+1) counts[i]<=0;
            end
            if(valid) begin
                if(last) begin x<=0;y<=py+1'b1;end
                else begin x<=px+4;y<=py;end
                if(active || user) begin
                    words<=user?20'd1:words+1'b1;
                    for(n=0;n<9;n=n+1) begin
                        cx=(n%3==0)?X0:((n%3==1)?X1:X2);
                        cy=(n/3==0)?Y0:((n/3==1)?Y1:Y2);
                        if(px>=cx-HX && px<cx+HX && py>=cy-HY && py<cy+HY) begin
                            counts[n]<=counts[n]+4;
                            if(py[0]) begin
                                sums[n*4+2]<=sums[n*4+2]+ev;
                                sums[n*4+3]<=sums[n*4+3]+od;
                            end else begin
                                sums[n*4]<=sums[n*4]+ev;
                                sums[n*4+1]<=sums[n*4+1]+od;
                            end
                            if(clip_word) clip_acc[n]<=1;
                        end
                    end
                    if(last && py==H-1) begin
                        active<=0;
                        // Bundled-data mailbox: hold ALL data until synchronized ack.
                        if(ack2==publish_toggle) begin
                            for(i=0;i<36;i=i+1) means[i*10+:10]<=sums[i]>>SHIFT;
                            for(i=0;i<9;i=i+1)
                                good[i]<=(counts[i]==4*HX*HY)&&(words==W*H/4-1);
                            clipped<=clip_acc;
                            publish_toggle<=~publish_toggle;
                        end
                    end
                end
            end
        end
    end
endmodule

module color_rgb_probe #(
    parameter integer W=1280,H=720,HX=32,HY=16
)(
    input wire clk,rst_n,de,
    input wire [11:0] x,y,
    input wire [23:0] rgb,
    output reg [215:0] means,
    output reg [8:0] good,clipped,
    output reg ready
);
    localparam integer X0=(W/10/4)*4, X1=W/2, X2=W-X0;
    localparam integer Y0=(H/8/2)*2, Y1=H/2, Y2=H-Y0;
    localparam integer SHIFT=$clog2(4*HX*HY);
    reg [18:0] sums[0:26];
    reg [11:0] counts[0:8];
    reg [8:0] clip_acc;
    reg [20:0] pixels;
    reg active;
    integer n,i,cx,cy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            means<=0;good<=0;clipped<=0;clip_acc<=0;ready<=0;
            pixels<=0;active<=0;
            for(i=0;i<27;i=i+1) sums[i]<=0;
            for(i=0;i<9;i=i+1) counts[i]<=0;
        end else if(de) begin
            if(x==0 && y==0) begin
                pixels<=1;active<=1;clip_acc<=0;
                for(i=0;i<27;i=i+1) sums[i]<=0;
                for(i=0;i<9;i=i+1) counts[i]<=0;
            end else if(active) pixels<=pixels+1'b1;
            if(active) begin
                for(n=0;n<9;n=n+1) begin
                    cx=(n%3==0)?X0:((n%3==1)?X1:X2);
                    cy=(n/3==0)?Y0:((n/3==1)?Y1:Y2);
                    if(x>=cx-HX && x<cx+HX && y>=cy-HY && y<cy+HY) begin
                        counts[n]<=counts[n]+1'b1;
                        sums[n*3]<=sums[n*3]+rgb[23:16];
                        sums[n*3+1]<=sums[n*3+1]+rgb[15:8];
                        sums[n*3+2]<=sums[n*3+2]+rgb[7:0];
                        if(rgb[23:16]>=250 || rgb[15:8]>=250 || rgb[7:0]>=250)
                            clip_acc[n]<=1;
                    end
                end
                if(x==W-1 && y==H-1) begin
                    active<=0;ready<=1;
                    for(i=0;i<27;i=i+1) means[i*8+:8]<=sums[i]>>SHIFT;
                    for(i=0;i<9;i=i+1)
                        good[i]<=(counts[i]==4*HX*HY)&&(pixels==W*H-1);
                    clipped<=clip_acc;
                end
            end
        end
    end
endmodule

// The diagnostic top inserts this ONLY in the display branch, after the ROI tap.
// First five seconds: true RGB=128 gray. Thereafter: camera + measured numbers.
// A snapshot of all displayed stats commits together in vertical blank.
module color_diagnostic_display #(
    parameter integer GRAY_FRAMES=300, UPDATE_FRAMES=16
)(
    input wire clk,rst_n,
    input wire vs,hs,de,protect,
    input wire [11:0] x,y,
    input wire [23:0] rgb,
    input wire [359:0] raw_mailbox,
    input wire [8:0] raw_good_mailbox,raw_clip_mailbox,
    input wire raw_toggle_async,
    output reg raw_ack,
    input wire [215:0] rgb_means,
    input wire [8:0] rgb_good,rgb_clip,
    output reg out_vs,out_hs,out_de,out_protect,
    output reg [23:0] out_rgb
);
    (* async_reg="true" *) reg req1,req2;
    reg vs_d;
    reg [8:0] gray_count;
    reg [7:0] refresh_count;
    reg [359:0] raw_stats;
    reg [8:0] raw_ok,raw_clip;
    reg [215:0] rgb_stats;
    reg [8:0] rgb_ok,rgb_clipped;
    wire gray_mode=(gray_count<GRAY_FRAMES);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            req1<=0;req2<=0;raw_ack<=0;vs_d<=0;gray_count<=0;refresh_count<=0;
            raw_stats<=0;raw_ok<=0;raw_clip<=0;
            rgb_stats<=0;rgb_ok<=0;rgb_clipped<=0;
        end else begin
            req1<=raw_toggle_async;req2<=req1;vs_d<=vs;
            if(vs && !vs_d) begin
                if(gray_count<GRAY_FRAMES) gray_count<=gray_count+1'b1;
                if(refresh_count==UPDATE_FRAMES-1) begin
                    refresh_count<=0;
                    rgb_stats<=rgb_means;rgb_ok<=rgb_good;rgb_clipped<=rgb_clip;
                    if(req2!=raw_ack) begin
                        raw_stats<=raw_mailbox;raw_ok<=raw_good_mailbox;raw_clip<=raw_clip_mailbox;
                        raw_ack<=req2;
                    end
                end else refresh_count<=refresh_count+1'b1;
            end
        end
    end
    function [7:0] hexchar;
        input [3:0] h;
        begin hexchar=(h<10)?8'd48+h:8'd65+h-10;end
    endfunction
    function [34:0] glyph;
        input [7:0] c;
        begin
            case(c)
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":glyph=35'b01110_10001_10000_10000_10000_10001_01110;
                "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
                "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
                ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
                default:glyph=0;
            endcase
        end
    endfunction
    // Four stages: select row, decode character, select font, draw pixel.
    // Fixed slices/cases avoid variable divides and wide index multipliers.
    reg [39:0] row_raw;
    reg [23:0] row_rgb;
    reg [3:0] row_q,row_node;
    integer k,cx,cy;
    reg rect;
    always @* begin
        row_raw=0;row_rgb=0;row_q=0;row_node=0;
        case(y[7:4])
            4'd2: begin row_raw=raw_stats[0+:40];row_rgb=rgb_stats[0+:24];row_q={raw_ok[0],raw_clip[0],rgb_ok[0],rgb_clipped[0]};row_node=4'd0;end
            4'd3: begin row_raw=raw_stats[40+:40];row_rgb=rgb_stats[24+:24];row_q={raw_ok[1],raw_clip[1],rgb_ok[1],rgb_clipped[1]};row_node=4'd1;end
            4'd4: begin row_raw=raw_stats[80+:40];row_rgb=rgb_stats[48+:24];row_q={raw_ok[2],raw_clip[2],rgb_ok[2],rgb_clipped[2]};row_node=4'd2;end
            4'd5: begin row_raw=raw_stats[120+:40];row_rgb=rgb_stats[72+:24];row_q={raw_ok[3],raw_clip[3],rgb_ok[3],rgb_clipped[3]};row_node=4'd3;end
            4'd6: begin row_raw=raw_stats[160+:40];row_rgb=rgb_stats[96+:24];row_q={raw_ok[4],raw_clip[4],rgb_ok[4],rgb_clipped[4]};row_node=4'd4;end
            4'd7: begin row_raw=raw_stats[200+:40];row_rgb=rgb_stats[120+:24];row_q={raw_ok[5],raw_clip[5],rgb_ok[5],rgb_clipped[5]};row_node=4'd5;end
            4'd8: begin row_raw=raw_stats[240+:40];row_rgb=rgb_stats[144+:24];row_q={raw_ok[6],raw_clip[6],rgb_ok[6],rgb_clipped[6]};row_node=4'd6;end
            4'd9: begin row_raw=raw_stats[280+:40];row_rgb=rgb_stats[168+:24];row_q={raw_ok[7],raw_clip[7],rgb_ok[7],rgb_clipped[7]};row_node=4'd7;end
            4'd10: begin row_raw=raw_stats[320+:40];row_rgb=rgb_stats[192+:24];row_q={raw_ok[8],raw_clip[8],rgb_ok[8],rgb_clipped[8]};row_node=4'd8;end
        endcase
        rect=0;
        for(k=0;k<9;k=k+1) begin
            cx=(k%3==0)?128:((k%3==1)?640:1152);
            cy=(k/3==0)?90:((k/3==1)?360:630);
            if(((x==cx-32 || x==cx+31) && y>=cy-16 && y<cy+16) ||
               ((y==cy-16 || y==cy+15) && x>=cx-32 && x<cx+32)) rect=1;
        end
    end
    reg [39:0] a_raw;
    reg [23:0] a_rgb;
    reg [3:0] a_q,a_node;
    reg [5:0] a_col,a_pos;
    reg [23:0] a_camera;
    reg a_vs,a_hs,a_de,a_protect,a_panel,a_rect,a_gray,a_draw,a_header;
    reg [7:0] character;
    always @* begin
        character=" ";
        if(a_header) begin
            case(a_col)
                0:character="N";2:character="R";3:character="A";4:character="W";
                6:character="B";10:character="G";11:character="B";
                14:character="G";15:character="R";18:character="R";
                23:character="R";24:character="G";25:character="B";
                28:character="R";31:character="G";34:character="B";
                38:character="Q";40:character="O";41:character="C";
                42:character="O";43:character="C";
            endcase
        end else begin
            case(a_col)
                0:character=hexchar(a_node);
                6:character=hexchar({2'b0,a_raw[9:8]});
                7:character=hexchar(a_raw[7:4]);
                8:character=hexchar(a_raw[3:0]);
                10:character=hexchar({2'b0,a_raw[19:18]});
                11:character=hexchar(a_raw[17:14]);
                12:character=hexchar(a_raw[13:10]);
                14:character=hexchar({2'b0,a_raw[29:28]});
                15:character=hexchar(a_raw[27:24]);
                16:character=hexchar(a_raw[23:20]);
                18:character=hexchar({2'b0,a_raw[39:38]});
                19:character=hexchar(a_raw[37:34]);
                20:character=hexchar(a_raw[33:30]);
                28:character=hexchar(a_rgb[7:4]);
                29:character=hexchar(a_rgb[3:0]);
                31:character=hexchar(a_rgb[15:12]);
                32:character=hexchar(a_rgb[11:8]);
                34:character=hexchar(a_rgb[23:20]);
                35:character=hexchar(a_rgb[19:16]);
                40:character=a_q[3]?"1":"0";
                41:character=a_q[2]?"1":"0";
                42:character=a_q[1]?"1":"0";
                43:character=a_q[0]?"1":"0";
            endcase
        end
    end
    reg b_vs,b_hs,b_de,b_protect,b_panel,b_rect,b_gray,b_draw;
    reg [23:0] b_rgb;
    reg [7:0] b_char;
    reg [5:0] b_pos;
    reg c_vs,c_hs,c_de,c_protect,c_panel,c_rect,c_gray,c_draw;
    reg [23:0] c_rgb;
    reg [34:0] c_glyph;
    reg [5:0] c_pos;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            a_vs<=0;a_hs<=0;a_de<=0;a_protect<=0;a_panel<=0;a_rect<=0;a_gray<=0;
            a_draw<=0;a_header<=0;a_raw<=0;a_rgb<=0;a_q<=0;a_node<=0;
            a_col<=0;a_pos<=0;a_camera<=0;
            b_vs<=0;b_hs<=0;b_de<=0;b_protect<=0;b_panel<=0;b_rect<=0;
            b_gray<=0;b_draw<=0;b_rgb<=0;b_char<=0;b_pos<=0;
            c_vs<=0;c_hs<=0;c_de<=0;c_protect<=0;c_panel<=0;c_rect<=0;
            c_gray<=0;c_draw<=0;c_rgb<=0;c_glyph<=0;c_pos<=0;
            out_vs<=0;out_hs<=0;out_de<=0;out_protect<=0;out_rgb<=0;
        end else begin
            a_vs<=vs;a_hs<=hs;a_de<=de;a_protect<=protect;a_camera<=rgb;
            a_panel<=(x>=16 && x<736 && y>=16 && y<176);
            a_header<=(y[7:4]==1);a_rect<=rect;a_gray<=gray_mode;
            a_raw<=row_raw;a_rgb<=row_rgb;a_q<=row_q;a_node<=row_node;
            a_col<=x[9:4]-1'b1;
            a_pos<=6'd34-{3'b0,y[3:1]}*6'd5-{3'b0,x[3:1]};
            a_draw<=(x[3:1]<5 && y[3:1]<7);
            b_vs<=a_vs;b_hs<=a_hs;b_de<=a_de;b_protect<=a_protect;b_rgb<=a_camera;
            b_panel<=a_panel;b_rect<=a_rect;b_gray<=a_gray;b_draw<=a_draw;
            b_char<=character;b_pos<=a_pos;
            c_vs<=b_vs;c_hs<=b_hs;c_de<=b_de;c_protect<=b_protect;c_rgb<=b_rgb;
            c_panel<=b_panel;c_rect<=b_rect;c_gray<=b_gray;c_draw<=b_draw;
            c_glyph<=glyph(b_char);c_pos<=b_pos;
            out_vs<=c_vs;out_hs<=c_hs;out_de<=c_de;
            out_protect<=c_protect||c_panel||c_rect||c_gray;
            if(!c_de) out_rgb<=0;
            else if(c_gray) out_rgb<=24'h808080;
            else if(c_panel) out_rgb<=(c_draw && c_glyph[c_pos])?24'hffffff:24'h000000;
            else if(c_rect) out_rgb<=24'hffffff;
            else out_rgb<=c_rgb;
        end
    end
endmodule

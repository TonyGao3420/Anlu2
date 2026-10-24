// One corrected camera stream feeds both ROI and display.
// Raster coordinates are reconstructed from VS/DE, independent of mixer's
// one-pixel SOF coordinate convention. Never modifies DDR request timing.
// Camera RGB is registered alongside mixer RGB, before OSD composition.
module scene_color_stream #(
    parameter integer W=1280,H=720,RGB_SHADING_ENABLE=1
)(
    input wire clk,rst_n,in_vs,in_hs,in_de,in_protect,
    input wire [23:0] camera_rgb,mixed_rgb,
    output wire out_vs,out_hs,out_de,out_protect,
    output wire [23:0] display_rgb,roi_rgb,
    output wire roi_de,roi_sof,roi_last
);
    reg vs_d,armed;
    reg [11:0] x,y;
    reg [7:0] protect_pipe,armed_pipe,sof_pipe,last_pipe;
    reg [23:0] mixed_pipe[0:7];
    wire [23:0] corrected;
    wire corrected_de;
    assign out_de=corrected_de;
    assign out_protect=protect_pipe[7];
    assign display_rgb=!corrected_de?24'd0:
                       (protect_pipe[7]?mixed_pipe[7]:corrected);
    assign roi_rgb=corrected;
    assign roi_de=corrected_de && armed_pipe[7];
    assign roi_sof=sof_pipe[7];
    assign roi_last=last_pipe[7];
    display_color_shading #(.ENABLE(RGB_SHADING_ENABLE)) corrector(
        .clk(clk),.rst_n(rst_n),.in_vs(in_vs),.in_hs(in_hs),.in_de(in_de),
        .in_protect(1'b0),.x(x),.y(y),.in_rgb(camera_rgb),
        .out_vs(out_vs),.out_hs(out_hs),.out_de(corrected_de),
        .out_protect(),.out_rgb(corrected)
    );
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;armed<=0;x<=0;y<=0;
            protect_pipe<=0;armed_pipe<=0;sof_pipe<=0;last_pipe<=0;
            for(i=0;i<8;i=i+1) mixed_pipe[i]<=0;
        end else begin
            vs_d<=in_vs;
            // VS begins in vertical blank; all active pixels follow it.
            if(in_vs && !vs_d) begin x<=0;y<=0;armed<=1;end
            else if(in_de && armed) begin
                if(x==W-1) begin x<=0;y<=(y==H-1)?12'd0:y+1'b1;end
                else x<=x+1'b1;
            end
            protect_pipe<={protect_pipe[6:0],in_protect};
            armed_pipe<={armed_pipe[6:0],armed};
            sof_pipe<={sof_pipe[6:0],in_de && armed && x==0 && y==0};
            last_pipe<={last_pipe[6:0],in_de && armed && x==W-1};
            mixed_pipe[0]<=mixed_rgb;
            for(i=1;i<8;i=i+1) mixed_pipe[i]<=mixed_pipe[i-1];
        end
    end
endmodule

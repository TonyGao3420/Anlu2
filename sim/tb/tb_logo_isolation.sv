`timescale 1ns/1ps
module tb_logo_isolation;
reg clk=0;always #5 clk=~clk;reg rst=0,vs=0,hs=0,de=0,user=0,last=0;
wire [1:0] mv,mh,md,mp,ev,eh,ed,ep,rd,rs,rl;
wire [23:0] m[0:1],rgb[0:1],roi[0:1],out[0:1];wire [11:0] mx[0:1],my[0:1];
reg [24:0] ref_logo[0:25599];initial $readmemh("../build/edge_refine_20261010/logo_reference.hex",ref_logo);
genvar k;
generate for(k=0;k<2;k=k+1)begin: branch
 hdmi_mixer #(.OSD_ENABLE(k)) mixer(.I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),
 .I_target_bbox_valid(1'b0),.I_target_bbox_x0(16'd0),.I_target_bbox_y0(16'd0),.I_target_bbox_x1(16'd0),.I_target_bbox_y1(16'd0),
 .O_video_rd_en(),.I_video_rd_data(24'ha0a0a0),.O_hdmi_vsync(mv[k]),.O_hdmi_hsync(mh[k]),.O_hdmi_de(md[k]),.O_hdmi_protect(mp[k]),.O_hdmi_data(m[k]),.O_hdmi_x(mx[k]),.O_hdmi_y(my[k]));
 scene_color_stream #(.RGB_SHADING_ENABLE(0)) stream(.clk(clk),.rst_n(rst),.in_vs(mv[k]),.in_hs(mh[k]),.in_de(md[k]),.in_protect(mp[k]),.camera_rgb(24'ha0a0a0),.mixed_rgb(m[k]),
 .out_vs(),.out_hs(),.out_de(),.out_protect(),.display_rgb(rgb[k]),.roi_rgb(roi[k]),.roi_de(rd[k]),.roi_sof(rs[k]),.roi_last(rl[k]));
 // Use this branch's exact matched control latency from scene_color_stream.
 wire sv,sh,sd,sp;
 assign sv=branch[k].stream.out_vs;assign sh=branch[k].stream.out_hs;assign sd=branch[k].stream.out_de;assign sp=branch[k].stream.out_protect;
 display_edge_color edge_stage(clk,rst,sv,sh,sd,sp,rgb[k],ev[k],eh[k],ed[k],ep[k],out[k]);
end endgenerate
integer pixels=0,logos=0,outside=0,transparent=0,postchecks=0,i;reg expected_mask;reg [24:0] logo;
reg [13:0] protected_pipeline=0;
always @(posedge clk)begin
 if(!rst)protected_pipeline=0;
 else begin
 protected_pipeline={protected_pipeline[12:0],mp[1]};
 #1;
 if({mv[0],mh[0],md[0]}!=={mv[1],mh[1],md[1]})$fatal(1,"OSD changed raster timing");
 if(md[1])begin
 pixels=pixels+1;
 if(mx[1]<160 && my[1]<160)begin
 logo=ref_logo[my[1]*160+mx[1]];expected_mask=logo[24];
 if(mp[1]!==expected_mask)$fatal(1,"Logo alpha/protect mismatch at %0d,%0d",mx[1],my[1]);
 if(expected_mask)begin
 if(m[1]!==logo[23:0])$fatal(1,"Logo pixel mismatch");logos=logos+1;
 end else begin if(m[1]!==m[0])$fatal(1,"Transparent logo pixel tinted camera");transparent=transparent+1;end
 end else if(!(mx[1]>=375 && mx[1]<575 && my[1]>=120 && my[1]<144))begin
 if(mp[1]!==0 || m[1]!==m[0])$fatal(1,"Logo/text escaped its region at %0d,%0d",mx[1],my[1]);outside=outside+1;
 end
 end
 if({rd[0],rs[0],rl[0],roi[0]}!=={rd[1],rs[1],rl[1],roi[1]})$fatal(1,"Logo affected ROI camera stream");
 if(ed[1])begin
 if(ed[0]!==1 || ep[1]!==protected_pipeline[13])$fatal(1,"Post-display alpha alignment error");
 if(!ep[1] && out[0]!==out[1])$fatal(1,"Logo caused surrounding displayed RGB contamination");
 postchecks=postchecks+1;
 end
 end
end
integer x,y;
initial begin
 repeat(6)@(negedge clk);rst=1;vs=1;repeat(8)@(negedge clk);vs=0;repeat(20)@(negedge clk);
 for(y=0;y<720;y=y+1)begin
 for(x=0;x<1280;x=x+1)begin @(negedge clk);de=1;user=(x==0&&y==0);last=(x==1279);end
 @(negedge clk);de=0;user=0;last=0;hs=1;repeat(20)@(negedge clk);hs=0;repeat(4)@(negedge clk);
 end
 repeat(40)@(negedge clk);
 if(pixels!=921600 || postchecks!=921600 || logos!=6387 || transparent<19000 || outside<890000)$fatal(1,"Logo isolation coverage failed %0d/%0d/%0d/%0d/%0d",pixels,postchecks,logos,transparent,outside);
 $display("PASS logo_isolation: actual mixer on/off, 6387 alpha pixels, %0d transparent pixels, %0d surrounding pixels, full 720p ROI and displayed camera identical outside OSD",transparent,outside);$finish;
end
initial begin #12000000;$fatal(1,"Logo isolation timeout");end
endmodule

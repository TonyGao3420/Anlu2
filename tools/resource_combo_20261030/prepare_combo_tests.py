from pathlib import Path
r=Path(__file__).resolve().parents[2];tag='resource_combo_20261030';tb=r/'sim/tb'/tag
s=(tb/'tb_equivalence.sv').read_text(encoding='utf-8-sig')
s=s.replace('N=6','N=7').replace('PASS resource_equivalence: 5529600','PASS combo_integration: 6451200')
s=s.replace('if(nrgb!==brgb)$fatal(1,"All-mode RGB differs");','if(!(dut.u_multi_overlay.mode && dut.S_style_enable) && nrgb!==brgb)$fatal(1,"Original independent mode RGB differs");')
s=s.replace('if(dut.S_style_enable)$fatal(1,"Fourth mode still stylized");','if(dut.S_style_enable && !dut.u_multi_overlay.style_mode)$fatal(1,"Combined mode HUD missing");')
s=s.replace('multiple!=W*H || styleframes!=2','multiple!=2*W*H || styleframes!=3')
s=s.replace('latest calibrated four-mode RGB exact at original latency','latest calibration/ROI/PWM/read requests preserved; independent modes exact; multi-only and combined style both entered')
s=s.replace('if(input_frame==3 && vtc.vcnt==40 && vtc.hcnt==200)sw3=0;', 'if(input_frame==3 && vtc.vcnt==40 && vtc.hcnt==200)sw2=0;')
s=s.replace('if(input_frame==4 && vtc.vcnt==40 && vtc.hcnt==200)begin sw2=0;sw1=0;end', 'if(input_frame==4 && vtc.vcnt==40 && vtc.hcnt==200)begin sw3=0;sw2=1;end\n  if(input_frame==5 && vtc.vcnt==40 && vtc.hcnt==200)begin sw2=0;sw1=0;end')
s=s.replace('integer f,l,x,j,fx,fy;', 'integer f,l,x,j,fx,fy,t;reg inside_any;integer combo_pixels=0,gray_samples=0;')
s=s.replace('checked=checked+1;', '''if(dut.u_multi_overlay.mode && dut.S_style_enable)begin
     combo_pixels=combo_pixels+1;inside_any=0;
     for(t=0;t<8;t=t+1)if(dut.S_multi_valid[t] && ox>=dut.S_multi_x0[t*12+:12] && ox<=dut.S_multi_x1[t*12+:12] && oy>=dut.S_multi_y0[t*12+:12] && oy<=dut.S_multi_y1[t*12+:12])inside_any=1;
     if(inside_any && nrgb!==brgb)$fatal(1,"Combined ROI original color lost x%0d y%0d %h %h",ox,oy,nrgb,brgb);
     if(ox==950 && oy==650)begin if(nrgb[23:16]!==nrgb[15:8] || nrgb[7:0]!==nrgb[15:8] || nrgb==0)$fatal(1,"Combined background not bright grayscale");gray_samples=gray_samples+1;end
    end
    checked=checked+1;''')
s=s.replace('if(ordinary!=5*W*H', 'if(combo_pixels!=W*H || gray_samples!=1)$fatal(1,"Combination coverage missing");\n     if(ordinary!=5*W*H')
(tb/'tb_combo.sv').write_text(s, encoding='utf-8')
c=(r/'sim/run_resource_equivalence/run.do').read_text(encoding='utf-8-sig').replace('tb_equivalence.sv','tb_combo.sv')
d=r/'sim/run_resource_combo';d.mkdir(exist_ok=True);(d/'run.do').write_text(c, encoding='utf-8')
d=r/'sim/run_resource_mask';d.mkdir(exist_ok=True)
(d/'run.do').write_text('onerror {quit -code 1 -f}\nvlib work\nvmap work work\nvlog -sv ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/resource_combo_20261030/tb_mask.sv\nvsim -c work.tb_mask\nrun -all\nquit -f\n', encoding='utf-8')
print('Prepared combination-mode full-display and eight-ROI mask tests')
c=(r/'sim/reference/resource_combo_20261030/coldboot_template.sv').read_text(encoding='utf-8-sig')
c=c.replace("camera,1'b0,1'b0,1'b1", "camera,1'b0,1'b1,1'b1")
c=c.replace('|| dut.S_style_enable)', '|| !dut.S_style_enable)')
c=c.replace('PASS spatial_coldboot:', 'PASS combo_coldboot:')
c=c.replace('SW2 always low','SW2 high with SW3').replace('direct multi before any ROI result','direct multi+style before any ROI result')
c=c.replace('SW2 is LOW throughout','SW2 is HIGH throughout').replace('with SW2 low','with SW2 high')
(tb/'tb_combo_coldboot.sv').write_text(c, encoding='utf-8')
common=(r/'sim/run_resource_equivalence/run.do').read_text(encoding='utf-8-sig').replace('tb_equivalence.sv','tb_combo_coldboot.sv').replace('work.tb_four_modes_vtc','work.tb_sw3_coldboot')
d=r/'sim/run_resource_coldboot';d.mkdir(exist_ok=True);(d/'run.do').write_text(common, encoding='utf-8')
d=r/'sim/run_resource_overlay';d.mkdir(exist_ok=True)
(d/'run.do').write_text('onerror {quit -code 1 -f}\nvlib work\nvmap work work\nvlog -sv ../../user_source/hdl_source/hdmi_mixer.v ../tb/resource_combo_20261030/tb_overlay.sv\nvsim -c work.tb_overlay\nrun -all\nquit -f\n',encoding='utf-8')

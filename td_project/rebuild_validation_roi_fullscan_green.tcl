set root {D:/HX1P35A_Contest_202606/Anlu2}
set out [file join $root sim build td_validation_roi_fullscan_green]
file mkdir $out
cd $out
if {![file exists [file join $out video_check.al]]} {
    create_project video_check $out -family PH1 -device PH1P35MDG324 -speed -3
}
open_project {D:/HX1P35A_Contest_202606/Anlu2/sim/build/td_validation_roi_fullscan_green/video_check.al}
import_device ph1_35p.db -package PH1P35MDG324
top_module design_top_wrapper
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/design_top_wrapper.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/video_in.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/video_out.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mc_to_user_interface.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/signal_delay.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/awb.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/csi_unpacket_2lane.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/isp_top.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/raw10_unpacket_2lane.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/uial2axis.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/demosaic.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/data128_96/data128_96.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/data96_128/data96_128.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uics520_cfg/SC520GainTbl.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uics520_cfg/uicfgcs520.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uics520_cfg/uics520reg_720p60.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uics520_cfg/uics520regAE.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uics500_cfg/uii2c.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/uiisp_beta/ae_set.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/vtc/uivtc.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/osd_char_lib.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/anlogic_logo_rom.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/hdmi_mixer.v}
  add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/track2/roi_target_tracker.v}
  add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/track2/red_mask_contour.v}
  add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/track2/visual_servo_pwm.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/video/video_enhance.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/audio_arc_calculate.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/I2S_receiver.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/key_remove_shakes.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/hdmi_phy_warpper.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/lane_lvds_10_1.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/hdmi_tx.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/mipi_dphy_rx_ph1p_mipiio_wrapper.sv}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/byte_aligner.enc.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/byte_aligner_wrapper.enc.sv}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/channel_aligner.enc.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/channel_aligner_wrapper.enc.sv}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/mipi_dphy_rx/hs_detect.enc.v}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/constraints_source/pin.adc}
add_files {D:/HX1P35A_Contest_202606/Anlu2/td_project/camera_to_dsi_display.sdc}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/ip_source/PLL/PLL.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/ip_source/w128_d512_fifo/w128_d512_fifo.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/ip_source/w155_d512_fifo/w155_d512_fifo.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/ip_source/divider/divider.ipc}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.xml}
add_files {D:/HX1P35A_Contest_202606/Anlu2/user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.xml}
launch_runs -step gate syn_1
wait_run syn_1
launch_runs -step route phy_1
wait_run phy_1
close_project
exit


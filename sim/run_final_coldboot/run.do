onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../models/spatial_bias_20261028/logo.v ../reference/spatial_bias_20261028/three_mode_tracker.v ../../user_source/hdl_source/video/style_switch_control.v ../../user_source/hdl_source/video/roi_motion_trail.v ../../user_source/hdl_source/video/roi_background_stylize.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../../user_source/hdl_source/track2/roi_target_tracker.v ../../user_source/hdl_source/track2/visual_servo_pwm.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/vtc/uivtc.v ../models/spatial_bias_20261028/display_paths.v ../tb/spatial_bias_20261028/tb_final_coldboot.sv
vsim -c work.tb_sw3_coldboot
run -all
quit -f

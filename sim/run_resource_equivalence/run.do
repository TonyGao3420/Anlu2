onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../models/resource_combo_20261030/rom.v ../reference/resource_combo_20261030/shading_before.v ../reference/resource_combo_20261030/scene_before.v ../../user_source/hdl_source/video/style_switch_control.v ../../user_source/hdl_source/video/roi_motion_trail.v ../../user_source/hdl_source/video/roi_background_stylize.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../../user_source/hdl_source/track2/roi_target_tracker.v ../../user_source/hdl_source/track2/visual_servo_pwm.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/vtc/uivtc.v ../models/resource_combo_20261030/display_paths.v ../tb/resource_combo_20261030/tb_equivalence.sv
vsim -c work.tb_four_modes_vtc
run -all
quit -f

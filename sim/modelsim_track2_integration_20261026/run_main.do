onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/track2_20261026/logo_rom_model.v ../models/track2_20261026/baseline_style.v ../../user_source/hdl_source/video/style_switch_control.v ../../user_source/hdl_source/video/roi_motion_trail.v ../../user_source/hdl_source/video/roi_background_stylize.v ../../user_source/hdl_source/track2/roi_target_tracker.v ../../user_source/hdl_source/track2/visual_servo_pwm.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../models/track2_20261026/display_paths.v ../tb/tb_main_track2_20261026.sv
vsim -c work.tb_main_track2
run -all
quit -f

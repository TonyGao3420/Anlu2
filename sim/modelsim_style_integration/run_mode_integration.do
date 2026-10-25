onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/style_switch_control.v ../../user_source/hdl_source/video/roi_motion_trail.v ../../user_source/hdl_source/video/roi_background_stylize.v ../../user_source/hdl_source/track2/roi_target_tracker.v ../../user_source/hdl_source/track2/visual_servo_pwm.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/hdmi_mixer.v ../models/style_mode/logo_rom_fast.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/style_mode/extracted_display_paths.v ../tb/style_mode/tb_mode_integration.sv
vsim -c work.tb_style_integration
run -all
quit -f

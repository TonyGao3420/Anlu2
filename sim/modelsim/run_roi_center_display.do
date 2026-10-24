transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/hdmi_mixer.v ../build/roi_origin_center_20261011/hdmi_mixer_baseline.v ../../user_source/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/osd_char_lib.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/tb_roi_center_display.sv
vsim -c work.tb_roi_center_display
run -all
quit -f

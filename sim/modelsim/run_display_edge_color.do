transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/video_enhance.v ../../user_source/hdl_source/video/display_common_tone.v ../tb/tb_display_edge_color.sv
vsim -c work.tb_display_edge_color
run -all
quit -f

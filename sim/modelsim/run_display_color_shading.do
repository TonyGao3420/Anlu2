transcript file ../build/shared_color_roi_20261009/run_display_color_shading.log
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/video_enhance.v ../tb/tb_display_color_shading.sv
vsim -c work.tb_display_color_shading
run -all
quit -f

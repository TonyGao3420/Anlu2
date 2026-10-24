transcript file ../build/shared_color_roi_20261009/run_shared_color_roi.log
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../../user_source/hdl_source/track2/roi_target_tracker.v ../tb/tb_shared_color_roi.sv
vsim -c work.tb_shared_color_roi
run -all
quit -f

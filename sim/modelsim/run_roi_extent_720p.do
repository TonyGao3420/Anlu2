transcript file roi_extent_720p.log
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/track2/roi_target_tracker.v ../tb/tb_roi_extent_720p.sv
vsim -c work.tb_roi_extent_720p
run -all
quit -f

transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/track2/roi_target_tracker.v ../tb/tb_roi_target_tracker.sv
vsim -c work.tb_roi_target_tracker
run -all
quit -f

onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/track2/roi_target_tracker.v ../reference/spatial_bias_20261028/three_mode_tracker.v ../tb/spatial_bias_20261028/tb_final_multi_tracker.sv
vsim -c work.tb_multi_tracker
run -all
quit -f

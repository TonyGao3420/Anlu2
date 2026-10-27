onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/track2/roi_target_tracker.v ../tb/final_four_modes_20261028/tb_final_multi_slots.sv
vsim -c work.tb_multi_slots
run -all
quit -f

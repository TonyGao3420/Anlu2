onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../tb/multi_trail_20261030/tb_budget.sv
vsim -c work.tb_multi_trail_budget
run -all
quit -f

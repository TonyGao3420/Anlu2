onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../reference/multi_trail_20261030/trail_reference.v ../tb/multi_trail_20261030/tb_multi_trail.sv
vsim -c work.tb_multi_trail
run -all
quit -f

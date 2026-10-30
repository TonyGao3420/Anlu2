onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/resource_combo_20261030/tb_mask.sv
vsim -c work.tb_mask
run -all
quit -f

onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../models/resource_combo_20261030/awb_test_models.v ../reference/resource_combo_20261030/awb_before.v ../../user_source/hdl_source/awb_frame_stable.v ../tb/resource_combo_20261030/tb_awb_frame.sv
vsim -c work.tb_awb_frame
run -all
quit -f


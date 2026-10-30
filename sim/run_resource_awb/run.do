onerror {quit -code 1 -f}
vlib work
vmap work work
vlog ../models/resource_combo_20261030/divider_vendor/al_map_basic.v ../models/resource_combo_20261030/divider_vendor/al_map_seq.v ../models/resource_combo_20261030/divider_vendor/al_map_lut.v ../models/resource_combo_20261030/divider_vendor/al_map_adder.v
vlog ../models/resource_combo_20261030/divider_vendor/al_phy_glbl.v
vlog -sv ../../user_source/ip_source/divider/divider_gate.v ../../user_source/hdl_source/awb_frame_stable.v ../tb/resource_combo_20261030/tb_awb_divider.sv
vsim -c work.tb_awb_divider work.glbl
run -all
quit -f


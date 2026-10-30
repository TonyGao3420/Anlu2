onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../models/resource_combo_20261030/rom.v ../reference/resource_combo_20261030/shading_before.v ../../../resource_trials/Anlu2_gain9_20261030/user_source/hdl_source/video/display_color_shading.v ../tb/resource_combo_20261030/tb_color.sv
vsim -c work.tb_color
run -all
quit -f


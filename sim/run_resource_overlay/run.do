onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/hdmi_mixer.v ../tb/resource_combo_20261030/tb_overlay.sv
vsim -c work.tb_overlay
run -all
quit -f

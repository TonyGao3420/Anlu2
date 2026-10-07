transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/awb.v ../../user_source/hdl_source/signal_delay.v ../tb/tb_awb_unit_gain.sv
vsim -c work.tb_awb_unit_gain
run -all
quit -f

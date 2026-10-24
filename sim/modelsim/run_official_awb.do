transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/awb.v ../../user_source/hdl_source/signal_delay.v ../tb/official_awb_models.sv ../tb/tb_official_awb.sv
vsim -c work.tb_official_awb
run -all
quit -f

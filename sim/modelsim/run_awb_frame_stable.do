transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/awb_frame_stable.v ../../user_source/hdl_source/signal_delay.v ../tb/official_awb_models.sv ../tb/tb_awb_frame_stable.sv
vsim -c work.tb_awb_frame_stable
run -all
quit -f

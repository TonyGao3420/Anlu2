transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/isp/raw_measured_shading.v ../tb/tb_raw_measured_shading.sv
vsim -c work.tb_raw_measured_shading
run -all
quit -f

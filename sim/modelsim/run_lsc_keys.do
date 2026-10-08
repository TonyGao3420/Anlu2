transcript file lsc_keys.log
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/isp/raw_color_shading.v ../tb/tb_lsc_keys.sv
vsim -c work.tb_lsc_keys
run -all
quit -f

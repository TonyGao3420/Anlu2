onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/style_switch_control.v ../tb/style_mode/tb_style_switch.sv
vsim -c work.tb_style_switch
run -all
quit -f

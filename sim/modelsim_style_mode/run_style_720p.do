onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/style_mode/tb_style_reference.sv
vsim -c work.tb_style_720p
run -all
quit -f

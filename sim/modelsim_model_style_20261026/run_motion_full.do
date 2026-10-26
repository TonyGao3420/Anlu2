onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_model_style_20261026.sv
vsim -c work.tb_motion_style_full
run -all
quit -f

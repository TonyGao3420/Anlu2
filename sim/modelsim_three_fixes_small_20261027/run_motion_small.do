onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/three_fixes_20261027/baseline_style.v ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_three_fixes_style_20261027.sv
vsim -c work.tb_motion_style
run -all
quit -f

onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/roi_original_20261027/before_roi.v ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_roi_original_20261027.sv
vsim -c work.tb_roi_original_small
run -all
quit -f

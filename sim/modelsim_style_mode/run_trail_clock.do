onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../tb/style_mode/tb_trail_reference.sv
vsim -c work.tb_trail_clock
run -all
quit -f

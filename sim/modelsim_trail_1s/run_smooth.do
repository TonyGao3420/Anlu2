onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_motion_trail.v ../tb/trail_1s/tb_smooth_trail.sv
vsim -c work.tb_smooth_trail
run -all
quit -f

onerror {quit -code 1 -f}
if {[file exists orient_work/_info]} { vdel -lib orient_work -all }
vlib orient_work
vmap orient_work orient_work
vlog -work orient_work -sv ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/track2/visual_servo_pwm.v ../tb/tb_orientation_preserve_20261027.sv
vsim -c orient_work.tb_orientation_preserve
run -all
quit -f

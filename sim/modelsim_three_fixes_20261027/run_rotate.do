onerror {quit -code 1 -f}
if {[file exists rotate_work/_info]} { vdel -lib rotate_work -all }
vlib rotate_work
vmap rotate_work rotate_work
vlog -work rotate_work -sv ../../user_source/hdl_source/video_out.v ../tb/tb_rotate180_20261027.sv
vsim -c rotate_work.tb_rotate180
run -all
quit -f

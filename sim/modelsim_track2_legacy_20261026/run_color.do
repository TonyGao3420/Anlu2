onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/video_enhance.v ../tb/tb_video_color_path.sv
vsim -c work.tb_video_color_path
run -all
quit -f

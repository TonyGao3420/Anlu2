transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../diagnostic/color_diagnostic.v ../../user_source/hdl_source/video/video_enhance.v ../tb/tb_color_diagnostic_render.sv
vsim -c work.tb_color_diagnostic_render
run -all
quit -f

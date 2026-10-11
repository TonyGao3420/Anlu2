transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/osd_char_lib.v ../tb/tb_roi_center_osd.sv
vsim -c work.tb_roi_center_osd
run -all
quit -f

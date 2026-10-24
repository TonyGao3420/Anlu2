transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v ../tb/tb_bilinear_color.sv
vsim -c work.tb_bilinear_color
run -all
quit -f

transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../diagnostic/color_diagnostic.v ../tb/tb_color_diagnostic.sv
vsim -c work.tb_color_diagnostic
run -all
quit -f

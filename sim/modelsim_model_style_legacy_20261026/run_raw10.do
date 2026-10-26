onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/isp/raw10_unpacket_2lane.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v ../tb/tb_raw10.sv
vsim -c work.tb_raw10
run -all
quit -f

set PrefMain(saveLines) 100000
if {[file exists work_v2]} { vdel -all -lib work_v2 }
vlib work_v2
vlog -work work_v2 ../src/camera/csi2_rx_unpack.v
vlog -work work_v2 ../sim/tb/tb_csi2_rx_unpack2.v
vsim -c work_v2.tb_csi2_rx_unpack2
run -all
quit -code 0

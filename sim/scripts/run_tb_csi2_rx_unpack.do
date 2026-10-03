# CSI-2 解包自检测试运行脚本
set PrefMain(saveLines) 100000
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog -work work ../src/camera/csi2_rx_unpack.v
vlog -work work ../sim/tb/tb_csi2_rx_unpack.v
vsim -c tb_csi2_rx_unpack
run -all
quit -code 0

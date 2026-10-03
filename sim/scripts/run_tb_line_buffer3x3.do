# =============================================================================
# 文件名 : run_tb_line_buffer3x3.do
# 功能   : 编译并运行 line_buffer3x3 的自检测试平台。
#          在 sim/ 目录下执行： vsim -c -do scripts/run_tb_line_buffer3x3.do
# =============================================================================

set PrefMain(saveLines) 100000
onerror {quit -code 1}

if {[file exists work]} { vdel -all -lib work }
vlib work

vlog -work work ../src/isp/line_buffer3x3.v
vlog -work work ../sim/tb/tb_line_buffer3x3.v

vsim -c tb_line_buffer3x3
run -all
quit -code 0

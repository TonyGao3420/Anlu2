# =============================================================================
# 文件名 : compile_all.do
# 功能   : 用 ModelSim 编译全部 RTL 与 Testbench，只做语法/综合前检查。
#          在 sim/ 目录下执行： vsim -c -do scripts/compile_all.do
# 说明   : 相对路径以启动 vsim 时的当前目录为基准，因此请在 sim/ 下运行。
#          加密文件（.enc.v/.enc.sv）在 ModelSim 下可能无法编译，
#          若报错请改用 scripts/compile_rtl.do（只编译可仿真的 RTL）。
# =============================================================================

set PrefMain(saveLines) 100000
onerror {quit -code 1}

if {[file exists work]} { vdel -all -lib work }
vlib work

# ---------------- 公共模块 ----------------
vlog -work work ../src/common/sync_ff.v
vlog -work work ../src/common/debounce.v
vlog -work work ../src/common/clk_rst_gen.v
vlog -work work ../src/common/async_fifo.v

# ---------------- 图像采集（摄像头侧） ----------------
vlog -work work ../src/camera/csi2_rx_unpack.v

puts "==== COMPILE ALL DONE ===="
quit -code 0

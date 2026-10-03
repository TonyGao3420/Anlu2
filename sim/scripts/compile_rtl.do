# =============================================================================
# 文件名 : compile_rtl.do
# 功能   : 编译本工程可仿真的 RTL（不含厂商加密 IP 与顶层 system_top，
#          因为顶层依赖 MIPI 硬核和 HDMI 加密核，只能在 TD 中综合）。
#          在 sim/ 目录下执行： vsim -c -do scripts/compile_rtl.do
# =============================================================================

set PrefMain(saveLines) 100000

if {[file exists work_rtl]} { vdel -all -lib work_rtl }
vlib work_rtl

# ---------------- 公共模块 ----------------
vlog -work work_rtl ../src/common/sync_ff.v
vlog -work work_rtl ../src/common/debounce.v
vlog -work work_rtl ../src/common/async_fifo.v
vlog -work work_rtl ../src/common/clk_rst_gen.v
vlog -work work_rtl ../src/common/i2c_master.v

# ---------------- 视频输出 ----------------
vlog -work work_rtl ../src/video/video_timing_720p60.v

# ---------------- 图像处理（基础件，算法后续补全） ----------------
vlog -work work_rtl ../src/isp/line_buffer3x3.v

# ---------------- 摄像头配置（非加密官方文件） ----------------
vlog -work work_rtl ../src/vendor/uii2c.v
vlog -work work_rtl ../src/camera/config/sc520_reg_table_base.v
vlog -work work_rtl ../src/camera/config/sc520_reg_table_720p60.v
vlog -work work_rtl ../src/camera/config/sc520_reg_table_2560x1920_30.v
vlog -work work_rtl ../src/camera/config/sc520_reg_table_ae.v
vlog -work work_rtl ../src/camera/config/sc520_gain_tbl.v
vlog -work work_rtl ../src/camera/config/sc520_cfg.v

puts "==== RTL COMPILE DONE ===="
quit -code 0

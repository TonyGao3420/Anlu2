# =============================================================================
# 文件名 : flow_syn.tcl
# 功能   : Anlu2 工程的自定义综合流程（**绕开 open_project**）。
#
# 为什么不用官方 DefaultFlow.tcl：
#   安路 TD 6.2.168116 的 open_project 在 analyze 官方 MIPI 包装
#   （mipi_dphy_rx_ph1p_mipiio_wrapper.sv，内含 SystemVerilog 非压缩数组端口）
#   时会报 HDL-8007 "cannot access memory ... directly" 并中止。
#   实测：用 analyze verilog <文件> 逐个分析**同样内容的同一文件**可以通过，
#   说明差异在 open_project 的分析器路径，而不是文件本身。
#   因此这里改为直接调用 analyze/elaborate/opt 命令，绕开 open_project。
#
# 用法（在工程根目录 D:/Anlogic/Anlu2 下执行）：
#   td_commands_prompt.exe <本文件路径>
# =============================================================================

set PrefMain(saveLines) 100000

# ---------------------------------------------------------------------------
# 工程根目录（按需修改）
# ---------------------------------------------------------------------------
set ROOT   D:/Anlogic/Anlu2
set SRC    $ROOT/src

# ---------------------------------------------------------------------------
# 1. 导入器件
# ---------------------------------------------------------------------------
import_device ph1_35p.db -package PH1P35MDG324 -speed 3

# ---------------------------------------------------------------------------
# 2. 逐个 analyze 所有源文件
#    顺序：被依赖的先分析（厂商 IP -> 配置表 -> 公共件 -> 顶层）
# ---------------------------------------------------------------------------
# --- 厂商 IP：先分析内层加密模块（端口都是普通向量），再分析使用它们的模块 ---
# 注意：已**不再使用** byte_aligner_wrapper.enc.sv / channel_aligner_wrapper.enc.sv
#       —— 它们用了 SystemVerilog 非压缩数组端口，会让 TD 6.2 的 analyze 报
#       HDL-8007 "cannot access memory ... directly"。本工程改用
#       src/vendor/mipi_dphy_rx_ph1p_wrapper_v2001.v（纯 Verilog-2001，
#       直接例化内层模块），这两个文件已删除。
analyze verilog $SRC/vendor/byte_aligner.enc.v
analyze verilog $SRC/vendor/channel_aligner.enc.v
analyze verilog $SRC/vendor/hs_detect.enc.v
analyze verilog $SRC/vendor/mipi_dphy_rx_ph1p_wrapper_v2001.v
analyze verilog $SRC/vendor/hdmi_1_4b_transmitter_core_wrapper.enc.v
analyze verilog $SRC/vendor/PLL.v
analyze verilog $SRC/vendor/ph1p_phy_pll_wrapper_25a56e5ce2f9.v
analyze verilog $SRC/vendor/lane_lvds_10_1.v
analyze verilog $SRC/vendor/hdmi_phy_wrapper.v
analyze verilog $SRC/vendor/uii2c.v

# --- 摄像头配置表与状态机 ---
analyze verilog $SRC/camera/config/sc520_reg_table_720p60.v
analyze verilog $SRC/camera/config/sc520_reg_table_ae.v
analyze verilog $SRC/camera/config/sc520_gain_tbl.v
analyze verilog $SRC/camera/config/sc520_cfg.v

# --- 公共件 ---
analyze verilog $SRC/common/sync_ff.v
analyze verilog $SRC/common/debounce.v
analyze verilog $SRC/common/clk_rst_gen.v
analyze verilog $SRC/common/async_fifo.v
analyze verilog $SRC/common/i2c_master.v

# --- CSI-2 解包 / 图像处理 / 视频输出 ---
analyze verilog $SRC/camera/csi2_rx_unpack.v
analyze verilog $SRC/isp/line_buffer3x3.v
analyze verilog $SRC/video/video_timing_720p60.v

# --- 顶层 ---
analyze verilog $SRC/system_top.v

# ---------------------------------------------------------------------------
# 3. 细化（elaborate）顶层
# ---------------------------------------------------------------------------
elaborate -top system_top

# ---------------------------------------------------------------------------
# 4. 读约束 + 综合优化到 opt_rtl / opt_gate
#    注意：TD 的 read_adc 只接受 .adc 扩展名（用 .fdc 会报
#    "USR-8063 ... is not a adc file"），因此约束文件统一使用 .adc。
#    官方例程（32_cs500_mipi_hdmi、lab_ex1/ex2/ex3）同样使用 .adc。
# ---------------------------------------------------------------------------
if {[file exists $ROOT/constrs/anlu2_pins.adc]} {
    read_adc $ROOT/constrs/anlu2_pins.adc
}
if {[file exists $ROOT/constrs/anlu2_timing.sdc]} {
    read_sdc $ROOT/constrs/anlu2_timing.sdc
}

optimize_rtl
optimize_gate

# ---------------------------------------------------------------------------
# 5. 输出报告
# ---------------------------------------------------------------------------
report_area -file $ROOT/prj/syn_area.rpt
report_timing -file $ROOT/prj/syn_timing.rpt

puts "==== CUSTOM FLOW DONE ===="
exit

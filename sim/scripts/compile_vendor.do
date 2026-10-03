# =============================================================================
# 文件名 : compile_vendor.do
# 功能   : 单独编译从官方例程移植的厂商文件，确认移植后语法/编码正常。
#          在 sim/ 目录下执行： vsim -c -do scripts/compile_vendor.do
# 说明   : *.enc.v / *.enc.sv 是加密文件，ModelSim 无法编译，属预期现象，
#          这里只编译非加密的厂商包装与 IP。
# =============================================================================

set PrefMain(saveLines) 100000

if {[file exists work_vendor]} { vdel -all -lib work_vendor }
vlib work_vendor

# PLL 相关（非加密）
catch { vlog -work work_vendor ../src/vendor/PLL.v }                                  rc1
catch { vlog -work work_vendor ../src/vendor/ph1p_phy_pll_wrapper_25a56e5ce2f9.v }    rc2
catch { vlog -work work_vendor ../src/vendor/pll_hdmi.v }                             rc3

# I2C 与 SC520 配置（米联客/官方，非加密）
catch { vlog -work work_vendor ../src/vendor/uii2c.v }                                rc4
catch { vlog -work work_vendor ../src/camera/config/sc520_reg_table_base.v }          rc5
catch { vlog -work work_vendor ../src/camera/config/sc520_reg_table_720p60.v }        rc6
catch { vlog -work work_vendor ../src/camera/config/sc520_reg_table_2560x1920_30.v }  rc7
catch { vlog -work work_vendor ../src/camera/config/sc520_reg_table_ae.v }            rc8
catch { vlog -work work_vendor ../src/camera/config/sc520_gain_tbl.v }                rc9
catch { vlog -work work_vendor ../src/camera/config/sc520_cfg.v }                     rc10

# HDMI 物理层串化（非加密）
catch { vlog -work work_vendor ../src/vendor/lane_lvds_10_1.v }                       rc11
catch { vlog -work work_vendor ../src/vendor/hdmi_phy_wrapper.v }                     rc12

puts "==== VENDOR COMPILE ATTEMPT DONE ===="
quit -code 0

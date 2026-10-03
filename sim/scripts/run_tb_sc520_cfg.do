# SC520 配置流程自检测试运行脚本
set PrefMain(saveLines) 100000
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog -work work ../src/vendor/uii2c.v
vlog -work work ../src/camera/config/sc520_reg_table_base.v
vlog -work work ../src/camera/config/sc520_reg_table_720p60.v
vlog -work work ../src/camera/config/sc520_reg_table_ae.v
vlog -work work ../src/camera/config/sc520_gain_tbl.v
vlog -work work ../src/camera/config/sc520_cfg.v
vlog -work work ../sim/tb/tb_sc520_cfg.v
vsim -c tb_sc520_cfg
run -all
quit -code 0

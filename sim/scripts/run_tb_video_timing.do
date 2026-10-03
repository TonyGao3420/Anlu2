# 720p60 视频时序自检测试运行脚本
set PrefMain(saveLines) 100000
if {[file exists work]} { vdel -all -lib work }
vlib work
vlog -work work ../src/video/video_timing_720p60.v
vlog -work work ../sim/tb/tb_video_timing_720p60.v
vsim -c tb_video_timing_720p60
run -all
quit -code 0

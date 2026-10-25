transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../tb/tb_display_path.sv ../../user_source/hdl_source/isp/data96_128/data96_128.v ../../user_source/hdl_source/video_out.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/anlogic_logo_eram.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/osd_char_lib.v
vsim -c work.tb_display_path
run -all
quit -f

transcript file ../build/color_diagnosis_20261009/run_color_probe_vtc.log
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/vtc/uivtc.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/osd_char_lib.v ../diagnostic/color_diagnostic.v ../tb/tb_color_probe_vtc.sv
vsim -c work.tb_color_probe_vtc
run -all
quit -f


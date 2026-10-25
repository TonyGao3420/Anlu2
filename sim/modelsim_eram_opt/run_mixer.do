onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/anlogic_logo_eram.v ../../user_source/hdl_source/hdmi_mixer.v ../models/eram_opt/baseline_hdmi_mixer.v ../models/style_mode/logo_rom_fast.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/osd_char_lib.v ../tb/eram_opt/tb_mixer_eram_equivalence.sv
vsim -c work.tb_mixer_eram_equivalence
run -all
quit -f

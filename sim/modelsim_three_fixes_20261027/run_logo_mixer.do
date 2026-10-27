onerror {quit -code 1 -f}
if {[file exists logo_mixer_work/_info]} { vdel -lib logo_mixer_work -all }
vlib logo_mixer_work
vmap logo_mixer_work logo_mixer_work
vlog -work logo_mixer_work -sv ../models/three_fixes_20261027/logo_rom_model.v ../../../lab_ex3_osd_SC520/src/hdl_source/anlogic_logo_rom.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/video/roi_center_osd.v ../../user_source/hdl_source/osd_char_lib.v ../tb/tb_official_logo_mixer_20261027.sv
vsim -c logo_mixer_work.tb_official_logo_mixer
run -all
quit -f

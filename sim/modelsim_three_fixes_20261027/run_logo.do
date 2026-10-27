onerror {quit -code 1 -f}
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/three_fixes_20261027/logo_rom_model.v ../../user_source/hdl_source/hdmi_mixer.v ../tb/tb_official_logo_20261027.sv
vsim -c work.tb_official_logo
run -all
quit -f

onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/anlogic_logo_eram.v ../models/style_mode/logo_rom_fast.v ../tb/eram_opt/tb_eram_logo.sv
vsim -c work.tb_eram_logo
run -all
quit -f

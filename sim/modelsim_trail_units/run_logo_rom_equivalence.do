onerror {quit -code 1 -f}
transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../models/style_mode/logo_rom_fast.v ../models/style_mode/logo_rom_reference.v ../tb/style_mode/tb_logo_rom_equivalence.sv
vsim -c work.tb_logo_rom_equivalence
run -all
quit -f

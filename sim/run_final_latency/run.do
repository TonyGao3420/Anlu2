onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video_out.v ../../user_source/hdl_source/hdmi_mixer.v ../tb/final_four_modes_20261028/tb_final_latency.sv
vsim -c work.tb_frame_latency
run -all
quit -f

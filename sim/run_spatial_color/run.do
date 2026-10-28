onerror {quit -code 1 -f}
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/video/display_edge_color.v ../../user_source/hdl_source/video/display_color_shading.v ../../user_source/hdl_source/video/scene_color_stream.v ../tb/spatial_bias_20261028/tb_spatial_bias.sv
vsim -c work.tb_spatial_bias
run -all
quit -f

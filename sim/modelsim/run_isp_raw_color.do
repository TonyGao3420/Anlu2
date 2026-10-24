transcript on
if {[file exists work/_info]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv ../../user_source/hdl_source/isp/isp_top.v ../../user_source/hdl_source/isp/raw_measured_shading.v ../../user_source/hdl_source/awb_frame_stable.v ../../user_source/hdl_source/signal_delay.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/demosaic.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v ../../user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v ../../user_source/hdl_source/isp/data128_96/data128_96.v ../../user_source/hdl_source/isp/data96_128/data96_128.v ../tb/official_awb_models.sv ../tb/isp_ram_models.sv ../tb/tb_isp_raw_color.sv
vsim -c work.tb_isp_raw_color
run -all
quit -f

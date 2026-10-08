> 2026-10-08 更新：活动ISP已增加 `isp/raw_color_shading.v` 四通道RAW空间校正及专用KEY3/KEY4控制。`hdmi_mixer`增加可选的LSC状态方块，顶层启用。原有检测门限和ROI高度修复保留。完整说明见 [开源核查与上板操作](OPEN_SOURCE_LSC_20261008.md)。

# Anlu2 逐文件代码说明

入口是 td_project/camera_to_dsi_display.al，顶层为 design_top_wrapper。表中“直接编译”表示.al显式列入；IP内部源码由.xml/.ipc间接引入。不要递归添加所有.v文件，目录中有同名备份模块。

源代码按文件审阅并补充职责/接口注释；生成网表按接口、参数和依赖核对。加密代码只有外部接口可见，不能声称已经审阅其内部实现。

| 文件 | 模块/类别 | 直接编译 | 用途与使用约定 |
|---|---|---|---|
| [constraints_source/pin.adc](../user_source/constraints_source/pin.adc) | 生成IP/配置 | 是 | 顶层IO引脚位置、电平标准、驱动强度与上下拉。 |
| [constraints_source/timing.sdc](../user_source/constraints_source/timing.sdc) | 生成IP/配置 | 否/IP间接 | 历史备用时序约束；主工程改用td_project/camera_to_dsi_display.sdc。 |
| [hdl_source/anlogic_logo_rom.v](../user_source/hdl_source/anlogic_logo_rom.v) | anlogic_logo_rom | 是 | Logo像素ROM，地址对应160×160图像，25位输出为透明有效位及RGB888。 此文件主要是图像常量；修改图案时需同步尺寸和透明位规则。 |
| [hdl_source/audio_arc_calculate.v](../user_source/hdl_source/audio_arc_calculate.v) | audio_arc_calculate | 是 | 根据音频有效节拍测量HDMI ACR所需CTS，并输出固定N。 默认N=6144用于48 kHz配置；当前顶层音频valid恒0，因此该功能不工作。 |
| [hdl_source/auto_white_balance.v](../user_source/hdl_source/auto_white_balance.v) | auto_white_balance | 否/IP间接 | 旧版固定增益RGB校正，每组四个像素分别乘R/G/B增益。 使用Q12增益并做255饱和，与当前awb.v的Q16格式不同；当前工程未使用。 |
| [hdl_source/awb.v](../user_source/hdl_source/awb.v) | awb | 是 | 四像素RGB流白平衡；只用中亮度、低色度样本估计R/B增益，并限制在约0.8–1.25倍。R/B两路Q16比值共用一个逐位除法器，每帧顺序计算；像素数据和接口流水不变。 |
| [hdl_source/camera/camera_frontend_wrapper.v](../user_source/hdl_source/camera/camera_frontend_wrapper.v) | camera_frontend_wrapper | 否/IP间接 | 相机接口占位封装。 只透传时钟/复位、SCL固定0、SDA高阻，cfg_done直接来自复位；没有配置传感器，当前顶层不用。 |
| [hdl_source/csi_unpacket.v](../user_source/hdl_source/csi_unpacket.v) | csi_unpacket | 否/IP间接 | 旧CSI载荷解析器，含cwc3调试探针实例。 未加入当前工程，若单独综合需要补齐调试核依赖。 |
| [hdl_source/data_96bit_to_128bit.v](../user_source/hdl_source/data_96bit_to_128bit.v) | data_96bit_to_128bit | 否/IP间接 | 96→128位RGB打包器的根目录备份。 与isp/data96_128/data96_128.v同名模块，当前.al只编译后者；不要同时加入工程。 |
| [hdl_source/debug/video_path_debug.v](../user_source/hdl_source/debug/video_path_debug.v) | video_path_debug | 否/IP间接 | 视频状态组合显示占位模块。 path_valid=VS&&DE不能作为当前极性下通路通过的判据；status_code只反映瞬时电平，非完整自检。 |
| [hdl_source/design_top_wrapper.v](../user_source/hdl_source/design_top_wrapper.v) | design_top_wrapper | 是 | 板级顶层：连接 SC520 配置、两路 MIPI 接收、ISP、DDR2 四帧缓存、OSD 和 HDMI 输出。HDMI继续走官方mixer像素链；ROI检测器只读旁路像素，不控制DDR或显示握手。 |
| [hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v](../user_source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v) | hdmi_1_4b_transmitter_core_wrapper | 是 | HDMI协议编码/数据包核；厂商加密源码，无法检查内部算法。 |
| [hdl_source/hdmi_mixer.v](../user_source/hdl_source/hdmi_mixer.v) | hdmi_mixer | 是 | 接收DDR输出像素，叠加Logo、中文字符、六位帧计数和目标矩形框，或选择调试图案。目标框比检测外接矩形留4像素边距、线宽2像素；读使能仍直接取VTC的DE。 |
| [hdl_source/hdmi_phy_warpper.v](../user_source/hdl_source/hdmi_phy_warpper.v) | hdmi_phy_wrapper | 是 | 调整TMDS十位编码字的位序，实例化三个数据通道和一个时钟通道串行器。 文件名沿用warp拼写，模块名为hdmi_phy_wrapper；必须保留每个10位字的位序与ODDR配合。 |
| [hdl_source/hdmi_tx.v](../user_source/hdl_source/hdmi_tx.v) | hdmi_tx | 是 | 把RGB时序转为HDMI核使用的user/valid/last流，并连接TMDS发送物理层。 RGB模式由VS上升沿等待下一有效像素作为帧首；加密HDMI核固定1280×720。当前顶层关闭音频和EDID触发。 |
| [hdl_source/I2S_receiver.v](../user_source/hdl_source/I2S_receiver.v) | I2S_receiver | 是 | 同步外部I2S时钟与串行数据，移位拼接左右声道24位采样。 HDMI像素钟域采样；当前视频工程将I2S输入置0，音频支路未启用。 |
| [hdl_source/image_correction.v](../user_source/hdl_source/image_correction.v) | image_correction | 否/IP间接 | 旧固定窗口裁剪，把RAW数据保留在256组×600行范围。 每组4像素，约1024×600；当前原生720p模式绕过此裁剪。 |
| [hdl_source/isp/awb/awb.v](../user_source/hdl_source/isp/awb/awb.v) | awb | 否/IP间接 | 保留的另一版白平衡实现，分别对每组四个像素位置累加。 与根目录awb.v同名，当前工程未选用；除法与延迟路径也不同，不可混用。 |
| [hdl_source/isp/awb/divider/divider.ipc](../user_source/hdl_source/isp/awb/divider/divider.ipc) | 生成IP/配置 | 是/保留 | 旧版48/32位流水除法IP配置；当前选用的根目录awb.v不再实例化它，综合不计入逻辑资源。 |
| [hdl_source/isp/awb/divider/divider_gate.v](../user_source/hdl_source/isp/awb/divider/divider_gate.v) | divider | 否/保留 | 旧版48/32位流水除法IP生成网表；当前选用的根目录awb.v不再实例化。 |
| [hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.ipc](../user_source/hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.ipc) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.v](../user_source/hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.v) | blk_mem_gen_awb_delay_signal | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.vhd](../user_source/hdl_source/isp/awb/ram/blk_mem_gen_awb_delay_signal.vhd) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [hdl_source/isp/awb/signal_delay.v](../user_source/hdl_source/isp/awb/signal_delay.v) | signal_delay | 否/IP间接 | 旧版AWB配套的RAM延迟模块。 与根目录signal_delay.v同名，当前工程未选用；修改AWB时应成套核对延迟和IP参数。 |
| [hdl_source/isp/BLC/BLC.v](../user_source/hdl_source/isp/BLC/BLC.v) | BLC | 否/IP间接 | 可选RAW10黑电平校正，对四个采样分别减去偏置并向0饱和。 当前主ISP未实例化。它会降低暗部数值，未经标定不应为解决偏暗而直接启用；O_tdest未赋值。 |
| [hdl_source/isp/csi_unpacket_2lane.v](../user_source/hdl_source/isp/csi_unpacket_2lane.v) | csi_unpacket_2lane | 是 | 解析两通道CSI-2数据包，识别DT=0x2B的RAW10载荷和帧开始/结束短包。 输入每拍16位，输出隔拍32位；长度字段按两字节节拍计数。本模块不校验ECC/CRC。 |
| [hdl_source/isp/data128_96/data128_96.v](../user_source/hdl_source/isp/data128_96/data128_96.v) | data128_96 | 是 | 移除四个32位RGB字中的8位填充，输出紧凑的96位像素组。 组合逻辑；输出高24位是第一个显示像素，重排与demosaic输出位序配套，不是图像镜像。 |
| [hdl_source/isp/data96_128/data96_128.v](../user_source/hdl_source/isp/data96_128/data96_128.v) | data_96bit_to_128bit, data96_128 | 是 | 把连续的4组96位RGB重排成3组128位DDR写数据。 实际模块名为data_96bit_to_128bit，主工程使用此文件；每行320个输入组形成240个DDR字，行中不得插空拍。 |
| [hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v](../user_source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v) | bilinear_interpolation | 是 | 按BGGR/GBRG/RGGB/GRBG排列，用邻近同色采样求平均重建RGB。 四像素并行，分级求和、除2/4和限幅；数据与tuser/tlast/tvalid走五个寄存级。原始采样分量直接保留。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.m_params_blk_mem_gen_demosaic.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.m_params_blk_mem_gen_demosaic.txt) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.params_blk_mem_gen_demosaic.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.params_blk_mem_gen_demosaic.txt) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.ports_blk_mem_gen_demosaic.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.ports_blk_mem_gen_demosaic.txt) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v) | blk_mem_gen_demosaic | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.xml) | 生成IP/配置 | 是 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/Design.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/Design.xml) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/DesignConfiguration.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/RTL/include/define.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/RTL/include/define.v) | 生成IP/配置 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v) | ram_c36c2ca3b3a7 | 否/IP间接 | 33位双口行缓存及生成元数据；32位像素附带帧首标记。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.m_params_blk_mem_gen_zhenghe.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.m_params_blk_mem_gen_zhenghe.txt) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.params_blk_mem_gen_zhenghe.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.params_blk_mem_gen_zhenghe.txt) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.ports_blk_mem_gen_zhenghe.txt](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/.ports_blk_mem_gen_zhenghe.txt) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v) | blk_mem_gen_zhenghe | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.xml) | 生成IP/配置 | 是 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/Design.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/Design.xml) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/DesignConfiguration.xml](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/RTL/include/define.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/RTL/include/define.v) | 生成IP/配置 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v](../user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v) | ram_d32970204f32 | 否/IP间接 | 32位双口行缓存及生成元数据；整理四像素RAW流的行有效。 |
| [hdl_source/isp/demosaic_4x_2_0/demosaic.v](../user_source/hdl_source/isp/demosaic_4x_2_0/demosaic.v) | demosaic | 是 | 将3×3邻域缓存和Bayer双线性插值连接成去马赛克处理器。 输入4×RAW10，输出4×{8位填充,RGB888}；BAYER_MODE必须与传感器起始像素排列一致。 |
| [hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v](../user_source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v) | line_buffer_demosaic | 是 | 用双口RAM产生一行延迟，连用两个实例形成三行数据。 输入含32位像素及1位帧首标记；每行IMG_WIDTH/4个字，读写地址在帧首复位。 |
| [hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v](../user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v) | mipi_to_raw_converter | 是 | 提取每个RAW10采样的高8位，并调整四像素的字节排列。 输出高字节是时间上第一个像素；RGB通路的位序依赖这里与data128_96的配合，不能只反转其中一级。 |
| [hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v](../user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v) | raw_matrix_3x3_buffer | 是 | 组合相邻三行和每组前后像素，构造四个并行插值位置的3×3邻域。 内部将RAW10压到RAW8并整理行有效；行首尾按原工程复制边界，bayer_ypos选择行奇偶。 |
| [hdl_source/isp/demosaic_4x_2_0/zhenghe.v](../user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v) | zhenghe | 是 | 用双口行RAM把带空拍的四像素流整理为每行连续有效的数据。 data_complete_delay提供写入领先量，首行测得的有效跨度影响下一帧读出窗口；只适配已有摄像头节拍。 |
| [hdl_source/isp/isp_top.v](../user_source/hdl_source/isp/isp_top.v) | isp_top | 是 | ISP组合：RAW10四像素并行→Bayer插值→去填充→白平衡→96/128位打包。 IMG=1280×720、BAYER_MODE=BGGR；这是连续流接口，不支持背压。O_tready 是下游就绪输入，I_tready 是上游就绪输出。 |
| [hdl_source/track2/roi_target_tracker.v](../user_source/hdl_source/track2/roi_target_tracker.v) | roi_target_tracker | 是 | 显示像素时钟域单红色目标检测：每帧扫描全屏，RGB阈值含有限绿偏容差并做3×3多数滤波；最小面积与候选框红色占比抑制零星误检，输出红色区域实际外接矩形。相邻多个红色区域可能合并。 |
| [hdl_source/track2/red_mask_contour.v](../user_source/hdl_source/track2/red_mask_contour.v) | red_mask_contour | 否 | 轮廓提取历史模块，仍保留在工程文件清单中但顶层不再实例化；当前显示端使用检测器输出的矩形框，不逐像素标记红色掩码。 |
| [hdl_source/isp/raw10_unpacket_2lane.v](../user_source/hdl_source/isp/raw10_unpacket_2lane.v) | raw10_unpacket_2lane | 是 | 将CSI载荷每5字节还原成4个10位Bayer采样。 输出最低10位是时间上第一个像素；输入要求32位数据隔拍有效。I_camera_black_level当前未参与计算。 |
| [hdl_source/isp/uial2axis.v](../user_source/hdl_source/isp/uial2axis.v) | uial2axis | 是 | 为四像素RAW流生成帧首tuser和行尾tlast。 有效拍计数，每行IMG_WIDTH/4拍；tuser与首个有效数据同拍，宽度必须能被4整除。 |
| [hdl_source/key_remove_shakes.v](../user_source/hdl_source/key_remove_shakes.v) | key_remove_shakes | 是 | 对低有效按键进行同步和计数消抖，输出单拍触发脉冲。 等待100000个输入时钟周期后确认按键仍按下；实际时间随时钟频率变化。 |
| [hdl_source/lane_lvds_10_1.v](../user_source/hdl_source/lane_lvds_10_1.v) | lane_lvds_10_1 | 是 | 用像素时钟与5倍串行时钟把10位TMDS字转换成串行输出。 在串行域检测像素翻转标志，每拍移出两位并经器件ODDR发送；PH1P分支由顶层选用。 |
| [hdl_source/mc_to_user_interface.v](../user_source/hdl_source/mc_to_user_interface.v) | mc_to_user_interface | 是 | 将用户读写请求和地址/数据打包到155位命令FIFO，转换为DDR控制器应用接口。 DDR时钟域；命令在读写两类ready同时满足时出队，写mask为0。上游需用O_ddr_user_ready控制请求。 |
| [hdl_source/mipi_dphy_rx/byte_aligner.enc.v](../user_source/hdl_source/mipi_dphy_rx/byte_aligner.enc.v) | byte_aligner | 是 | MIPI字节对齐；厂商加密源码，无法检查内部算法。 |
| [hdl_source/mipi_dphy_rx/byte_aligner_wrapper.enc.sv](../user_source/hdl_source/mipi_dphy_rx/byte_aligner_wrapper.enc.sv) | byte_aligner_wrapper | 是 | MIPI字节对齐；厂商加密源码，无法检查内部算法。 |
| [hdl_source/mipi_dphy_rx/channel_aligner.enc.v](../user_source/hdl_source/mipi_dphy_rx/channel_aligner.enc.v) | channel_aligner | 是 | MIPI通道对齐；厂商加密源码，无法检查内部算法。 |
| [hdl_source/mipi_dphy_rx/channel_aligner_wrapper.enc.sv](../user_source/hdl_source/mipi_dphy_rx/channel_aligner_wrapper.enc.sv) | channel_aligner_wrapper | 是 | MIPI通道对齐；厂商加密源码，无法检查内部算法。 |
| [hdl_source/mipi_dphy_rx/hs_detect.enc.v](../user_source/hdl_source/mipi_dphy_rx/hs_detect.enc.v) | hs_detect | 是 | MIPI高速状态检测；厂商加密源码，无法检查内部算法。 |
| [hdl_source/mipi_dphy_rx/mipi_dphy_rx_ph1p_mipiio_wrapper.sv](../user_source/hdl_source/mipi_dphy_rx/mipi_dphy_rx_ph1p_mipiio_wrapper.sv) | mipi_dphy_rx_ph1p_mipiio_wrapper | 是 | MIPI接收层封装，组合硬核DPHY、字节对齐与通道对齐。 顶层选择DPHY0、2 lane、每通道1 byte，输出16位高速数据和错误标志；不能用通用仿真代替板级采样校准。 |
| [hdl_source/mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v](../user_source/hdl_source/mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v) | ph1p_mipiio_rx_wrapper | 是 | PH1P硬MIPI接收原语参数/端口封装。 设置接收物理位置、均衡、延迟和时钟；参数直接影响物理采样，保留厂商结构。 |
| [hdl_source/mipi_rx_error_detect.v](../user_source/hdl_source/mipi_rx_error_detect.v) | mipi_rx_error_detect | 否/IP间接 | 旧MIPI行数检测器，按帧结束检查832行并暴露调试探针。 与当前720行模式不匹配，且依赖cwc1；当前顶层错误输入固定0。 |
| [hdl_source/osd_char_lib.v](../user_source/hdl_source/osd_char_lib.v) | osd_char_lib | 是 | 根据字符代码与行号输出16位点阵行，用于中文、CNT和数字叠加。 组合ROM，返回行掩码；仅字形数据，缩放和位置由hdmi_mixer计算。 |
| [hdl_source/ph1p35_ddr/ddr2/.m_params_ddr2.txt](../user_source/hdl_source/ph1p35_ddr/ddr2/.m_params_ddr2.txt) | 生成IP/配置 | 否/IP间接 | 配套文件；结合所在IP目录与文件内容使用。 |
| [hdl_source/ph1p35_ddr/ddr2/.params_ddr2.txt](../user_source/hdl_source/ph1p35_ddr/ddr2/.params_ddr2.txt) | 生成IP/配置 | 否/IP间接 | 配套文件；结合所在IP目录与文件内容使用。 |
| [hdl_source/ph1p35_ddr/ddr2/.ports_ddr2.txt](../user_source/hdl_source/ph1p35_ddr/ddr2/.ports_ddr2.txt) | 生成IP/配置 | 否/IP间接 | 配套文件；结合所在IP目录与文件内容使用。 |
| [hdl_source/ph1p35_ddr/ddr2/ddr2.v](../user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.v) | ddr2 | 否/IP间接 | 用户可见DDR2 IP接口及生成参数；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/ddr2.xml](../user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.xml) | 生成IP/配置 | 是 | IP-XACT文件清单、模块端口及参数；供TD导入对应生成IP。 |
| [hdl_source/ph1p35_ddr/ddr2/Design.xml](../user_source/hdl_source/ph1p35_ddr/ddr2/Design.xml) | 生成IP/配置 | 否/IP间接 | IP-XACT文件清单、模块端口及参数；供TD导入对应生成IP。 |
| [hdl_source/ph1p35_ddr/ddr2/DesignConfiguration.xml](../user_source/hdl_source/ph1p35_ddr/ddr2/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | IP-XACT文件清单、模块端口及参数；供TD导入对应生成IP。 |
| [hdl_source/ph1p35_ddr/ddr2/ph1p_ddrmc_wrapper_63f4ac254419.v](../user_source/hdl_source/ph1p35_ddr/ddr2/ph1p_ddrmc_wrapper_63f4ac254419.v) | ph1p_ddrmc_wrapper_63f4ac254419 | 否/IP间接 | DDR2参数化生成封装，实例化控制器与PHY顶层；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/sim/fileset/fileset_mis.f](../user_source/hdl_source/ph1p35_ddr/ddr2/sim/fileset/fileset_mis.f) | 生成IP/配置 | 否/IP间接 | 厂商仿真文件清单；可能包含参考安装路径，单独仿真前需核对。 |
| [hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc](../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc) | 生成IP/配置 | 否/IP间接 | DDR2专用引脚、电气及布局约束，由DDR IP引入。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_clk_top.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_clk_top.v) | ph1p_ddrphy_clk_top | 否/IP间接 | DDR PHY时钟与复位汇总；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll0.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll0.v) | ph1p_ddrphy_pll0 | 否/IP间接 | DDR高频与控制域PLL原语封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll1.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll1.v) | ph1p_ddrphy_pll1 | 否/IP间接 | DDR附属时钟PLL原语封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh) | 生成IP/配置 | 否/IP间接 | DDR模型编译宏；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/init/ph1p_ddrphy_dram_init_ddr2.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/init/ph1p_ddrphy_dram_init_ddr2.v) | ph1p_ddrphy_dram_init | 否/IP间接 | DDR2初始化/模式寄存器/等待周期控制；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all.enc.sv](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all.enc.sv) | alc_mc_top | 否/IP间接 | DDR内存控制器；厂商加密源码，无法检查内部算法。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_phy2mc_fifo_ctrl.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_phy2mc_fifo_ctrl.v) | alc_phy2mc_fifo_ctrl | 否/IP间接 | PHY到控制器的FIFO控制和有效节拍转换；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddr_fifo_dram_sync.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddr_fifo_dram_sync.v) | ph1p_ddr_fifo_dram_sync | 否/IP间接 | 基于分布式RAM的DDR同步FIFO；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddrphy_sync_rst_gen.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddrphy_sync_rst_gen.v) | ph1p_ddrphy_sync_rst_gen | 否/IP间接 | 指定时钟域内同步释放复位；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ddrphy_cfg_rom.txt](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ddrphy_cfg_rom.txt) | 生成IP/配置 | 否/IP间接 | DDR PHY配置ROM初始值；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_board_delay.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_board_delay.vh) | 生成IP/配置 | 否/IP间接 | 板级DDR走线延迟参数；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_bus_matrix.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_bus_matrix.vh) | 生成IP/配置 | 否/IP间接 | DDR物理/逻辑字节通道映射；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_ddrio.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_ddrio.vh) | 生成IP/配置 | 否/IP间接 | DDR IO位置宏定义；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_pad_type.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/include/ph1p_ddrphy_pad_type.vh) | 生成IP/配置 | 否/IP间接 | DDR引脚类型宏定义；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy.v) | ph1p_ddrphy | 否/IP间接 | DDR物理层核心逻辑汇总；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_apb_bridge.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_apb_bridge.v) | ph1p_ddrphy_apb_bridge | 否/IP间接 | APB寄存器访问到PHY配置接口桥接；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_bankref_cfg.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_bankref_cfg.v) | ph1p_ddrphy_bankref_cfg | 否/IP间接 | DDR IO bank参考/校准参数；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_byte_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_byte_wrapper.v) | ph1p_ddrphy_byte_wrapper | 否/IP间接 | 一个DDR字节通道的DQ/DQS原语封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_decode.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_decode.v) | ph1p_ddrphy_cmd_decode | 否/IP间接 | PHY配置/校准指令译码；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_execution.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_execution.v) | ph1p_ddrphy_cmd_execution | 否/IP间接 | PHY指令执行与应答；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v) | ph1p_ddrphy_cmd_wrapper | 否/IP间接 | PHY指令子系统封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu.v) | ph1p_ddrphy_dcu | 否/IP间接 | DDR延迟/校准控制单元；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu_wrapper.v) | ph1p_ddrphy_dcu_wrapper | 否/IP间接 | DCU控制单元封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init.v) | ph1p_ddrphy_fast_init | 否/IP间接 | DDR快速初始化状态机；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v) | ph1p_ddrphy_fast_init_wrapper | 否/IP间接 | 快速初始化流程与配置连接；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_init.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_init.v) | ph1p_ddrphy_init | 否/IP间接 | DDR PHY上电初始化流程；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal.v) | ph1p_ddrphy_mdl_cal | 否/IP间接 | DDR主延迟线校准逻辑；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal_wrapper.v) | ph1p_ddrphy_mdl_cal_wrapper | 否/IP间接 | 主延迟线校准接口封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_rphase_ctl.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_rphase_ctl.v) | ph1p_ddrphy_rphase_ctl | 否/IP间接 | DDR读采样相位控制；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_top.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_top.v) | ph1p_ddrphy_top | 否/IP间接 | DDR PHY顶层，连接时钟、初始化、校准和IO；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wphase_ctl.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wphase_ctl.v) | ph1p_ddrphy_wphase_ctl | 否/IP间接 | DDR写数据/DQS相位控制；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wrapper.v) | ph1p_ddrphy_wrapper | 否/IP间接 | DDR物理层原语与总线封装；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_1066.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_1066.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_1333.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_1333.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_400.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_400.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_533.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_533.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_667.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_667.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_800.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_800.vh) | 生成IP/配置 | 否/IP间接 | DDR2对应数据速率的时序常量；由ddr2_parameter.vh选择。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_parameter.vh](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/timing/ddr2/ddr2_parameter.vh) | 生成IP/配置 | 否/IP间接 | 按选定速率选择DDR2时序参数；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/rtl/top/ph1p_ddrmc_top.v](../user_source/hdl_source/ph1p35_ddr/ddr2/src/rtl/top/ph1p_ddrmc_top.v) | ph1p_ddrmc_top | 否/IP间接 | DDR控制器顶层，连接PHY、MC与PAXI接口；厂商生成依赖，保留原文件。 |
| [hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc](../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc) | 生成IP/配置 | 否/IP间接 | DDR PHY/控制器内部时序约束，由DDR IP引入。 |
| [hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v](../user_source/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v) | ph1p35_324_ddr_wrapper | 是 | 把工程DDR应用接口转换为厂商DDR2的PAXI端口，并连接板上16位DDR数据总线。 O_ddr_clk来自dhi_clk；ddrphy_rdy表示初始化完成。底层ddr2目录是厂商生成实现与时序/引脚约束。 |
| [hdl_source/pll_hdmi.v](../user_source/hdl_source/pll_hdmi.v) | pll_hdmi | 否/IP间接 | 旧独立HDMI PLL封装。 当前使用ip_source/PLL/PLL.v提供75/375 MHz；此旧模块依赖另一版PLL封装，未加入主工程。 |
| [hdl_source/ps_wrapper.v](../user_source/hdl_source/ps_wrapper.v) | ps_wrapper | 否/IP间接 | MCU处理器封装，连接APB、UART、JTAG和GPIO。 当前视频工程无MCU控制路径；GPIO3/4三态控制存在历史接线疑点，未启用前不得据此认为可用。 |
| [hdl_source/raw10_unpacket.v](../user_source/hdl_source/raw10_unpacket.v) | raw10_unpacket | 否/IP间接 | 旧RAW10解包模块，输出四个完整10位采样。 当前工程选择isp/raw10_unpacket_2lane.v。 |
| [hdl_source/raw8_to_rgb888.v](../user_source/hdl_source/raw8_to_rgb888.v) | raw8_to_rgb888 | 否/IP间接 | 旧四像素RAW8去马赛克实现，使用固定258深度行移位器。 尺寸与当前720p主ISP不同，当前未使用；不可直接替换可配置demosaic。 |
| [hdl_source/signal_delay.v](../user_source/hdl_source/signal_delay.v) | signal_delay | 是 | 白平衡流水使用的RAM延迟/行有效重建模块。 计满每行IMG_WIDTH/4组数据；DELAY_CYCLE决定启动读出位置，内部RAM为96位宽，本模块不是任意接口的通用延迟队列。 |
| [hdl_source/track2/track2_lab3_merge.v](../user_source/hdl_source/track2/track2_lab3_merge.v) | track2_lab3_merge | 否/IP间接 | Track2目标检测扩展：累计ROI内颜色匹配点，计算包围框、质心、面积并画框。 当前未接入视频链路。逻辑在VS为0时清统计，与当前VTC的有效区VS极性不兼容，不能只实例化就认为可用。 |
| [hdl_source/track2_lab3_merge.v](../user_source/hdl_source/track2_lab3_merge.v) | track2_lab3_merge | 否/IP间接 | 颜色阈值目标检测与ROI/包围框/质心叠加的历史集成模块。 当前.al及顶层未接入；与track2子目录模块重名，含逐像素除法及VS极性假设，启用前需单独验证。 |
| [hdl_source/uial2axis/uial2axis.v](../user_source/hdl_source/uial2axis/uial2axis.v) | uial2axis | 否/IP间接 | RAW原生流到帧首/行尾流接口的历史副本。 与isp/uial2axis.v模块同名；主工程只选择isp目录文件。 |
| [hdl_source/uics500_cfg/SC500GainTbl.v](../user_source/hdl_source/uics500_cfg/SC500GainTbl.v) | SC500GainTbl | 否/IP间接 | 旧SC500软件档位到增益寄存器编码的查表逻辑。 增益编码与SC520不同，当前主工程未选用。 |
| [hdl_source/uics500_cfg/uicfgcs500.v](../user_source/hdl_source/uics500_cfg/uicfgcs500.v) | uicfgcs500 | 否/IP间接 | 旧SC500传感器配置状态机，选择初始化表或AE表并逐项写I2C。 当前SC520主工程未用，不能作为SC520配置器替代品。 |
| [hdl_source/uics500_cfg/uicfgcs500_720p.v](../user_source/hdl_source/uics500_cfg/uicfgcs500_720p.v) | uicfgcs500_720p | 否/IP间接 | 旧SC500 720p配置状态机，含开流后的额外等待。 只与SC500寄存器表和增益表配套；当前主工程未用。 |
| [hdl_source/uics500_cfg/uics500reg.v](../user_source/hdl_source/uics500_cfg/uics500reg.v) | uics500reg | 否/IP间接 | 旧SC500默认模式初始化寄存器表。 当前SC520工程未选用；表索引对应24位地址/数据字。 |
| [hdl_source/uics500_cfg/uics500reg_720p60.v](../user_source/hdl_source/uics500_cfg/uics500reg_720p60.v) | uics500reg_720p60 | 否/IP间接 | 旧SC500 720p60模式初始化寄存器表。 传感器型号与当前SC520不同，不能直接替换当前表。 |
| [hdl_source/uics500_cfg/uics500regAE.v](../user_source/hdl_source/uics500_cfg/uics500regAE.v) | uics500regAE | 否/IP间接 | 旧SC500曝光和增益寄存器更新表。 由旧SC500配置器使用，当前主工程未选用。 |
| [hdl_source/uics500_cfg/uii2c.v](../user_source/hdl_source/uics500_cfg/uii2c.v) | uii2c | 是 | 传感器通用I2C主机，支持按字节写入、读回、ACK检测和SDA开漏输出。 虽然位于uics500_cfg，SC520配置也使用本文件。输入低字节先发送；CLK_DIV按输入时钟设定。 |
| [hdl_source/uics520_cfg/SC520GainTbl.v](../user_source/hdl_source/uics520_cfg/SC520GainTbl.v) | SC520GainTbl | 是 | 把16～176的软件增益档位转换为SC520模拟和数字细增益寄存器。 输出{0x3e09,0x3e06,0x3e07对应值}，输入越界时限幅；当前默认128映射0x0b/0x00/0xc0。 |
| [hdl_source/uics520_cfg/uicfgcs520.v](../user_source/hdl_source/uics520_cfg/uicfgcs520.v) | uicfgcs520 | 是 | SC520配置状态机：读芯片ID，写720p寄存器表，处理曝光/增益更新。 24 MHz附近时钟域，I2C分频由顶层给定；接受ee4b/9e4b，复位后等待5 ms，输出配置完成与错误标志。 |
| [hdl_source/uics520_cfg/uics520reg.v](../user_source/hdl_source/uics520_cfg/uics520reg.v) | uics520reg | 否/IP间接 | SC520保留的原始模式寄存器表。 不是当前720p60初始化入口；更换表时必须同步RAW/ISP尺寸、lane速率和显示带宽。 |
| [hdl_source/uics520_cfg/uics520reg_720p60.v](../user_source/hdl_source/uics520_cfg/uics520reg_720p60.v) | uics520reg_720p60 | 是 | 当前使用的SC520 1280×720 RAW10两通道模式寄存器表。 REG_INDEX选出{16位地址,8位值}；输出VTS=1000，0x3222关闭外部触发等待。保持表项顺序与REG_SIZE一致。 |
| [hdl_source/uics520_cfg/uics520reg_full_2560x1920_30.v](../user_source/hdl_source/uics520_cfg/uics520reg_full_2560x1920_30.v) | uics520reg_full_2560x1920_30 | 否/IP间接 | SC520 2560×1920全分辨率30帧模式寄存器表。 当前主通路未使用；直接换入会与1280×720的ISP、DDR行长和HDMI时序不匹配。 |
| [hdl_source/uics520_cfg/uics520regAE.v](../user_source/hdl_source/uics520_cfg/uics520regAE.v) | uics520regAE | 是 | 曝光/增益写入表，先开启组保持，再写曝光高低位、模拟/数字增益，最后释放。 8项写入；I_AE以半行为单位，I_AG由SC520GainTbl提供三个寄存器字节。 |
| [hdl_source/uiisp_beta/ae_set.v](../user_source/hdl_source/uiisp_beta/ae_set.v) | ae_set | 是 | 按键驱动的手动曝光/增益设定器，配置完成且数值变化时发一次写请求。 不是基于画面统计的自动曝光。默认曝光1991半行、增益档位128；顶层两个按键只接增益减/增。 |
| [hdl_source/uiisp_beta/csi_unpacket_2lane.v](../user_source/hdl_source/uiisp_beta/csi_unpacket_2lane.v) | csi_unpacket_2lane | 否/IP间接 | 两通道CSI解包器的历史副本。 与isp/csi_unpacket_2lane.v模块同名，主工程使用isp目录版本。 |
| [hdl_source/uiisp_beta/raw10_unpacket_2lane.v](../user_source/hdl_source/uiisp_beta/raw10_unpacket_2lane.v) | raw10_unpacket_2lane | 否/IP间接 | 两通道RAW10解包器的历史副本。 与isp/raw10_unpacket_2lane.v模块同名，主工程使用isp目录版本。 |
| [hdl_source/video/hdmi_output_wrapper.v](../user_source/hdl_source/video/hdmi_output_wrapper.v) | hdmi_output_wrapper | 否/IP间接 | 显示信号直通占位封装。 仅组合透传VS/HS/DE/RGB，不实现TMDS编码，也未接入当前顶层。 |
| [hdl_source/video/video_enhance.v](../user_source/hdl_source/video/video_enhance.v) | video_enhance | 是 | HDMI显示支路六级流水对齐模块。当前仅对相机视频RGB各通道增加6级亮度并饱和截顶，保护ROI框和OSD颜色；对比度、锐化、饱和度和Gamma仍旁路。 |
| [hdl_source/video_cuttting.v](../user_source/hdl_source/video_cuttting.v) | video_cutting | 否/IP间接 | 旧RAW8固定区域裁剪，按行有效边沿计数并选择固定行列区间。 模块名video_cutting，输出258组×602行供旧插值路径使用，当前未启用。 |
| [hdl_source/video_in.v](../user_source/hdl_source/video_in.v) | video_in | 是 | 摄像头到DDR写通路：异步FIFO跨时钟，按240字突发写入四帧轮转缓存。 frame_start为提前复位FIFO的通知，不能随意改成首像素同拍；写地址每次加8，四帧基地址与video_out必须一致。 |
| [hdl_source/video_out.v](../user_source/hdl_source/video_out.v) | video_out | 是 | DDR到HDMI读通路：预读128位字到异步FIFO，再按24位RGB顺序输出。 每16像素读取3个128位字；读请求到RGB经过FIFO及输出寄存级，hdmi_mixer的DE必须与这两级一致。 |
| [hdl_source/vtc/uivtc.v](../user_source/hdl_source/vtc/uivtc.v) | uivtc | 是 | 生成显示水平/垂直计数、同步、有效区、帧首和行尾。 顶层设置1280×720有效区、1650×750总周期；PLL像素钟实际为75 MHz，不能只按模块注释认定标准60 Hz。 |
| [ip_source/blk_mem_gen_awb_delay_signal/.m_params_blk_mem_gen_awb_delay_signal.txt](../user_source/ip_source/blk_mem_gen_awb_delay_signal/.m_params_blk_mem_gen_awb_delay_signal.txt) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/.params_blk_mem_gen_awb_delay_signal.txt](../user_source/ip_source/blk_mem_gen_awb_delay_signal/.params_blk_mem_gen_awb_delay_signal.txt) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/.ports_blk_mem_gen_awb_delay_signal.txt](../user_source/ip_source/blk_mem_gen_awb_delay_signal/.ports_blk_mem_gen_awb_delay_signal.txt) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.v](../user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.v) | blk_mem_gen_awb_delay_signal | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.xml](../user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.xml) | 生成IP/配置 | 是 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/Design.xml](../user_source/ip_source/blk_mem_gen_awb_delay_signal/Design.xml) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/DesignConfiguration.xml](../user_source/ip_source/blk_mem_gen_awb_delay_signal/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/blk_mem_gen_awb_delay_signal/ram_f84573da5ab5.v](../user_source/ip_source/blk_mem_gen_awb_delay_signal/ram_f84573da5ab5.v) | ram_f84573da5ab5 | 否/IP间接 | 96位双口RAM及生成元数据；AWB像素延迟缓存。 |
| [ip_source/divider/divider.ipc](../user_source/ip_source/divider/divider.ipc) | 生成IP/配置 | 是 | 48位无符号分子/32位分母、50级流水除法IP；用于AWB的Q16通道比。 |
| [ip_source/divider/divider_gate.v](../user_source/ip_source/divider/divider_gate.v) | divider | 否/IP间接 | 48位无符号分子/32位分母、50级流水除法IP；用于AWB的Q16通道比。 |
| [ip_source/MCU/.m_params_MCU.txt](../user_source/ip_source/MCU/.m_params_MCU.txt) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/.params_MCU.txt](../user_source/ip_source/MCU/.params_MCU.txt) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/.ports_MCU.txt](../user_source/ip_source/MCU/.ports_MCU.txt) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/Design.xml](../user_source/ip_source/MCU/Design.xml) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/DesignConfiguration.xml](../user_source/ip_source/MCU/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/MCU.v](../user_source/ip_source/MCU/MCU.v) | MCU | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/MCU.xml](../user_source/ip_source/MCU/MCU.xml) | 生成IP/配置 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/MCU/MCU_f9f874759a41.v](../user_source/ip_source/MCU/MCU_f9f874759a41.v) | MCU_f9f874759a41 | 否/IP间接 | MCU硬核封装和生成元数据；当前视频顶层未启用。 |
| [ip_source/PLL/.m_params_PLL.txt](../user_source/ip_source/PLL/.m_params_PLL.txt) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/.params_PLL.txt](../user_source/ip_source/PLL/.params_PLL.txt) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/.ports_PLL.txt](../user_source/ip_source/PLL/.ports_PLL.txt) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/Design.xml](../user_source/ip_source/PLL/Design.xml) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/DesignConfiguration.xml](../user_source/ip_source/PLL/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/PLL.v](../user_source/ip_source/PLL/PLL.v) | PLL | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/PLL.xml](../user_source/ip_source/PLL/PLL.xml) | 生成IP/配置 | 是 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/RTL/include/define.v](../user_source/ip_source/PLL/RTL/include/define.v) | 生成IP/配置 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/PLL/RTL/ph1p_phy_pll_wrapper_25a56e5ce2f9.v](../user_source/ip_source/PLL/RTL/ph1p_phy_pll_wrapper_25a56e5ce2f9.v) | ph1p_phy_pll_wrapper_25a56e5ce2f9 | 否/IP间接 | 当前PLL IP封装/参数：50MHz输入，100MHz、23.809524MHz、75MHz、375MHz输出。 |
| [ip_source/w128_d512_fifo/.m_params_w128_d512_fifo.txt](../user_source/ip_source/w128_d512_fifo/.m_params_w128_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/.params_w128_d512_fifo.txt](../user_source/ip_source/w128_d512_fifo/.params_w128_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/.ports_w128_d512_fifo.txt](../user_source/ip_source/w128_d512_fifo/.ports_w128_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/Design.xml](../user_source/ip_source/w128_d512_fifo/Design.xml) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/DesignConfiguration.xml](../user_source/ip_source/w128_d512_fifo/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v](../user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v) | soft_fifo_al_4057d6b76aa6, fifo_cross_domain_addr_process_al_4057d6b76aa6, ram_infer_4057d6b76aa6 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/w128_d512_fifo.tcl](../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl) | 生成IP/配置 | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/w128_d512_fifo.v](../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v) | w128_d512_fifo | 否/IP间接 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w128_d512_fifo/w128_d512_fifo.xml](../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.xml) | 生成IP/配置 | 是 | 128×512异步FIFO及生成元数据；摄像头/DDR/显示跨域缓存。 |
| [ip_source/w155_d512_fifo/.m_params_w155_d512_fifo.txt](../user_source/ip_source/w155_d512_fifo/.m_params_w155_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/.params_w155_d512_fifo.txt](../user_source/ip_source/w155_d512_fifo/.params_w155_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/.ports_w155_d512_fifo.txt](../user_source/ip_source/w155_d512_fifo/.ports_w155_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/Design.xml](../user_source/ip_source/w155_d512_fifo/Design.xml) | 生成IP/配置 | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/DesignConfiguration.xml](../user_source/ip_source/w155_d512_fifo/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v](../user_source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v) | soft_fifo_al_f58e8b3e1f3d, ram_infer_f58e8b3e1f3d | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/w155_d512_fifo.v](../user_source/ip_source/w155_d512_fifo/w155_d512_fifo.v) | w155_d512_fifo | 否/IP间接 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w155_d512_fifo/w155_d512_fifo.xml](../user_source/ip_source/w155_d512_fifo/w155_d512_fifo.xml) | 生成IP/配置 | 是 | 155×512同步FIFO及生成元数据；缓存DDR读写标志、地址和128位数据。 |
| [ip_source/w40_d512_fifo/.m_params_w40_d512_fifo.txt](../user_source/ip_source/w40_d512_fifo/.m_params_w40_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/.params_w40_d512_fifo.txt](../user_source/ip_source/w40_d512_fifo/.params_w40_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/.ports_w40_d512_fifo.txt](../user_source/ip_source/w40_d512_fifo/.ports_w40_d512_fifo.txt) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/Design.xml](../user_source/ip_source/w40_d512_fifo/Design.xml) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/DesignConfiguration.xml](../user_source/ip_source/w40_d512_fifo/DesignConfiguration.xml) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/soft_fifo_al_2758cdf81c93.v](../user_source/ip_source/w40_d512_fifo/soft_fifo_al_2758cdf81c93.v) | soft_fifo_al_2758cdf81c93, ram_infer_2758cdf81c93 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/w40_d512_fifo.tcl](../user_source/ip_source/w40_d512_fifo/w40_d512_fifo.tcl) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/w40_d512_fifo.v](../user_source/ip_source/w40_d512_fifo/w40_d512_fifo.v) | w40_d512_fifo | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |
| [ip_source/w40_d512_fifo/w40_d512_fifo.xml](../user_source/ip_source/w40_d512_fifo/w40_d512_fifo.xml) | 生成IP/配置 | 否/IP间接 | 40位RAW数据FIFO及生成元数据；当前主通路未选用。 |

## td_project目录

| 文件 | 用途 |
|---|---|
| camera_to_dsi_display.al | TD器件、顶层、源文件、IP与约束清单；使用相对源码路径。 |
| camera_to_dsi_display.sdc | 当前主工程时钟/时序约束。 |
| validate.tcl | 重新综合和布局布线到route阶段的脚本，不烧录。 |
| design_top_wrapper_route.timingsummary | 历史报告，包含旧DSI时钟和负hold slack，不代表当前工程通过。 |
| camera_to_dsi_display_Runs/ | TD生成目录，不是手写源码；可重新构建。 |
| .recent_user_depot.ini | TD本机最近路径状态，不参与硬件逻辑。 |

## 重名与占位模块

- awb、signal_delay：当前使用hdl_source根目录版本，isp/awb是备份。
- uial2axis、csi_unpacket_2lane、raw10_unpacket_2lane：当前使用isp目录版本。
- data_96bit_to_128bit：当前使用isp/data96_128/data96_128.v，根目录同名文件为备份。
- track2_lab3_merge：两个副本均未实例化，旧README中“已集成Track2”的描述不成立。
- camera_frontend_wrapper、hdmi_output_wrapper、video_path_debug为占位/直通示例，不能替代工作通路。

## 维护边界

版权声明和厂商加密/生成实现保留原样。可维护RTL统一UTF-8、4空格缩进，并用Verible验证格式化没有改变词法内容。具体图像修改和验证范围见VIDEO_QUALITY.md。

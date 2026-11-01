# Anlu2 当前源码清单

> 生成依据：`td_project/camera_to_dsi_display.al`
> 生成日期：2026-10-31
> 工程：`camera_to_dsi_display`
> 顶层：`design_top_wrapper`
> 器件：`PH1P35MDG324-3`

---

## 1. 总览

```text
工程源条目：68
AutoExcluded：6
当前参与编译：62
```

说明：

- 以 `.al` 为准；
- `.prj` 是 TD 运行目录自动生成的副本；
- 不要递归添加所有 `.v` 文件；
- `sim`、历史归档和备份文件不属于当前工程源列表。

---

## 2. 当前参与编译的源文件

### 2.1 顶层与控制

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/design_top_wrapper.v` | 顶层：摄像头、ISP、DDR、HDMI、识别、舵机、UI |
| `user_source/hdl_source/mc_to_user_interface.v` | DDR 用户接口 |
| `user_source/hdl_source/video_in.v` | 写入 DDR |
| `user_source/hdl_source/video_out.v` | DDR 读出、180° 旋转 |
| `user_source/hdl_source/signal_delay.v` | AWB 固定延迟，内部使用 `blk_mem_gen_awb_delay_signal` |

### 2.2 MIPI / CSI

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/mipi_dphy_rx/mipi_dphy_rx_ph1p_mipiio_wrapper.sv` | MIPI D-PHY 顶层 |
| `user_source/hdl_source/mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v` | MIPI IO 接收 |
| `user_source/hdl_source/mipi_dphy_rx/byte_aligner.enc.v` | 字节对齐 |
| `user_source/hdl_source/mipi_dphy_rx/byte_aligner_wrapper.enc.sv` | 字节对齐封装 |
| `user_source/hdl_source/mipi_dphy_rx/channel_aligner.enc.v` | Lane 对齐 |
| `user_source/hdl_source/mipi_dphy_rx/channel_aligner_wrapper.enc.sv` | Lane 对齐封装 |
| `user_source/hdl_source/mipi_dphy_rx/hs_detect.enc.v` | HS 检测 |
| `user_source/hdl_source/isp/csi_unpacket_2lane.v` | CSI-2 解包 |
| `user_source/hdl_source/isp/raw10_unpacket_2lane.v` | RAW10 重组 |
| `user_source/hdl_source/isp/uial2axis.v` | RAW 流转 AXI Stream |

### 2.3 ISP / 去马赛克

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/isp/isp_top.v` | ISP 顶层：demosaic、AWB、打包 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/demosaic.v` | demosaic 顶层 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v` | 双线性插值 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v` | 行缓存 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v` | 3×3 RAW 窗口 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v` | RAW 转换 |
| `user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v` | 去马赛克整合 |
| `user_source/hdl_source/isp/data128_96/data128_96.v` | 128→96 位 |
| `user_source/hdl_source/isp/data96_128/data96_128.v` | 96→128 位 |
| `user_source/hdl_source/awb_frame_stable.v` | 帧级稳定 AWB，内含 `awb_frame_divider` |

> `isp_top.v` 中的 `axis_gamma_rgb96` 是未实例化的历史模块。

### 2.4 摄像头配置

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/uics520_cfg/uicfgcs520.v` | SC520 配置状态机 |
| `user_source/hdl_source/uics520_cfg/uics520reg_720p60.v` | 720p60 寄存器表 |
| `user_source/hdl_source/uics520_cfg/uics520regAE.v` | AE 寄存器 |
| `user_source/hdl_source/uics520_cfg/SC520GainTbl.v` | 增益表 |
| `user_source/hdl_source/uics500_cfg/uii2c.v` | I2C |
| `user_source/hdl_source/uiisp_beta/ae_set.v` | AE 控制 |

### 2.5 视频存储 / 显示

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v` | DDR2 控制器 |
| `user_source/hdl_source/vtc/uivtc.v` | 720p 视频时序 |
| `user_source/hdl_source/hdmi_mixer.v` | Logo、anlu CNT、ROI 坐标、右侧 HUD、目标框 |
| `user_source/hdl_source/osd_char_lib.v` | 16×16 字符库 |
| `user_source/hdl_source/hdmi_tx.v` | HDMI 发送封装 |
| `user_source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v` | HDMI 1.4b 加密核 |
| `user_source/hdl_source/hdmi_phy_warpper.v` | HDMI PHY |
| `user_source/hdl_source/lane_lvds_10_1.v` | TMDS lane |
| `user_source/hdl_source/audio_arc_calculate.v` | 音频 ARC |
| `user_source/hdl_source/I2S_receiver.v` | I2S |
| `user_source/hdl_source/key_remove_shakes.v` | 按键去抖 |

### 2.6 识别 / 舵机

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/track2/roi_target_tracker.v` | 绿色单/多目标检测、连通域、多槽位 |
| `user_source/hdl_source/track2/visual_servo_pwm.v` | pan/tilt PWM、步长、D 阻尼 |

### 2.7 颜色 / 风格化 / 轨迹

| 文件 | 作用 |
|---|---|
| `user_source/hdl_source/video/scene_color_stream.v` | 显示/ROI 共享流、3×3 接入（当前开启） |
| `user_source/hdl_source/video/display_color_shading.v` | 3×3 R/B 双线性增益（当前开启） |
| `user_source/hdl_source/video/display_edge_color.v` | 边缘 R/B 修正，当前 ENABLE=0 作为六拍旁路 |
| `user_source/hdl_source/video/video_enhance.v` | 全局亮度/对比度/饱和度/锐化；当前全局 ×1.0，1.2 已关闭 |
| `user_source/hdl_source/video/display_common_tone.v` | 公共 tone |
| `user_source/hdl_source/video/roi_center_osd.v` | 中心 ROI 坐标 OSD，透明底 |
| `user_source/hdl_source/video/roi_background_stylize.v` | 背景风格化 |
| `user_source/hdl_source/video/roi_motion_trail.v` | 一秒轨迹 |
| `user_source/hdl_source/video/style_switch_control.v` | SW2/SW3 同步 |

### 2.8 IP

| 文件 | 作用 |
|---|---|
| `user_source/ip_source/PLL/PLL.xml` | PLL |
| `user_source/ip_source/w128_d512_fifo/w128_d512_fifo.xml` | 128 位 FIFO |
| `user_source/ip_source/w155_d512_fifo/w155_d512_fifo.xml` | 155 位 FIFO |
| `user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.xml` | AWB 延迟 RAM |
| `user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.xml` | DDR2 IP |
| `user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.xml` | demosaic 行缓存 RAM |
| `user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.xml` | demosaic 整合 RAM |

### 2.9 约束

| 文件 | 作用 |
|---|---|
| `camera_to_dsi_display.sdc` | 时钟与时序约束 |
| `user_source/constraints_source/pin.adc` | 引脚约束，SW1-SW4、摄像头、HDMI、舵机 |

---

## 3. AutoExcluded 条目

以下条目在 `.al` 中标记为 `AutoExcluded`，当前不参与综合：

| 文件 | 状态 | 说明 |
|---|---|---|
| `user_source/hdl_source/awb.v` | 排除 | 官方旧 AWB，当前用 `awb_frame_stable.v` |
| `user_source/hdl_source/anlogic_logo_rom.v` | 排除 | 旧 Logo ROM，当前 Logo 在 `hdmi_mixer` 内 |
| `user_source/hdl_source/track2/red_mask_contour.v` | 排除 | 旧红色检测 |
| `user_source/hdl_source/isp/raw_measured_shading.v` | 排除 | 已从 `isp_top` 移除 |
| `user_source/hdl_source/video/white_field_rgb_osd.v` | 排除 | 九宫格调试，`CALIBRATION_MODE=0` |
| `user_source/ip_source/divider/divider.ipc` | 排除 | 旧 AWB 除法器 |

这些文件暂时保留，不在最终数据通路中。

---

## 4. 不在工程源列表中的备份/归档

```text
user_source/hdl_source/design_top_wrapper.before_fast_image.v
user_source/hdl_source/design_top_wrapper.grid_diagnostic.v
user_source/hdl_source/video/white_field_rgb_osd.before_grid.v
```

这些是调试备份，不属于当前工程。

---

## 5. 隐式资源

以下文件不在 `.al` 的 Verilog 列表里，但会被 RTL 通过 `INIT_FILE` 读取：

```text
user_source/hdl_source/video/shading_row0.mif
user_source/hdl_source/video/shading_row1.mif
user_source/hdl_source/video/shading_row2.mif
user_source/hdl_source/official_logo_index0.mif
user_source/hdl_source/official_logo_index1.mif
user_source/hdl_source/official_logo_index2.mif
user_source/hdl_source/official_logo_palette.mif
```

修改 3×3 节点后：

```text
python tools/resource_combo_20261030/generate_shading_rom.py
```

---

## 6. 源文件维护规则

```text
1. 只把生产 RTL 放进 .al
2. 不递归添加 sim / doc / 备份目录
3. 修改 3×3 后必须重新生成 MIF
4. 修改颜色/识别后重新跑综合和布局布线
5. 不把 AutoExcluded 文件重新启用，除非明确需要旧功能
```

---

## 7. 与最终构建的关系

最终 bit：

```text
td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit
2026-10-31 20:06:19
```

最终时序：

```text
Setup WNS +0.266 ns
Hold  WNS +0.021 ns
```

最终资源：

```text
Slice 19,729 / 21,216 = 92.99%
ERAM  106 / 108
DSP   25 / 40
```

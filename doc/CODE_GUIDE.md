# Anlu2 统一代码介绍

> 本文是当前工程的唯一代码总览，替代 2026-10-24 的旧版 `CODE_GUIDE.md`。
> 旧版代码指南已移出交付目录，不再随工程提交。
> 最后更新：2026-10-31

---

## 1. 工程目标

基于安路 PH1P35 的 **MIPI 摄像头 → FPGA 图像处理 → DDR → HDMI 显示 + 绿色目标识别 + 舵机控制** 工程。

主要功能：

```text
SC520CS MIPI 摄像头输入
ISP / demosaic / AWB
DDR 帧缓存
HDMI 1280×720 @ 60 Hz
单目标绿色检测
多目标检测（最多 8 个）
舵机 pan/tilt 控制
背景风格化
一秒运动轨迹
目标框 / 坐标 / 计数 HUD
```

最终交付 bit：

```text
D:\Anlogic\Anlu2\td_project\camera_to_dsi_display_Runs\phy_1\camera_to_dsi_display.bit
生成时间：2026-11-01 14:01:32
SHA256：4C362804A7F0C57101112EF6FBD9E6EA1492FECD8FD34A3151407A29A2553996
```

---

## 2. 顶层接口

顶层：

```text
user_source/hdl_source/design_top_wrapper.v
module design_top_wrapper #(parameter integer CAMERA_ROTATE_180=1)
```

### 2.1 主要输入

| 信号 | 说明 |
|---|---|
| `I_sys_clk` | 50 MHz 板载时钟 |
| `I_rst_n` | 外部低有效复位 |
| `I_sw1` | 舵机控制使能，1=开，0=保持 |
| `I_sw2` | 风格化 + 一秒轨迹 |
| `I_sw3` | 多目标识别 |
| `I_sw4` | 舵机 HOME 复位，0→1 触发 |
| `I_button[0]` | 降低曝光 AE，低有效，D5 |
| `I_button[1]` | 提高曝光 AE，低有效，A9 |
| `IO_cam_sda` / `O_cam_scl` | 摄像头 I2C |
| MIPI 差分输入 | 2-lane CSI |

SW 引脚：

```text
SW1 = A4
SW2 = B4
SW3 = E11
SW4 = D11
```

曝光：

```text
默认 AE = 498 半行
范围 = 2 ～ 1991
D5 = 降低曝光
A9 = 提高曝光
按住持续调整
```

### 2.2 主要输出

```text
O_cam_scl / O_cam_24m / O_cam_pwdn
O_servo_pan / O_servo_tilt
O_tmds_ch0_p / O_tmds_ch1_p / O_tmds_ch2_p / O_tmds_clk_p
DDR2 接口
```

---

## 3. 时钟与复位

### 3.1 时钟域

| 时钟 | 用途 |
|---|---|
| `I_sys_clk` 50 MHz | 舵机、控制、部分配置 |
| `S_csi_rx_clk` | MIPI/CSI 接收 |
| `S_ddr_clk` | DDR 控制器 |
| `S_hdmi_pixel_clk` | 约 75 MHz 像素时钟 |
| `S_hdmi_serial_clk` | HDMI 串行时钟 |
| `S_24m_clk` | 摄像头配置/电源时序 |

### 3.2 主复位

```verilog
assign S_rst_n      = S_pll_lock;
assign S_hdmi_rst_n = S_pll_lock;
```

外部 `I_rst_n` 先复位 PLL；PLL 失锁会复位全系统，锁定后释放。

### 3.3 舵机复位

舵机有独立复位：

```verilog
S_servo_rst_n = I_rst_n && !S_servo_home_rst;
```

SW4 行为：

```text
SW4 0 → 1
  → 等待 2 秒
  → 舵机复位 2 秒
  → 自动释放
```

复位期间：

```text
pan  = 512
tilt = 656
PWM  = HOME
```

即使 SW4 保持 1，也只复位一次；必须回到 0 再 1 才能再次触发。

---

## 4. 视频主链路

```text
MIPI CSI-2 RAW10
  ↓
CSI 解包 / RAW10 整理
  ↓
demosaic（BGGR）
  ↓
data128_96
  ↓
awb_frame_stable
  ↓
data96_128
  ↓
video_in → DDR 帧缓存
  ↓
video_out（180° 旋转）
  ↓
hdmi_mixer
  ↓
scene_color_stream（display_color_shading 3×3）
  ↓
display_edge_color（ENABLE=0，六拍旁路）
  ↓
video_enhance（ENABLE=0，全局 ×1.0；1.2 已关闭）
  ↓
display_common_tone
  ↓
roi_background_stylize
  ↓
roi_motion_trail
  ↓
multi_target_overlay
  ↓
hdmi_tx
  ↓
HDMI 1280×720 @ 60Hz
```

### 4.1 当前生效

```text
AWB              开启
显示端 3×3       开启
RAW 静态阴影     关闭/未实例化
全局 1.2         关闭
公共 tone        开启
```

---

## 5. 模块目录

### 5.1 顶层与显示

| 文件 | 模块 | 作用 |
|---|---|---|
| `design_top_wrapper.v` | `design_top_wrapper` | 顶层，连接摄像头、ISP、DDR、HDMI、识别和舵机 |
| `video_in.v` | `video_in` | 摄像头数据写入 DDR |
| `video_out.v` | `video_out` | DDR 读出、180° 旋转 |
| `hdmi_mixer.v` | `hdmi_mixer` | Logo、anlu CNT、ROI 坐标、右侧 HUD、目标框 |
| `hdmi_mixer.v` | `multi_target_overlay` | 多目标框和右侧状态 HUD |
| `hdmi_tx`（IP/封装） | `hdmi_tx` | HDMI 发送 |

### 5.2 ISP / 摄像头

| 文件 | 模块 | 作用 |
|---|---|---|
| `isp/isp_top.v` | `isp_top` | ISP 顶层 |
| `isp/csi_unpacket_2lane.v` | CSI 解包 | 2-lane MIPI |
| `isp/raw10_unpacket_2lane.v` | RAW10 整理 | RAW10 对齐 |
| `isp/demosaic_4x_2_0/*` | `demosaic` | Bayer → RGB |
| `awb_frame_stable.v` | `awb_frame_stable` | 帧级 AWB |
| `signal_delay.v` | `signal_delay` | AWB 50 拍延迟 |
| `uics520_cfg/*` | 摄像头配置 | SC520 寄存器/I2C |

> `awb.v` 是官方旧 AWB，当前没有使用，工程中为 AutoExcluded。
> `raw_measured_shading.v` 当前未实例化。

### 5.3 颜色 / 显示后处理

| 文件 | 模块 | 作用 |
|---|---|---|
| `video/scene_color_stream.v` | `scene_color_stream` | 显示/ROI 共享流、3×3 颜色校正接入（当前开启） |
| `video/display_color_shading.v` | `display_color_shading` | 3×3 R/B 双线性增益 |
| `video/display_edge_color.v` | `display_edge_color` | 边缘 R/B 修正；当前旁路 |
| `video/video_enhance.v` | `video_enhance` | 全局亮度/对比度/饱和度/锐化；当前全局 ×1.0，1.2 已关闭 |
| `video/display_common_tone.v` | `display_common_tone` | 公共亮度 tone |
| `video/roi_center_osd.v` | `roi_center_osd` | 中心 ROI 坐标 OSD，透明底 |

### 5.4 识别 / 跟踪

| 文件 | 模块 | 作用 |
|---|---|---|
| `track2/roi_target_tracker.v` | `roi_target_tracker` | 绿色单/多目标检测 |
| 同上 | `green_region_tracker` | 连通域 |
| 同上 | `multi_target_slots` | 8 槽位多目标 |
| `track2/red_mask_contour.v` | — | 旧红色检测，当前未使用 |

### 5.5 风格化 / 轨迹

| 文件 | 模块 | 作用 |
|---|---|---|
| `video/roi_background_stylize.v` | `roi_background_stylize` | 背景风格化 |
| 同上 | `style_status_osd` | 风格化状态 |
| `video/roi_motion_trail.v` | `roi_motion_trail` | 一秒轨迹 |
| 同上 | `roi_multi_trail_samples` | 多目标轨迹采样（三级流水） |
| `video/style_switch_control.v` | `style_switch_control` | SW2/SW3 同步 |

### 5.6 舵机

| 文件 | 模块 | 作用 |
|---|---|---|
| `track2/visual_servo_pwm.v` | `visual_servo_pwm` | pan/tilt PWM 与步进控制 |

---

## 6. 颜色链路

### 6.1 AWB

```text
AWB_ENABLE = 1
```

`awb_frame_stable`：

- 每帧统计有效像素；
- 计算 R/B 全局增益；
- G 不变；
- 帧起始更新；
- 平滑逼近；
- 排除过暗/过曝点。

### 6.2 3×3 显示端颜色校正（当前开启）

`display_color_shading` 当前启用，使用以下 9 节点 R/B 增益。

- 9 个节点；
- 水平/垂直双线性插值；
- 只调 R/B；
- G 不变；
- 黑电平枢轴 14；
- 节点位置：

```text
x: 64 / 640 / 1216
y: 32 / 360 / 688
```

当前 R：

```text
204  282  192
197  327  185
185  249  183
```

当前 B：

```text
228  257  240
229  281  237
227  251  243
```

### 6.3 MIF

硬件读取：

```text
shading_row0.mif
shading_row1.mif
shading_row2.mif
```

修改 9 个节点后必须执行：

```text
python tools/resource_combo_20261030/generate_shading_rom.py
```

否则 bit 不会更新。

### 6.4 全局亮度 / tone

```text
RGB_GAIN_Q8 = 256  // 1.0 倍，1.2 已关闭
display_common_tone // 公共曲线
```

---

## 7. 绿色目标识别

参数：

```text
MIN_VALUE   = 24
MIN_AREA    = 64
MAX_AREA    = 120000
HIGHLIGHT_G = 248
```

判定：

```text
G >= R
G >= B
chroma >= 10
chroma >= G/4
2*|R-B| <= chroma
G >= 24
高亮白点抑制
```

3×3 去噪：

```text
邻域绿色像素 >= 3
```

连通域：

```text
16×16 tile
4 邻域 flood fill
bbox / 面积 / 中心
```

多目标：

```text
MULTI_ENABLE = 1
MAX_TARGETS  = 8
ASSOC_DISTANCE = 128
HOLD_FRAMES = 1
```

---

## 8. 舵机控制

### 8.1 PWM

```text
50 Hz
0.5 ms ～ 2.5 ms
```

### 8.2 位置

```text
pan  home 512，0～1024
tilt home 656，512～800
deadband 50
```

### 8.3 步长

pan：

```text
近距：step = 1 + (error >> 6)，上限 8
超过 300：线性加速
边缘最大 21
周期 10 ms
```

tilt：

```text
近距：step = 1 + (error >> 6)，上限 6
超过 192：加速
边缘最大 27
周期 50 ms
```

D 项：

```text
Kd = 0.5
D = 上一步步长 >> 1
pan 300～560 启用
tilt 192～320 启用
```

### 8.4 SW4

```text
SW4 = D11
0→1：延时 2 秒
复位：2 秒
然后自动释放
```

---

## 9. 显示 UI

### 9.1 右侧 HUD

七行：

```text
MODE:SINGLE / MODE:MULTI
N:x  TOT:xxxxxx  +  L
SERVO:ON / SERVO:OFF
LAT:xxxxxx US
DET:xxxxxx US
FID:xxxx
1 2 3 4 5 6 7 8
```

说明：

- `N`：有效目标数；
- `TOT`：候选目标总数；
- `+`：超过最大槽位；
- `L`：处理迟到；
- `SERVO`：SW1 状态；
- `LAT`：目标结果年龄；
- `DET`：检测耗时；
- `FID`：帧号；
- 最后一行：目标框颜色编号。

### 9.2 中心 ROI 坐标

- 透明底；
- 只叠加字符；
- 多目标或舵机控制时隐藏；
- `anlu CNT` 保留。

### 9.3 Logo

- 左上角；
- 由 `anlogic_logo_eram` 提供；
- OSD/颜色处理不覆盖 Logo。

---

## 10. 构建流程

### 10.1 工程

```text
D:\Anlogic\Anlu2\td_project\camera_to_dsi_display.al
```

### 10.2 综合时序优先

```tcl
gate map_mode logic_level_prior
gate map_strategy 3
gate pack_effort high
rtl min_control_set 8
```

### 10.3 布局布线时序优先

```tcl
place effort high
place opt_timing high
place post_place_opt high
place pack_effort high
place pr_strategy 7
route post_route_opt high
```

### 10.4 最终结果

```text
Setup WNS : +0.117 ns
Setup TNS :  0.000 ns
Hold WNS  : +0.020 ns
Hold TNS  :  0.000 ns
```

资源：

```text
Slice 16,974 / 21,216 = 80.01%
LUT6  16,236 / 21,216 = 76.53%
ERAM  106 / 108
DSP   22 / 40
```

---

## 11. 未使用/历史代码

这些文件目前不在最终数据通路中：

```text
awb.v
raw_measured_shading.v
red_mask_contour.v
white_field_rgb_osd.v（仅 CALIBRATION_MODE=1）
```

不要误删的“看似未启用”模块：

```text
display_edge_color.v   // 提供 6 拍旁路
video_enhance.v        // 全局 1.2 已关闭，当前 ×1.0
signal_delay.v         // AWB 50 拍延迟
scene_position_color_bias.v // generate 分支仍引用
```

最终清理策略见 `PROJECT_LOG_UNIFIED.md`。

---

## 12. 调试与常见问题

### 画面全绿

- 检查 AWB 是否开启；
- 检查 3×3 是否真正加载 MIF；
- 修改 3×3 后是否重新生成 MIF。

### 3×3 改了没变化

- 只改了 RTL 函数，没有重新生成 MIF；
- 或综合没有重新读取 MIF。

### ROI 坐标铺满屏幕

- `hit` 必须同时受 HUD 区域和 `glyph_on` 限制。

### 多目标 HUD 第二行丢失

- 检查 `N/TOT` 行是否被 SERVO 行覆盖；
- 当前顺序是 MODE / N-TOT / SERVO / LAT / DET / FID / 颜色。

### 时序不足

- 优先检查 `roi_motion_trail` 的 `roi_multi_trail_samples`；
- 保持三级流水；
- 不要回退到 `area_prior`。

### SW4 不触发

- 必须看到 0→1 的上升沿；
- 上电时 SW4 已是 1 不会触发；
- 复位期间拉回 0 会中止本次流程。

---

## 13. 关联文档

- `PROJECT_LOG_UNIFIED.md`：统一日志、阶段记录、资源/时序历史。
- `SOURCE_INVENTORY.md`：当前 `.al` 源文件、AutoExcluded 和隐式 MIF 清单。
- `SHADING_GAINS_20261031.md`：3×3 增益快照（当前 3×3 已开启）。
- `doc/` 历史资料已移出交付目录。

---

## 14. 分辨率与算法扩展边界

### 14.1 1080p

结论：

```text
1280×720@60：当前实现
1920×1080@30：可行，但未实现
1920×1080@60：不可行
```

原因：

- SC520CS 的 1080p 是 1×1 Crop，手册标称 30 fps；
- 720p60 使用 2×2 binning；
- 2-lane MIPI 带宽不足以支持 1080p60；
- 传感器读出上限也没有余量；
- 当前 PLL 只能给 75 MHz，无法产生标准 1080p60 的 148.5 MHz；
- 1080p30 可以用 75 MHz / (2200×1125) ≈ 30.303 Hz。

当前未实现 1080p 的原因：

```text
需要更大的帧缓存和像素吞吐
当前 Slice 已到 80.01%
当前 ERAM 已到 106/108
时序余量只有 +0.117 ns
```

### 14.2 未采用的算法

| 方案 | 当前状态 | 原因 |
|---|---|---|
| 逐像素 LSC | 未采用 | 需要巨大 ERAM/外部 DDR 表 |
| 5×5 颜色节点 | 未采用 | 资源和时序成本高 |
| 完整像素级 CCL | 未采用 | 行缓存和标签资源大 |
| MHC/边缘引导去马赛克 | 未采用 | 行缓存和乘法增加 |
| 完整 PID / α-β / Kalman | 未采用 | 当前 PD/分段步长已能满足 |
| 整帧彩色轨迹历史 | 未采用 | 需要大量 ERAM |

### 14.3 画质口径

- 检测读取显示增强前的相机 RGB；
- OSD/Logo/目标框受保护，不参与检测；
- AWB 是全局增益，不能修空间色偏；
- 当前没有通用像素级分割，相邻/重叠目标可能合并；
- 历史红色检测文档和旧资源数据不能用于当前版本。

---

## 15. 交付结论

```text
代码：当前 tree
bit ：camera_to_dsi_display.bit（2026-11-01 14:01:32）
时序：Setup +0.117 ns / Hold +0.020 ns
资源：Slice 80.01% / ERAM 106/108
```

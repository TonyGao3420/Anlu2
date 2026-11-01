# Anlu2 工程统一日志

> 本文把 `doc/` 下分散的阶段报告、调试日志、上板记录和资源记录合并为一份总日志。
> 原始文件仍保留，用于追溯细节；日常查阅以本文为准。
> 最后更新：2026-10-31

---

## 0. 最终交付状态

### 0.1 最终 bit

```text
D:\Anlogic\Anlu2\td_project\camera_to_dsi_display_Runs\phy_1\camera_to_dsi_display.bit
生成时间：2026-10-31 20:06:19
```

压缩版：

```text
camera_to_dsi_display_compress.bit
```

### 0.2 最终时序

```text
Setup WNS : +0.266 ns
Setup TNS :  0.000 ns
Setup 违例:  0
Hold WNS  : +0.021 ns
Hold TNS  :  0.000 ns
Hold 违例 :  0
```

综合 gate 阶段约：

```text
WNS -1.029 ns
```

最终布局布线后转正，以 route 结果为准。

### 0.3 最终资源

| 资源 | 使用 | 总量 | 占用 |
|---|---:|---:|---:|
| Slice | 19,729 | 21,216 | 92.99% |
| LUT6 | 19,203 | 21,216 | 90.51% |
| ERAM | 106 | 108 | 98.15% |
| DSP | 25 | 40 | 62.50% |

时序余量很小，后续新增逻辑必须重新跑完整流程。

### 0.4 最终启用功能

```text
MIPI CSI-2 / SC520CS 摄像头输入
720p60 HDMI 输出
ISP demosaic
AWB 自动白平衡
显示端 3×3 R/B 颜色校正：开启
全局 1.2 倍亮度：已关闭
公共 tone
单目标识别
多目标识别（最多 8 个）
舵机 pan/tilt PWM 控制
风格化
一秒轨迹
多目标框
中心 ROI 坐标 OSD（透明底）
Logo / anlu CNT / 右侧状态 HUD
SW1 舵机使能
SW2 风格化
SW3 多目标
SW4 舵机 HOME 复位
```

最终关闭/移除：

```text
RAW 静态阴影校正：已从数据通路移除
白场九宫格调试：关闭
CALIBRATION_MODE：0
```

---

## 1. 工程阶段时间线

| 时间 | 阶段 | 主要结果 |
|---|---|---|
| 2026-10-08 | 绿色 ROI 基线 | 绿色目标检测、bbox、单目标跟踪 |
| 2026-10-09 | 官方显示链路 | MIPI→ISP→DDR→HDMI 720p 打通 |
| 2026-10-09 | RAW 颜色/亮度 | RAW 域颜色与亮度修正试验 |
| 2026-10-09 | 颜色诊断 | 九区 RAW/RGB 诊断、AWB 与颜色链路分析 |
| 2026-10-10 | 边缘颜色 | 画面边缘残留色修正 |
| 2026-10-11 | ROI 中心坐标 | ROI 中心相对屏幕原点的 OSD |
| 2026-10-18 | 工程分析 | 全链路、模块、资源和风险梳理 |
| 2026-10-24 | 文档整理 | 中文代码结构与阶段报告 |
| 2026-10-25 | ERAM/GUI/风格化 | ERAM 优化、GUI 编译修复、风格化接入、1 秒轨迹 |
| 2026-10-26 | 模型风格/Track2 | 模型风格、Track2 需求和上板检查 |
| 2026-10-27 | 三项修正 | 颜色、ROI、显示相关修正 |
| 2026-10-28 | 四种模式/空间偏置 | 四模式整合、ROI 原点回退、空间颜色偏置 |
| 2026-10-30 | 八目标轨迹/资源组合 | 8 目标轨迹、风格化与多目标组合、资源优化 |
| 2026-10-31 | 颜色合并/最终 UI/时序 | AWB/3×3 调整、最终 HUD、SW4、motion trail 流水线、时序转正 |

---

## 2. 视频主链路

最终链路：

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
hdmi_mixer（Logo / anlu CNT / 右侧 HUD / 目标框）
  ↓
scene_color_stream（display_color_shading 3×3，当前开启）
  ↓
display_edge_color（ENABLE=0，六拍旁路）
  ↓
video_enhance（ENABLE=0，RGB_GAIN_Q8=256）
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

说明：

- `raw_measured_shading` 已从 `isp_top` 中移除；
- `awb_frame_stable` 使用自定义帧级稳定 AWB；
- `display_color_shading` 使用 3 张 MIF ROM，当前 `RGB_SHADING_ENABLE=1`；
- `display_edge_color` 当前只作为固定延迟旁路；
- `video_enhance` 的全局增益当前为 ×1.0（1.2 已关闭）；
- 白场九宫格调试模块只在 `CALIBRATION_MODE=1` 时存在，最终模式为 0。

---

## 3. 目标识别与跟踪

### 3.1 颜色判定

参数：

```text
MIN_VALUE   = 24
MIN_AREA    = 64
MAX_AREA    = 120000
HIGHLIGHT_G = 248
```

绿色判定：

```text
G >= R
G >= B
chroma = G - min(R,B) >= 10
chroma >= G/4
2*|R-B| <= chroma
G >= MIN_VALUE
高亮白点抑制
```

再做 3×3 邻域去噪：

```text
3×3 内绿色像素数 >= 3
```

### 3.2 连通域

- 16×16 tile；
- 垂直消隐期间 flood fill；
- bbox、面积、中心；
- 单目标关联/选择；
- 多目标最多 8 槽位，关联距离 128，hold 1 帧。

### 3.3 多目标

```text
MULTI_ENABLE = 1
MAX_TARGETS  = 8
```

多目标框颜色编号与右侧 HUD 第 7 行对应。

---

## 4. 颜色处理阶段

### 4.1 AWB

`awb_frame_stable.v`：

- 全局 R/B 自动增益；
- 每帧统计；
- 排除过暗和过曝点；
- 帧起始更新；
- 平滑逼近；
- G 不变。

最终状态：

```text
AWB_ENABLE = 1
```

### 4.2 RAW 阴影

已从数据通路删除，不再使用 36 节点静态阴影校正。

### 4.3 3×3 显示端颜色校正（当前开启）

当前 `RGB_SHADING_ENABLE=1`，3×3 参与显示。

```text
x：64 / 640 / 1216
y：32 / 360 / 688
```

R 增益：

```text
204  282  192
197  327  185
185  249  183
```

B 增益：

```text
228  257  240
229  281  237
227  251  243
```

G 不变。

### 4.4 MIF 必须重新生成

`display_color_shading` 硬件读取：

```text
shading_row0.mif
shading_row1.mif
shading_row2.mif
```

修改 9 个节点后必须执行：

```text
python tools/resource_combo_20261030/generate_shading_rom.py
```

否则改动不会进入 bit。

### 4.5 全局亮度与 tone

```text
RGB_GAIN_Q8 = 256  // 1.0 倍，1.2 已关闭
display_common_tone  // 公共亮度曲线
```

---

## 5. 风格化、轨迹与多目标

### 5.1 风格化

`roi_background_stylize`：

- SW2 使能；
- 背景灰度/简化；
- 保留 ROI 彩色；
- 状态 HUD；
- 多 ROI 并集；
- 显示端处理，不反馈检测。

### 5.2 一秒轨迹

`roi_motion_trail`：

- 历史按毫秒时间戳；
- TTL 1000 ms；
- 采样间隔 50 ms；
- 中值/跳变保护；
- 单目标与多目标轨迹；
- 仅显示，不影响检测和舵机。

### 5.3 最终时序优化

对 `roi_multi_trail_samples` 做了三级流水：

```text
Stage 1：槽位 bbox/valid/历史值捕获
Stage 2：px/py、median、restart、dx/dy
Stage 3：candidate、gx/gy、link、写回
```

效果：

```text
motion trail 20 级组合路径
→ 三级流水
→ 最终 WNS +0.266 ns
```

三个时钟/槽位，采样间隔 50 ms，不影响功能。

---

## 6. 舵机控制

### 6.1 PWM

```text
50 Hz
0.5 ms ～ 2.5 ms
```

### 6.2 位置与步长

```text
pan  home 512，范围 0～1024
tilt home 656，范围 512～800
deadband 50
```

pan：

```text
近距 step = 1 + (error >> 6)，上限 8
超过 300 后线性加速
边缘最大 21
周期 10 ms
```

tilt：

```text
近距 step = 1 + (error >> 6)，上限 6
超过 192 后加速
边缘最大 27
周期 50 ms
```

D 项：

```text
Kd = 0.5
D = 上一步步长 >> 1
pan 在 300～560 启用
tilt 在 192～320 启用
```

### 6.3 SW4 复位

```text
SW4 = D11
```

行为：

```text
SW4 0 → 1
  ↓
等待 2 秒
  ↓
舵机 HOME 复位 2 秒
  ↓
自动释放，即使 SW4 仍为 1
```

复位期间：

```text
pan  = 512
tilt = 656
PWM  = HOME
```

SW4 回到 0 后重新武装。

---

## 7. 显示 UI

### 7.1 右侧 HUD

位于右上角，共 7 行：

```text
MODE:SINGLE / MODE:MULTI
N:x  TOT:xxxxxx  +  L
SERVO:ON / SERVO:OFF
LAT:xxxxxx US
DET:xxxxxx US
FID:xxxx
1 2 3 4 5 6 7 8
```

含义：

- MODE：单/多目标；
- N：有效目标数；
- TOT：候选目标总数；
- `+`：超过最大槽位；
- `L`：处理迟到；
- SERVO：SW1 舵机控制状态；
- LAT：目标结果年龄；
- DET：检测处理耗时；
- FID：帧号；
- 最后一行：目标框颜色编号。

### 7.2 中心 ROI 坐标

- 已改成透明底；
- 只叠加字符笔画；
- 不再有黑色矩形背景；
- 在多目标或舵机控制时隐藏；
- `anlu CNT` 始终保留。

### 7.3 Logo / anlu CNT

- 左上 Logo；
- 动态 `anlu CNT:xxxxxx`；
- 帧计数始终保留。

---

## 8. 资源与实现记录

### 8.1 资源优化阶段

历史措施：

- 3×3 水平插值 ROM 化，节省 LUT；
- ERAM 节点表；
- 多目标槽位复用；
- 风格化/轨迹共用视频缓存；
- 移除未使用 RAW 阴影；
- 面积优先阶段曾把 slice 降到 77.96%，但时序余量不足。

### 8.2 最终时序优先

综合：

```tcl
gate map_mode logic_level_prior
gate map_strategy 3
gate pack_effort high
rtl min_control_set 8
```

布局布线：

```tcl
place effort high
place opt_timing high
place post_place_opt high
place pack_effort high
place pr_strategy 7
route post_route_opt high
```

### 8.3 时序演变

```text
上一版 SWNS -2.206 ns，47 违例
时序优先 + motion trail 流水线后
最终 WNS +0.266 ns，0 违例
```

---

## 9. 已知问题与限制

1. **时序余量极小**  
   `+0.266 ns`，任何新增逻辑都可能再次违例。

2. **ERAM 接近满**  
   106/108，新增表/缓存空间很小。

3. **AWB 是全局平均**  
   大面积单色目标仍可能影响白平衡。

4. **3×3 分辨率有限**  
   只能做空间平滑校正，不能精准修最外圈 128 像素。

5. **MIF 与 RTL 分离**  
   修改 3×3 节点后必须重新生成 MIF。

6. **SW4 复位是单次脉冲**  
   必须重新 0→1 才能再次触发。

7. **综合 gate WNS 仍为负**  
   最终 route 转正；若综合阶段也必须为正，需要继续优化或降低约束。

---

## 10. 构建与上板检查

### 10.1 构建

```text
D:\Anlogic\Anlu2\td_project\camera_to_dsi_display.al
```

流程：

```text
综合 → 布局 → 布线 → bitgen
```

### 10.2 上板检查

- 720p60 HDMI 有画面；
- AWB 稳定后颜色正常；
- 单目标框；
- 多目标框；
- 右侧 HUD 七行；
- SW1 控制舵机；
- SW2 风格化；
- SW3 多目标；
- SW4 0→1 后 2 秒延时、2 秒 HOME 复位；
- 中心 ROI 坐标透明、多目标/舵机时隐藏；
- Logo 与 anlu CNT 正常。

---

## 11. 原始文档索引

> 以下仅为历史索引。旧报告、图片、参考代码、docx 和 JSON 已移出 `Anlu2` 交付目录，不在当前工程内。
> 文件名保留用于追溯，不再对应工程内路径。

### 11.1 早期链路与算法

| 文件 | 内容 |
|---|---|
| `GREEN_ROI_20261008.md` | 绿色 ROI 基线 |
| `ROI_COLOR_REVIEW_20261008.md` | ROI 颜色审查 |
| `ROI_HEIGHT_ROLLBACK_20261008.md` | ROI 高度回退 |
| `OFFICIAL_DISPLAY_20261009.md` | 官方显示链路核对 |
| `RAW_COLOR_BRIGHT_20261009.md` | RAW 颜色/亮度 |
| `SHARED_COLOR_GREEN_ROI_20261009.md` | 共享颜色与绿色 ROI |
| `EDGE_COLOR_20261009.md` | 边缘颜色 |
| `DISPLAY_COLOR_TRIAL_20261009.md` | 显示颜色试验 |
| `COLOR_DIAGNOSTIC_20261009.md` | 颜色诊断 |
| `EDGE_REFINE_MAIN_20261010.md` | 边缘修正 |
| `ROI_CENTER_20261011.md` | ROI 中心坐标 |
| `ROI_SCREEN_ORIGIN_20261011.md` | ROI 屏幕原点 |
| `ALGORITHM_RESEARCH.md` | 算法研究 |
| `VIDEO_QUALITY.md` | 视频质量 |

### 11.2 工程分析与结构

| 文件 | 内容 |
|---|---|
| `PROJECT_ANALYSIS_20261018.md` | 工程整体分析 |
| `CODE_GUIDE_20261024.md` | 旧代码指南（历史版，已移出） |
| `architecture.md` | 架构摘要 |
| `代码结构说明报告.md` | 中文代码结构 |
| `阶段一报告.md` | 阶段一报告 |
| `1080p可行性分析.md` | 1080p 可行性 |
| `source_descriptions.json` | 旧源文件描述（已移出） |
| `source_inventory.json` | 旧源文件清单（已移出） |

### 11.3 风格化/轨迹/多目标

| 文件 | 内容 |
|---|---|
| `ERAM_OPTIMIZATION_20261025.md` | ERAM 优化 |
| `GUI_COMPILE_FIX_20261025.md` | GUI 编译修复 |
| `STYLE_MODE_INTEGRATION_20261025.md` | 风格化接入 |
| `TRAIL_1S_SMOOTH_20261025.md` | 1 秒平滑轨迹 |
| `THREE_MODE_BOARD_CHECK_20261025.md` | 三模式上板 |
| `MODEL_STYLE_20261026.md` | 模型风格 |
| `MODEL_STYLE_BOARD_CHECK_20261026.md` | 模型风格上板 |
| `TRACK2_REQUIREMENTS_AND_MOTION_STYLE_20261026.md` | Track2 需求 |
| `TRACK2_BOARD_CHECK_20261026.md` | Track2 上板 |
| `THREE_FIXES_20261027.md` | 三项修正 |
| `README_BEFORE_THREE_FIXES_20261027.md` | 修正前说明 |
| `FINAL_FOUR_MODES_20261028.md` | 四模式整合 |
| `ROI_ORIGINAL_20261028.md` | ROI 原点 |
| `SPATIAL_BIAS_20261028.md` | 空间偏置 |
| `EIGHT_TRAILS_20261030.md` | 八目标轨迹 |
| `RESOURCE_COMBO_20261030.md` | 资源组合 |
| `README_BEFORE_RESOURCE_COMBO_20261030.md` | 资源组合前说明 |

### 11.4 最终参数与交付

| 文件 | 内容 |
|---|---|
| `SHADING_GAINS_20261031.md` | 3×3 增益快照 |
| `PROJECT_LOG_UNIFIED.md` | 本文，统一日志 |
| `CODE_GUIDE.md` | 统一代码介绍 |
| `SOURCE_INVENTORY.md` | 当前工程源文件清单与启用状态 |

---

## 12. 扩展边界与算法取舍

### 12.1 1080p 可行性结论

历史分析结论：

```text
1280×720@60：当前方案，已工作
1920×1080@30：可行
1920×1080@60：不可行
```

原因：

1. SC520CS 的 1080p 是 **1×1 Crop**，手册标称 FHD 30 fps；
2. 当前 720p60 使用 **2×2 binning**，所以能到 60 fps；
3. 2-lane MIPI 在 85% 效率下约 140.8 Mpixel/s，1080p60 需要约 149.3 Mpixel/s；
4. 传感器最高读出约 151.2 Mpixel/s，1080p60 已占 98.8%，没有余量；
5. PLL 当前只能给 75 MHz，标准 1080p60 的 148.5 MHz 无法由整数分频得到。

1080p30 的显示时序可采用：

```text
75 MHz / (2200 × 1125) ≈ 30.303 Hz
```

与当前 720p60 的：

```text
75 MHz / (1650 × 750) ≈ 60.606 Hz
```

属于同一量级的非标准帧率偏差。

限制：

- `hdmi_mixer` 不做缩放，1080p 画布上直接显示 720p 源会居中留黑边；
- 当前最终资源已到 Slice 92.99%，ERAM 106/108；
- 1080p 需要更大的帧缓存和像素吞吐，当前版本未实现；
- 以上只是可行性分析，不是当前交付功能。

### 12.2 算法取舍

| 环节 | 当前方案 | 暂缓方案 | 原因 |
|---|---|---|---|
| 全局白平衡 | 帧级 AWB，R/B 全局增益 | 更复杂的颜色恒常性 | 资源低，能修正整体偏色 |
| 空间颜色 | 显示端 3×3 R/B，AWB 之后 | 逐像素 LSC / 5×5 | ERAM 和乘法资源紧张 |
| 绿色判定 | RGB 整数比较、色度、3×3 支持 | HSV/YCbCr 全变换 | 无除法，适合 FPGA |
| 连通域 | 16×16 tile + flood fill | 完整像素级 CCL | 行缓存和标签资源大 |
| 多目标 | 单次扫描 + 8 槽位 | 每目标独立跟踪器 | 复用扫描，节省资源 |
| 去马赛克 | 双线性 | MHC/边缘引导 | 当前画质与资源平衡 |
| 云台 | 死区 + 分段步长 + D 阻尼 | 完整 PID / α-β / Kalman | 当前机械和延迟条件下 PD 足够 |
| 轨迹 | 毫秒时间戳 + 1 位双缓冲位图 | 整帧彩色历史 | 节省 ERAM |

核心原则：

```text
不复制检测器
不保存整帧彩色历史
不增加不必要的 DSP/ERAM
显示与识别共用校正后的相机流
```

### 12.3 旧画质文档的使用边界

旧画质文档（已移出交付目录）是 2026-10-09 的红色检测阶段文档，已经被当前的绿色单/多目标方案取代。

其中仍然有效的通用结论：

- 检测读取显示增强前的相机 RGB；
- OSD、Logo、目标框必须受保护，不能参与检测；
- 全局 AWB 不能修正空间色偏；
- 传感器内部 AWB 如果另开，可能与软件 AWB 叠加；
- 当前没有通用像素级分割，相邻/重叠目标可能合并；
- 旧资源与时序数字不能用于当前版本。

旧文档中的红色阈值、旧 Slice 数据和旧时序数据均不再适用。

## 13. 工程分析与阶段一经验

本节来自 2026-10-18 工程分析和 2026-10-02 阶段一报告。

只保留仍然有效的工程事实、踩坑经验和对当前版本有约束的结论；旧资源、旧时序、旧模块状态不再作为当前数据。

### 13.1 早期已确证的事实

| 项目 | 早期确证值 | 当前是否仍适用 |
|---|---|---|
| 摄像头 | SC520CS，不是 SC500 | 是 |
| I2C 地址 | `0x6C` | 是 |
| 芯片 ID | `0x3107/0x3108`，合法值 `0xEE4B/0x9E4B` | 是 |
| 720p60 模式 | 1280×720，2-lane RAW10，828 Mbps/lane | 是 |
| 720p60 读出 | 2×2 binning + crop | 是 |
| 初始化表 | 165 条寄存器 | 是 |
| 摄像头参考时钟 | 约 23.809524 MHz | 是 |
| MIPI 字节时钟 | 约 103.52 MHz | 是 |
| DDR 用户时钟 | 约 66.667 MHz | 是 |
| HDMI 像素时钟 | 75 MHz | 是 |
| HDMI 串行时钟 | 375 MHz | 是 |
| 上电时序 | PWDNB 先拉低约 1 ms，释放后再等约 5 ms 才启动 I2C | 是 |
| 主复位引脚 | `I_rst_n = R10` | 是 |

早期验证的引脚：

```text
I_sys_clk = C4
I_rst_n   = R10
O_cam_scl = K3
IO_cam_sda= J3
O_cam_24m = L3
O_cam_rst = L2
HDMI ch0  = G16
HDMI ch1  = F17
HDMI ch2  = H14
HDMI clk  = C17
```

这些应以当前 `pin.adc` 为准；如果板级约束改动，以约束文件为最终依据。

### 13.2 阶段一完成的工作

阶段一目标：

```text
把只有 led_blink 的空工程补成
SC520CS → MIPI → 图像处理 → HDMI 视频输出
```

完成内容：

- 从官方知识库提取并核实 SC520CS 参数；
- 移植 PLL、I2C、HDMI PHY、MIPI D-PHY 等官方文件；
- 编写系统顶层、视频时序、同步器、去抖、异步 FIFO、I2C 主机等模块；
- 720p60 视频时序验证通过；
- ModelSim 编译 0 error；
- TD 综合做到部分成功；
- 解决 TI/TD 对 SystemVerilog 数组端口的兼容问题。

历史状态：

```text
720p60 视频时序：通过
ModelSim 编译：通过
TD 综合：部分成功
RAW → HDMI 全链路：当时尚未打通
图像处理算法：当时按计划暂缓
```

### 13.3 当时的主要阻塞

#### MIPI D-PHY 包装兼容

官方 `.sv` 包装使用了 SystemVerilog 非压缩数组端口，TD `open_project` 分析器拒绝。

解决方式：

```text
新增纯 Verilog-2001 的 MIPI 包装
直接实例化加密的 byte_aligner / channel_aligner
不修改加密 IP
```

这个问题的经验：

```text
加密 IP 只能改包装，不能改内部
工具版本兼容问题优先用薄包装解决
不要为了编译去改官方加密文件
```

#### 整帧缓存资源不足

片上 ERAM 不可能缓存整帧 RGB，必须使用 DDR。

最终方案：

```text
DDR 四槽帧缓存
写侧 240 个 128 位字突发
读写异步 FIFO 跨域
```

#### 官方例程本身时序未收敛

早期官方基线 gate 报告曾有：

```text
Setup WNS 约 -121 ps
```

说明：

```text
官方例程“能出图”不等于时序已经收敛
不能把官方旧 bit 或旧时序当作当前基线
```

### 13.4 当时的文档/代码漂移

旧文档曾出现：

```text
说当前用 awb.v
说 Track2 是红色检测
说 video_enhance 负责 +6 亮度
说 display_color_shading 已关闭
说工程路径是 D:\HX1P35A_Contest_202606
```

这些在最终版本中已经不成立。

当前事实：

```text
AWB 使用 awb_frame_stable
检测是绿色单/多目标
显示端 3×3 已开启
全局亮度旧版由 video_enhance 的 ×1.2 提供，当前已关闭为 ×1.0
工程路径是 D:\Anlogic\Anlu2
```

经验：

```text
.al 是源文件清单的唯一依据
旧 CODE_GUIDE / 旧报告只能作历史参考
改颜色或检测前先确认当前实际数据通路
```

### 13.5 按键与 AE

早期发现：

```text
I_button 实际接的是曝光 AE，不是增益 AG
顶层没有实例化 key_remove_shakes
```

最终版本：

```text
SW1 舵机
SW2 风格化
SW3 多目标
SW4 舵机 HOME 复位
```

旧的“按键调增益”描述不再适用。

### 13.6 早期风险与当前状态

| 早期风险 | 当前状态 |
|---|---|
| MIPI 包装不兼容 | 已解决 |
| RAW→HDMI 未打通 | 已解决 |
| 图像算法暂缓 | 已实现绿色检测/风格化/轨迹 |
| 官方时序未收敛 | 最终 WNS +0.266 ns |
| 颜色链路层叠 | AWB + 3×3（开启）+ 全局 1.2（关闭） |
| 未使用模块留在 `.al` | 已标记/部分 AutoExcluded |
| 复位/CDC 约束不足 | 仍以 PLL lock 为主，SW4 独立舵机复位 |
| 文档漂移 | 已用统一日志/代码介绍收敛 |

### 13.7 工程经验

1. **以 `.al` 为准**  
   不要递归添加所有 `.v`，目录里有大量备份和同名模块。

2. **旧时序数字不能复用**  
   每次改 RTL、MIF、约束后都要重新综合和布局布线。

3. **颜色链路一次只改一层**  
   AWB、3×3、边缘、全局增益、tone 要逐层验证，避免双重补偿。

4. **OSD 必须和检测隔离**  
   Logo、文字、目标框不能参与绿色检测。

5. **复位和 CDC 要显式设计**  
   当前主复位是 PLL lock；舵机有独立 SW4 复位；跨域信号必须同步。

6. **新功能先算资源**  
   当前 Slice 92.99%、ERAM 106/108，新增逻辑必须先评估资源和时序。

## 14. 结论

```text
工程已完成从摄像头输入到 HDMI 输出、
目标识别、多目标、舵机、风格化、轨迹、
OSD 和最终时序收敛的完整链路。

最终交付 bit：2026-10-31 20:06:19
最终时序：Setup +0.266 ns，Hold +0.021 ns
最终资源：Slice 92.99%，ERAM 106/108
```

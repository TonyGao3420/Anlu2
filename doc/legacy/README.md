# doc/legacy 归档索引

> 本目录保存 2026-10-08 ～ 2026-10-31 的历史文档、调试记录、标定图片、参考代码和旧技术文档。
>
> **当前有效文档不在本目录**：
>
> - [`../PROJECT_LOG_UNIFIED.md`](../PROJECT_LOG_UNIFIED.md)：统一工程日志
> - [`../CODE_GUIDE.md`](../CODE_GUIDE.md)：统一代码介绍
> - [`../SOURCE_INVENTORY.md`](../SOURCE_INVENTORY.md)：当前源码清单
> - [`../SHADING_GAINS_20261031.md`](../SHADING_GAINS_20261031.md)：3×3 增益快照

---

## 1. 目录结构

```text
legacy/
├─ README.md
├─ reports/          # 历史 md 报告和日志（38 个）
├─ evidence/         # 标定图片、截图、Logo 测试图（46 个）
├─ reference/
│  ├─ open_source_lsc/
│  ├─ sc500_official/
│  └─ contest_reference/
└─ archive/
   ├─ 基于PH1P35的动态视觉追踪_技术文档.docx
   ├─ source_inventory.json
   └─ source_descriptions.json
```

本次已经完成分组移动：

```text
md 报告      → reports/
png 图片     → evidence/
开源 LSC     → reference/open_source_lsc/
官方 ISP     → reference/sc500_official/
竞赛参考     → reference/contest_reference/
docx / JSON  → archive/
```

旧 markdown 中的图片引用已尽量改为 `../evidence/...`；如有遗漏，属于历史文档，不影响当前工程。

---

## 2. 重要说明

这些文件是历史证据，不代表最终交付状态。

以下内容已经过期，**不要直接引用为本工程当前参数**：

```text
RAW 静态阴影校正
旧四模式资源数据
旧 Slice/时序数据
旧舵机步长上限
旧 HUD 布局
旧 AWB 方案
```

最终状态以 `../PROJECT_LOG_UNIFIED.md` 和 `../CODE_GUIDE.md` 为准。

---

## 3. 历史报告

以下文件均位于 `reports/`。

### 3.1 早期链路与颜色

| 文件 | 内容 |
|---|---|
| `GREEN_ROI_20261008.md` | 绿色 ROI 基线 |
| `ROI_COLOR_REVIEW_20261008.md` | ROI 颜色审查 |
| `ROI_HEIGHT_ROLLBACK_20261008.md` | ROI 高度回退 |
| `OFFICIAL_DISPLAY_20261009.md` | 官方显示链路核对 |
| `RAW_COLOR_BRIGHT_20261009.md` | RAW 域颜色/亮度试验 |
| `SHARED_COLOR_GREEN_ROI_20261009.md` | 共享颜色与绿色 ROI |
| `EDGE_COLOR_20261009.md` | 边缘颜色修正 |
| `DISPLAY_COLOR_TRIAL_20261009.md` | 显示颜色试验 |
| `COLOR_DIAGNOSTIC_20261009.md` | 九区颜色诊断 |
| `EDGE_REFINE_MAIN_20261010.md` | 边缘修正细化 |
| `ROI_CENTER_20261011.md` | ROI 中心坐标 |
| `ROI_SCREEN_ORIGIN_20261011.md` | ROI 屏幕原点 |
| `ALGORITHM_RESEARCH.md` | 颜色/阴影算法研究 |
| `VIDEO_QUALITY.md` | 视频质量记录 |

### 3.2 工程分析

| 文件 | 内容 |
|---|---|
| `PROJECT_ANALYSIS_20261018.md` | 工程整体分析 |
| `architecture.md` | 架构摘要 |
| `代码结构说明报告.md` | 中文代码结构 |
| `阶段一报告.md` | 阶段一总结 |
| `1080p可行性分析.md` | 1080p 可行性分析 |
| `CODE_GUIDE_20261024.md` | 旧版逐文件代码指南 |

### 3.3 风格化 / 轨迹 / 多目标

| 文件 | 内容 |
|---|---|
| `ERAM_OPTIMIZATION_20261025.md` | ERAM 优化 |
| `GUI_COMPILE_FIX_20261025.md` | GUI 编译修复 |
| `STYLE_MODE_INTEGRATION_20261025.md` | 风格化接入 |
| `TRAIL_1S_SMOOTH_20261025.md` | 一秒平滑轨迹 |
| `THREE_MODE_BOARD_CHECK_20261025.md` | 三模式上板 |
| `MODEL_STYLE_20261026.md` | 模型风格 |
| `MODEL_STYLE_BOARD_CHECK_20261026.md` | 模型风格上板 |
| `TRACK2_REQUIREMENTS_AND_MOTION_STYLE_20261026.md` | Track2 需求 |
| `TRACK2_BOARD_CHECK_20261026.md` | Track2 上板 |
| `THREE_FIXES_20261027.md` | 三项修正 |
| `README_BEFORE_THREE_FIXES_20261027.md` | 修正前说明 |
| `FINAL_FOUR_MODES_20261028.md` | 四模式整合 |
| `ROI_ORIGINAL_20261028.md` | ROI 原点 |
| `SPATIAL_BIAS_20261028.md` | 空间颜色偏置 |
| `EIGHT_TRAILS_20261030.md` | 八目标轨迹 |
| `RESOURCE_COMBO_20261030.md` | 资源组合 |
| `README_BEFORE_RESOURCE_COMBO_20261030.md` | 资源组合前说明 |
| `README_ROI_ORIGINAL_20261028.md` | ROI 原点回退说明 |

---

## 4. 标定图片和截图

以下文件均位于 `evidence/`，是历史证据，不是当前 UI 状态。

### 4.1 九区标定

```text
cal_digits1.png ～ cal_digits9.png
cal_label1.png  ～ cal_label9.png
cal_labels_montage.png
```

### 4.2 新九区调试

```text
new_full2.png / new_full3.png / new_full5.png / new_full9.png
new_label1.png ～ new_label9.png
new_labels_montage.png
```

### 4.3 Logo 测试

```text
logo_230x80.png
logo_230x80_black_up.png
logo_345x120.png
logo_460x160.png
logo_460x160_quant.png
logo_text_crop.png
official_logo_clean2.png
official_logo_clean3.png
official_logo_clean4.png
official_logo_clean_up.png
official_logo_recon.png
official_logo_recon_up.png
```

### 4.4 屏幕截图

```text
screen_text_crop.png
```

---

## 5. 参考代码

### 5.1 开源 LSC 参考

```text
reference/open_source_lsc/
```

内容：

```text
libcamera_alsc.cpp
libcamera_lsc_rpi.py
libcamera_lsc_tuning.py
libcamera_rkisp1_lsc.cpp
libcamera_tuning_alsc.py
vitis_lsc.hpp
infinite_lsc.py
fork_lsc.py
mini_isp_lsc.py
LICENSE_APACHE2.txt
LICENSE_BSD2.txt
LICENSE_GPL2.txt
LICENSE_MIT_MINI.txt
```

这是第三方参考代码，带独立许可证，不并入项目代码介绍。

### 5.2 官方 ISP 参考

```text
reference/sc500_official/
```

包括：

```text
awb.v
awb2.v
ae_set.v
bound_cut.v
csi_unpacket_2lane.v
raw10_unpacket_2lane.v
raw8_2_rgb888.v
Line_Shift_RAM_8Bit.v
video_source_test.v
```

### 5.3 竞赛工程参考

```text
reference/contest_reference/
```

包括：

```text
line_ram_640x8.v
udp_cam_ctrl.v
```

这些是参考实现，不是当前生产代码。

---

## 6. 旧技术文档和清单

### 6.1 技术文档 docx

```text
archive/基于PH1P35的动态视觉追踪_技术文档.docx
```

状态：

```text
内容较完整，但基于 2026-10-28 旧版本
包含已移除的 RAW 阴影、旧四模式资源、旧时序、旧舵机参数
最终交付文档由其他人维护，本目录不负责更新该 docx
```

### 6.2 旧源文件清单

```text
archive/source_inventory.json
archive/source_descriptions.json
```

状态：

```text
2026-10-24 生成，已与当前源文件不一致
已归档到 archive/
```

当前有效清单：

```text
../SOURCE_INVENTORY.md
```

建议：

```text
不要再使用旧 JSON；需要时从当前 .al / RTL 重新生成
```

### 6.3 硬件配置

```text
../hw/config.json
```

状态：

```text
通用 PH1P35 配置，不是当前完整引脚表
```

建议：

```text
或在 CODE_GUIDE 中维护当前 SW1-SW4、摄像头、HDMI、舵机引脚表
```

---

## 7. 后续整合建议

已完成：

```text
legacy 索引
reports / evidence / reference / archive 分组
旧 source JSON 归档
```

仍需按需处理：

```text
1. 旧图片如被旧报告引用，检查 ../evidence/ 相对路径
2. 旧 docx 由最终文档维护者处理，本目录不更新
3. 后续新增历史文件按 reports/evidence/reference/archive 分类放置
```

## 8. 不要误删

```text
display_edge_color.v   # 提供 6 拍旁路
video_enhance.v        # 全局 1.2 倍仍生效
signal_delay.v         # AWB 50 拍延迟
scene_position_color_bias.v # generate 分支仍引用
```

这些不在本目录，但清理工程时容易误判。

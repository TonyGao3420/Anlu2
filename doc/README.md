# Anlu2 文档总入口

> 工程：Anlu2 / PH1P35MDG324-3
> 最终状态：2026-10-31
> 当前有效文档只保留 4 份，历史资料统一放在 `legacy/`。

---

## 1. 当前文档

| 文档 | 用途 |
|---|---|
| [PROJECT_LOG_UNIFIED.md](PROJECT_LOG_UNIFIED.md) | 统一工程日志：时间线、调试记录、资源/时序、扩展边界、工程经验 |
| [CODE_GUIDE.md](CODE_GUIDE.md) | 统一代码介绍：架构、模块、视频链路、颜色、识别、舵机、UI、构建 |
| [SOURCE_INVENTORY.md](SOURCE_INVENTORY.md) | 当前 `.al` 源文件、AutoExcluded、隐式 MIF 清单 |
| [SHADING_GAINS_20261031.md](SHADING_GAINS_20261031.md) | 3×3 R/B 增益快照与 MIF 生成说明 |

日常查阅顺序：

```text
1. CODE_GUIDE.md        了解代码和数据流
2. SOURCE_INVENTORY.md  确认文件是否在工程里
3. PROJECT_LOG_UNIFIED  查历史、调试、资源和时序
4. SHADING_GAINS        改 3×3 前先看
```

---

## 2. 最终交付状态

```text
bit：
td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit

生成时间：
2026-10-31 20:06:19

时序：
Setup WNS +0.266 ns
Setup TNS  0.000 ns
Hold  WNS +0.021 ns
Hold  TNS  0.000 ns

资源：
Slice 19,729 / 21,216 = 92.99%
LUT6  19,203 / 21,216 = 90.51%
ERAM  106 / 108
DSP   25 / 40
```

时序余量很小，新增逻辑必须重新跑综合、布局布线和 bitgen。

---

## 3. 历史资料

历史日志、旧报告、标定图片、参考代码和归档文件都在：

```text
legacy/
```

入口：

[legacy/README.md](legacy/README.md)

结构：

```text
legacy/
├─ reports/          # 38 份历史 md 报告和日志
├─ evidence/         # 46 张标定图片、截图、Logo 测试图
├─ reference/
│  ├─ open_source_lsc/
│  ├─ sc500_official/
│  └─ contest_reference/
└─ archive/
   ├─ 基于PH1P35的动态视觉追踪_技术文档.docx
   ├─ source_inventory.json
   └─ source_descriptions.json
```

说明：

- `reports/` 中的旧资源、旧时序、旧模块状态不代表当前版本；
- `archive/` 中的 docx 和 JSON 是历史归档，不作为当前依据；
- `reference/` 中的第三方代码保留各自许可证，不并入项目代码介绍。

---

## 4. 其它目录

```text
hw/
```

其中 `hw/config.json` 是通用 PH1P35 配置，不是当前完整引脚表。

当前引脚以：

```text
user_source/constraints_source/pin.adc
```

和 [CODE_GUIDE.md](CODE_GUIDE.md) 的顶层接口章节为准。

---

## 5. 维护规则

```text
1. 当前文档只维护根目录这 4 份
2. 新增历史日志放入 legacy/reports/
3. 新增标定图片放入 legacy/evidence/
4. 第三方参考代码放入 legacy/reference/
5. 旧版交付物放入 legacy/archive/
6. 修改 3×3 后必须重新生成 shading_row*.mif
7. 修改 RTL 后重新跑综合、布局布线、bitgen
```

---

## 6. 关键提醒

- `AWB_ENABLE = 1`；
- 显示端 3×3 已开启；
- `raw_measured_shading` 不在数据通路；
- `CALIBRATION_MODE = 0`；
- SW4 是 0→1 延时 2 秒、复位 2 秒的舵机 HOME 复位；
- motion trail 使用三级流水；
- 当前时序只有 +0.266 ns 余量。

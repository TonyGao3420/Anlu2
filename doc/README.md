# Anlu2 文档总入口

> 工程：Anlu2 / PH1P35MDG324-3
> 最终状态：2026-10-31
> 当前有效文档只保留 5 份（含本入口），历史资料已移出交付目录。

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
2026-11-01 14:01:32

SHA256：
4C362804A7F0C57101112EF6FBD9E6EA1492FECD8FD34A3151407A29A2553996

时序：
Setup WNS +0.117 ns
Setup TNS  0.000 ns
Hold  WNS +0.020 ns
Hold  TNS  0.000 ns

资源：
Slice 16,974 / 21,216 = 80.01%
LUT6  16,236 / 21,216 = 76.53%
ERAM  106 / 108
DSP   22 / 40
```

时序余量很小，新增逻辑必须重新跑综合、布局布线和 bitgen。

---

## 3. 历史资料

历史日志、旧报告、标定图片、参考代码和旧交付物已经移出 `Anlu2` 交付目录，不再随工程提交。

当前工程只保留：

```text
doc/
├─ README.md
├─ PROJECT_LOG_UNIFIED.md
├─ CODE_GUIDE.md
├─ SOURCE_INVENTORY.md
└─ SHADING_GAINS_20261031.md
```

如果后续需要新增历史记录，统一放到工程外部的归档目录，不放入 `Anlu2`。

---

## 4. 引脚依据

`doc/hw/` 已随历史资料移出。

当前引脚以：

```text
user_source/constraints_source/pin.adc
```

和 [CODE_GUIDE.md](CODE_GUIDE.md) 的顶层接口章节为准。

---

## 5. 维护规则

```text
1. 当前文档只维护 doc/ 根目录这 5 份
2. 历史日志不放入 Anlu2，统一存外部归档
3. 不把旧报告、旧截图、旧 zip 放回工程
4. 修改 3×3 后必须重新生成 shading_row*.mif
5. 修改 RTL 后重新跑综合、布局布线、bitgen
```

---

## 6. 关键提醒

- `AWB_ENABLE = 1`；
- 显示端 3×3 已开启；
- `raw_measured_shading` 不在数据通路；
- `CALIBRATION_MODE = 0`；
- SW4 是 0→1 延时 2 秒、复位 2 秒的舵机 HOME 复位；
- motion trail 使用三级流水；
- 当前时序只有 +0.117 ns 余量。

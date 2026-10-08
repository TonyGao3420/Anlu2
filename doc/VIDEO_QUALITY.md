> Current 2026-10-08 update: green-only single-region ROI with frame-atomic stable bounds replaces the red detector. Earlier red/ROI descriptions below are historical. See GREEN_ROI_20261008.md.

> 2026-10-08 rollback: restored the pre-LSC video pipeline, controls and constraints. The only retained RTL change is the ROI height cap (ROI_HALF_H -> IMG_H - 1). Original width cap and centroid tracking are restored. See ROI_HEIGHT_ROLLBACK_20261008.md.

# 视频色彩与红色目标检测

## 当前设置

当前 MIPI → ISP → DDR 帧缓存 → HDMI 链路及 ISP AWB 保持开启。目标检测读取 AWB/DDR 后、显示增强前的 RGB，不改写视频数据。HDMI输出末级只给未保护的相机画面每个RGB通道加6级，ROI框和OSD保持原色；检测每帧覆盖全屏并输出红色像素的动态外接矩形，避免窄搜索窗漏掉目标。

ISP AWB按每帧1/8误差量平滑，显示端仍旁路对比度、锐化、饱和度和Gamma；亮度偏移等量加到RGB三个通道，降低改变色相的风险。偏移只作用于相机画面，不改变红色检测输入。为适应画面中心的绿偏，红色判定允许R比G低20级、仍要求R明显高于B，并保留色度和面积密度筛选。

红色检测门槛保持：红色色相容限为 `0.875 * chroma`，绝对色度下限8、相对色度下限为R/16、最低R值24；候选红色像素面积128至120,000，最小框宽高12像素，候选框内至少50%像素为红色。目标面积输出为20位。

## 能力边界

候选框内50%比例只代表红色像素在其自身外接框中的密度，不能证明整件物体超过一半面积为红色。当前也没有通用连通域分割；ROI内多个红色块可能合并。传感器寄存器中的自动白平衡若另行开启，也可能继续引入场景变化；本工程的软件 AWB 平滑不能控制传感器内部算法。

## 验证

按用户要求未运行仿真。2026-10-07 使用 TD 6.2.168116 对 PH1P35MDG324 完成当前版本综合和布局布线，结果在 `sim/build/td_validation_roi_fullscan_green/video_check_Runs/`：14,740/21,216 slices（69.48%）、39/108 ERAM、11/40 DSP；最终 WNS +0.102 ns、TNS 0，HWNS +0.020 ns、HTNS 0。相较官方 AWB基线18,920 slices（89.18%），减少4,180 slices（约22.1%）。本版本显示提亮为RGB各通道+6；检测每帧全屏扫描并容忍有限绿偏，输出动态红色外接框。TD综合与布线通过不等同于上板画面已确认。

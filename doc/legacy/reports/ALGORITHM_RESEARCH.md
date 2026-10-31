# 视觉通路算法调研与当前取舍

本文对照当前 PH1P35MDG324 工程的流水线，记录适合 FPGA 实时实现的算法、已经采用的方案以及暂缓方案。目标是先保持官方采集/DDR/显示通路稳定，再逐段增加识别能力。

## 当前数据通路

传感器输出 RAW10，经 RAW 解包、Bayer 插值和 AWB 后进入帧缓存；显示侧从帧缓存取 RGB，检测器并行旁路检测 RGB/DE，最后由 HDMI 混合器叠加目标矩形框。检测逻辑不反压、不修改显示像素。

## 算法调研与决策

| 环节 | 常见/研究方案 | 资源与适用性判断 | 当前决策 |
|---|---|---|---|
| 全局色彩平衡 | Gray-world、White-patch、Shades-of-gray、基于中性色统计的自动白平衡 | 只估计整帧或整幅画面的通道增益；会受场景中某种颜色占比影响，也不能纠正画面中心与边缘不同的局部偏色 | 保留 ISP 中现有的中性像素统计 AWB 和限幅/缓变。它能修正全局轻微绿偏，不宣称能消除空间色偏 |
| 空间色偏/镜头阴影 | Flat-field / lens-shading correction (FFC/LSC)，对位置施加分区或逐像素增益 | 适合“中心偏绿、边缘偏暖”这类空间变化；增益表必须由固定镜头、光圈和工作条件下的均匀白/灰场标定得到 | 当前不写入臆测的增益表。应先拍均匀中性平场并测得各颜色通道的空间响应，再实现分区双线性插值增益 |
| 红色分割 | HSV 色相/饱和度/亮度阈值、YCbCr 色度阈值、RGB 通道比值 | HSV/YCbCr 都可减弱亮度对色相判定的影响；完整除法式 RGB→HSV 会增加组合逻辑。阈值对传感器色彩响应和局部偏色仍敏感 | 使用无除法 RGB 判定：R 必须为最大通道；`3*|G-B| <= R-min(G,B)` 将色相限制在约 340°–20°；红色饱和度至少约 25%，并保留最低亮度/色度门限。由 AWB 处理全局偏色；局部校准后再重新量阈值 |
| 二值噪声抑制 | 3×3 腐蚀/膨胀、开闭运算、邻域多数滤波 | 需要少量行缓存；抑制孤立噪点，但会缩小很小的目标 | 保留已有 3×3 多数滤波，不叠加第二套形态学流水线；最小红像素数继续作为帧级过滤 |
| 单目标定位 | 帧级红像素统计 + 最小/最大坐标；质心作下一帧预测 | 极低资源，不需要帧缓存；多个相隔的红色物体会被合并成一个外接框 | 保留帧级统计，但启用动态 ROI：首帧/漏检时全画面搜索，锁定时只在前一帧质心窗口内搜索，窗口大小由目标框尺寸和运动余量决定 |
| 多目标/独立物体框 | 单遍连通域标记与连通域分析 (CCL/CCA)，每个连通域分别累计面积、质心和外接框 | 能真正区分互不连通的目标；需要行缓存、标签等价/合并和对象统计表。论文报告的 4K 实时实现面向更高端 FPGA，不能直接当作本器件资源/时序结论 | 暂缓完整 CCL；当前单目标任务先采用动态 ROI。若后续必须区分同一搜索区内的多个红色物体，再做受限标签数的 CCL 原型及单独资源评估 |
| 运动平滑/云台 | α-β 常速度滤波、定点 PID、速度/加速度限幅 | α-β 比通用 Kalman 轻，适合平滑质心和短时预测；PID 应使用真实帧周期、舵机方向/限位和机械响应调参 | 目前只用上一帧质心生成搜索 ROI；不改变舵机控制器，避免图像识别尚未稳定时叠加闭环风险 |
| RAW 转彩色/清晰度 | 双线性 Bayer 插值、Malvar–He–Cutler 5×5 线性插值、方向边缘引导插值 | MHC/边缘引导可减少彩色边缘伪影、改善细节；需要更宽行缓存和更多加减/乘法，会影响 slices 与时序 | 当前保留已仿真的双线性插值；“分辨率不够”不能由锐化恢复传感器未采样信息。待颜色/ROI验证通过后，再以 MHC 为候选单独比较画质和综合资源 |

## 本次落地的改动

`roi_target_tracker.v` 原本计算了质心距离和自适应窗口尺寸，但 `in_roi` 被固定为常量 1，导致 ROI 窗口从未参与检测。本次将门控恢复为：

1. 复位后 `full_frame_search=1`，全画面获取目标。
2. 检测成功后记录质心，并按检测框尺寸加运动余量设置下一帧搜索窗。
3. 目标漏检时清除框并恢复全画面搜索；不在下一帧继续沿用失效窗口。
4. 检测框仍由当前搜索范围内的红色像素实际极值构成，不输出固定尺寸框。

ModelSim ROI 回归覆盖普通红色框、低占空比 H 形红色区域、白/橙/棕/紫误检抑制、棕红/浅红/深红检出、远离已锁定 ROI 的目标被门控，以及漏检后下一帧全画面重捕获。颜色扇区只使用通道比较、移位和常数乘法，没有引入通用 HSV 除法器或额外帧缓存。仿真只验证逻辑功能，不代替 TangDynasty 综合/时序分析或上板画质验证。

## 关键局限与下一步测量

- AWB 是全局通道增益，无法校正屏幕中心与边缘不同的色调。要修复局部偏色，先固定相机/镜头/光圈，拍摄均匀中性场，按区域统计 R/G/B 均值并生成受限增益表；之后再用真实图像检查颜色和饱和裁剪。
- 当前帧统计把搜索 ROI 内所有通过红色判定的连通区域合并。因此它实现的是单目标矩形跟踪，不等同于多目标检测，也不等同于对每个实体物体做“红色占比超过 50%”判断。
- 当前红色扇区约为 HSV 色相 340°–20°、饱和度不低于约 25%。它是为了排除白色、橙色、紫色的工程阈值；若相机空间偏色把真实红色推离此范围，需要先做颜色标定，再按目标样本微调阈值，不能单靠放宽阈值同时保证不误检。
- 双线性插值是现有稳定基线。先确认当前采集实际输出尺寸、像素时钟、显示缩放和镜头焦距；只有插值/缩放是清晰度瓶颈时，才值得换用更高阶去马赛克。
- 项目中的历史资源/时序报告不等于本次源代码的最新综合结果。本次没有运行 TD 综合或布局布线；新的 ROI 组合逻辑仍需在现有 TD 工程中综合并检查 WNS/HWNS 与 slices 后，才能确认上板时序余量。

## 参考资料

1. Kowalczyk et al., *Real-Time FPGA Implementation of Parallel Connected Component Labelling for a 4K Video Stream*, Journal of Signal Processing Systems, 2021. <https://link.springer.com/article/10.1007/s11265-021-01636-4>
2. *Uniformity Correction of CMOS Image Sensor Modules for Machine Vision Cameras*, Sensors, 2022. <https://www.mdpi.com/1424-8220/22/24/9733>
3. Finlayson & Trezzi, *Shades of Gray and Colour Constancy*, Color and Imaging Conference, 2004. <https://library.imaging.org/cic/articles/12/1/art00008>
4. Malvar, He & Cutler, *High-quality linear interpolation for demosaicing of Bayer-patterned color images*, ICASSP, 2004. <https://web.stanford.edu/class/ee367/reading/Demosaicing_ICASSP04.pdf>
5. SmartSens, SC520CS product flyer (RAW RGB, MIPI output). <https://smartsens.oss-cn-beijing.aliyuncs.com/web/img/1659074759492511058.pdf>
6. OpenCV, *Thresholding Operations using inRange* (documented HSV interval masking workflow). <https://docs.opencv.org/doc/doxygen/html/da/d97/tutorial_threshold_inRange.html>

# Anlu2：官方Logo、倒装转正与灰色模型风格

当前2026-10-27主工程入口为 **`td_project/camera_to_dsi_display.al`**，源码为`user_source/`。旧`prj/Anlu2.al`不是当前入口。

本版按顺序将左上角替换为官方例程3的160×160安路Logo；利用原RGB帧缓存读取完成180°转正；为第三模式增加目标中值去噪、暗绿/黄绿保色及柔和灰色背景。原绿色目标检测、ROI高度、中心原点坐标、舵机算法、拨码、颜色校正及一秒平滑轨迹保留。详细记录见[三项修改与验证报告](doc/THREE_FIXES_20261027.md)。

## 拨码与安装

拨上为1、拨下为0；SW1=A4，SW2=B4，原引脚不变。

| SW2 | SW1 | 效果 |
|---|---|---|
| 下 | 下 | 原彩色、ROI和中心坐标，舵机保持 |
| 下 | 上 | 原彩色、ROI和中心坐标，原舵机追踪 |
| 上 | 下 | 灰色模型观感背景、目标绿色保色、一秒橙色平滑轨迹，舵机保持 |
| 上 | 上 | 第三模式，继续原舵机追踪 |

倒装转正默认开启：顶层参数`CAMERA_ROTATE_180=1`。正常摆放摄像头时改为0并重编译。转正同时反转图像行列；Logo、文字保持正向。检测、坐标、轨迹、舵机使用同一正向坐标，不在反馈上重复翻转；原舵机方向、限位、步进及PWM参数不变。实际闭环方向需按机械安装上板确认。

## 第三模式

全部背景物品不论是否运动都逐帧灰化、简化并随场景变化。8×8均值、低对比块面平滑、连续明亮灰阶和窄轮廓减少碎片感；块面灰值96–223，柔和轮廓最低72，不绘制运动青色区域。

仅在有效ROI内保留具有绿色优势的目标像素：先做横向五点逐通道中值，再作显示保色。暗绿和黄绿阴影适当保留；红/蓝/中性色和过曝近白继续排除。上游识别器的严格色域及白色排除没有改动。Logo、坐标、边框和HUD保留原色，不参与中值。

一秒轨迹继续使用三点中值、1/2平滑、4像素死区及50ms采样，退出模式清空；它是屏幕路径，没有世界坐标或相机运动补偿。MODE表示显示算法，MOT为16×16活动网格数，GLOBAL仅标记大范围变化，不控制背景颜色。

滤波增加6个像素时钟（75MHz下80ns），RGB与全部控制/保护标记同步，普通模式RGB不变；不改变ROI检测或舵机反馈时序。此效果为二维实时风格化，不重建三维几何。中值不等于完整二维/时间降噪，也不能恢复失焦细节。

## 编译与发布

正常TD GUI打开主工程，完整运行综合和物理设计即可，不需要Python。Logo完整模块在`hdmi_mixer.v`内，复制工程时必须保留同目录4个`official_logo_*.mif`；历史5个旧MIF不影响当前硬件。

标准输出：`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。

本版命名bit、完整干净ZIP、manifest、全部检查日志和实际RTL预览位于`sim/build/three_fixes_20261027/`。视频回放预览以用户手机录像原帧为输入，不是SC520新bit上板实拍。

<!-- FINAL_RESULT -->
完整综合、布局布线及bitgen通过：Slice 18610/21216，ERAM 103/108，DSP 40/40。

Setup WNS +190ps、Hold WNS +20ps，Setup/Hold TNS均为0，STA覆盖96.36%。没有降低时钟或放松约束。

所有发布检查通过；主通路记录：`PASS final_main: 7372800 full 720p pixels; ROI/coordinates/upright servo input/PWM unchanged by denoising; normal3553390 ROI9604 OSD201062 HUD65536 background3543208 trail32; 2 entries/1 exit with switch bounce; +6 aligned video clocks`。

本次命名bit与主输出SHA256相同：`63e63fd696cfca4abf33f3ff4f1f33f227a19a0299094288fd38100490e2ac8f`。尚未上板验证。
<!-- /FINAL_RESULT -->

原版本和本轮各阶段均保留；修改前备份为`../recovery_backups/Anlu2_before_three_fixes_20261027/`。上一版说明保存在`doc/README_BEFORE_THREE_FIXES_20261027.md`，历史编译结果不能作为本版结果。

完整工作区可离线重验：`powershell -ExecutionPolicy Bypass -File tools/three_fixes_20261027/rebuild.ps1`。需要现有阶段快照、官方例程、原仿真数据、Python、ModelSim和TD；干净ZIP面向常规GUI编译，不含数百MB参考数组。旧常用重建入口转发本脚本。

最新bit尚未上板。长期稳定性、FIFO状态、光照突变、实际帧率和机械闭环需实测；原CNT不是采集到显示的延迟测量。原75MHz/1650×750时序未改，理论输出约60.606Hz。

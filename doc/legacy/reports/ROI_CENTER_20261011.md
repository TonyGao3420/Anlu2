# ROI 中心坐标显示（2026-10-11）

在现有帧计数下方新增黑底黄字 `ROI X:0640 Y:0360`，位置 x=375..918、y=160..191。数字为四位十进制，保留前导零。无有效 ROI 时显示 `ROI X:---- Y:----`。

坐标原点是 1280×720 图像的左上角，X 向右、Y 向下，单位为像素。中心取稳定 ROI 逻辑边界的 `(x0+x1)/2`、`(y0+y1)/2`，半像素向下取整；不是绿色像素重心，也不计绘框时额外添加的 4 像素装饰边距。合法范围 X=0..1279、Y=0..719。

ROI 检测结果在校正后的相机帧开始发布，晚于 mixer 的帧开始。因此文字模块在第 1 行首个有效像素处采样完整 ROI 结果，用 16 拍移位加法完成十进制转换，再同时发布 X、Y 和对应数字，早于第 160 行的文字显示。两个坐标来自同一次采样，显示期间不变化。原跟踪器的暂时丢失保持策略不变；ROI valid 清除后显示横线，不把 `(0,0)` 当作有效目标。

新增 `user_source/hdl_source/video/roi_center_osd.v` 的 `center_valid/center_x/center_y` 输出在同一 HDMI 像素时钟域可用，连接到 mixer 内部 `S_center_valid/S_center_x/S_center_y`。本次输出载体为 HDMI 文字，没有新增板级管脚或串口。

功能代码仅新增坐标 OSD，并在 hdmi_mixer 连接它；主工程 .al 加入该源文件。坐标面板通过原 OSD protect 通路保护，ROI 边框继续保持原有绘制优先级。现有 RAW 校正、白平衡、边缘削红、亮度曲线、绿色识别与白色高光排除、ROI 高度/稳定性、舵机、DDR、传感器配置、顶层及引脚/时序约束均保持原文件内容。

单元仿真检查 2289 组边界，包括完整 X 范围、全部 Y 范围、奇偶和极限边界、十进制进位、无效目标、采样原子性与 34816 个字形像素。集成仿真比较用户已确认颜色效果的旧 mixer 和新 mixer，驱动四个完整 720p 帧（移动、失效、重新获得及文字区域穿过 ROI 边框），通过实际 scene_color_stream、边缘校正、video_enhance 和共同亮度链路，检查 ROI 输入及新面板外每个最终 HDMI 像素完全一致。

本次 bit 从当前主工程正常运行目录 `td_project/camera_to_dsi_display_Runs` 完成综合、布局布线与 bitgen。主工程输出 `phy_1/camera_to_dsi_display.bit` 与交付的 `sim/build/SC520_roi_center_20261011.bit` 内容一致；源码、时序、资源及哈希见同名 manifest。可继续在 TD 打开 `td_project/camera_to_dsi_display.al` 完整重新编译。

上板后用绿色物体移动 ROI，查看数字是否随框中心更新；移走目标并等 ROI 框消失后，应显示横线。新功能的实际板卡显示效果尚需确认。回退可直接下载已确认颜色正常的 `sim/build/SC520_main_edge_refined_20261010.bit`。

最终实现：Setup WNS=155 ps、Hold WNS=20 ps，两项 TNS 均为 0；19043 slices、54 ERAM、40 DSP。相对颜色已正常版本增加 48 slices，ERAM 与 DSP 数量不变。

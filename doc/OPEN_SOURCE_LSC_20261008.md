# 中心绿、边缘红：开源检索与FPGA实现

检索日期：2026-10-08。对主流相机栈、Python ISP、厂商FPGA ISP、厂商无关ISP及测试框架进行了源码核查；这不表示已穷尽互联网上所有仓库。不能因为README列了LSC就把它当作可用实现。

## 源码核查

| 项目/源码 | 实际情况 | 本工程结论 |
|---|---|---|
| [libcamera Raspberry Pi ALSC](https://github.com/raspberrypi/libcamera/blob/6c1dd9d55573010f710c9e190a73e7e76f0d9432/src/ipa/rpi/controller/rpi/alsc.cpp) | 完整分区色彩阴影控制算法，含校准表、空间权重与迭代 | 主要算法参考；其CPU线程/浮点控制器不能直接综合到PH1P35 |
| [libcamera LSC标定](https://github.com/raspberrypi/libcamera/blob/6c1dd9d55573010f710c9e190a73e7e76f0d9432/utils/tuning/libtuning/modules/lsc/lsc.py) | 平场分区统计、黑电平处理、按绿色通道归一、平滑 | 采用“实测每通道增益”的原则；板内实现省去用户导出RAW和重新生成表 |
| [libcamera rkisp1 LSC](https://github.com/raspberrypi/libcamera/blob/6c1dd9d55573010f710c9e190a73e7e76f0d9432/src/ipa/rkisp1/algorithms/lsc.cpp) | 向Rockchip ISP提交网格表，依赖对应硬件 | 可参考网格表使用，不能移植驱动就替代安路RTL |
| [AMD Vitis LSC](https://github.com/Xilinx/Vitis_Libraries/blob/3ab1ecd20cf338b3f8f2824fdfeee115f3398889/vision/L1/include/imgproc/xf_lensshadingcorrection.hpp) | HLS径向距离模型、统一增益与饱和截顶 | 不区分Bayer颜色通道，单独使用不能消除中心和边缘的通道比例差；依赖AMD HLS |
| [openISP](https://github.com/cruxopen/openISP/tree/d4947e1aa5f4af83c3640131dbca8a675b613ec6) | 该提交树中没有LSC实现文件 | 排除直接移植 |
| [Infinite-ISP LSC](https://github.com/10x-Engineers/Infinite-ISP/blob/32212079dc13528125df711fed27da332250485e/modules/lens_shading_correction/lens_shading_correction.py) | execute无论enable值均直接返回原图 | 空壳，不能作为修复 |
| [AMD mini-isp](https://github.com/amd/mini-isp/tree/67e752d6bf668179ec45446089a709bbc1ef9736) | README标注LSC未实现；python/mini_isp/lsc.py只有版权头 | 排除 |
| [fast-openISP原版](https://github.com/QiuJueqin/fast-openISP/tree/26fd824049c020ce7eb2dc4e2839f7f3ce4fdc47) | 提交树无LSC模块 | 排除 |
| [fast-openISP扩展分支](https://github.com/yumiao0557/fast-openISP/blob/d6bd3b205b35b9ce8b958107d5f6656a09f7359d/modules/lsc.py) | NumPy径向统一增益，未区分四种Bayer通道 | 可校正亮度渐变，单独不能校正颜色阴影 |
| [Antmicro FPGA ISP](https://github.com/antmicro/fpga-isp-core/tree/edf67203b6454118e823940ec390a8928f6e869a) | 厂商无关Migen ISP；提交树没有LSC/shading文件 | 无可直接使用的LSC实现 |
| [AOSP CameraITS](https://android.googlesource.com/platform/cts/+/refs/heads/main/apps/CameraITS/utils/image_processing_utils.py) | 从元数据取得四通道LSC表并插值，测试/离线RAW处理 | 验证思路参考，不是安路实时模块 |
| [Espressif ESP32-P4 ISP](https://docs.espressif.com/projects/esp-idf/en/latest/esp32p4/api-reference/peripherals/isp.html) | 四通道增益表配置API，依赖ESP32-P4专用ISP | 不能直接作为PH1P35 RTL |

参考源文件按固定提交保存于 `doc/open_source_lsc/`，含版权头、对应许可证及SHA-256清单。新RTL是针对当前流接口独立编写，没有把libcamera的GPL调参脚本或AMD专用HLS依赖编入FPGA。

## 当前实现

`user_source/hdl_source/isp/raw_color_shading.v` 包含四像素并行校正器和独立按键控制。

路径：SC520 RAW10 → 空间色偏校正 → 原有BGGR插值 → 原有全局AWB → DDR → 检测/画框/HDMI。

网格3×3，每个节点采样64×32像素的白/灰平场窗口；每个Bayer平面512个样本。节点为x=128/640/1152、y=104/360/616。分别累计B、Gb、Gr、R，局部目标取两个绿色平面的均值，通道增益为局部目标/该通道均值，以Q10表示。四通道独立、双线性插值，每个像素均有各自的横坐标权重；网格外沿用最近边界值。它校正色彩比例，保留原有绿色亮度阴影，不做强行提亮边角。

增益默认限制0.75–1.5倍；每节点各通道平均RAW值必须在80–900之间，有1000以上采样则拒绝。全帧采集和36个系数都成功后，在下一帧帧首同时提交，失败不替换旧图。参数BLACK_LEVEL默认0，保持当前传感器模式；若以后取得可靠暗场值，可统一在统计和增益应用中减去该黑电平并加回，避免放大底座。未擅改SC520内部BLC寄存器。

校正增加固定5个RAW时钟周期，数据、valid、user、last、dest一起延迟，不引入反压或丢像素。仅在用户明确请求时学习；普通目标场景不更新系数。复位及清除后为单位增益。

保留了此前ROI尺寸修复、红色门限、面积门限、舵机控制、DDR/MIPI/HDMI参数、现有两个增益输入的接线与功能。

## 上板使用

1. 使用活动工程 `td_project/camera_to_dsi_display.al` 重新编译。新增KEY3(B9)、KEY4(C7)依据 `9_康芯开发板使用手册及实验平台/HX1P35B开发板引脚分配汇总.docx`；它与A版手册列出的KEY3/4引脚一致。当前旧I_button仍保留N2/J14，未改动该外部输入。
2. 固定摄像头和镜头，在正常使用光源下让均匀白/灰面覆盖整个视野，避开反光、手影和过曝。先用原有方式调好曝光/增益，再等待稳定。
3. 按住KEY3约2秒，再松开；继续保持白/灰场至少半秒。长按以120个60fps帧首计数，低帧率下需要按得更久。
4. 左下角12×12方块：灰=单位增益，黄=采集/计算，绿=实测表已启用，红=采样过暗/过曝/通道比超限等而拒绝（若已有表，则继续保留旧表）。红色时调整平场与曝光后重试。
5. 移开白/灰面正常识别。需要撤销时按住KEY4约2秒后松开，恢复单位增益。复位/断电也恢复单位增益，当前不写Flash，重新上电需要再次标定。

校正表必须对应实际镜头、焦距、光源。不能用普通彩色场景代替白场；检测检查只是一层保护，不能证明采集面真的中性均匀。实际色偏比允许范围更大时，软件会拒绝，而不是过度放大通道。

## 验证与边界

原有七组回归及新增LSC和720p超大ROI回归通过。新增独立按键回归通过；720p空间校正回归覆盖约645万像素，单位增益位序保持、同步对齐、有效标定、真实红色目标不学习、暗/过曝拒绝、旧表保留和帧首清除均通过。在合成中心绿/红边平场上，最大残差6/1023；这是数字逻辑测试，不是实物修正效果数据。

3×3网格针对低频渐变色偏；复杂环状/局部光斑、IR泄漏、曝光相关黑电平、颜色串扰等未必能靠该模型消除。软件乘法不能恢复被红外混入或饱和丢失的可见光信息。若正确白场标定后仍偏色，再检查IR-cut、镜头CRA、Bayer排列及更高密度网格，不能宣称已由仿真证明真实画面完全修好。

独立硬件验证目录：`sim/build/td_validation_color_shading_20261008/`。TD 6.2.168116完整综合、布局布线通过：17651/21216 slices（83.20%）、39/108 ERAM、26/40 DSP；建立WNS +0.112 ns、TNS 0，保持WNS +0.020 ns、HTNS 0。报告 `video_check_Runs/phy_1/route.qor`。位流生成完成，交付文件 `sim/build/SC520_color_shading_20261008.bit`（1,789,539字节），源文件及位流校验值见同目录manifest JSON。未烧写硬件。

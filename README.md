# Anlu2 最新校色、资源优化与组合模式总工程（2026-10-30）

唯一工程入口：**td_project/camera_to_dsi_display.al**；生产源码：**user_source/**。所有功能均在Anlu2主工程内，正常测试及提交无需加载独立子工程。当前是否已完成最终编译以BUILD_STATUS.md和output/manifest.json为准。

本轮以你30日更新后的九点校色和舵机参数为基准，先完成资源优化和旧四模式逐像素对照，再接入多目标风格化。校色系数、整数舍入、黑电平、保护及八拍延迟均保持；原相机/RAW/ISP/旋转、ROI/关联、舵机、Logo、坐标、亮度、灰色背景算法和一秒平滑轨迹均保留。

主要资源优化包括精确校色ERAM表、复用帧稳定ROI坐标，以及把每帧仅启动一次的白平衡流水除法改为同精度、同50拍完成时刻的迭代除法。原增益计算规则、平滑、生效时刻和视频流水不变，均有对照验证。

## 拨码操作

HX1P35A V1.0：拨上为1、拨下为0。SW1=A4控制原主目标舵机；SW2=B4独立控制风格化；SW3=E11独立控制多目标。

| SW3 | SW2 | SW1 | 效果 |
|---|---|---|---|
| 下 | 下 | 下 | 原单目标ROI、彩色视频、屏幕中心原点坐标 |
| 下 | 下 | 上 | 原单目标ROI及双轴云台追踪 |
| 下 | 上 | 任意 | 原单目标风格化：ROI整框原图、框外灰色简化、主目标1秒轨迹 |
| 上 | 下 | 任意 | 原最多8目标分别框选，正常彩色视频、计数和延迟显示 |
| 上 | 上 | 任意 | 多目标风格化：所有有效目标ROI整框原图，框外灰色简化，独立彩框/计数及原主目标轨迹 |

组合模式右上显示MODE:MULTI+STYLE。SW1在风格化/多目标/组合时仍独立控制原主目标舵机；多目标不代表多路舵机。一秒轨迹仍沿用原主目标策略。相接、遮挡或过小的同色区域可能合并；最多保留8个，超出容量保留面积最大的8个并提示“+”。

N为有效槽位数（含原短暂保持），TOT为合格区域数，LAT为带真实DDR帧标签的RAW接收至HDMI有效输出延迟，DET为检测用时，FID为显示帧号。MOT仍是活动网格统计，不是物体数。

## 编译与下载

TD GUI重新打开唯一.al，完整运行综合及物理设计。GUI编译不需要Python。请完整复制user_source，保留官方Logo的official_logo_*.mif，以及新增的video/shading_row0.mif～shading_row2.mif。颜色查表数据已生成，不需要手动添加IP。

最终布局起点会同时固定在工程自定义物理脚本和CLI配置中。应保留td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.tcl，避免GUI和命令行使用不同布局设置。原引脚、器件、速度等级及时钟约束不变。

- 新比特流：output/Anlu2_Combo_Optimized_20261030.bit
- 完整提交包：output/Anlu2_Combo_Optimized_20261030.zip
- 常规主输出：td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit
- 校验记录：output/manifest.json

发布后，原Anlu2_Final_4Mode_20261028和Anlu2_SpatialColor_20261028兼容文件名同步为同一最新版；修改前输出已随工程备份。为避免下载器缓存旧选择，首次测试应重新选中30日新命名bit。

完整自动验证/重建：tools/rebuild.ps1，可通过参数指定本机Python、ModelSim和TD位置。相关测试基准均随包携带。若移动工程目录，可用prepare_tests.py更新工程根路径，或在TD中按新位置重新保存工程。

如果以后修改display_color_shading.v的九点系数，需用tools/resource_combo_20261030/generate_shading_rom.py同步更新三张MIF；只改函数不能更新已有ROM内容。当前复制及GUI编译无需执行此步骤。

本轮说明见doc/RESOURCE_COMBO_20261030.md。修改前完整快照在../recovery_backups/Anlu2_before_resource_combo_20261030。历史报告/旧bit不代表当前状态。软件验证不能替代真实光照、机械联动及长期运行的实板验收。

## 本轮验证结果

最终组合版：Slice 16373/21216，ERAM 106/108，DSP 39/40；Setup +148ps、Hold +20ps，TNS均0。

先完成不改变功能的资源优化及5529600像素旧四模式对照，再接入组合模式。2764800像素最新校色对照逐位一致；6451200像素组合整合、八ROI并集/坐标复用等价、1843200像素八目标组合冷启动均通过。原独立模式RGB、ROI、PWM和读请求保持一致。

布局Seed 0已同时写入GUI自定义物理脚本及CLI配置，未改变引脚或时钟约束。综合报告中带星号的Slice是估算值，最终容量以此处物理结果为准。

新比特流：output/Anlu2_Combo_Optimized_20261030.bit；主输出与两份旧命名兼容文件内容一致。SHA256：`39439cb19ef7182d67b36a85f2c8f7db0e8f9e12e2b835177f3ee03f80d47872`。未上板验收。

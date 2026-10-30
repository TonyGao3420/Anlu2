# Anlu2 八目标独立轨迹总工程（2026-10-30）

本次新增：SW2+SW3 组合模式下，最多八个目标各自显示连续的一秒轨迹。仅改轨迹模块及顶层轨迹接线，其余本轮开始时的生产代码与资源文件保持一致。

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
| 上 | 上 | 任意 | 多目标风格化：所有有效目标ROI整框原图，框外灰色简化，独立彩框/计数及八目标各自的一秒轨迹 |

组合模式右上显示MODE:MULTI+STYLE。SW1在风格化/多目标/组合时仍独立控制原主目标舵机；多目标不代表多路舵机。组合模式八目标各自保留一秒轨迹；单目标模式仍沿用原轨迹策略。相接、遮挡或过小的同色区域可能合并；最多保留8个，超出容量保留面积最大的8个并提示“+”。

N为有效槽位数（含原短暂保持），TOT为合格区域数，LAT为带真实DDR帧标签的RAW接收至HDMI有效输出延迟，DET为检测用时，FID为显示帧号。MOT仍是活动网格统计，不是物体数。

## 编译与下载

TD GUI重新打开唯一.al，完整运行综合及物理设计。GUI编译不需要Python。请完整复制user_source，保留官方Logo的official_logo_*.mif，以及新增的video/shading_row0.mif～shading_row2.mif。颜色查表数据已生成，不需要手动添加IP。

本轮使用工具默认布局设置、normal 布线、auto 后布线优化。GUI 工程策略已与实际通过的命令行编译设置一致；原引脚、器件、速度等级及时钟约束不变。

- 新比特流：output/Anlu2_EightTrails_20261030.bit
- 完整提交包：output/Anlu2_EightTrails_20261030.zip
- 常规主输出：td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit
- 校验记录：output/manifest.json

旧命名 bit/zip 保留为历史版本；本次请选 Anlu2_EightTrails_20261030.bit 或相同内容的主工程标准输出。

完整自动验证/重建：tools/rebuild.ps1，可通过参数指定本机Python、ModelSim和TD位置。相关测试基准均随包携带。若移动工程目录，可用tools/multi_trail_20261030/prepare_tests.py更新工程根路径，或在TD中按新位置重新保存工程。

如果以后修改display_color_shading.v的九点系数，需用tools/resource_combo_20261030/generate_shading_rom.py同步更新三张MIF；只改函数不能更新已有ROM内容。当前复制及GUI编译无需执行此步骤。

最新八轨迹修复见doc/EIGHT_TRAILS_20261030.md；之前资源优化见doc/RESOURCE_COMBO_20261030.md。修改前完整快照在../recovery_backups/Anlu2_before_resource_combo_20261030。历史报告/旧bit不代表当前状态。软件验证不能替代真实光照、机械联动及长期运行的实板验收。

## 本轮验证结果

当前入口：td_project/camera_to_dsi_display.al。当前比特流：output/Anlu2_EightTrails_20261030.bit。

仅轨迹模块及顶层接线改变；本轮开始时的全部颜色处理、检测、舵机、背景和显示功能保留。SW2+SW3 同时开启可显示最多八个目标各自的一秒连续轨迹，SW2 单开仍为原单目标轨迹，SW3 单开仍为普通多目标显示。

主工程完整综合、布局布线、比特流生成已通过。实际 Slice 17642/21216（83.15%），ERAM 106/108，DSP 39/40。Setup WNS +7ps，Hold WNS +20ps，TNS 均为零。

八轨迹整数参考逐像素及单目标新旧对照：10485760 像素通过；720p 满 256 条历史绘线预算通过；实际主工程 720p 八目标和各模式显示回归：6451200 像素通过。资源、时序和逐像素结果记录于 output/manifest.json 与 sim/build/multi_trail_20261030。

SHA256：fb744a4342a8b0f6d191653c7970f6f8dc49336fd4ed4622bb66adabbc3d23d2。

未上板验收。旧命名 bit/zip 保留为历史版本，测试本次八轨迹请选上述新命名文件或同内容的主工程标准输出。

# Anlu2 四模式最终总工程（2026-10-28）

单目标识别、舵机跟踪、风格化与八目标识别现已全部合入本工程。唯一入口是 **td_project/camera_to_dsi_display.al**，生产源码是 **user_source/**。正常使用及最终提交均以本目录为准，不再需要单独的多目标子工程。

本轮增加翻转后顶部红偏、右下紫偏的位置修正，显示和ROI共用补偿后的RGB，并保护白灰及OSD。说明见doc/SPATIAL_BIAS_20261028.md；最新命名输出为output/Anlu2_SpatialColor_20261028.bit及同名ZIP。发布成功后，原Anlu2_Final_4Mode_20261028文件名也同步为本轮内容，修改前输出另有恢复备份。当前是否构建完成以BUILD_STATUS.md为准。

## 拨码使用

HX1P35A V1.0：SW1=A4、SW2=B4、SW3=E11；拨上为1，拨下为0。SW3优先选择多目标模式，SW1继续独立控制原主目标舵机。

| SW3 | SW2 | SW1 | 显示/控制 |
|---|---|---|---|
| 下 | 下 | 下 | 模式1：单目标ROI、屏幕中心原点坐标、正常彩色视频 |
| 下 | 下 | 上 | 模式2：单目标识别与原双轴云台跟踪 |
| 下 | 上 | 任意 | 模式3：ROI整个矩形保持原图，框外灰色风格化，保留1秒平滑轨迹；SW1仍控制云台 |
| 上 | 任意 | 任意 | 模式4：最多8个分离绿色区域分别框选，数量/容量提示及帧延迟显示；SW1仍控制原主目标云台 |

演示多目标时建议SW1拨下，防止相机转动；无需先进入风格化模式。模式4右上显示 MODE:MULTI 和 N/TOT/LAT/DET/FID。目标彼此接触、遮挡或过小时，绿色区域可能合并；上限8个，超出保留面积最大的8个并提示“+”。这不是八路舵机跟踪。

官方安路Logo、180度画面转正、颜色校正与亮度、ROI高度修复、中心坐标和原舵机参数均保留。模式3按整个ROI矩形选择原RGB，包含白色高光和暗面，避免逐像素保色造成碎点。全部模式继续保留现有OSD。

## 编译与下载

TD GUI打开上述唯一.al，完整运行综合与物理设计。GUI编译不需要Python。必须保留完整user_source，包括4个official_logo_*.mif。anlogic_logo_eram定义在hdmi_mixer.v内。

- 常规主输出：td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit
- 正式命名输出：output/Anlu2_Final_4Mode_20261028.bit
- 完整提交包：output/Anlu2_Final_4Mode_20261028.zip
- 校验记录：output/manifest.json；当前状态：BUILD_STATUS.md

正式命名文件只在合并后的Anlu2完成仿真、综合、布局布线及时序检查后生成。主输出与命名输出须SHA256相同；旧的Anlu2_ROI_Original比特流属于合并前的三模式历史版本。

完整自动检查与重建入口为 tools/rebuild.ps1，参数可指定本机Python、ModelSim和TD路径。测试资料均随总工程携带。若移动工程目录，可先运行prepare_tests.py更新工程根路径，或在TD中按新目录重新保存工程。

合并前工程及旧编译产物已完整备份至 ../recovery_backups/Anlu2_before_final_four_mode_merge_20261028。历史报告和实验工具不代表本次最终状态；具体实现、限制和验证口径见 doc/FINAL_FOUR_MODES_20261028.md。

当前构建结果由发布检查追加于下方。软件验证通过后仍须实板验收显示、拨码、舵机方向和光照适应性。

## 本次主工程构建结果

位置颜色修正版Anlu2已完成三项本轮仿真、综合、布局布线及bitgen。Slice 20929/21216，ERAM 103/108，DSP 40/40；Setup WNS +114ps，Hold WNS +20ps，TNS均0。

1843200输入像素分别对照正常/180度映射的独立颜色参考模型通过。白/灰保护、合成角落偏色绿恢复、OSD及共享显示/ROI、八拍同步均通过。实际VTC四模式5529600像素通过；纯绿/黑保留测试图上的原RGB/ROI/PWM/读请求一致，其他颜色按本轮偏置有意变化。SW3直接启动8目标、1843200像素冷启动检查通过。

标准主输出与output/Anlu2_SpatialColor_20261028.bit完全相同。SHA256：`d133ea117a0055c169ddaf7b537907b58478c64669953c18c845304230c4b9f3`。本轮未上板；需白场和真实目标复核偏置强度。

# TD GUI 黑盒错误修复与干净编译验证

用户截图的报错为`HDL-8007: anlogic_logo_eram is a black box`，以及对应的`HDL-7144`未知模块警告，表示该次综合没有读到图标模块定义。之前命令行综合读到了该定义，但没有覆盖GUI重新打开后的完整流程。本机GUI能列出原文件，未复现另一台电脑为何漏读；不能据此将用户的报错归为操作错误。

## 修改

将完整、未改动的`anlogic_logo_eram`模块及其ERAM初始化数据放进`user_source/hdl_source/hdmi_mixer.v`，与调用者一起编译，消除对新增独立源文件条目的依赖。旧`anlogic_logo_eram.v`保留为空兼容条目，避免已有工程列表报文件丢失或出现重复定义。今后不能再拿旧的完整模块覆盖这个兼容文件。

逐字节审计确认mixer原有模块体和图标模块体/数据都不变；除这两份文件的定义搬移外，所有`user_source/`文件与一秒平滑轨迹版一致。ROI、舵机、拨码、颜色、坐标、风格化和一秒平滑轨迹不变，无新增显示流水级。

TD GUI已重新载入并保存主工程，整理了编译顺序并自动排除了不用的旧ROM/空兼容条目；源文件集合、器件、顶层、策略、引脚和时序约束保持对应配置。GUI生成的syn/phy工作工程源文件集合与主工程一致，settings.cfg与修改前一致。

## 验证结果

- 关闭旧工程后，将原Runs目录完整移到恢复备份，重新打开主工程，从Flow Runs的Launch Runs启动全新综合和物理设计。并非使用旧缓存或仅运行命令行。
- GUI综合日志明确记录`anlogic_logo_eram`在`hdmi_mixer.v`展开，`HDL-8007/HDL-7144`未再出现；综合、布局布线和bitgen完成。
- 32768图标地址及所有580种颜色、透明值、复位恢复保持一致。
- 三个完整720p画面、2764800像素的mixer等价检查通过；RGB/OSD/ROI/坐标、DDR读请求、同步逐拍一致。
- 刻意从仿真文件列表去掉`anlogic_logo_eram.v`，再做2764800像素对照仍通过，覆盖截图中“缺独立条目”的情形。
- 原7项功能回归通过，包括亮白排除、完整ROI高度、RAW和显示路径。轨迹与背景算法源码逐字节保持上一版，不在本轮改动范围。

| 最终布线结果 | 数值 |
|---|---:|
| Slice / 21216 | 18168 |
| ERAM / 108 | 94 |
| DSP / 40 | 40 |
| Setup WNS | +233 ps |
| Hold WNS | +20 ps |

Setup/Hold TNS均为0，资源未超限。STA覆盖率96.39%，既有时钟critical warning没有增加；不等于零警告或上板实测。

## 使用

请复制完整的修正版工程，关闭之前已打开的工程，再打开`Anlu2/td_project/camera_to_dsi_display.al`。`prj/Anlu2.al`为旧入口，不含当前完整功能。正常完整运行综合、物理设计和bitgen即可，不需要先运行Python。

干净工程ZIP含全部user_source、主工程配置、约束和已编译比特流；不含旧Runs缓存。比特流在ZIP的`Anlu2/output/`内。自己重新编译后的常规输出仍是`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。

GUI中也可以依次选择Flow Runs里的`syn_1`、`phy_1`，右键`Launch Runs`。本轮正是按这一入口从空运行目录编译。

命名比特流：`sim/build/gui_compile_fix_20261025/Anlu2_GUI_compile_fixed_20261025.bit`，与本次主工程常规输出字节一致。SHA256：`cd77b9d16068e4ac85811c5c298befd4b5d78f8220e472cf4a75d920f4418920`。

原工程运行目录、原两份HDL和上一版清单完整保存在`../recovery_backups/Anlu2_before_GUI_project_fix_20261025/`。上一版比特流SHA256：`0cb797e232630d963fb090048d4faf0f2fb641593d44b8d019c1c69cca591568`。本版尚未上板验证。

# Anlu2：ROI整框原图修复版（2026-10-28）

主入口为`td_project/camera_to_dsi_display.al`，生产源码为`user_source/`。第三模式整个ROI矩形显示正常彩色原图，含白色、暗面及其他颜色；只对框外做现有灰色风格化。移除了造成目标碎点观感的逐像素保色选择，保留原Logo、坐标、边框及一秒轨迹叠加。

SW1=A4继续控制原舵机追踪，SW2=B4继续选择第三模式。180度转正、颜色校正、检测阈值、ROI高度及屏幕中心原点不变。仅有两处ROI输出选择修改，显示延迟及全部控制时序保持不变。

小画面184320像素及完整720p三帧2764800像素仿真通过：ROI原RGB逐位一致，框外和普通模式与修改前逐位一致。完整综合、布局布线、bitgen通过：Slice 18628/21216，ERAM 103/108，DSP 40/40；Setup +304ps、Hold +20ps，TNS均0。未降低时钟或放松约束，未上板验证。

命名比特流和完整干净工程ZIP位于`sim/build/roi_original_20261027/Anlu2_ROI_Original_20261028.bit`与同名ZIP。主输出位于`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`，与命名bit的SHA256一致：`51d343a58b5db03d2aaa9779c300c51ddfccfeb8133a8e18cf00a809638f4ed3`。

TD GUI正常打开主工程，完整运行综合和物理设计即可，不需要Python。保留完整user_source，尤其是4个official_logo_*.mif。Logo模块anlogic_logo_eram在hdmi_mixer.v内，历史独立同名文件不是当前实现。

完整验证入口：`powershell -ExecutionPolicy Bypass -File tools/roi_original_20261028/rebuild.ps1`。仿真依赖工作区保留的修改前快照、Python和ModelSim；干净ZIP用于常规GUI编译。历史three_fixes工具只对应历史版本，不能用其旧预期验证新ROI行为。

第四模式在独立目录`../Anlu2_MultiTarget_20261028/`开发，不覆盖本工程。此前历史报告见doc/THREE_FIXES_20261027.md，本修复详见doc/ROI_ORIGINAL_20261028.md；历史资源数字不能作为当前版本结果。

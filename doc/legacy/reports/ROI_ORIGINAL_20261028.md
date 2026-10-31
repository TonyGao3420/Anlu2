# ROI整框原图修复（2026-10-28）

第三模式ROI整个矩形内恢复正常彩色原图，不再逐像素判绿或中值修改目标。原有Logo、框、坐标文字仍叠加；仅框外保持现有灰色风格化。普通模式、舵机、拨码、颜色校正、180度转正和一秒轨迹不变。

生产源码只改roi_background_stylize.v的两处ROI选择。显示延迟、VS/HS/DE/保护/模式/ROI标记不变。小画面184320像素和完整720p三帧2764800像素通过：所有ROI原RGB（含红蓝白暗面及噪点）精确一致，其他像素与修改前逐位相同。

完整主工程综合/布局布线/bitgen通过：{'slices': 18628, 'ERAM': 103, 'DSP': 40}；Setup +304ps、Hold +20ps，TNS均0。继承原时钟/舵机警告，不声称全部路径已约束。

主入口td_project/camera_to_dsi_display.al，命名bit与主输出SHA256一致：51d343a58b5db03d2aaa9779c300c51ddfccfeb8133a8e18cf00a809638f4ed3。本版未上板。第四模式另在../Anlu2_MultiTarget_20261028开发，不覆盖本修复版。

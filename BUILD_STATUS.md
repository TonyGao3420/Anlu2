# 四模式主工程已完成编译与软件验证

## 本次主工程构建结果

合并后Anlu2重新完成全部5项仿真、综合、布局布线及bitgen。Slice 20751/21216，ERAM 103/108，DSP 40/40；Setup WNS +30ps，Hold WNS +20ps，TNS均0。

原三模式5529600像素逐位对比通过（统一增加3个对齐像素时钟），原主目标反馈/PWM逐周期一致；直接拨SW3启动8目标、独立区域/关联/容量、真实DDR槽位延迟测试均通过。

标准主输出与output/Anlu2_Final_4Mode_20261028.bit完全相同。SHA256：`e42b60c661e2e958c193bfe430a86d3da31743f4f72fe94448486acf95aaa61e`。本次没有实板验证。

工程入口为td_project/camera_to_dsi_display.al。仅从本次Anlu2新编译结果发布比特流。

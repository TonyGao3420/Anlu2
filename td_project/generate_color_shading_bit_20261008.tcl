cd {D:/HX1P35A_Contest_202606/Anlu2/sim/build/td_validation_color_shading_20261008}
open_project {video_check.al}
import_device ph1_35p.db -package PH1P35MDG324
top_module design_top_wrapper
launch_runs -step bitgen phy_1
wait_run phy_1
close_project
exit

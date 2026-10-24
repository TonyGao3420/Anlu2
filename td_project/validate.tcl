# Run with TD command shell; no hardware programming.
open_project {D:/HX1P35A_Contest_202606/Anlu2/td_project/camera_to_dsi_display.al}
launch_runs -step gate syn_1
wait_run syn_1
launch_runs -step route phy_1
wait_run phy_1
close_project
exit

# =============================================================================
# 文件名 : anlu2_timing.sdc
# 功能   : 时序约束（时钟与跨时钟域）
#
# ===================== 设计要点与踩坑记录 =====================
# 1) 必须给 MIPI 时钟 pad 与字节时钟建时钟，否则 MIPI 域（103.5MHz）
#    没有任何时序要求，工具不做优化，上板会采到坏数据。
#
# 2) **必须**用 set_clock_groups 把各时钟域声明为异步！
#    踩坑记录：只加 create_clock/rename_clock 而漏掉 set_clock_groups 时，
#    工具会去分析本来就不相关的跨域路径，例如
#        Begin: u_hdmi_core/I_rst_syn_2.clk   (pll_clk_24m, 42ns)
#        End  : O_tmds_ch2_p_syn_2.rst        (HDMI_SERIAL_CLK, 2.666ns)
#    这条 24MHz -> 375MHz 的复位路径被按 375MHz 的严格周期分析，
#    预算只剩 0.656ns 而实际延迟 1.079ns -> Setup WNS = -1.191ns，
#    并连带 HDMI_PIXEL_CLK 域出现 -0.270ns 违例。
#    **这些跨域路径由 HDMI 核内部的同步器处理（官方例程同样如此），
#      不应由静态时序分析去约束。**
#    另：24MHz 域（摄像头 I2C/上电时序）与 HDMI 显示域本来就无数据依赖。
#
# 3) 官方 lab_ex1_mipi_hdmi 的 camera_to_dsi_display.sdc 也是同样做法：
#    create_clock（含 MIPI pad） + derive_clocks + rename_clock + set_clock_groups。
# =============================================================================

# ---------------------------------------------------------------------------
# 1. 输入参考时钟：50MHz 系统时钟
# ---------------------------------------------------------------------------
create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]

# ---------------------------------------------------------------------------
# 2. MIPI 时钟 pad（差分时钟对 P 端）
#    period 2.415ns 取自官方 SDC：828Mbps/lane 下 DDR 时钟约 414MHz
# ---------------------------------------------------------------------------
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

# ---------------------------------------------------------------------------
# 3. 派生 PLL 输出时钟并重命名
# ---------------------------------------------------------------------------
derive_clocks

rename_clock -name {pll_clk_100m}    [get_clocks {u_pll/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m}     [get_clocks {u_pll/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK}  [get_clocks {u_pll/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_pll/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

# ---------------------------------------------------------------------------
# 4. MIPI 字节时钟：由 MIPI 硬核分频输出（约 103.5MHz）
# ---------------------------------------------------------------------------
rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_rx/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# ---------------------------------------------------------------------------
# 5. 异步时钟组（关键！）
#    - MIPI 域    : 与系统域之间由异步行缓存跨域
#    - 24MHz 域   : 摄像头 I2C/上电时序，与视频显示无数据依赖
#    - 100MHz 域  : 仅作 MIPI LP 时钟，与其它域无数据依赖
#    这三域与 HDMI 显示域（像素/串行）都声明为异步，
#    避免工具对本来无关的跨域路径做不可能满足的分析。
# ---------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m}] \
    -group [get_clocks {HDMI_PIXEL_CLK HDMI_SERIAL_CLK}]

# ---------------------------------------------------------------------------
# 6. 异步复位与按键输入
#    注：TD 的 get_ports 不支持 [*] 通配，故用逐位写法；
#        并去掉对 I_rst_n 的 false_path —— 它是 PLL 复位输入，
#        与 I_sys_clk 属于同一个时钟域，需要正常时序分析。
# ---------------------------------------------------------------------------
set_false_path -from [get_ports {I_button[0]}]
set_false_path -from [get_ports {I_button[1]}]
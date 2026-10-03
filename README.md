# Anlu2 — 安路 PH1P35A 摄像头采集与 HDMI 显示工程

FPGA Competition

******************************************************
不要在仓库根目录乱放文件，文件都放在以下几个目录中：
  prj/            ：存放 TangDynasty 工程文件（.al）与构建产物
  lab_user_source/：存放 HDL 源码（当前为官方 lab_ex1 实现）
  doc/            ：存放文档、架构图、引脚映射表
  sim/            ：存放 Testbench（仿真测试文件）—— 当前已归档，见下
  constrs/        ：存放约束文件 —— 当前约束在 lab_user_source/constraints_source/
******************************************************
写代码一定要有注释！！！！！！！！！！
每次 Commit 时写清楚 Summary，不要写无意义的描述
******************************************************

---

## 当前状态（2026-10-03 上板验证）

✅ **摄像头采集 + HDMI 显示全链路跑通，显示器显示完整彩色图像。**

| 项 | 值 |
|---|---|
| 器件 | PH1P35MDG324（PH1P35A 开发板），speed -3 |
| 工具 | TangDynasty **6.2.168116** |
| 顶层 | `design_top_wrapper` |
| 摄像头 | SC520CS（MIPI CSI-2，2 Lane，RAW10，1280×720@60） |
| 输出 | HDMI 1280×720@60 |
| 时序 | Setup WNS = **+1242 ps**，Hold WNS = **+20 ps**，违例 **0/0** |

## 打开与烧录

```
打开工程：prj/Anlu2.al                      （唯一工程）
烧录文件：prj/Anlu2_Runs/phy_1/Anlu2.bit    （1,789,539 字节）
```

## 目录结构

```
Anlu2/
├── prj/
│   ├── Anlu2.al                      <- 唯一工程，顶层 design_top_wrapper
│   └── Anlu2_Runs/
│       ├── syn_1/                    <- 综合
│       └── phy_1/
│           └── Anlu2.bit             <- 可烧录比特流
├── lab_user_source/                  <- 官方 lab_ex1 源码（196 文件，完全采用官方实现）
│   ├── hdl_source/                   <- HDL 源码
│   ├── constraints_source/pin.adc    <- 引脚约束
│   └── ip_source/                    <- IP 定义（PLL / FIFO / DDR / DSP）
├── lab_camera_to_dsi_display.sdc     <- 时序约束
└── doc/                              <- 文档与参考代码
```

## 数据流

```
SC520CS --MIPI CSI-2--> mipi_dphy_rx_ph1p_mipiio_wrapper.sv
        --> csi_unpacket_2lane          (16bit -> 32bit)
        --> raw10_unpacket_2lane        (-> 40bit，4 像素/拍)
        --> uial2axis
        --> isp_top                     (BLC + demosaic_4x_2_0 + AWB)
        --> video_in   【摄像头域 -> DDR 域】
        --> DDR2 整帧缓存
        --> video_out  【DDR 域 -> 像素域】
        --> uivtc + hdmi_mixer
        --> hdmi_tx --> hdmi_phy --> HDMI 显示器
```

## 如何构建

```powershell
cd D:\Anlogic\Anlu2\prj\Anlu2_Runs\syn_1
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' `
  'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'

cd ..\phy_1
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' `
  'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'
```

> ⚠️ **注意**：TD GUI 有时会改写 `Anlu2.al`（清空源文件列表），或把
> `settings.cfg` 的 `ADCList`/`SDCList` 清成 `{}` —— 后者会导致
> `BIT-8123 ERROR: Bitgen is prohibited as there is(are) unconstrained io(s)`。
> 每次用 GUI 跑完建议 `git diff prj/` 检查一下。

## 硬件引脚

| 功能 | 端口 | 引脚 |
|---|---|---|
| 系统时钟 50MHz | `I_sys_clk` | C4 |
| 复位 | `I_rst_n` | R10 |
| 摄像头 I2C SCL | `O_cam_scl` | K3 |
| 摄像头 I2C SDA | `IO_cam_sda` | J3 |
| 摄像头 24MHz MCLK | `O_cam_24m` | L3 |
| 摄像头 PWDNB | `O_cam_rst` | L2 |
| HDMI TMDS 数据 0/1/2 | `O_tmds_ch0/1/2_p` | G16 / F17 / H14 |
| HDMI TMDS 时钟 | `O_tmds_clk_p` | C17 |
| 按键 | `I_button[1:0]` | N2 / J14 |

> 官方顶层 `design_top_wrapper` **没有 LED 端口**，所以板上 LED 全灭属正常现象。

## 重要说明

本工程的 `lab_user_source/` **完全采用官方 lab_ex1_mipi_hdmi 的实现**。

此前曾尝试自研 MIPI 接收 + CSI 解包链路，导致上板图像始终是噪点。
该失败案例（含完整错误原因分析与可复用件）已归档到知识库：

```
安路FPGA知识库/错误案例_Anlu2自研MIPI链路_出噪点/
```

**核心教训：官方例程能跑通时，优先照搬官方实现，不要自己重写。**

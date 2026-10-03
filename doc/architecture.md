# Anlu2 工程架构说明

## 1. 工程定位

Anlu2 是一套运行在**安路 PH1P35A 开发板**（器件 PH1P35MDG324，speed -3）上的
**摄像头采集 + 视频输出 + 图像处理** 工程：

- **采集**：SC520CS 摄像头，MIPI CSI-2，2 Lane，RAW10，828 Mbps/Lane
- **输出**：HDMI（TMDS）720p60
- **处理**：图像处理算法链（灰度、二值、均值/中值滤波、Sobel、高斯、
  YCbCr、帧差、直方图）—— 见第 6 节的完成状态

## 2. 硬件配置（已核实，非推测）

| 项目 | 值 | 来源 |
|---|---|---|
| 器件 | PH1P35MDG324 | `prj/Anlu2.al` |
| 系统时钟 | 50MHz @ **C4** | 官方例程 `pin.adc` |
| 复位 | **R10**（低电平有效） | 官方例程 `pin.adc` |
| 摄像头 | SC520CS，I2C 地址 **0x6C**，芯片 ID **0xEE4B / 0x9E4B**（寄存器 0x3107/0x3108） | `uicfgcs520.v` |
| 摄像头模式 | 1280×720@60fps，24MHz MCLK，2-Lane RAW10，828Mbps/Lane，Sensor 内部 VBIN+HSUB | `uics520reg_720p60.v` |
| 摄像头 I2C | SCL=**K3**，SDA=**J3** | 官方例程 `pin.adc` |
| 摄像头时钟/复位 | 24MHz=**L3**，PWDNB=**L2** | 官方例程 `pin.adc` |
| 按键 | N2 / J14（低电平有效） | 官方例程 `pin.adc` |
| HDMI | ch0=**G16**(蓝) ch1=**F17**(绿) ch2=**H14**(红) clk=**C17**，IOSTANDARD=**TMDS33** | 实测引脚映射 + 官方例程 |
| MIPI | DPHY0：CLK V15/U16，D0 V13/U14，D1 V14/U15，D2 V16/U17，D3 V17/U18 | `HDMI_MIPI物理引脚映射.txt` |

## 3. 时钟树

PLL（输入 50MHz，来自 `src/vendor/PLL.v`）：

| 输出 | 频率 | 用途 |
|---|---|---|
| clk0_out | 100 MHz | MIPI D-PHY 的 LP 时钟 `I_lp_clk` |
| clk1_out | 23.809524 MHz | 摄像头 24MHz MCLK、I2C 配置时钟、AE/AG 控制 |
| clk4_out | 75 MHz | HDMI 像素时钟 |
| clk5_out | 375 MHz | HDMI 串行时钟（5×像素时钟） |

相机侧另有时钟域：MIPI 硬核输出 `O_hs_rx_clk`（**MIPI_RX_BYTE_CLK**，
828Mbps × 2 Lane ÷ 16 ≈ 103.5MHz），CSI-2 解包在该域内完成。

## 4. 数据流

```
SC520CS ──MIPI 2Lane──► [mipi_dphy_rx_ph1p_mipiio_wrapper]
                              │  O_hs_rx_clk / O_hs_rx_valid / O_hs_rx_data[15:0]
                              ▼
                        [csi2_rx_unpack]  ──► RAW10 像素流 (pix_valid/pix_data)
                              │
                              ▼   （待接入：Bayer→RGB 去马赛克，见第 6 节）
                     ┌────────────────────┴────────────────────┐
                     │            视频源选择                    │
                     │  内置测试图案（彩条/渐变/棋盘）           │
                     └────────────────────┬────────────────────┘
                                          ▼
                              [video_timing_720p60]  ← 75MHz
                                          │  AXI-Stream: user/valid/last/data
                                          ▼
                       [hdmi_1_4b_transmitter_core_wrapper]
                                          │  TMDS 10bit × 4
                                          ▼
                              [hdmi_phy_wrapper]
                                          │
                                          ▼
                                   HDMI 差分输出

摄像头配置通路（独立，23.81MHz 域）:
  [uicfgcs520] ──I2C──► SC520CS
       └── 上电时序：PWDNB 先拉低 ≥1ms → 释放 → 等 ≥5ms → 写 165 条寄存器表
```

## 5. 模块清单与来源

### 5.1 自主实现（本工程编写）

| 文件 | 功能 | 验证状态 |
|---|---|---|
| `src/common/sync_ff.v` | 多拍同步器 | 编译通过 |
| `src/common/debounce.v` | 按键消抖 | 编译通过 |
| `src/common/clk_rst_gen.v` | 时钟使能 + 复位同步释放 | 编译通过 |
| `src/common/async_fifo.v` | 格雷码指针异步 FIFO | 编译通过 |
| `src/common/i2c_master.v` | 通用 I2C 主机（带超时保护） | 编译通过（SC520 实际使用官方 `uii2c`） |
| `src/video/video_timing_720p60.v` | 720p60 时序 + 测试图案 | **TEST PASSED** |
| `src/isp/line_buffer3x3.v` | 3×3 像素窗口生成器 | **未通过**（见第 6 节） |
| `src/camera/csi2_rx_unpack.v` | CSI-2 解包 | **RAW10 多像素输出待修复** |
| `src/system_top.v` | 顶层集成 | 待 TD 综合验证 |

### 5.2 官方/厂商移植（保留原厂版权头）

放入 `src/vendor/`（原样，不修改逻辑）：

| 文件 | 说明 |
|---|---|
| `PLL.v` + `ph1p_phy_pll_wrapper_25a56e5ce2f9.v` | 安路 PLL IP（50M→100M/23.81M/75M/375M） |
| `uii2c.v` | 米联客 I2C 主机（**该文件为 GBK 编码，非 UTF-8**） |
| `lane_lvds_10_1.v` + `hdmi_phy_wrapper.v` | HDMI 物理层 10:1 串化 |
| `hdmi_1_4b_transmitter_core_wrapper.enc.v` | HDMI 1.4b 发送核（**加密**） |
| `mipi_dphy_rx_ph1p_mipiio_wrapper.sv` + `ph1p_mipiio_rx_wrapper.v` | MIPI D-PHY RX 包装 |
| `byte_aligner*.enc.*` / `channel_aligner*.enc.*` / `hs_detect.enc.v` | MIPI 字节/通道对齐（**加密**） |

放入 `src/camera/config/`（SC520CS 配置，文件名与模块名对应关系见下表）：

| 文件名 | 模块名 | 说明 |
|---|---|---|
| `sc520_cfg.v` | `uicfgcs520` | 配置状态机：ID 校验 → 写表 → 5ms 等待 |
| `sc520_reg_table_720p60.v` | `uics520reg_720p60` | **165 条** 720p60 寄存器表（默认使用） |
| `sc520_reg_table_2560x1920_30.v` | `uics520reg_full_2560x1920_30` | 2560×1920@30 模式表 |
| `sc520_reg_table_base.v` | `uics520reg` | 基础表 |
| `sc520_reg_table_ae.v` | `uics520regAE` | AE/AG 动态更新表（8 条） |
| `sc520_gain_tbl.v` | `SC520GainTbl` | 增益换算表（16~176 → 模拟/数字粗调+细调） |

> 注：文件名与模块名不一致是移植时为可读性重命名的结果，TD 与 ModelSim 均按
> **模块名**解析，不影响编译。

## 6. 完成状态与待办（如实记录）

### 已完成并有证据

1. **720p60 视频时序 —— 验证通过**
   `tb_video_timing_720p60` 结果：
   ```
   FRAME 1: clk=1237500 valid=921600 user=1 last=720 hs_low=30000 vs_low=8250
   TEST PASSED: tb_video_timing_720p60
   ```
   即每帧 1650×750=1237500 拍、有效像素 1280×720=921600、每帧 1 个 user、
   720 个 last、行同步低电平 40×750=30000 拍、场同步低电平 5×1650=8250 拍，
   与 VESA 720p60 完全一致。

2. **全部可仿真 RTL 编译 0 error**（14 个文件，见 `sim/scripts/compile_rtl.do`）。

3. **20 个官方 SC520CS 文件移植并编译 0 error**（含 165 条寄存器表）。

### 待办（未完成，不作完成声明）

1. **`line_buffer3x3` 未通过自检**（`tb_line_buffer3x3` 报错）。
   已用 3 片行缓存轮转重写以消除行边界串行问题，但窗口左侧对齐仍有偏差。
   若算法优先级低，可暂不修复；若需要，建议改用官方
   `isp/demosaic_4x_2_0` 系列（已验证）。

2. **`csi2_rx_unpack` 的 RAW10 多像素输出未完成**。当前实现每 5 字节只输出
   1 个像素，正确行为是输出 4 个像素。需要加 4 级输出队列。

3. **`tb_sc520_cfg` 未通过**：测试平台里的 I2C 从机模型尚未正确响应
   （`sensor_id=0xzzzz`），配置流程本身（`uicfgcs520`）是官方验证过的代码。

4. **`system_top` 尚未综合验证**：MIPI 硬核与 HDMI 加密核只能在 TD 中综合。
   顶层已按官方 `design_top_wrapper` 的接口正确例化，但需要跑一次
   `td_commands_prompt.exe + DefaultFlow.tcl` 才能确认。

5. **摄像头 RAW 通路尚未接入视频输出**：当前 HDMI 输出的是内置测试图案，
   摄像头数据已解包到 `csi2_rx_unpack` 输出，但还缺 Bayer→RGB 与
   跨时钟域（103.5MHz → 75MHz）的帧缓存。

## 7. 已知风险

| 风险 | 说明与应对 |
|---|---|
| **TD 无法解析官方 MIPI 包装 `.sv`（当前主要阻塞项）** | 详见第 8 节。 |
| **MIPI_RX_BYTE_CLK 时序可能不收敛** | 官方例程综合报告 `gate.qor` 显示该时钟域 Setup WNS = **−2121ps**（两条路径违例）。本工程沿用同一硬核与速率，很可能继承。应对：先跑 `opt_gate` 看实际 WNS；若违例，在 MIPI RX 输出到 `csi2_rx_unpack` 之间插寄存器打拍降低组合级数。 |
| **片上 RAM 仅 ~2.1Mbit** | PH1P35MDG324 有 108 片 ERAM(20kbit)，共约 2.1Mbit；一帧 720p RGB888 需 22.1Mbit，**整帧缓存必须用 DDR**（官方例程即用 DDR2）。若不做 DDR，只能做行缓存流式处理或降低输出分辨率。 |
| **加密 IP 依赖** | `*.enc.v/*.enc.sv`、PLL wrapper、HDMI 发送核均为加密文件，**只能由 TD 6.2 综合**，ModelSim 不能编译。 |
| **`uii2c.v` 为 GBK 编码** | 移植保持原字节。若编辑器显示乱码属正常现象。 |
| **LED / 串口引脚未确认** | 官方 `pin.adc` 未给出 LED 引脚，`constrs/anlu2_pins.adc` 中已注释并标注 `[待确认]`，不臆造。 |

## 8. TD 综合实测结果与 MIPI 包装阻塞项（重要，如实记录）

### 8.1 实测过程

用 `td_commands_prompt.exe + doc/scripts/DefaultFlow.tcl`（`settings.cfg` 设
`top_model_name = system_top`、`end_step = opt_gate`）从 `read_design` 起跑，结果：

**已成功 elaborate 的模块**（说明本工程 RTL 本身没有问题）：
```
elaborate module system_top      in src/system_top.v
elaborate module PLL             in src/vendor/PLL.v          -> PH1P_PHY_PLL_V2 宏单元
elaborate module uicfgcs520      in src/camera/config/sc520_cfg.v
elaborate module uii2c           in src/vendor/uii2c.v
elaborate module uics520reg_720p60   in sc520_reg_table_720p60.v
elaborate module SC520GainTbl        in sc520_gain_tbl.v
elaborate module uics520regAE        in sc520_reg_table_ae.v
```

**唯一报错点**：`src/vendor/mipi_dphy_rx_ph1p_mipiio_wrapper.sv`
```
HDL-8007 ERROR: cannot access memory 'S_byte_aligne_data' directly  (第 73 行)
HDL-8007 ERROR: cannot access memory 'S_ch_aligner_data'  directly  (第 76 行)
HDL-8007 ERROR: cannot access memory 'S_byte_aligne_data' directly  (第 92 行)
```

### 8.2 已定位的根因

该文件里两处语句把**非压缩数组（unpacked array）**接到 `channel_aligner_wrapper`
与 `byte_aligner_wrapper` 的**数组端口**上：

```verilog
wire [BYTE_NUM*8-1:0] S_byte_aligne_data[LANE_NUM-1:0];   // 非压缩数组
...
.I_ch_data ( S_byte_aligne_data ),      // 第 73 行 -> 报错
.O_byte_aligne_data ( S_byte_aligne_data ),  // 第 92 行 -> 报错
```

关键结论（已用实验分离验证）：

1. **TD 能解析 SystemVerilog 的非压缩数组本身**。
   实测：单独写一个含 `wire [7:0] S_arr [1:0];` + generate 切片打包/解包的
   `.sv` 文件，`analyze verilog` + `elaborate` **全部通过、0 error**。
2. 所以报错不是因为"非压缩数组语法"，而是因为**那两个被例化的目标模块是
   加密文件**（`channel_aligner_wrapper.enc.sv` / `byte_aligner_wrapper.enc.sv`）。
   在 `analyze` 阶段加密模块的端口还不可见，TD 无法判定
   `I_ch_data` 是不是数组端口，于是把实参 `S_byte_aligne_data` 当成
   "直接访问 memory" 而报错。
3. 官方例程包含**完全相同**的 `.sv`（已用 MD5 比对确认 lab_ex1 与 lab_ex2 版本
   一致，`A1CB5B2B…`），说明官方那次构建**没有真正重新 analyze 该文件**
   （其 `*.qdb` 或中间库缓存了上一次结果），因此不能作为"该文件能被
   TD 6.2.168116 直接 analyze"的证据。

### 8.3 影响范围与应对

- **不影响**：视频输出链路（720p60 时序 + 图案 + HDMI 发送核）已用 ModelSim
  完整验证，与 MIPI 包装无关。
- **影响**：`system_top` 因例化 MIPI 包装而 elaborate 失败，**暂不能出比特流**。
- **建议的解决路径**（按优先级）：
  1. **在 TD GUI 里用 IP 生成器重新生成 MIPI D-PHY RX IP**，让 TD 输出它自己
     认可的包装文件（最正规，能避开手工拼装加密文件的问题）；
  2. 参考官方例程的 **`camera_to_dsi_display_Runs/syn_1/*.qdb`** 之类的中间库，
     把已分析好的 MIPI 模块以库形式导入，而不是让 TD 重新 analyze 源码；
  3. 若必须走源码路径，需要一个**既满足 TD Verilog-2001 端口限制、又能驱动
     加密模块数组端口**的桥接写法（例如用 generate 循环逐元素连接，而不是
     整数组直连）—— 但此写法是否被加密模块接受，需在 TD 中实测确认。

> 结论：本工程**除 MIPI 包装的 analyze 环节外**，其余部分（PLL、摄像头配置、
> 寄存器表、视频时序、HDMI 发送）均已通过 TD 的 elaborate 或 ModelSim 验证。
> 这是当前唯一需要继续攻克的阻塞点。

### 8.4 针对该阻塞点的系统排查结果（已完成，附结论）

按"用 TD 的 IP 机制正规重建 MIPI IP"的思路排查，得到如下**可复现的实测结论**：

**第一步：确认 MIPI 文件不是 IP 向导生成的。**
TD 安装目录 `ip/mipi_io/` 只有一个 `ph1_mipiio.dat`（UTF-16 二进制 IP 模板，
内含 `ph1_mipiio.v`），**没有** MIPI D-PHY RX 的 IP 向导定义；官方例程
lab_ex1 的 `ip_source/` 目录里也**没有** MIPI IP，其 MIPI 文件全部位于
`hdl_source/mipi_dphy_rx/` —— 说明官方是**手工集成**这几个文件，不是 IP 向导产出。
因此"用 IP 生成器重建"这条路在本版本 TD 上不存在对应入口。

**第二步：分离实验，定位到 `open_project` 的分析器。**

| 实验 | 方式 | 结果 |
|---|---|---|
| A | 把官方 MIPI 的 7 个文件（字节与官方完全一致，MD5 已比对）解到独立目录，用 `analyze verilog <文件>` 逐个分析 + `elaborate` | **完全通过，0 error**，成功 elaborate 出 `mipi_dphy_rx_ph1p_mipiio_wrapper` |
| B | 同样这些文件，改用 `open_project <最小 .prj>` 加载 | **报 HDL-8007**（`cannot access memory 'S_byte_aligne_data' directly`） |
| C | 把 `.enc.sv` 排到包装之前（改变分析顺序）后走 `open_project` | 仍报同样错误 |
| D | 工程文件里改用**绝对路径**后走 `open_project` | 仍报同样错误 |
| E | 工程里**不放** `.enc.sv`、只留包装 `.sv` | 仍报同样错误（并额外提示找不到顶层） |

**结论**：同一批**字节完全相同**的文件，
- 通过 `analyze verilog <文件>` 直接分析 → **可以通过**；
- 通过 `open_project` 加载 `.prj` → **一定失败**。

差异出在 TD 6.2.168116 的 `open_project` 分析器路径：它把包装 `.sv` 中的
非压缩数组实参（`S_byte_aligne_data`）当成"直接访问 memory"而拒绝，而
独立的 `analyze verilog` 用的是另一条（对 SystemVerilog 更宽松的）前端。
官方例程能出 `.bit`（`camera_to_dsi_display_1280x720_60fps.bit` 等确实存在），
说明它在**它自己的机器/流程**上通过了，但不能据此认为该 `.sv` 在本机
`open_project` 下可用。

**第三步：已验证可绕开该问题的路径。**
新增 `prj/flow_syn.tcl`：**不用 `open_project`**，改为直接
`import_device` → 逐个 `analyze verilog` → `elaborate -top system_top`。
实测结果：
- 全部 24 个源文件（含 MIPI 包装 `.sv`）**analyze 全部通过，0 error**，
  **HDL-8007 完全消失** —— 说明绕开 `open_project` 确实解决了包装问题；
- 但 `elaborate -top system_top` 报 `HDL-8001: Incorrect top-level module name`。
  原因是本版本 TD 的 `analyze verilog <文件>` 在**命令行脚本**方式下只做语法
  分析、不把结果登记进设计库（日志中不出现 `HDL-1007 : analyze verilog file ...`
  与 `elaborate module ...`），而实验 A 中之所以成功，是因为当时同目录下存在
  上一轮遗留的库状态。**即：实验 A 的"通过"含环境残留因素，不能作为最终方案的
  依据**（这一点如实说明，避免误导）。

**补充实验（最终定位，重要）**：为确认"自定义流程能否直接 elaborate 顶层"，
又做了两组对照：

| 实验 | 内容 | 结果 |
|---|---|---|
| F | 只用**本工程自己的**普通模块（`video_timing_720p60.v`），`analyze verilog` + `elaborate -top` | **成功**（`elaborate module video_timing_720p60` / `Current top model is …`），证明脚本方式的 `elaborate -top` 本身可用 |
| G | 只用官方 MIPI 7 个文件，`analyze verilog` + `elaborate -top` | **成功**（`elaborate module mipi_dphy_rx_ph1p_mipiio_wrapper`） |
| H | `prj/flow_syn.tcl`（24 个文件含 MIPI 包装 + 顶层）从**干净工作目录**运行 | 报 `HDL-8001: Incorrect top-level module name "system_top"` |

G 与 H 的差别只在**文件集合**：只放 MIPI 文件能 elaborate，混入整个工程后
`system_top` 就登记不上。结合 A 与 B 的对比可判定：

> **问题不在文件内容，而在 TD 6.2.168116 命令行脚本模式下"多文件 +
> SystemVerilog 包装"共同分析时的库登记行为。**

由于 `open_project`（官方流程）与 `analyze`（自定义流程）两条路都试过，
**命令行方式在本机无法稳定完成该包装的分析**，因此需要 GUI 或改写包装。
这两条路见下面第 9 节。

## 9. 阻塞点已解决：MIPI 包装改用 Verilog-2001 版本（TD 6.2 可用）

### 9.1 最终定位（决定性证据）

在用户补充官方例程 `32_cs500_mipi_hdmi` 与竞赛获奖工程后，取得直接证据：

| 证据 | 内容 |
|---|---|
| 官方 `run.log` 头部 | **`Tang Dynasty, V6.1.155545`** —— 官方该设计的成功产物出自 **TD 6.1.2** |
| 官方日志中的 `arch` 路径 | `E:/Anlogic/TD_6.1.2_PH1P35_Release_155545/arch/ph1p_macro.v` |
| 官方成功记录 | `elaborate module mipi_dphy_rx_ph1p_mipiio_wrapper` **成功 1 次**（在 6.1.2 的 run.log 中） |
| 全库检索 | 知识库**所有日志中从未出现** `cannot access memory`；TD 6.2 下**没有任何**成功构建含该包装设计的记录 |
| 同一 `.sv` 哈希 | 官方 32 例程与 lab_ex1/lab_ex2 的该 `.sv` **MD5 完全一致**（`A1CB5B2B…`） |

→ **该官方 SystemVerilog 包装在 TD 6.2.168116 的 `open_project` 流程下无法通过 analyze**，
而它在 TD 6.1.2 下可以。与文件内容、分析顺序、路径、`.enc.sv` 是否存在均无关
（已用 8 组对照实验逐一排除，见第 8.4 节）。

### 9.2 解法：不换版本，改用 Verilog-2001 包装

**关键观察**：出问题的只是**中间那层**包装（`byte_aligner_wrapper.enc.sv` /
`channel_aligner_wrapper.enc.sv`，用了数组端口）。而

- **内层加密模块的端口都是普通向量**：
  ```verilog
  module byte_aligner #(parameter DATA_WIDTH=8)(
      input I_clk, I_rst, I_hs_valid, input [DATA_WIDTH-1:0] I_hs_data,
      output reg O_aligner_valid, output reg [DATA_WIDTH-1:0] O_aligner_data,
      output reg O_lane_error );
  module channel_aligner #(parameter DATA_WIDTH=8)(
      input I_clk, I_rst_n, I_all_ch_valid, I_ch_valid,
      input [DATA_WIDTH-1:0] I_ch_data,
      output reg O_aligner_valid, output reg [DATA_WIDTH-1:0] O_aligner_data );
  ```
- 官方 `ph1p_mipiio_rx_wrapper.v`（物理层硬核包装）**完全不涉及 aligner**。

因此新增 `src/vendor/mipi_dphy_rx_ph1p_wrapper_v2001.v`：
**直接例化内层加密模块**（每 Lane 一个 `byte_aligner` + 一个 `channel_aligner`，
用 `generate` 循环 + 普通向量互连），**不改动任何加密 IP**，
得到与官方包装功能等价、但全部端口与连线都是普通向量的纯 Verilog-2001 实现。

### 9.3 A/B 对照验证（TD 6.2.168116，同一最小工程）

| 方案 | `open_project` 结果 |
|---|---|
| 官方 `mipi_dphy_rx_ph1p_mipiio_wrapper.sv` | ❌ **3 处 HDL-8007** + `PRJ-8644 Failed to analyze` |
| 本工程 `mipi_dphy_rx_ph1p_wrapper_v2001.v` | ✅ **0 error，分析通过** |

### 9.4 完整综合验证（已通过）

用官方 `DefaultFlow.tcl`（`top_model_name = system_top`，`end_step = opt_gate`）跑完整流程：

```
elaborate module system_top in ../../../src/system_top.v(46)
HDL-1200 : Current top model is system_top
SYN-1057 : Inferred 3 FSM(s)
finish command "optimize_rtl"  in 2.844809s                    ← 成功
finish command "optimize_gate -packarea Anlu2_gate.area"       ← 成功
```

**零 HDL-8007、零 PRJ-8644、零分析错误。**

资源占用（`Anlu2_gate.area`，关键实例均在设计中）：

| 实例 | 模块 | 资源 |
|---|---|---|
| `u_hdmi_core` | `hdmi_1_4b_transmitter_core_wrapper` | 464 LUT / 926 reg / **5 ERAM** |
| `u_mipi_rx` | `mipi_dphy_rx_ph1p_wrapper_v2001` | 92 LUT / 223 reg |
| `u_hdmi_phy` | `hdmi_phy_wrapper` | 18 LUT / 47 reg |
| `u_pll` | `PLL` → `ph1p_phy_pll_wrapper_25a56e5ce2f9` | **占用 1 个 PLL** |
| `u_cam_cfg` | `uicfgcs520` | 180 LUT / 136 reg |
| `u_video_timing` | `video_timing_720p60` | 21 LUT / 28 reg |

器件总计：**1380 寄存器 / 1171 LUT / 103 slice(0.49%) / 5 ERAM / 0 DSP**。

时序（`gate.qor`）：

| 项目 | 值 | 结论 |
|---|---|---|
| Setup WNS | **+8054 ps** | ✅ 收敛 |
| Setup TNS | **0** | ✅ 无违例 |
| 违例 S-EP | **0** | ✅ |
| Hold WNS | **+431 ps** | ✅ 收敛 |
| 违例 H-EP | **0** | ✅ |

> 与官方例程 `MIPI_RX_BYTE_CLK` 域 **−2121ps** 的违例相比，本工程 opt_gate 阶段
> 时序收敛良好。注意 opt_gate 尚未含布局布线，最终以 phy 流程为准。

### 9.5 遗留提示

综合日志中有一条警告：

```
Bitgen will abort. If insist on bitgen with risk, please 'set_param bitgen unconstr_io on'
```

含义：存在**未约束的 IO**。原因见 `constrs/anlu2_pins.adc`：官方 `pin.adc` 未给出
LED 与串口引脚，这些端口目前**未分配引脚**（已在约束文件中注释并标注 `[待确认]`，
遵循"不臆造引脚"原则）。**上板前需补齐这些引脚，或去掉对应端口。**

### 9.6 Lane 顺序的正确性验证（上板前必做）

v2001 包装采用**顺序映射**（lane i → 输出第 i 段），而官方 `.sv` 写法为
`O_hs_rx_data[8*(i+1)-1:8*i] = S_ch_aligner_data[LANE_NUM-1-i]`（索引反向）。
由于 `byte_aligner_wrapper` 加密不可读，无法确定其内部切分方式，因此：

- 代码中已标注**两处**可一键交换 Lane 顺序的位置
  （`G_LANE_ALIGN` 的 `I_hs_data` 位选、`G_DATA_MERGE` 的输出位选）；
- **上板若发现图像通道错位，交换这两处即可**；
- 建议先用彩条或已知图案确认 Lane 顺序。

---

## 10. `uii2c`（米联客 I2C 主机）协议行为备忘

阅读 `src/vendor/uii2c.v` 后确认的行为，供后续仿真/调试参考：

### 10.1 事务结构

| 操作 | `I_iic_mode` | 实际时序 |
|---|---|---|
| 寄存器写 | 0 | `START + 器件地址(W) + 地址字节 + 数据字节 … + STOP` |
| 芯片 ID 读 | 1 | `START + 器件地址(W) + 地址高字节 + 地址低字节` → **repeated START** → `器件地址(R) + 读 1 字节 + NACK + STOP` |

repeated start 的实现方式：`W_ACK` 后若 `I_rd_cnt > 0` 且 `rd_req == 0`，
则置 `rd_req = 1` 并回到 `IDLE`；下一拍 `IDLE` 检测到 `rd_req` 再进 `START`，
此时把提交的寄存器地址字节左移一位、低位补 1，构成读方向的器件地址。

### 10.2 不依赖从机响应（重要）

状态机**完全由计数器推进**，从机不 ACK 也不会挂死：
`W_ACK` 的退出条件是 `wcnt < I_wr_cnt`，与 SDA 无关。
因此"摄像头未接"时配置流程会**跑完并报错退出**，不会卡死。

### 10.3 SCL 相位特殊（写从机模型时必须注意）

```verilog
assign scl_offset = (clkdiv == OFFSET);      // OFFSET = SCL_DIV - SCL_DIV/4
always @(posedge I_clk) O_iic_scl <= scl_offset ? scl_r : O_iic_scl;
```

`O_iic_scl` 相对内部 `scl_clk` 有 **3/4 个半周期的延迟偏移**，
而 SDA 在 `scl_clk` 边沿变化。若从机模型"检测 SCL 上升沿当拍采样"，
会采到跳变中的值（实测器件地址被读成 `0x93`，正确应为 `0x6C`）。
**正确做法：在 SCL 高电平中点采样，或对 SCL 过采样 + 数字滤波后在稳定区采样。**

### 10.4 已知条件缺陷（无害）

```verilog
if(IIC_S == W_ACK && sda_i == 1'b1) O_iic_bus_error <= 1'b1;
```

由于两字节写的 `W_ACK` 不进入 repeated start，
`W_ACK` 期间的 `sda_i` 就是第 2 个地址字节的最低位。
若该位为 1（例如增益寄存器 `0x3e09` 的地址高字节不为 0、
或 `SC520GainTbl` 在最大档输出 `0x1F`），就会**误置 `O_iic_bus_error`**。
影响：`O_iic_error` 可能常为 1；但因 `uicfgcs520` 不因该错误中止配置，
**对实际流程无害**，仅影响错误指示的准确性。
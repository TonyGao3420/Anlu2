# Anlu2 工程分析（2026-10-18）

> 分析对象：`D:\Anlogic\Anlu2`（分支 `第一版工程`，HEAD `e5300d6`，2026-10-11 13:18）。
> 分析依据：工作区实际源码、`td_project/camera_to_dsi_display.al`、`td_project/camera_to_dsi_display_Runs/` 的最新构建报告，以及 `doc/` 下的阶段说明。
> 本文只描述“当前实际代码与构建产物”，不把历史文档中的描述自动当作现状。凡文档与代码不一致处，均在文中单独标出。

---

## 1. 结论摘要

1. 这是一个 **SC520CS → MIPI CSI-2 → RAW10 → Bayer 插值 → 白平衡 → DDR2 四帧缓存 → HDMI 1280×720** 的完整视频工程，主顶层为 `user_source/hdl_source/design_top_wrapper.v`。
2. 当前视频主链路的核心新增层是：RAW 域九点空间校正（`raw_measured_shading`）、帧级稳定 AWB（`awb_frame_stable`）、显示端公共亮度曲线（`display_common_tone`）、边缘残留红色修正（`display_edge_color`）、绿色单目标 ROI（`roi_target_tracker`）和 ROI 中心坐标 OSD（`roi_center_osd`）。
3. 最新一次完整布局布线（2026-10-11 14:27）结果：**Setup WNS +0.105 ns、Hold WNS +0.020 ns，TNS 均为 0；18,916 slices（89.16%）、17,947 LUT6（84.59%）、54/108 ERAM、40/40 DSP**。资源已经很紧，尤其是 DSP 已用满。
4. 现有 `doc/` 文档明显落后于源码：新增的 7 个模块没有被 `CODE_GUIDE.md` 和《工程结构与模块说明》收录；多处仍把旧的 `awb.v`、红色 ROI、`video_enhance` 提亮写成当前实现。
5. 两个按键实际接的是 **曝光（AE）**，不是增益（AG）；`I_button` 直接进入 `ae_set`，顶层没有实例化 `key_remove_shakes`。这与文档“两个按键只接增益减/增”的描述相反。
6. 显示/识别颜色链路由多层补偿叠加而成，顺序和开关必须成套修改；当前 `display_color_shading` 在顶层被 `RGB_SHADING_ENABLE(0)` 关闭，`video_enhance` 也被 `ENABLE(0)` 旁路，真正生效的是 RAW 九点校正、边缘红色修正和公共亮度曲线。
7. 工程中仍有大量历史模块、同名备份和占位模块，且部分未使用模块仍在 `.al` 清单中。新增逻辑前应先清理或至少确认综合是否真的裁剪，否则会在 89% slices / 100% DSP 的余量下直接碰到时序和资源上限。

---

## 2. 工程定位与目录

### 2.1 定位

- 器件：`PH1P35MDG324`，TD 6.2.168116，工程名沿用 `camera_to_dsi_display`。
- 摄像头：SmartSens SC520CS，1280×720@60、RAW10、MIPI CSI-2 双 Lane、828 Mbps/Lane。
- 显示：HDMI 1280×720，RGB888，像素时钟 75 MHz，VTC 总周期 1650×750。
- 扩展：绿色单目标检测、目标框、ROI 中心坐标 OSD、双轴舵机 PWM。

### 2.2 目录分工

| 目录 | 作用 | 当前状态 |
|---|---|---|
| `user_source/hdl_source/` | 手写 RTL，按顶层、ISP、MIPI、DDR、显示、摄像头配置、Track2 分层 | 在用；存在大量同名备份和未编译文件 |
| `user_source/ip_source/` | PLL、FIFO、除法器、AWB 延迟 RAM 等生成型 IP | 在用 |
| `user_source/constraints_source/` | `pin.adc` 引脚约束；`timing.sdc` 为历史备用 | `pin.adc` 在用；`timing.sdc` 不在主约束 |
| `td_project/` | TD 工程入口、SDC、构建脚本和 `*_Runs/` 输出 | 在用 |
| `sim/` | ModelSim 脚本与 30 个 Testbench | 在用；`sim/build/` 目录在本副本中不存在 |
| `doc/` | 架构、代码说明、阶段总结 | 部分过时，需以本文和实际源码为准 |

### 2.3 源码规模

- `.al` 直接列入的 Verilog 源文件 47 个、SystemVerilog 入口 7 个（其中包含 `AutoExcluded` 的历史模块和厂商加密/包装文件），IP 入口 8 个。
- `hdl_source` 目录下实际 `.v/.sv` 文件远多于编译清单；大量是旧版本、备份或占位模块。
- 核心新增文件（当前 `.al` 已包含）：
  - `awb_frame_stable.v`
  - `isp/raw_measured_shading.v`
  - `video/display_color_shading.v`
  - `video/scene_color_stream.v`
  - `video/display_common_tone.v`
  - `video/display_edge_color.v`
  - `video/roi_center_osd.v`

---

## 3. 实际数据通路

### 3.1 采集与 ISP

```
SC520CS (RAW10, 2-lane)
  -> MIPI D-PHY RX (DPHY0, 2 lane, 1 byte/lane)
  -> csi_unpacket_2lane (DT=0x2B, 帧起止)
  -> raw10_unpacket_2lane (5 byte -> 4 x 10 bit)
  -> uial2axis (tuser/tlast, 320 beat/line)
  -> raw_measured_shading (BGGR 四平面九点双线性，黑电平 64，8 拍)
  -> demosaic (3x3 行缓存 + 双线性, BGGR)
  -> data128_96 (4 x RGB888 -> 96 bit)
  -> awb_frame_stable (整帧统计, Q16 R/B 增益, 50 级除法器, 1/4 缓变)
  -> data96_128 (4 x 96 bit -> 3 x 128 bit)
  -> video_in
```

要点：

- `isp_top` 的 `O_tready` 在顶层恒为 `1'b1`，整条 ISP 是连续流、不支持反压；上游摄像头不能停。
- `raw_measured_shading` 的九点增益表覆盖 3×3 节点 × 4 个 Bayer 平面，共 36 个系数；低于黑电平 64 的像素原样通过。
- `awb_frame_stable` 只统计“非过暗、非近饱和”的像素（`pixel_sum < 720` 且各通道 > 黑电平+7），整帧统计完成后在下一个 SOF 更新；有效样本少于 256 时保持上一组增益。
- AWB 的 R/B 增益只有上限钳位（约 16 倍），没有下限钳位；场景颜色极端时可能出现通道被压得很低的情况，需要实拍确认。
- 颜色处理顺序不可随意调换：RAW 校正 → 去马赛克 → AWB → DDR → 显示端边缘/亮度；`display_color_shading` 是显示端备用层，当前关闭，避免与 RAW 校正叠加。

### 3.2 DDR 帧缓存

```
video_in -> w128_d512_fifo -> mc_to_user_interface -> ph1p35_324_ddr_wrapper -> DDR2
video_out <- w128_d512_fifo <- mc_to_user_interface <- ph1p35_324_ddr_wrapper <- DDR2
```

- 4 帧轮转，基地址：`0`、`7_000_000`、`14_000_000`、`21_000_000`。这是 25 位应用地址，单位为 16 位字（2 字节）；对应字节地址 0 / 14 MB / 28 MB / 42 MB。
- 每帧 1280×720×3 = 2,764,800 字节；写侧每 240 个 128 位字为一次突发，地址每次 +8（正好 16 字节），四帧合计约 45 MB，落在 64 MB DDR 空间内。
- 写指针 `S_video_in_wp` 在帧首递增；显示读指针 `O_video_out_rp = wp + 2 (mod 4)`，即显示滞后写入约两帧，降低撕裂风险。
- `video_in` 在 `I_mipi_rx_error` 有效时冻结写指针，意图是让下一帧覆盖出错帧；顶层当前把该输入恒接 `0`，所以这条保护实际未启用。
- `video_out` 每 16 像素读 3 个 128 位字，FIFO 预取深度 512；读触发要求剩余空间 ≥300，避免 DDR 读延迟导致 FIFO 溢出。
- `mc_to_user_interface` 用 155 位命令 FIFO 把读写请求转成 DDR 应用接口；写掩码恒 0，写命令优先。

需要复核的点：

- 写/读启动条件分别依赖对方的 `busy` 标志，但两个标志都是寄存器输出；在同一拍双方都空闲时，理论上可能同时启动。顶层地址 mux 写优先，此时读命令会拿到写地址。建议后续加显式仲裁（grant）或在 `mc_to_user_interface` 内按命令类型分别锁存地址。
- 四个帧基地址对应 0/14/28/42 MB，最后一帧结束约 44.8 MB；这与 512 Mb x16 器件（64 MB）和 `AXI_ADDR_WIDTH=26` 的 64 MB 字节地址空间一致。仍建议核对板上实际 DDR 容量与地址译码，不要把 64 MB 空间当成可以随意增加帧数的余量。

### 3.3 显示与叠加

```
video_out (24-bit RGB)
  -> hdmi_mixer (Logo / 中文 / 帧计数 / ROI 框 / 中心坐标 HUD)
  -> scene_color_stream (相机/受保护图层分离，坐标重建，8 拍)
  -> display_edge_color (6 拍边缘红/蓝修正)
  -> video_enhance (6 拍，当前 ENABLE=0 单位增益旁路)
  -> display_common_tone (3 拍公共亮度曲线)
  -> hdmi_tx -> HDMI 1.4b 加密核 -> TMDS PHY
```

- `hdmi_mixer` 的读使能直接取 VTC 的 DE；`video_out` 的两级寄存与 mixer 的两拍同步是配套调过的，不能单独给 RGB 再加延迟。
- `scene_color_stream` 在 VS 上升沿重新对齐坐标，用 DE 计数重建 1280×720 光栅；相机 RGB 走 8 拍校正/延迟，受保护图层（Logo、文字、框、HUD）走另一条 8 拍延迟，最后按保护标志选择。这样 ROI 与显示看到的是同一份相机像素。
- `display_color_shading` 目前 `RGB_SHADING_ENABLE(0)`，只保留 8 拍延迟；如果重新打开，会与 RAW 九点校正形成两层空间补偿，必须先确认不重复。
- `display_edge_color` 只在显示端做残留红色修正：中心矩形 x=384..896、y=216..504 增益严格为 1；红通道向左上/上/下增强衰减，蓝通道轻微调整，绿通道不变；黑电平 14 以下原样通过。
- `display_common_tone` 以 `max(R,G,B)` 查 256 项增益表，对扣黑后的三通道施加同一增益；暗部最大 2 倍，亮白回到 1 倍；OSD/框保护像素绕过。
- `video_enhance` 虽然参数很多，但顶层 `ENABLE=0`、`RGB_GAIN_Q8=256`、`BRIGHTNESS_OFFSET=0`，实际只保留 6 拍对齐延迟。

### 3.4 目标检测与舵机

- `roi_target_tracker` 只识别绿色：G 为最大通道、色相约 90°–150°、饱和度 ≥25%、色度 ≥12、G≥24；G≥248 时还要求 G 比 R/B 各高约 G/4，排除近白高光。
- 3×3 多数滤波后，按 16×16 网格做四邻域泛洪，输出实际像素边界；相邻区域还要边界接近才合并。
- 帧级稳定：2 像素死区；扩张立即跟随；收缩需连续稳定后按 1/4 步长收敛；漏检保留 2 帧，第 3 帧清框；结果只在 SOF 原子提交。
- 框在显示端额外加 4 像素边距、2 像素线宽；中心 HUD 使用未加边距的逻辑边界中点，再减 `(640,360)`，显示为 `ROI X:+000 Y:+000`。
- `visual_servo_pwm` 在独立 50 MHz 域产生 20 ms 周期、1.0–2.0 ms 脉宽的 PWM；`pan_error = x-640`、`tilt_error = 360-y`，每像素 31/55 个 50 MHz 周期，3 像素死区，命令在 20 ms 边界更新，目标丢失保持最后角度。
- 注意：640×31 = 19,840 周期 ≈396.8 µs，360×55 = 19,800 周期 ≈396 µs，因此实际可用脉宽约 **1.103–1.897 ms**，并不会达到参数上的 1.0/2.0 ms 极限。若舵机需要更大行程，应调整 `PAN_TICKS_PER_PIXEL` / `TILT_TICKS_PER_PIXEL`。

---

## 4. 当前配置与时钟

| 项目 | 当前值 | 来源/说明 |
|---|---|---|
| 板级输入时钟 | 50 MHz | `I_sys_clk`，pin C4 |
| PLL 输出 | 100 MHz / 23.809524 MHz / 75 MHz / 375 MHz | `ip_source/PLL/.params_PLL.txt` |
| MIPI 字节时钟 | 约 103.52 MHz | 828 Mbps/Lane，2 Lane |
| DDR 用户时钟 | 66.667 MHz | DDR2-1066，16-bit DQ，128-bit 应用数据 |
| HDMI 像素时钟 | 75.000 MHz | 1650×750 → 约 60.606 Hz |
| 摄像头 MCLK | 23.809524 MHz | 不是名义 24 MHz |
| 摄像头 I2C | 约 100 kHz | `CLK_DIV = 23809524/100000-1` |
| 传感器 ID | 接受 `ee4b` / `9e4b` | 其他 ID 进入 `ST_ERROR`，不配置 |
| 默认曝光/增益 | 曝光 1991 半行；增益档位 128 | `ae_set.v`；曝光约为 16.6 ms，接近整帧 |
| 显示时序 | H: 1280 active / 1650 total / sync 1390–1430；V: 720 / 750 / sync 725–730 | `design_top_wrapper.v` |
| 目标检测 | 1280×720 全屏，16×16 网格，MIN_AREA=128，MAX_AREA=120000 | `design_top_wrapper.v` 参数 |
| 舵机 PWM | 50 MHz，20 ms，1.5 ms 中心，3 px 死区 | `visual_servo_pwm.v` |

HDMI 刷新率是按 75.000 MHz / (1650×750) 计算出来的约 60.606 Hz，不是标准 720p60 的 74.25 MHz/60 Hz。工程没有 DDC/EDID 读取（`I_edid_read_trig=0`，`O_ddc_scl` 未连接），显示器兼容性依赖其接受能力。

---

## 5. 构建、资源与时序

### 5.1 最新完整构建

- 目录：`td_project/camera_to_dsi_display_Runs/phy_1/`
- 时间：2026-10-11 14:27
- 比特流：`camera_to_dsi_display.bit`，1,789,539 字节，SHA-256 `71834662AA955A96218BBF5054967321C0547E717674B5E9252557853B2019A5`
- 时序（routed，final）：Setup WNS **+0.105 ns**，Hold WNS **+0.020 ns**，TNS 均为 0
- 资源：
  - slices 18,916 / 21,216 = **89.16%**
  - LUT6 17,947 / 21,216 = **84.59%**
  - slice reg 18,177 / 42,432 = 42.84%
  - ERAM 54 / 108 = 50%
  - DSP 40 / 40 = **100%**

### 5.2 重要区分：综合 gate 报告不是最终时序

`syn_1/flow.status` 当前显示的是同一次综合的 gate 级结果：Setup WNS **-2.365 ns**、26 个失败端点。这是布局布线前的估计值，不是最终签核结果；最终以 `phy_1/camera_to_dsi_display_pr.timing` 的 routed 结果为准。不要用 gate 的负值判断当前 bit 不可用，也不要用历史文档中的 +0.155 ns 覆盖实际报告的 +0.105 ns。

### 5.3 余量判断

- DSP 已 100% 使用，任何新增乘法器（新的色彩校正、锐化、缩放、双线性插值等）都必须先复用现有 DSP 或改成移位/加法。
- slices 89.16%，LUT6 84.59%；再增加一个中等规模的 OSD/检测模块就可能把 WNS 推到负值。
- 现有 `display_color_shading` 在顶层关闭，如果重新启用，会新增 4 个乘法器量级的逻辑，当前资源下不建议直接打开。
- 后续若要做更高分辨率、双摄像头、缩放或完整连通域标记，必须先做资源预算和时序评估，不能只改参数。

---

## 6. 主要发现与风险

### 6.1 文档与代码漂移（优先级高）

| 文档位置 | 文档说法 | 实际代码 |
|---|---|---|
| `CODE_GUIDE.md` 第 14 行 | 当前使用根目录 `awb.v` | `isp_top` 实例化的是 `awb_frame_stable`；`.al` 已把 `awb.v` 标为 `AutoExcluded` |
| `CODE_GUIDE.md` 第 62 行 | `roi_target_tracker` 检测红色 | 当前是绿色检测，阈值和区域生长均为绿色 |
| `CODE_GUIDE.md` 第 155 行 | `video_enhance` 给 RGB 加 6 级亮度 | 顶层 `ENABLE=0`、增益 256、偏移 0；亮度由 `display_common_tone` 完成 |
| `CODE_GUIDE.md` | 未收录 7 个新增模块 | `awb_frame_stable`、`raw_measured_shading`、`display_color_shading`、`scene_color_stream`、`display_common_tone`、`display_edge_color`、`roi_center_osd` |
| `工程结构与模块说明.md` 第 42 行 | 当前 AWB 为 `awb.v` | 同上 |
| `工程结构与模块说明.md` 第 61、77 行 | 显示增强加固定亮度；Track2 红色 | 同上 |
| `VIDEO_QUALITY.md` 第 1 行 | AWB 逐字节恢复官方、统一 17/16 提亮 | 当前是 `awb_frame_stable` + 公共亮度曲线；17/16 已改为单位增益 |
| `architecture.md` 第 25、43 行 | Track2 使用 `track2_lab3_merge.v`；工程根目录是 `D:\HX1P35A_Contest_202606\lab_ex3_osd_SC520` | 该模块未实例化；该路径不存在 |
| `README.md` | 源码放 `src/`、约束放 `constrs/`、工程放 `prj/` | 实际是 `user_source/`、`constraints_source/`、`td_project/` |

影响：新成员按文档修改很容易改错文件（例如又去改 `awb.v`、又去加 `video_enhance` 亮度），或者把已关闭的模块重新打开造成双重补偿。建议以本文第 3 节和实际 `.al` 为准，并尽快更新 `CODE_GUIDE.md`。

### 6.2 按键功能与文档相反（优先级高）

- 顶层：`.I_btn({I_button, 2'b11})`（`design_top_wrapper.v:446`）。
- `ae_set`：`I_btn[0]` 减 AE、`I_btn[1]` 加 AE；`I_btn[2]/[3]` 才是 AG 减/加（`ae_set.v:92-100`）。
- 由于高两位被固定为 `2'b11`，反相后为 0，**AG 永远不变；两个按键只调曝光**。
- 顶层没有实例化 `key_remove_shakes`；按键直接进 `ae_set`，只有 `ae_set` 内部的 1 ms（实际约 4.2 ms）节拍，没有消抖。
- `ae_set` 注释“100 MHz 门限、1 ms”与当前 23.81 MHz 不符：100,000 周期 ≈4.2 ms；AG 的 32 分频 ≈134 ms。
- 默认曝光 1991 半行、增益 128（8 倍模拟 + 1.5 倍数字）适合暗光，但运动场景会拖影；如果现场偏亮，应先降曝光。

建议：明确按键到底要控制曝光还是增益；如果要两者都控，需要 4 个按键并去掉固定高两位；同时把 `key_remove_shakes` 接上，或把 `ae_set` 的节拍参数化。

### 6.3 AWB 的行为边界

- 只统计低饱和、非过暗样本；白场/高亮场景可能样本不足，增益保持上一帧，表现为“白平衡不更新”。
- R/B 增益只有上限 16 倍钳位，没有下限；极端场景可能把某通道压得很低。
- 每帧向目标靠近 1/4，首次直接应用；场景切换时会有几帧过渡。
- 这些是算法取舍，不一定是缺陷，但需要在真实场景中确认；如果后续改 RAW 校正或镜头，AWB 阈值和增益范围要一起复核。

### 6.4 颜色链路层叠

当前实际生效的显示颜色处理：

```
RAW 九点空间校正 (raw_measured_shading)
  -> 去马赛克
  -> 帧级 AWB
  -> 显示端边缘红色修正 (display_edge_color)
  -> 公共亮度曲线 (display_common_tone)
```

已关闭但仍在代码里的：

- `display_color_shading`（`RGB_SHADING_ENABLE(0)`）
- `video_enhance` 的对比度/锐化/饱和度/Gamma/亮度（`ENABLE=0`）

风险：如果为了“再亮一点”或“再修一下边缘”直接打开其中一层，容易与 RAW 校正或公共亮度曲线叠加，造成过补偿、DSP 超限或时序失败。任何颜色改动都应只改一层，并重新跑整帧仿真和时序。

### 6.5 复位与跨时钟域

- `S_rst_n = S_pll_lock`，直接作为全设计的异步复位释放；没有复位同步器。PLL lock 是异步信号，理论上存在 recovery/removal 风险。
- `visual_servo_pwm` 用的是外部 `I_rst_n`，与视频域的 `S_rst_n` 不同步；如果外部复位在 PLL 锁定前释放，舵机会先进入默认中心，随后视频域才复位，功能上通常无害，但复位语义不统一。
- 舵机的 `source_toggle` 和 16 位坐标是“数据保持 + 2FF + toggle”跨域；源端在下一帧更新前保持不变，功能上是安全的，但 SDC 只做了异步时钟组，没有对这条 bundled bus 加 `set_max_delay`/`set_false_path`。建议补约束或在文档中明确 CDC 约定。

### 6.6 HDMI 时序与兼容性

- 75.000 MHz / 1650×750 = 60.606 Hz，不是标准 720p60；部分显示器可能不接受，或显示为 60.6 Hz。
- 没有 DDC/EDID，`I_edid_read_trig=0`，`O_ddc_scl` 悬空；无法读取显示器能力。
- HDMI 核固定 1280×720；改分辨率需要同时改 VTC、PLL、mixer、HDMI 核参数和 DDR 带宽预算。

### 6.7 未使用/历史模块

- `.al` 中仍包含但顶层未使用：`key_remove_shakes`、`audio_arc_calculate`、`I2S_receiver`、`red_mask_contour`（`AutoExcluded`）。
- `isp_top.v` 内部定义了但未实例化：`axis_gamma_rgb96`、`axis_crop_rgb96`。
- `awb.v` 已标 `AutoExcluded`，但文件仍保留；`divider.ipc` 仍编译（`awb_frame_stable` 使用）。
- 根目录与 `track2/` 下各有一份 `track2_lab3_merge.v`，均未实例化；`camera/`、`debug/`、`video/hdmi_output_wrapper.v` 是占位/直通示例。
- `isp/awb/` 是旧版 AWB 备份，不能与根目录 `awb.v` 或 `awb_frame_stable` 同时加入。

建议：在 `.al` 中显式排除未使用模块，减少综合歧义；清理前先备份，避免误删被 IP 间接引用的文件。

### 6.8 仿真与交付物缺失

- `doc/` 中大量阶段文档引用 `sim/build/...` 下的 bit、manifest、备份和验证工程；当前工作副本 **没有 `sim/build/` 目录**。
- 根目录只有一个 `SC520_display_color_trial_20261009.bit`，其 SHA-256 与当前 `phy_1` 主 bit 不同（`EA94...` vs `7183...`），不能当作当前主工程 bit 使用。
- 最新可用主 bit 在 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
- `doc/hw/config.json` 是 2026-10-18 新生成、未跟踪的硬件配置文件；其中 `chip_confirmed:false`、`boardInfo/pinmap/schematic` 均为空，不能作为引脚或板卡事实依据。

---

## 7. 验证状态

- 本次分析 **没有重新运行** ModelSim 回归、TD 综合或布局布线；上述时序/资源数据来自 2026-10-11 的已有构建报告。
- 代码中可运行的 Testbench 共 30 个（`sim/tb/`），覆盖 RAW10、去马赛克、AWB、显示顺序、颜色、ROI、边缘、中心 OSD、整帧联动等；`sim/modelsim/` 有对应 `.do` 脚本。
- 按《工程需求》第 4 条，只有“仿真 + 综合 + 比特流生成”全部通过才能判定可行；实板验证还需需求方同意。历史文档中的“通过”不等于当前源码今天重新验证通过。
- 若要在当前源码上继续开发，建议先跑一遍现有回归和一次完整 TD 流程，建立新的基线；不要直接引用 10 月 9 日/10 日的旧 bit 或旧时序。

---

## 8. 建议的下一步

1. **先定基线**：确认当前 `phy_1/camera_to_dsi_display.bit` 是否为交付基线；如果是，记录 hash 和构建时间，后续改动都相对它比较。
2. **更新文档**：至少更新 `doc/CODE_GUIDE.md` 和根目录《工程结构与模块说明》，把 7 个新增模块、绿色 ROI、AWB 派生、亮度曲线、按键实际功能写清楚。
3. **确认按键语义**：如果确实要调增益，改顶层 `I_btn` 接线并补消抖；如果只要曝光，删掉文档中的“增益”描述。
4. **资源预算**：任何新功能先估算 DSP/slices；优先复用 `display_common_tone` 的乘法器或改成移位，避免突破 40 DSP。
5. **颜色改动单层化**：一次只改 RAW 校正、边缘修正或公共亮度中的一层，并跑整帧颜色/ROI 联动仿真。
6. **补 CDC/复位约束**：为舵机 bundled bus 加时序约束；考虑给 `S_rst_n` 加复位同步器。
7. **确认 DDR 容量/仲裁**：核对 64 MB 地址空间与四帧 0/14/28/42 MB 的布局；复核读写同时启动的仲裁 race。
8. **整理编译清单**：把未使用模块从 `.al` 排除，保留同名备份但不要同时编译。

---

## 9. 新建测试工程说明

按需求方 2026-10-18 的确认，新建的 `Servo_PWM_Test` 是 **独立测试工程**，放在 `D:\Anlogic\Servo_PWM_Test`，不与 `Anlu2` 共享源码、IP、约束或构建目录。它只把 `Anlu2/user_source/hdl_source/track2/visual_servo_pwm.v` 的接口与时序行为作为参考，重新实现为参数化的双轴 PWM 控制器，用于单独测试舵机脉冲、按键步进和 20 ms 周期。

当前测试工程已用 ModelSim ALTERA 10.3c 跑通 8 项自检（20 ms 周期、1500/2000/1000 us 脉宽、两档输入钳位、tilt +512、enable=0 低电平），0 errors / 0 warnings；已提供 `td_project/servo_pwm_test.al`，并用 TD 6.2.168116 打开分析（2 个源文件），但按要求未运行综合、布局布线或 bitgen，未上板。

由于该工程在 `Anlu2/` 之外，`Anlu2` 的目录规则不直接约束它；但《工程需求》第 3、4 条的原则仍然适用：引脚/电气信息必须有板卡资料依据，仿真、综合、比特流和实板验证要分开记录，不得用推测值或仿真代替实板结论。测试工程的引脚约束只提供模板，未填写任何未核实的坐标。

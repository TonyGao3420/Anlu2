# 3x3 R/B 增益快照 2026-10-31

## 当前配置

```text
RAW 阴影校正：关闭
AWB：开启
显示端 3x3 R/B：开启
采样框图层：关闭
节点位置 x：64 / 640 / 1216
节点位置 y：32 / 360 / 688
```

## R 增益（节点 0..8）

```text
204  282  192
197  327  185
185  249  183
```

## B 增益（节点 0..8）

```text
228  257  240
229  281  237
227  251  243
```

## 与上一版的额外调整

```text
当前：1/3/4/6/7/9 区 R -10%（四舍五入）
历史：2 区 R -2%
历史：3/4/6/7 区 R/B +3%
历史：5 区 R -2%，B 从测试值 400 恢复为正常计算值
```

## 硬件生效条件

`display_color_shading` 使用以下 MIF，不是直接使用 RTL 函数：

```text
user_source/hdl_source/video/shading_row0.mif
user_source/hdl_source/video/shading_row1.mif
user_source/hdl_source/video/shading_row2.mif
```

修改 9 个节点后必须执行：

```text
python tools/resource_combo_20261030/generate_shading_rom.py
```

然后重新综合。

## MIF 生成时间

```text
2026-10-31 15:24:35
```

## 显示

```text
摄像头原图 + 每格 RGB 数值
不显示 128x64 采样框边框
```

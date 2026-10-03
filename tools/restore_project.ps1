# =============================================================================
# 文件名 : tools/restore_project.ps1
# 功能   : 一键重建 Anlu2 工程文件 —— 防止 TD GUI 覆盖导致工程丢失
#
# ============================== 背景 ==============================
# TD GUI 会在某些操作下（例如用 New Project、或它内存里开着旧工程时）
# 把 `prj/Anlu2.al` 覆盖成空壳：
#     <Source_Files> 为空、顶层变回旧工程的 system_top、TD_Encoding 变回 GB2312
# 历史上已发生多次。本脚本从**官方工程**重建出正确的 `Anlu2.al`。
#
# 官方工程位置（永久存在，是最终恢复源）：
#     D:\Anlogic\lab_ex1_mipi_hdmi\td_project\camera_to_dsi_display.al
#
# ============================== 用法 ==============================
#     pwsh -File D:\Anlogic\Anlu2\tools\restore_project.ps1
#
# 执行前请先**完全关闭 TangDynasty**，否则重建后可能被再次覆盖。
# =============================================================================

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 配置
$Anlu2Root   = 'D:\Anlogic\Anlu2'
$OfficialAl  = 'D:\Anlogic\lab_ex1_mipi_hdmi\td_project\camera_to_dsi_display.al'
$ProjectName = 'Anlu2'
$TargetAl    = Join-Path $Anlu2Root 'prj\Anlu2.al'
$BackupAl    = Join-Path $Anlu2Root 'prj\.al_backup\Anlu2.al'

Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ' Anlu2 工程文件重建工具' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- 0. 检查 TD 是否在运行
$td = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^td$|Tang|Dynasty' }
if ($td) {
    Write-Host '[警告] TangDynasty 正在运行：' -ForegroundColor Yellow
    $td | ForEach-Object { Write-Host "         $($_.ProcessName) PID=$($_.Id)" }
    Write-Host '       请先完全关闭 TD，否则重建结果可能被它再次覆盖。' -ForegroundColor Yellow
    Write-Host ''
    $ans = Read-Host '仍要继续？(y/N)'
    if ($ans -ne 'y') { Write-Host '已取消。'; exit 1 }
}

# ---------------------------------------------------------------- 1. 检查官方源
if (-not (Test-Path $OfficialAl)) {
    Write-Host "[错误] 找不到官方工程文件：$OfficialAl" -ForegroundColor Red
    Write-Host '       这是最终恢复源，请确认官方工程是否还在。' -ForegroundColor Red
    exit 1
}
Write-Host "[1/5] 官方源存在：$OfficialAl" -ForegroundColor Green

# ---------------------------------------------------------------- 2. 备份当前（若有效）
if (Test-Path $TargetAl) {
    $cur = [System.IO.File]::ReadAllText($TargetAl)
    $curCnt = ([regex]::Matches($cur, '<File ')).Count
    if ($curCnt -gt 0) {
        New-Item -ItemType Directory -Force -Path (Split-Path $BackupAl) | Out-Null
        Copy-Item $TargetAl $BackupAl -Force
        Write-Host "[2/5] 当前 .al 有效（$curCnt 个文件），已备份到 $BackupAl" -ForegroundColor Green
    } else {
        Write-Host '[2/5] 当前 .al 是空壳（0 个文件），跳过备份' -ForegroundColor Yellow
    }
} else {
    Write-Host '[2/5] 当前 .al 不存在，跳过备份' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 3. 从官方源重建
Write-Host '[3/5] 从官方源重建 Anlu2.al ...'
$raw = [System.IO.File]::ReadAllText($OfficialAl)

# 路径改写说明：
#   官方 .al 位于 lab_ex1_mipi_hdmi/td_project/，源码用 ../user_source/
#   我们的 .al 位于 Anlu2/prj/，源码在 Anlu2/lab_user_source/
$new = $raw
$new = $new.Replace('Path="D:/Anlogic/lab_ex1_mipi_hdmi/td_project"', "Path=""$($Anlu2Root.Replace('\','/'))/prj""")
$new = $new.Replace('<Name>camera_to_dsi_display</Name>', "<Name>$ProjectName</Name>")
$new = $new.Replace('<File Path="../user_source/', '<File Path="../lab_user_source/')
$new = $new.Replace('<File Path="camera_to_dsi_display.sdc">', '<File Path="../lab_camera_to_dsi_display.sdc">')
# 移除 ChipWatcher 调试 IP（官方标 AutoExcluded，不参与构建且我们的工程里没有）
$new = [regex]::Replace($new, '(?s)\s*<File Path="[^"]*ChipWatcher_mipi\.xml">.*?</File>', '')

New-Item -ItemType Directory -Force -Path (Split-Path $TargetAl) | Out-Null
[System.IO.File]::WriteAllText($TargetAl, $new, [System.Text.UTF8Encoding]::new($false))

$cnt  = ([regex]::Matches($new, '<File ')).Count
$top  = if ($new -match '<MODULE>([^<]*)</MODULE>') { $Matches[1] } else { '?' }
$enc  = if ($new -match '<TD_Encoding>([^<]*)</TD_Encoding>') { $Matches[1] } else { '?' }
$sv   = ([regex]::Matches($new, '<System_Verilog>')).Count

Write-Host "[4/5] 已写入 $TargetAl" -ForegroundColor Green
Write-Host "        文件数      : $cnt"
Write-Host "        顶层        : $top"
Write-Host "        TD_Encoding : $enc"
Write-Host "        System_Verilog 段: $sv"

# ---------------------------------------------------------------- 4. 校验每条路径
Write-Host '[5/5] 校验引用文件 ...'
$bad = 0; $ok = 0
foreach ($m in [regex]::Matches($new, '<File Path="([^"]*)">')) {
    $p = $m.Groups[1].Value -replace '/', '\'
    if ($p -match '^\.\.') {
        $full = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $TargetAl) $p))
    } else {
        $full = $p
    }
    if (Test-Path $full) { $ok++ } else { $bad++; Write-Host "        [缺失] $($m.Groups[1].Value)" -ForegroundColor Red }
}

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
if ($bad -eq 0 -and $cnt -gt 0 -and $top -eq 'design_top_wrapper') {
    Write-Host " 重建成功：$ok 个引用文件全部存在" -ForegroundColor Green
} else {
    Write-Host " 重建完成但有问题：存在 $ok 个、缺失 $bad 个" -ForegroundColor Red
}
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host '  1) 启动 TangDynasty'
Write-Host '  2) File -> Open Project -> 选 D:\Anlogic\Anlu2\prj\Anlu2.al'
Write-Host '     （不要用 New Project，它会写一个全新的空工程）'
Write-Host '  3) 打开后确认左侧 Hierarchy Navigation 里有 56 个源文件'
Write-Host ''

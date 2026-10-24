$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModelSimDir = $env:MODELSIM_DIR
if (-not $ModelSimDir) {
    $ModelSimDir = "D:\altera\14.1\modelsim_ase\win32aloem"
}

$Vlib = Join-Path $ModelSimDir "vlib.exe"
$Vlog = Join-Path $ModelSimDir "vlog.exe"
$Vsim = Join-Path $ModelSimDir "vsim.exe"

if (-not (Test-Path $Vlib)) {
    throw "Missing ModelSim library tool: $Vlib"
}
if (-not (Test-Path $Vlog)) {
    throw "Missing ModelSim compiler: $Vlog"
}
if (-not (Test-Path $Vsim)) {
    throw "Missing ModelSim simulator: $Vsim"
}

$SimDir = Join-Path $RepoRoot "sim"
$CompileList = @(
    (Join-Path $RepoRoot "sim\tb\tb_basic_video_enhance.sv"),
    (Join-Path $RepoRoot "sim\tb\tb_awb_disable.sv"),
    (Join-Path $RepoRoot "sim\tb\tb_camera_link_replay.sv"),
    (Join-Path $RepoRoot "sim\tb\tb_rgb_green_bias_check.sv"),
    (Join-Path $RepoRoot "sim\PH1P_LOGIC_ERAM_stub.v"),
    (Join-Path $RepoRoot "user_source\hdl_source\video\video_enhance.v"),
    (Join-Path $RepoRoot "user_source\hdl_source\awb.v"),
    (Join-Path $RepoRoot "user_source\hdl_source\signal_delay.v"),
    (Join-Path $RepoRoot "user_source\ip_source\blk_mem_gen_awb_delay_signal\ram_f84573da5ab5.v"),
    (Join-Path $RepoRoot "user_source\ip_source\blk_mem_gen_awb_delay_signal\blk_mem_gen_awb_delay_signal.v")
)

Set-Location $SimDir
& $Vlib work
if ($LASTEXITCODE -ne 0) {
    throw "ModelSim library creation failed."
}

& $Vlog -quiet -work work -sv $CompileList
if ($LASTEXITCODE -ne 0) {
    throw "ModelSim compilation failed."
}

$Tests = @("tb_basic_video_enhance", "tb_awb_disable", "tb_camera_link_replay", "tb_rgb_green_bias_check")
foreach ($TestName in $Tests) {
    Write-Host "=== Running $TestName ==="
    & $Vsim -c -quiet -do "set NumericStdNoWarnings 1; set StdArithNoWarnings 1; vsim work.$TestName; run -all; quit -f"
    if ($LASTEXITCODE -ne 0) {
        throw "ModelSim simulation failed for $TestName"
    }
}

Write-Host "ModelSim simulation completed successfully."

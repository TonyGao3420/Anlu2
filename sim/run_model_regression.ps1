param(
    [string]$ModelSimPath = 'D:\altera\14.1\modelsim_ase\win32aloem\vsim.exe'
)

$ErrorActionPreference = 'Stop'
$simDir = Join-Path $PSScriptRoot 'modelsim'
$transcript = Join-Path $simDir 'run_regression.log'
$runs = @(
    @{ Script = 'run_roi.do'; Marker = 'PASS ROI acquire' },
    @{ Script = 'run_display.do'; Marker = 'PASS display_path' },
    @{ Script = 'run_color.do'; Marker = 'PASS video_color_path' },
    @{ Script = 'run_raw10.do'; Marker = 'PASS raw10' },
    @{ Script = 'run_bilinear_color.do'; Marker = 'PASS bilinear_color' },
    @{ Script = 'run_awb.do'; Marker = 'PASS awb_unit_gain' },
    @{ Script = 'run_awb_auto_gain.do'; Marker = 'PASS awb_auto_gain' }
)

if (-not (Test-Path -LiteralPath $ModelSimPath -PathType Leaf)) {
    throw "ModelSim executable not found: $ModelSimPath. Pass -ModelSimPath to select vsim.exe."
}

Push-Location $simDir
try {
    if (Test-Path -LiteralPath $transcript) { Remove-Item -LiteralPath $transcript }
    foreach ($run in $runs) {
        Write-Output "===== ModelSim $($run.Script) ====="
        & $ModelSimPath -c -do $run.Script 2>&1 | Tee-Object -FilePath $transcript -Append
        if ($LASTEXITCODE -ne 0) {
            throw "ModelSim exited with code $LASTEXITCODE during $($run.Script). See $transcript"
        }
    }
} finally {
    Pop-Location
}

$logText = Get-Content -LiteralPath $transcript -Raw
$missing = @($runs | Where-Object { $logText -notmatch [regex]::Escape($_.Marker) })
if ($missing.Count -gt 0 -or $logText -match '\*\* Fatal:|Errors: [1-9]') {
    $missingText = if ($missing.Count) { " Missing pass markers: $(($missing.Marker) -join ', ')." } else { '' }
    throw "ModelSim regression failed.$missingText See $transcript"
}

Write-Output "ModelSim regression passed. Transcript: $transcript"

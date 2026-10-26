param([string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Build=Join-Path $Root 'sim/build/model_style_20261026'
$Combined=Join-Path $Build 'production_regression.log'
Set-Content -LiteralPath $Combined -Value ''
Push-Location "$Root/sim/modelsim_model_style_legacy_20261026"
try {
 foreach($Name in @('roi','display','color','raw10','bilinear_color','official_awb','roi_extent_720p')) {
  $Log=Join-Path $Build "legacy_$Name.log"
  & $ModelSim -c -do "run_$Name.do" *> $Log
  if($LASTEXITCODE -ne 0){throw "Failed legacy check: $Name"}
  $Content=Get-Content -LiteralPath $Log -Raw
  if($Content -notmatch 'PASS ' -or $Content -match '\*\* Fatal:|Errors: [1-9]'){throw "Legacy check did not pass: $Name"}
  Add-Content -LiteralPath $Combined -Value $Content
  Write-Output "PASS legacy $Name"
 }
 Add-Content -LiteralPath $Combined -Value 'ModelSim regression passed.'
} finally {Pop-Location}

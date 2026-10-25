param([string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LogRoot=Join-Path $Root 'sim/build/style_mode_20261025'
Push-Location (Join-Path $Root 'sim/modelsim_style_mode')
try {
 foreach($Name in @('style_switch','style_small','style_720p','trail_small','trail_clock','trail_watchdog','trail_budget','trail_movie','logo_rom_equivalence')) {
  $Log=Join-Path $LogRoot "$Name.log"
  & $ModelSim -c -do "run_$Name.do" *> $Log
  if($LASTEXITCODE -ne 0){throw "ModelSim failed: $Name"}
  $Content=Get-Content -LiteralPath $Log -Raw
  if($Content -notmatch 'PASS ' -or $Content -match '\*\* Fatal:|Errors: [1-9]'){throw "Verification failed: $Name; see $Log"}
  Write-Output "PASS $Name"
 }
} finally {Pop-Location}

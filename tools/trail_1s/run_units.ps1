param([string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',[string]$LogDirectory='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LogRoot=if($LogDirectory){$LogDirectory}else{Join-Path $Root 'sim/build/trail_1s_20261025'}
Push-Location (Join-Path $Root 'sim/modelsim_trail_units')
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

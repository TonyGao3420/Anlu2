param(
 [string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',
 [string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',
 [string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
 [string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Build=Join-Path $Root 'sim/build/style_mode_20261025'
function Invoke-Checked([string]$Exe,[string[]]$Argv,[string]$Directory,[string]$Log) {
 Push-Location $Directory
 try { & $Exe @Argv *> $Log; if($LASTEXITCODE -ne 0){throw "Failed $Exe; see $Log"} }
 finally {Pop-Location}
}
Push-Location $Root
try {
 foreach($Script in @('audit','make_reference','make_trajectory_fixture','make_rom_model','make_integration')) {
  & $Python "tools/style_mode/$Script.py"
  if($LASTEXITCODE -ne 0){throw "Preparation failed: $Script"}
 }
 & tools/style_mode/run_units.ps1 -ModelSim $ModelSim
 if($LASTEXITCODE -ne 0){throw 'Module verification failed'}
 Invoke-Checked $ModelSim @('-c','-do','run_mode_integration.do') "$Root/sim/modelsim_style_mode" "$Build/mode_integration.log"
 & sim/run_model_regression.ps1 -ModelSimPath $ModelSim *> "$Build/production_regression.log"
 if($LASTEXITCODE -ne 0){throw 'Existing regression failed'}
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/syn_1" "$Build/synthesis.log"
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/phy_1" "$Build/route_bitgen.log"
 & $Python tools/style_mode/package.py
 if($LASTEXITCODE -ne 0){throw 'Final checks/packaging failed'}
} finally {Pop-Location}

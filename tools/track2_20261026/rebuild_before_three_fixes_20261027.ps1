param(
 [string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',
 [string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',
 [string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
 [string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Build=Join-Path $Root 'sim/build/track2_requirements_20261026'
function Invoke-Checked([string]$Exe,[string[]]$Argv,[string]$Directory,[string]$Log) {
 Push-Location $Directory
 try { & $Exe @Argv *> $Log; if($LASTEXITCODE -ne 0){throw "Failed $Exe; see $Log"} }
 finally {Pop-Location}
}
Push-Location $Root
try {
 foreach($Name in @('audit','make_reference','make_integration')) {
  & $Python "tools/track2_20261026/$Name.py"
  if($LASTEXITCODE -ne 0){throw "Preparation failed: $Name"}
 }
 Invoke-Checked $ModelSim @('-c','-do','run_style_small.do') "$Root/sim/modelsim_trail_units" "$Build/legacy_style_small.log"
 Invoke-Checked $ModelSim @('-c','-do','run_motion_small.do') "$Root/sim/modelsim_track2_20261026" "$Build/motion_small.log"
 Invoke-Checked $ModelSim @('-c','-do','run_motion_full.do') "$Root/sim/modelsim_track2_full_20261026" "$Build/motion_full.log"
 Invoke-Checked $ModelSim @('-c','-do','run_main.do') "$Root/sim/modelsim_track2_integration_20261026" "$Build/main_integration.log"
 & tools/track2_20261026/run_legacy.ps1 -ModelSim $ModelSim
 if($LASTEXITCODE -ne 0){throw 'Original regression failed'}
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/syn_1" "$Build/synthesis.log"
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/phy_1" "$Build/route_bitgen.log"
 & $Python tools/track2_20261026/package.py
 if($LASTEXITCODE -ne 0){throw 'Packaging/validation failed'}
} finally {Pop-Location}

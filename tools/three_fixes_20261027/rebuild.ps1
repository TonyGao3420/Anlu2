param(
 [string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',
 [string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',
 [string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
 [string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Build=Join-Path $Root 'sim/build/three_fixes_20261027'
function Invoke-Checked([string]$Exe,[string[]]$Argv,[string]$Directory,[string]$Log) {
 Push-Location $Directory
 try { & $Exe @Argv *> $Log; if($LASTEXITCODE -ne 0){throw "Failed $Exe; see $Log"} }
 finally {Pop-Location}
}
Push-Location $Root
try {
 foreach($Name in @('official_logo','audit','make_integration','make_reference','make_replay')) {
  & $Python -I "tools/three_fixes_20261027/$Name.py"
  if($LASTEXITCODE -ne 0){throw "Preparation failed: $Name"}
 }
 foreach($Unit in @('logo','logo_mixer','rotate','orientation')) {
  Invoke-Checked $ModelSim @('-c','-do',"run_$Unit.do") "$Root/sim/modelsim_three_fixes_20261027" "$Build/$Unit.log"
 }
 Invoke-Checked $ModelSim @('-c','-do','run_motion_small.do') "$Root/sim/modelsim_three_fixes_small_20261027" "$Build/small.log"
 Invoke-Checked $ModelSim @('-c','-do','run_motion_full.do') "$Root/sim/modelsim_three_fixes_full_20261027" "$Build/full.log"
 Invoke-Checked $ModelSim @('-c','-do','run_replay.do') "$Root/sim/modelsim_three_fixes_replay_20261027" "$Build/replay.log"
 Invoke-Checked $ModelSim @('-c','-do','run_main.do') "$Root/sim/modelsim_three_fixes_integration_final_20261027" "$Build/main.log"
 & tools/three_fixes_20261027/run_legacy.ps1 -ModelSim $ModelSim
 if($LASTEXITCODE -ne 0){throw 'Original regression failed'}
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/syn_1" "$Build/synthesis.log"
 Invoke-Checked $TD @($Flow) "$Root/td_project/camera_to_dsi_display_Runs/phy_1" "$Build/route_bitgen.log"
 & $Python -I tools/three_fixes_20261027/package.py
 if($LASTEXITCODE -ne 0){throw 'Publication checks failed'}
} finally {Pop-Location}

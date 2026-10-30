param([string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',[string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',[string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',[string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl')
$ErrorActionPreference='Stop';$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot);$taskBuild="$taskRoot/sim/build/multi_trail_20261030"
Push-Location $taskRoot
try {
 & $Python -I tools/multi_trail_20261030/audit.py;if($LASTEXITCODE){throw 'Audit failed'}
 & $Python -I tools/multi_trail_20261030/prepare_tests.py;if($LASTEXITCODE){throw 'Prepare failed'}
 foreach($taskCase in @('units','budget','display')){
  Push-Location "sim/run_multi_trail_$taskCase"
  try {& $ModelSim -c -do run.do *> "$taskBuild/$taskCase.log";if($LASTEXITCODE){throw 'Simulation failed'}}finally{Pop-Location}
 }
 foreach($taskRun in @('syn_1','phy_1')){
  Push-Location "td_project/camera_to_dsi_display_Runs/$taskRun"
  try {$taskLog=if($taskRun -eq 'syn_1'){'synthesis.log'}else{'route.log'};& $TD $Flow *> "$taskBuild/$taskLog";if($LASTEXITCODE){throw 'TD failed'}}finally{Pop-Location}
 }
 & $Python -I tools/multi_trail_20261030/package.py;if($LASTEXITCODE){throw 'Publication failed'}
}finally{Pop-Location}

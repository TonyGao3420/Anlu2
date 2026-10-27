param([string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',[string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',[string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',[string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl')
$ErrorActionPreference='Stop';$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot);$taskBuild="$taskRoot/sim/build/final_four_modes_20261028"
Push-Location $taskRoot
try {
 & $Python -I tools/final_four_modes_20261028/prepare_tests.py;if($LASTEXITCODE){throw 'Preparation failed'}
 & $Python -I tools/final_four_modes_20261028/audit.py;if($LASTEXITCODE){throw 'Audit failed'}
 foreach($taskCase in @('slots','latency','tracker','coldboot','main')){
  Push-Location "sim/run_final_$taskCase";try{& $ModelSim -c -do run.do *> "$taskBuild/$taskCase.log";if($LASTEXITCODE){throw 'Simulation failed'}}finally{Pop-Location}
 }
 foreach($taskRun in @('syn_1','phy_1')){
  Push-Location "td_project/camera_to_dsi_display_Runs/$taskRun";try{$taskLog=if($taskRun -eq 'syn_1'){'synthesis.log'}else{'route_bitgen.log'};& $TD $Flow *> "$taskBuild/$taskLog";if($LASTEXITCODE){throw 'TD failed'}}finally{Pop-Location}
 }
 & $Python -I tools/final_four_modes_20261028/package.py;if($LASTEXITCODE){throw 'Publication checks failed'}
}finally{Pop-Location}

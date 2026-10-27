param([string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',[string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',[string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',[string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl')
$ErrorActionPreference='Stop';$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot);$Build="$Root/sim/build/roi_original_20261027"
Push-Location $Root
try {
 & $Python -I tools/roi_original_20261028/prepare_roi_test.py;if($LASTEXITCODE){throw 'Preparation failed'}
 foreach($taskMode in @('small','full')){Push-Location "$Root/sim/modelsim_roi_original_${taskMode}_20261027";try{& $ModelSim -c -do "run_$taskMode.do" *> "$Build/$taskMode.log";if($LASTEXITCODE){throw 'Simulation failed'}}finally{Pop-Location}}
 foreach($taskRun in @('syn_1','phy_1')){Push-Location "$Root/td_project/camera_to_dsi_display_Runs/$taskRun";try{$taskLog=if($taskRun -eq 'syn_1'){'synthesis.log'}else{'route_bitgen.log'};& $TD $Flow *> "$Build/$taskLog";if($LASTEXITCODE){throw 'TD failed'}}finally{Pop-Location}}
 & $Python -I tools/roi_original_20261028/package.py;if($LASTEXITCODE){throw 'Publication failed'}
}finally{Pop-Location}

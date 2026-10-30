param([string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',[string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',[string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',[string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl')
$ErrorActionPreference='Stop';$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot);$taskBuild="$taskRoot/sim/build/resource_combo_20261030"
Push-Location $taskRoot
try {
 & $Python -I tools/resource_combo_20261030/prepare_tests.py;if($LASTEXITCODE){throw 'Prepare failed'}
 & $Python -I tools/resource_combo_20261030/prepare_combo_tests.py;if($LASTEXITCODE){throw 'Prepare combo failed'}
 & $Python -I tools/resource_combo_20261030/audit.py;if($LASTEXITCODE){throw 'Audit failed'}
 foreach($taskPair in @(@('color','color_equivalence'),@('mask','union_mask'),@('overlay','overlay_reuse'),@('awb','awb_divider'),@('awb_frame','awb_frame'),@('coldboot','combo_coldboot_final'),@('combo','combo_integration'))){
  Push-Location "sim/run_resource_$($taskPair[0])"
  try {& $ModelSim -c -do run.do *> "$taskBuild/$($taskPair[1]).log";if($LASTEXITCODE){throw 'Simulation failed'}}finally{Pop-Location}
 }
 foreach($taskRun in @('syn_1','phy_1')){
  Push-Location "td_project/camera_to_dsi_display_Runs/$taskRun"
  try {$taskLog=if($taskRun -eq 'syn_1'){'combo_synthesis.log'}else{'combo_route.log'};& $TD $Flow *> "$taskBuild/$taskLog";if($LASTEXITCODE){throw 'TD failed'}}finally{Pop-Location}
 }
 Copy-Item -LiteralPath "$taskBuild/combo_route.log" -Destination "$taskBuild/final_route.log" -Force
 & $Python -I -c "from pathlib import Path; import json; p=Path('sim/build/resource_combo_20261030/record.json'); m=json.loads(p.read_text()); m['selected_run']=str(Path('td_project/camera_to_dsi_display_Runs/phy_1').resolve()); p.write_text(json.dumps(m,indent=2))"
 & $Python -I tools/resource_combo_20261030/package.py;if($LASTEXITCODE){throw 'Publication failed'}
}finally{Pop-Location}

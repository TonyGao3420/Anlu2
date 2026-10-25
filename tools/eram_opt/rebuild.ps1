param(
 [string]$Python='C:/Users/11512/AppData/Local/Programs/Python/Python312/python.exe',
 [string]$ModelSim='D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe',
 [string]$TD='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
 [string]$Flow='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl'
)
& "$PSScriptRoot/../trail_1s/rebuild.ps1" -Python $Python -ModelSim $ModelSim -TD $TD -Flow $Flow

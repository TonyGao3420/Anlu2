from pathlib import Path
root=Path(__file__).resolve().parents[2]
backup=root.parent/'recovery_backups/Anlu2_before_roi_original_20261027'
models=root/'sim/models/roi_original_20261027';models.mkdir(exist_ok=True)
s=(backup/'user_source/hdl_source/video/roi_background_stylize.v').read_text(encoding='utf-8')
s=s.replace('roi_background_stylize','roi_background_stylize_before_roi').replace('style_target_clean','style_target_clean_before_roi').replace('style_status_osd','style_status_osd_before_roi')
(models/'before_roi.v').write_text(s,encoding='utf-8')
for folder,script,tb in [('modelsim_roi_original_small_20261027','run_small.do','tb_roi_original_small'),('modelsim_roi_original_full_20261027','run_full.do','tb_roi_original_full')]:
 work=root/'sim'/folder;work.mkdir(exist_ok=True)
 (work/script).write_text('onerror {quit -code 1 -f}\nif {[file exists work/_info]} { vdel -lib work -all }\nvlib work\nvmap work work\nvlog -sv ../models/roi_original_20261027/before_roi.v ../../user_source/hdl_source/video/roi_background_stylize.v ../tb/tb_roi_original_20261027.sv\nvsim -c work.'+tb+'\nrun -all\nquit -f\n')

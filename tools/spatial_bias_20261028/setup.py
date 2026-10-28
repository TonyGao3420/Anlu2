from pathlib import Path
import shutil,json,hashlib
r=Path(__file__).resolve().parents[2];tag='spatial_bias_20261028';old='final_four_modes_20261028'
backup=r.parent/'recovery_backups/Anlu2_before_spatial_bias_20261028'
b=r/'sim/build'/tag;b.mkdir(parents=True,exist_ok=True)
for folder in ['sim/models','sim/reference','sim/tb']:
 dst=r/folder/tag
 if not dst.exists():shutil.copytree(r/folder/old,dst)
p=r/'sim/models'/tag/'logo.v';p.write_text(p.read_text().replace('../build/'+old+'/','../build/'+tag+'/'))
tool=Path(__file__).parent
s=(r/'tools'/old/'prepare_tests.py').read_text(encoding='utf-8').replace("tag='"+old+"'","tag='"+tag+"'")
s=s.replace("('tracker',['../../user_source", "('tracker',['../../user_source")
# Keep the proven source-extraction method and ship all reference files locally.
(tool/'prepare_tests.py').write_text(s,encoding='utf-8')
p=r/'sim/tb'/tag/'tb_final_four_modes_vtc.sv'
s=p.read_text().replace("24'h707070","24'h0e0e0e").replace("24'h20a030","24'h00a000")
s=s.replace('PASS final_main_vtc:', 'PASS spatial_main_vtc:').replace('all original-mode RGB exact +3 aligned clocks','preserved pure-green/black stimulus: RGB/OSD exact +3 aligned clocks; color changes separately golden-model checked')
p.write_text(s,encoding='utf-8')
p=r/'sim/tb'/tag/'tb_final_coldboot.sv';p.write_text(p.read_text().replace('PASS final_coldboot:','PASS spatial_coldboot:'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
previous=json.loads((backup/'source_sha256.json').read_text(encoding='utf-8'))
current={p.relative_to(r).as_posix():sha(p) for p in sorted((r/'user_source').rglob('*')) if p.is_file()}
record={'backup':str(backup),'changed_hardware':[n for n,h in current.items() if previous[n]!=h],
 'production_sha256':current,'previous_production_sha256':previous,
 'previous_main_bit_sha256':sha(backup/'output/Anlu2_Final_4Mode_20261028.bit'),
 'reference_four_mode_bit_sha256':sha(backup/'output/Anlu2_Final_4Mode_20261028.bit'),
 'new_main_bit_generated':False,'sdc_sha256':sha(r/'td_project/camera_to_dsi_display.sdc'),
 'color_note':'Empirical residual coefficients from screen feedback, not calibrated from the monitor photograph. Top R -16 maximum; upright lower-right R -12, B -24 maximum; shared old perimeter stage; neutral guard.'}
(b/'merge_record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared color-stage references and frozen before/after production hashes:',record['changed_hardware'])

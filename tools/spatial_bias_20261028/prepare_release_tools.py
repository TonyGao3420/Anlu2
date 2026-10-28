from pathlib import Path
r=Path(__file__).resolve().parents[2];t=Path(__file__).parent
s=(r/'tools/final_four_modes_20261028/package.py').read_text(encoding='utf-8')
s=s.replace('final_four_modes_20261028','spatial_bias_20261028').replace('Anlu2_Final_4Mode_20261028','Anlu2_SpatialColor_20261028')
a=s.index("markers={'slots'");b=s.index('\npassed={}',a)
s=s[:a]+"markers={'color':'PASS spatial_bias:','coldboot':'PASS spatial_coldboot:','main':'PASS spatial_main_vtc:'}"+s[b:]
a=s.index('status=(');b=s.index('\nfor doc in',a)
s=s[:a]+'''status=(f'## 本次主工程构建结果\\n\\n位置颜色修正版Anlu2已完成三项本轮仿真、综合、布局布线及bitgen。'
 f"Slice {metrics['#slices']}/21216，ERAM {metrics['#RAMs']}/108，DSP {metrics['#DSPs']}/40；"
 f"Setup WNS +{metrics['Setup WNS']}ps，Hold WNS +{metrics['Hold WNS']}ps，TNS均0。\\n\\n"
 '1843200输入像素分别对照正常/180度映射的独立颜色参考模型通过。白/灰保护、合成角落偏色绿恢复、OSD及共享显示/ROI、八拍同步均通过。'
 '实际VTC四模式5529600像素通过；纯绿/黑保留测试图上的原RGB/ROI/PWM/读请求一致，其他颜色按本轮偏置有意变化。'
 'SW3直接启动8目标、1843200像素冷启动检查通过。\\n\\n'
 f'标准主输出与output/Anlu2_SpatialColor_20261028.bit完全相同。SHA256：`{sha(bit)}`。本轮未上板；需白场和真实目标复核偏置强度。\\n')''' + s[b:]
s=s.replace('doc/FINAL_FOUR_MODES_20261028.md','doc/SPATIAL_BIAS_20261028.md')
s=s.replace('全部5项仿真','全部本轮仿真')
s=s.replace("named=out/(stem+'.bit');shutil.copy2(bit,named)","named=out/(stem+'.bit');shutil.copy2(bit,named);shutil.copy2(bit,out/'Anlu2_Final_4Mode_20261028.bit')")
s=s.replace("bit,named,out/'manifest.json'", "bit,named,out/'Anlu2_Final_4Mode_20261028.bit',out/'manifest.json'")
s=s.replace("'capacity':{'slices':21216,'ERAM':108,'DSP':40},", "'capacity':{'slices':21216,'ERAM':108,'DSP':40},'color_note':m['color_note'],'test_scope':'Color golden model plus preserved pure-green/black four-mode control equivalence; not all original colors unchanged',")
s=s.replace("files.add(r/'sim'/('run_final_'+name)/'run.do')", "files.add(r/'sim'/('run_spatial_color' if name=='color' else 'run_final_'+name)/'run.do')")
s=s.replace("print('PASS publication:","shutil.copy2(archive,out/'Anlu2_Final_4Mode_20261028.zip')\nprint('PASS publication:")
(t/'package.py').write_text(s,encoding='utf-8')
s=(r/'tools/final_four_modes_20261028/rebuild.ps1').read_text(encoding='utf-8').replace('final_four_modes_20261028','spatial_bias_20261028')
s=s.replace("@('slots','latency','tracker','coldboot','main')","@('color','coldboot','main')")
s=s.replace('Push-Location "sim/run_final_$taskCase"','if($taskCase -eq \'color\'){Push-Location "sim/run_spatial_color"}else{Push-Location "sim/run_final_$taskCase"}')
(t/'rebuild.ps1').write_text(s,encoding='utf-8')
for rel in ['tools/rebuild.ps1','tools/final_four_modes_20261028/rebuild.ps1']:
 p=r/rel
 if rel=='tools/rebuild.ps1':s=p.read_text(encoding='utf-8').replace('final_four_modes_20261028','spatial_bias_20261028')
 else:
  s=(r/'tools/rebuild.ps1').read_text(encoding='utf-8').replace('$PSScriptRoot/spatial_bias_20261028/','$PSScriptRoot/../spatial_bias_20261028/')
 p.write_text(s,encoding='utf-8')
print('Prepared current release/rebuild scripts and redirected common entry to spatial color revision')

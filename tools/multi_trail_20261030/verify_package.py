from pathlib import Path
import json,hashlib,zipfile,subprocess,sys,datetime,shlex
r=Path(__file__).resolve().parents[2];stem='Anlu2_EightTrails_20261030'
archive=r/'output'/(stem+'.zip');m=json.loads((r/'output/manifest.json').read_text(encoding='utf-8'))
target=r.parent/'work'/('eight_trails_package_check_'+datetime.datetime.now().strftime('%H%M%S'))
assert not target.exists();target.mkdir(parents=True)
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for name in z.namelist():
  p=Path(name);assert not p.is_absolute() and '..' not in p.parts and p.parts[0]=='Anlu2'
 for n,h in {**m['production_sha256'],**m['config_sha256'],m['named_bit']:m['bit_sha256'],m['standard_bit']:m['bit_sha256']}.items():
  assert hashlib.sha256(z.read('Anlu2/'+n)).hexdigest()==h,n
 z.extractall(target)
copied=target/'Anlu2'
for script in ['audit.py','prepare_tests.py']:
 result=subprocess.run([sys.executable,'-I',str(copied/'tools/multi_trail_20261030'/script)],cwd=copied,check=True,capture_output=True,text=True,encoding='utf-8')
 print(result.stdout.strip())
refs=[]
for d in ['units','budget','display']:
 folder=copied/'sim'/('run_multi_trail_'+d)
 for line in (folder/'run.do').read_text(encoding='utf-8').splitlines():
  if line.startswith('vlog '):
   for n in shlex.split(line)[1:]:
    if not n.startswith('-'):assert (folder/n).is_file(),n;refs.append(n)
report={'zip_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'production_source_files':len(m['production_sha256']),
 'crc_and_all_source_config_and_bit_hashes_match':True,'unpacked_audit_and_prepare_pass':True,
 'simulation_compile_references_present':len(refs),'unpacked_root':str(copied)}
(r/'output/package_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS portable package: '+json.dumps(report,ensure_ascii=False))

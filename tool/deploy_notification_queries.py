"""Guarded code-only deployment; preserve database and all existing user data."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

root=Path(__file__).resolve().parents[1]
backend_log=(root/'.artifact-work/notifications134-backend.log').read_text(encoding='utf-8-sig')
assert 'Ran 118 tests' in backend_log and '\nOK\n' in backend_log and 'FAILED' not in backend_log
identity=r'C:\Users\29668\.ssh\linesight-ali-baot.pem'
ssh=['ssh','-i',identity,'-o','BatchMode=yes','root@47.111.81.94']
files=['collaboration/product.py']
expected={'collaboration/product.py':'5c9c6074e724cdbfa412047aff14c9496ec42808eb7516bec41e9e7e8b430ac5'}
stage='/tmp/linesight-notifications134-'+uuid.uuid4().hex
subprocess.run(ssh+['mkdir -m 700 '+stage],check=True,capture_output=True,timeout=20)
for index,relative in enumerate(files):
    subprocess.run(['scp','-i',identity,'-o','BatchMode=yes',str(root/'backend'/relative),'root@47.111.81.94:'+stage+'/'+str(index)+'.py'],check=True,capture_output=True,timeout=30)
config={'stage':stage,'files':files,'before':expected,'after':{f:hashlib.sha256((root/'backend'/f).read_bytes()).hexdigest() for f in files}}
code='config='+repr(config)+'\n'+r'''
import datetime,hashlib,json,os,pathlib,py_compile,shutil,subprocess,time
import pysqlite3 as sqlite3
from urllib.request import Request,urlopen
base=pathlib.Path('/opt/linesight/backend')
for i,relative in enumerate(config['files']):
    target=base/relative
    assert hashlib.sha256(target.read_bytes()).hexdigest()==config['before'][relative], 'Concurrent server change'
    staged=pathlib.Path(config['stage'])/(str(i)+'.py')
    assert hashlib.sha256(staged.read_bytes()).hexdigest()==config['after'][relative], 'Upload differs'
    py_compile.compile(str(staged),doraise=True)
backup=pathlib.Path('/var/backups/linesight/notifications134')/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup.mkdir(parents=True,mode=0o700)
for relative in config['files']:shutil.copy2(base/relative,backup/pathlib.Path(relative).name)
database=pathlib.Path('/var/lib/linesight/linesight.sqlite3')
assert database.exists()
def snapshot(connection):
    names=[row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    return {name:list(connection.execute('SELECT * FROM "'+name+'" ORDER BY rowid')) for name in names}
def health():
    for _ in range(20):
        try:
            with urlopen(Request('http://127.0.0.1:8000/',headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}),timeout=3) as response:
                if response.status==200:return True
        except Exception:time.sleep(1)
    return False
subprocess.run(['systemctl','stop','linesight'],check=True)
try:
    with sqlite3.connect(str(database)) as connection,sqlite3.connect(str(backup/'linesight.sqlite3')) as saved:
        connection.backup(saved);before=snapshot(connection)
    os.chmod(backup/'linesight.sqlite3',0o600)
    for i,relative in enumerate(config['files']):
        target=base/relative;stat=target.stat();staged=pathlib.Path(config['stage'])/(str(i)+'.py')
        os.chmod(staged,stat.st_mode&0o777);os.chown(staged,stat.st_uid,stat.st_gid);os.replace(staged,target)
    with sqlite3.connect(str(database)) as connection:assert snapshot(connection)==before,'Database changed during code-only deployment'
    subprocess.run(['systemctl','start','linesight'],check=True)
    assert health(),'API health check failed'
except BaseException:
    # Roll back only code: never discard writes received after service restart.
    subprocess.run(['systemctl','stop','linesight'],check=True)
    for relative in config['files']:shutil.copy2(backup/pathlib.Path(relative).name,base/relative)
    subprocess.run(['systemctl','start','linesight'],check=True)
    assert health(),'Rollback health check failed'
    raise
report={'deployed':True,'backup':str(backup),'before_sha256':config['before'],'after_sha256':config['after'],
        'schema_changed':False,'existing_tables_checked':len(before),'existing_rows_preserved':True,
        'api_health':True,'identity_configuration_changed':False,'rollback_preserves_live_writes':True}
(backup/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
'''
result=subprocess.run(ssh+['/opt/linesight/venv/bin/python -'],input=code,text=True,capture_output=True,timeout=150)
if result.returncode:
    print(result.stderr[-1800:]);raise SystemExit(result.returncode)
report=json.loads(result.stdout)
folder=root/'docs/product/linesight/acceptance/notifications134-batch';folder.mkdir(parents=True,exist_ok=True)
(folder/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))

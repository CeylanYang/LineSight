"""Atomic, guarded team self-identity deployment; no schema or identity changes."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

root=Path(__file__).resolve().parents[1]
ssh=['ssh','-i',r'C:\Users\29668\.ssh\linesight-ali-baot.pem','-o','BatchMode=yes','root@47.111.81.94']
old=root/'.artifact-work/team-remote-api-before.py'
source=root/'backend/collaboration/api.py'
stage='/tmp/linesight-team-'+uuid.uuid4().hex+'.py'
subprocess.run(['scp','-i',r'C:\Users\29668\.ssh\linesight-ali-baot.pem','-o','BatchMode=yes',str(source),'root@47.111.81.94:'+stage],check=True,capture_output=True,timeout=30)
config={'expected_before':hashlib.sha256(old.read_bytes()).hexdigest(),'expected_after':hashlib.sha256(source.read_bytes()).hexdigest(),'stage':stage}
code='config='+repr(config)+'\n'+'''import datetime,hashlib,json,os,pathlib,py_compile,shutil,subprocess,time
from urllib.request import Request,urlopen
source=pathlib.Path(config['stage'])
target=pathlib.Path('/opt/linesight/backend/collaboration/api.py')
assert hashlib.sha256(target.read_bytes()).hexdigest()==config['expected_before'], 'Concurrent server code change'
assert hashlib.sha256(source.read_bytes()).hexdigest()==config['expected_after'], 'Upload differs'
py_compile.compile(str(source),doraise=True)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup=pathlib.Path('/var/backups/linesight/team')/stamp
backup.mkdir(parents=True,mode=0o700)
shutil.copy2(target,backup/'api.py')
stat=target.stat()
os.chmod(source,stat.st_mode & 0o777)
os.chown(source,stat.st_uid,stat.st_gid)
try:
    os.replace(source,target)
    subprocess.run(['systemctl','restart','linesight'],check=True)
    healthy=False
    for attempt in range(20):
        try:
            with urlopen(Request('http://127.0.0.1:8000/',headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}),timeout=3) as response:
                healthy=response.status==200
            if healthy:break
        except Exception:time.sleep(1)
    assert healthy, 'API failed health check'
    assert subprocess.check_output(['systemctl','is-active','linesight'],text=True).strip()=='active'
except BaseException:
    shutil.copy2(backup/'api.py',target)
    subprocess.run(['systemctl','restart','linesight'],check=True)
    raise
report={'deployed':True,'before_sha256':config['expected_before'],'after_sha256':config['expected_after'],'backup':str(backup),'api_health':True,'database_schema_changed':False,'identity_configuration_changed':False}
(backup/'deployment.json').write_text(json.dumps(report,indent=2)+'\\n')
print(json.dumps(report))
'''
result=subprocess.run(ssh+['/opt/linesight/venv/bin/python -'],input=code,text=True,capture_output=True,timeout=60)
if result.returncode:
    print(result.stderr[-2500:])
    raise SystemExit(result.returncode)
report=json.loads(result.stdout)
folder=root/'docs/product/linesight/acceptance/team-batch'
folder.mkdir(parents=True,exist_ok=True)
(folder/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))

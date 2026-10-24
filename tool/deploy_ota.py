"""Deploy read-only OTA routes, with source backup and automatic rollback."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

root = Path(__file__).resolve().parents[1]
key = r'C:\Users\29668\.ssh\linesight-ali-baot.pem'
ssh = ['ssh', '-i', key, '-o', 'BatchMode=yes', 'root@47.111.81.94']
stage = '/tmp/linesight-ota-' + uuid.uuid4().hex
files = ['collaboration/urls.py', 'collaboration/ota.py']
subprocess.run(ssh + ['mkdir -m 700 ' + stage], check=True, timeout=25)
for index, name in enumerate(files):
    subprocess.run(['scp', '-i', key, '-o', 'BatchMode=yes', str(root / 'backend' / name),
        f'root@47.111.81.94:{stage}/{index}.py'], check=True, timeout=30)
config = {'stage': stage, 'files': files,
    'hashes': [hashlib.sha256((root / 'backend' / n).read_bytes()).hexdigest() for n in files]}
code = 'config=' + repr(config) + '\n' + r'''
import datetime,hashlib,json,os,pathlib,py_compile,shutil,subprocess,time
from urllib.request import urlopen,Request
base=pathlib.Path('/opt/linesight/backend')
old=hashlib.sha256((base/'collaboration/urls.py').read_bytes()).hexdigest()
assert old=='b254b790b35d1dcc6ad7c67d9867d5bcf074492460aca261342996a300690cb4','Concurrent route change'
backup=pathlib.Path('/var/backups/linesight/ota')/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup.mkdir(parents=True,mode=0o700)
for i,name in enumerate(config['files']):
    source=pathlib.Path(config['stage'])/f'{i}.py'
    assert hashlib.sha256(source.read_bytes()).hexdigest()==config['hashes'][i]
    py_compile.compile(str(source),doraise=True)
    if (base/name).exists():shutil.copy2(base/name,backup/pathlib.Path(name).name)
def probe(path):
    for i in range(15):
        try:
            with urlopen(Request('http://127.0.0.1:8000'+path,headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}),timeout=3) as r:
                return r.status
        except Exception:time.sleep(1)
    return None
try:
    for i,name in enumerate(config['files']):
        source=pathlib.Path(config['stage'])/f'{i}.py'
        stat=(base/'collaboration/urls.py').stat()
        os.chmod(source,stat.st_mode&0o777);os.chown(source,stat.st_uid,stat.st_gid)
        os.replace(source,base/name)
    subprocess.run(['systemctl','restart','linesight'],check=True)
    assert probe('/')==200
    assert probe('/api/v1/ota/preview/8078/x86_64/manifest.json')==204
    assert probe('/api/v1/ota/production/8078/arm64-v8a/manifest.json')==204
except BaseException:
    for name in config['files']:
        saved=backup/pathlib.Path(name).name
        if saved.exists():shutil.copy2(saved,base/name)
        else:(base/name).unlink(missing_ok=True)
    subprocess.run(['systemctl','restart','linesight'],check=True)
    raise
print(json.dumps({'deployed':True,'health':True,'empty_update':204,'database_changed':False,'backup':str(backup)}))
'''
result = subprocess.run(ssh + ['/opt/linesight/venv/bin/python -'], input=code,
    text=True, capture_output=True, timeout=90)
if result.returncode:
    raise SystemExit(result.stderr[-2000:])
folder = root / 'docs/product/linesight/acceptance/ota54-batch'
folder.mkdir(parents=True, exist_ok=True)
(folder / 'deployment.json').write_text(result.stdout, encoding='utf8')
print(result.stdout)

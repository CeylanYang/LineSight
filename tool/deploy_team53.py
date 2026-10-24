"""Guarded additive profile migration with stopped-service database backup and row audit."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

root = Path(__file__).resolve().parents[1]
assert '+448: All tests passed!' in (root/'.artifact-work/team53-full.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/team53-analyze.log').read_text(encoding='utf-8-sig')
assert 'Ran 93 tests' in (root/'.artifact-work/team53-backend.log').read_text(encoding='utf-8-sig')
assert '\nOK\n' in (root/'.artifact-work/team53-backend.log').read_text(encoding='utf-8-sig')
identity = r'C:\Users\29668\.ssh\linesight-ali-baot.pem'
ssh = ['ssh', '-i', identity, '-o', 'BatchMode=yes', 'root@47.111.81.94']
files = ['collaboration/api.py', 'collaboration/models.py', 'collaboration/product.py', 'collaboration/workflow.py', 'collaboration/avatars.py', 'collaboration/migrations/0010_member_profiles_and_manager.py']
expected = {'collaboration/api.py': '969d1c870352772865a6b79d6ccd02c243754418f9dc6b3a0d15e183f7161daa', 'collaboration/models.py': 'aacb77b774883b1888fde7aa442a55ee8fa7b15c7eef8a4700e35d80bf6323a5', 'collaboration/product.py': '057a4c043a0b229b2332244baf3e20a73ff2f91e7d7b0e949ce9b70cf53b2434', 'collaboration/workflow.py': 'baa3d27a6346253ad0ded4beb61aec74dd62c98d4f31628288f31bf4a6147105', 'collaboration/avatars.py': None, 'collaboration/migrations/0010_member_profiles_and_manager.py': None}
stage = '/tmp/linesight-team53-' + uuid.uuid4().hex
subprocess.run(ssh + ['mkdir -m 700 ' + stage], check=True, capture_output=True, timeout=20)
for index, relative in enumerate(files):
    subprocess.run(['scp', '-i', identity, '-o', 'BatchMode=yes', str(root/'backend'/relative),
        'root@47.111.81.94:' + stage + '/' + str(index) + '.py'], check=True, capture_output=True, timeout=30)
config = {'stage': stage, 'files': files, 'before': expected,
    'after': {f: hashlib.sha256((root/'backend'/f).read_bytes()).hexdigest() for f in files}}
code = 'config=' + repr(config) + '\n' + r'''
import datetime,hashlib,json,os,pathlib,py_compile,shlex,shutil,subprocess,sys,time
import pysqlite3 as sqlite3
from urllib.request import Request,urlopen
base = pathlib.Path('/opt/linesight/backend')
for index, relative in enumerate(config['files']):
    target = base/relative
    expected = config['before'][relative]
    assert (hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None) == expected, 'Concurrent server change'
    uploaded = pathlib.Path(config['stage'])/(str(index)+'.py')
    assert hashlib.sha256(uploaded.read_bytes()).hexdigest() == config['after'][relative], 'Upload differs'
    py_compile.compile(str(uploaded),doraise=True)
environment = dict(os.environ)
for line in pathlib.Path('/etc/linesight/linesight.env').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#') or '=' not in line:continue
    key,value=line.split('=',1)
    values=shlex.split(value)
    environment[key.strip()]=' '.join(values)
environment.setdefault('DJANGO_SETTINGS_MODULE','linesight.production_settings')
assert environment['DJANGO_SETTINGS_MODULE']=='linesight.production_settings'
database = pathlib.Path(environment.get('LINESIGHT_DATA_DIR','/var/lib/linesight'))/'linesight.sqlite3'
assert database.is_absolute() and database.exists()
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup=pathlib.Path('/var/backups/linesight/team53')/stamp
backup.mkdir(parents=True,mode=0o700)
for relative in config['files']:
    target=base/relative
    if target.exists():shutil.copy2(target,backup/target.name)

def snapshot(connection):
    result={}
    names=[row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    for name in names:
        columns=[row[1] for row in connection.execute('PRAGMA table_info("'+name+'")')]
        # Only the original columns participate when checking the additive migration.
        result[name]={'columns':columns,'rows':list(connection.execute('SELECT '+','.join('"'+c+'"' for c in columns)+' FROM "'+name+'" ORDER BY rowid'))}
    return result

def health():
    for attempt in range(20):
        try:
            with urlopen(Request('http://127.0.0.1:8000/',headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}),timeout=3) as response:
                if response.status==200:return True
        except Exception:time.sleep(1)
    return False

subprocess.run(['systemctl','stop','linesight'],check=True)
connection=sqlite3.connect(str(database))
with sqlite3.connect(str(backup/'linesight.sqlite3')) as saved:connection.backup(saved)
os.chmod(backup/'linesight.sqlite3',0o600)
before=snapshot(connection)
connection.close()
try:
    for index,relative in enumerate(config['files']):
        target=base/relative
        uploaded=pathlib.Path(config['stage'])/(str(index)+'.py')
        stat=target.stat() if target.exists() else (base/'collaboration/models.py').stat()
        os.chmod(uploaded,stat.st_mode & 0o777);os.chown(uploaded,stat.st_uid,stat.st_gid)
        os.replace(uploaded,target)
    migrated=subprocess.run(['/opt/linesight/venv/bin/python','manage.py','migrate','--noinput'],cwd=base,env=environment,text=True,capture_output=True,timeout=60)
    assert migrated.returncode==0, 'Database migration failed: '+migrated.stderr[-800:]
    with sqlite3.connect(str(database)) as connection:
        for name,original in before.items():
            columns=','.join('"'+c+'"' for c in original['columns'])
            where=" WHERE NOT (app='collaboration' AND name='0010_member_profiles_and_manager')" if name=='django_migrations' else ''
            rows=list(connection.execute('SELECT '+columns+' FROM "'+name+'"'+where+' ORDER BY rowid'))
            assert rows==original['rows'], 'Existing rows changed: '+name
        assert connection.execute("SELECT count(*) FROM django_migrations WHERE app='collaboration' AND name='0010_member_profiles_and_manager'").fetchone()[0]==1
    subprocess.run(['systemctl','start','linesight'],check=True)
    assert health(),'API health check failed'
except BaseException:
    subprocess.run(['systemctl','stop','linesight'],check=True)
    for relative in config['files']:
        target=base/relative
        saved=backup/target.name
        if saved.exists():shutil.copy2(saved,target)
        elif target.exists():target.unlink()
    with sqlite3.connect(str(backup/'linesight.sqlite3')) as saved,sqlite3.connect(str(database)) as original:
        saved.backup(original)
    subprocess.run(['systemctl','start','linesight'],check=True)
    assert health(),'Rollback health check failed'
    raise
report={'deployed':True,'backup':str(backup),'before_sha256':config['before'],'after_sha256':config['after'],
    'schema_migration':'0010_member_profiles_and_manager','existing_tables_checked':len(before),
    'existing_rows_preserved':True,'api_health':True,'identity_configuration_changed':False}
(backup/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
'''
result = subprocess.run(ssh + ['/opt/linesight/venv/bin/python -'], input=code, text=True, capture_output=True, timeout=150)
if result.returncode:
    print(result.stderr[-1800:])
    raise SystemExit(result.returncode)
report = json.loads(result.stdout)
folder = root/'docs/product/linesight/acceptance/team53-batch'
folder.mkdir(parents=True, exist_ok=True)
(folder/'deployment.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))

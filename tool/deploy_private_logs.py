"""Deploy only operational logging, with source guard, rollback and live probes."""
import hashlib
import json
from pathlib import Path
import subprocess
import uuid


def main():
    root=Path(__file__).resolve().parents[1]
    testlog=(root/'.artifact-work/privacy58-backend.log').read_text(encoding='utf-8-sig')
    assert 'Ran 101 tests' in testlog and '\nOK\n' in testlog
    ssh=['ssh','-o','BatchMode=yes','-i',str(Path.home()/'.ssh/linesight-ali-baot.pem'),'root@47.111.81.94']
    stage='/tmp/linesight-private-logs-'+uuid.uuid4().hex
    subprocess.run(ssh+['mkdir -m 700 '+stage],check=True,capture_output=True)
    names=['linesight/production_settings.py','linesight/privacy_log.py']
    previous=(root/'.artifact-work/privacy58-production-before.py').read_bytes()
    head=subprocess.check_output(['git','show','HEAD:backend/linesight/production_settings.py'],cwd=root).decode()
    assert previous.decode().replace('\r\n','\n')==head.replace('\r\n','\n')
    for i,name in enumerate(names):
        subprocess.run(['scp',*ssh[1:-1],str(root/'backend'/name),ssh[-1]+':'+stage+'/'+str(i)+'.py'],check=True,capture_output=True)
    config={'stage':stage,'files':names,'before':hashlib.sha256(previous).hexdigest(),
            'after':[hashlib.sha256((root/'backend'/name).read_bytes()).hexdigest() for name in names]}
    remote='config='+repr(config)+'\n'+r'''
import datetime,hashlib,json,os,pathlib,py_compile,shlex,shutil,subprocess,time,uuid
from urllib.request import Request,urlopen
from urllib.error import HTTPError
base=pathlib.Path('/opt/linesight/backend')
assert hashlib.sha256((base/config['files'][0]).read_bytes()).hexdigest()==config['before']
assert not (base/config['files'][1]).exists()
for i,name in enumerate(config['files']):
    p=pathlib.Path(config['stage'])/(str(i)+'.py')
    assert hashlib.sha256(p.read_bytes()).hexdigest()==config['after'][i]
    py_compile.compile(str(p),doraise=True)
environment=dict(os.environ)
for line in pathlib.Path('/etc/linesight/linesight.env').read_text().splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        k,v=line.split('=',1);environment[k.strip()]=' '.join(shlex.split(v))
environment['DJANGO_SETTINGS_MODULE']='linesight.production_settings'
backup=pathlib.Path('/var/backups/linesight/private-logs')/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup.mkdir(parents=True,mode=0o700)
target=base/config['files'][0];shutil.copy2(target,backup/'production_settings.py')
since=str(int(time.time())-1)
def get(path,token=None):
    headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}
    if token: headers['Authorization']='Bearer '+token
    try:
        with urlopen(Request('http://127.0.0.1:8000/'+path,headers=headers),timeout=5) as response:
            return response.status,response.headers
    except HTTPError as e: return e.code,e.headers
try:
    for i,name in enumerate(config['files']):
        p=pathlib.Path(config['stage'])/(str(i)+'.py')
        stat=target.stat();os.chmod(p,stat.st_mode&0o777);os.chown(p,stat.st_uid,stat.st_gid)
        os.replace(p,base/name)
    result=subprocess.run(['/opt/linesight/venv/bin/python','manage.py','check'],cwd=base,env=environment,capture_output=True)
    assert result.returncode==0,'Production Django check failed'
    subprocess.run(['systemctl','restart','linesight'],check=True,capture_output=True)
    for attempt in range(20):
        try:
            status,headers=get('')
            if status==200 and headers.get('X-Request-ID'): break
        except OSError: pass
        time.sleep(1)
    else: raise RuntimeError('Post-deploy health failed')
    canary='PRIVATE-CANARY-'+uuid.uuid4().hex
    ids=[]
    for path,expected in [('api/v1/auth/me/?password='+canary,401),
        ('api/v1/workspaces/0/members/'+canary+'/?token='+canary,401),
        ('missing-'+canary+'/?code='+canary,404)]:
        status,headers=get(path,canary);assert status==expected
        ids.append(headers['X-Request-ID'])
    time.sleep(1)
    logs=subprocess.check_output(['journalctl','-u','linesight','--since','@'+since,'-o','cat','--no-pager'],text=True)
    assert canary not in logs,'Secret canary leaked to journal'
    records=[]
    for line in logs.splitlines():
        try:
            record=json.loads(line)
            if record.get('request_id') in ids: records.append(record)
        except ValueError: pass
    assert all(any(r.get('request_id')==i for r in records) for i in ids)
    assert any(r.get('route')=='api/v1/workspaces/<int:workspace_id>/members/<str:username>/' for r in records)
    report={'production_check_passed':True,'service_health':200,'live_invalid_auth':401,
        'live_unknown_route':404,'journal_canary_absent':True,'request_ids_correlated':len(ids),
        'only_url_templates_logged':True,'production_database_migrated':False,
        'app_binary_changed':False,'backup':str(backup),'source_sha256':config['after']}
    print(json.dumps(report))
except BaseException:
    shutil.copy2(backup/'production_settings.py',target)
    (base/config['files'][1]).unlink(missing_ok=True)
    subprocess.run(['systemctl','restart','linesight'],check=True,capture_output=True)
    raise
'''
    result=subprocess.run(ssh+['/opt/linesight/venv/bin/python -'],input=remote,text=True,capture_output=True,timeout=100)
    assert result.returncode==0,'Deployment/probe failed; inspect server backup before retry'
    report=json.loads(result.stdout)
    folder=root/'docs/product/linesight/acceptance/privacy58-batch';folder.mkdir(parents=True,exist_ok=True)
    (folder/'live-logs.json').write_text(json.dumps(report,indent=2)+'\n')
    (folder/'backend-tests.txt').write_text(testlog)
    print(json.dumps(report))


if __name__=='__main__':main()

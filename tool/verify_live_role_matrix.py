"""Real PKCE role checks in a disposable workspace; never touches customer teams."""
import json
from pathlib import Path
import secrets
import subprocess
import traceback
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

import verify_cloud_sessions as kc


def api(path, token, data=None, method=None):
    headers={'Accept':'application/json','Authorization':'Bearer '+token}
    if data is not None:
        headers.update({'Content-Type':'application/json','Idempotency-Key':uuid.uuid4().hex})
    request=Request(kc.api+path,headers=headers,method=method,
                    data=json.dumps(data).encode() if data is not None else None)
    try:
        with urlopen(request,timeout=20) as response:
            raw=response.read()
            return response.status,json.loads(raw) if 'json' in response.headers.get('Content-Type','') else raw
    except HTTPError as error:
        error.read();return error.code,None


def cleanup(subjects, workspace, team_name):
    config={'subjects':subjects,'workspace':workspace,'team_name':team_name,'issuer':kc.issuer}
    code='config='+repr(config)+'\n'+r'''
import os,sys,json
from pathlib import Path
import pysqlite3 as sqlite3
sys.modules['sqlite3']=sqlite3
for line in Path('/etc/linesight/linesight.env').read_text().splitlines():
    if line and not line.startswith('#') and '=' in line:
        key,value=line.split('=',1);os.environ[key]=value
os.environ['DJANGO_SETTINGS_MODULE']='linesight.production_settings'
sys.path.insert(0,'/opt/linesight/backend')
import django;django.setup()
from django.db import transaction
from django.contrib.auth import get_user_model
from collaboration.models import CloudIdentity,Workspace,Membership
with transaction.atomic():
    identities=list(CloudIdentity.objects.filter(issuer=config['issuer'],subject__in=config['subjects']))
    users=[i.user_id for i in identities]
    homes=[i.home_workspace_id for i in identities if i.home_workspace_id]
    shared=Workspace.objects.filter(pk=config['workspace'],name=config['team_name']) if config['workspace'] else Workspace.objects.none()
    if config['workspace']:assert shared.count()==1
    scopes=homes+list(shared.values_list('pk',flat=True))
    assert not Membership.objects.filter(user_id__in=users).exclude(workspace_id__in=scopes).exists()
    assert not Membership.objects.filter(workspace_id__in=scopes).exclude(user_id__in=users).exists()
    assert not Workspace.objects.filter(pk__in=homes).exclude(name__startswith='Role56 ').exists()
    Workspace.objects.filter(pk__in=scopes).delete()
    get_user_model().objects.filter(pk__in=users).delete()
    assert not CloudIdentity.objects.filter(issuer=config['issuer'],subject__in=config['subjects']).exists()
print(json.dumps({'disposable_api_users_deleted':len(users),'disposable_workspaces_deleted':len(scopes),'customer_teams_modified':False}))
'''
    result=subprocess.run(['ssh','-i',str(Path.home()/'.ssh/linesight-ali-baot.pem'),
        '-o','BatchMode=yes','root@47.111.81.94','/opt/linesight/venv/bin/python -'],
        input=code,capture_output=True,text=True,timeout=60)
    if result.returncode:
        Path('.artifact-work/roles56-cleanup-error.txt').write_text(result.stderr)
        Path('.artifact-work/roles56-cleanup-config.json').write_text(json.dumps(config))
        raise RuntimeError('Disposable API cleanup failed; inspect private environment')
    return json.loads(result.stdout)


def main():
    status,_,admin=kc.call(kc.origin+'/realms/master/protocol/openid-connect/token',urlencode({
        'client_id':'admin-cli','grant_type':'password','username':kc.private['KEYCLOAK_ADMIN_USERNAME'],
        'password':kc.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200
    run=uuid.uuid4().hex; team_name='Role56 '+run
    people={}; locations=[];subjects=[];workspace=None;result={}
    try:
        for role in ['owner','manager','operator','viewer']:
            username='role56-'+run+'-'+role;password=secrets.token_urlsafe(32)
            status,headers,_=kc.call(kc.origin+'/admin/realms/linesight/users',{
                'username':username,'enabled':True,'firstName':'Role56','lastName':run+' '+role,
                'email':username+'@example.invalid','credentials':[{'type':'password','value':password,'temporary':False}]},admin['access_token'])
            assert status==201
            locations.append(headers['Location']);subjects.append(headers['Location'].rsplit('/',1)[1])
            tokens=kc.authorize(kc.browser(),username,password)
            status,me=api('auth/me/',tokens['access_token']);assert status==200
            people[role]={'tokens':tokens,'username':username,'password':password,'me':me}
        owner=people['owner']['tokens']['access_token']
        status,team=api('workspaces/create/',owner,{'name':team_name});assert status==201
        workspace=team['id'];base=f'workspaces/{workspace}/'
        for role in ['manager','operator','viewer']:
            status,invitation=api(base+'invite/',owner,{'role':role});assert status==201
            status,joined=api('workspaces/redeem/',people[role]['tokens']['access_token'],{'code':invitation['code']})
            assert status==201 and joined['role']==role
        matrix={}
        for role,person in people.items():
            token=person['tokens']['access_token'];checks={}
            for suffix in ['jobs/','records/','metrics/','report/','report/?download=csv','templates/','members/','printer-profiles/','notifications/']:
                status,_=api(base+suffix,token);assert status==200,(role,suffix,status)
                checks['read_'+suffix.split('/')[0].split('?')[0]]=status
            status,_=api(base+'jobs/',token,{'part_name':'Role56 '+role,'printer':'A1','quantity':1})
            assert status==(403 if role=='viewer' else 201),(role,'create',status)
            checks['create_task']=status
            if role!='owner':
                status,_=api(base+'invite/',token,{'role':'viewer'});assert status==403
                checks['invite_member']=status
            matrix[role]=checks
        status,members=api(base+'members/',owner);assert status==200
        target=next(m for m in members if m['role']=='manager')['username']
        old=people['manager']['tokens']['access_token']
        status,_=api(base+'members/'+target+'/',owner,{'role':'viewer'},'PATCH');assert status==200
        assert api(base+'jobs/',old)[0]==401
        person=people['manager'];fresh=kc.authorize(kc.browser(),person['username'],person['password'])
        person['tokens']=fresh
        assert api(base+'jobs/',fresh['access_token'])[0]==200
        assert api(base+'jobs/',fresh['access_token'],{'part_name':'denied','printer':'A1','quantity':1})[0]==403
        assert api(base+'members/'+target+'/',owner,{},'DELETE')[0]==200
        assert api(base+'jobs/',fresh['access_token'])[0]==404
        assert api(base+'leave/',owner,{})[0]==409
        result={'real_https_pkce_identities':4,'roles':matrix,'downgrade_old_token_status':401,
            'downgraded_fresh_token_read_status':200,'downgraded_fresh_token_write_status':403,
            'removed_member_old_token_status':404,'last_owner_leave_status':409,
            'native_final_apk_role_matrix_verified':False,'physical_devices_verified':False}
    finally:
        cleanup_result=cleanup(subjects,workspace,team_name)
        for person in people.values():
            kc.call(kc.issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-android','refresh_token':person['tokens']['refresh_token']}).encode())
        for location in locations:
            assert kc.call(location,token=admin['access_token'],method='DELETE')[0]==204
        kc.call(kc.origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
    result.update(cleanup_result);result['disposable_identity_accounts_deleted']=len(locations)
    folder=Path('docs/product/linesight/acceptance/roles56-batch');folder.mkdir(parents=True,exist_ok=True)
    (folder/'live-role-matrix.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':
    try:main()
    except Exception as error:
        print(json.dumps({'passed':False,'error':type(error).__name__,
            'frames':[(Path(f.filename).name,f.lineno) for f in traceback.extract_tb(error.__traceback__)]}))
        raise SystemExit(1)

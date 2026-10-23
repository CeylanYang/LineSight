"""Revoke only the newly created Android demo session and verify draft recovery."""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('phase',choices=['prepare','revoke','recovered','submitted'])
args=parser.parse_args()
folder=Path('docs/product/linesight/acceptance/reauth-batch');folder.mkdir(parents=True,exist_ok=True)
fixture_path=folder/'live-reauthentication.json'
private_path=Path('.artifact-work/sso/reauth-sessions-private.json')
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
private=dict(line.split('=',1) for line in Path('.artifact-work/sso/identity.env').read_text().splitlines() if '=' in line)
issuer=config['LINESIGHT_OIDC_ISSUER'];origin=issuer.split('/realms/')[0]
api=config['LINESIGHT_API_BASE_URL']

def call(url,body=None,token=None,method=None,key=None):
    headers={'Accept':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    if key:headers['Idempotency-Key']=key
    if isinstance(body,dict):headers['Content-Type']='application/json';body=json.dumps(body).encode()
    elif body is not None:headers['Content-Type']='application/x-www-form-urlencoded'
    try:
        with urlopen(Request(url,data=body,headers=headers,method=method),timeout=30) as response:
            raw=response.read();return response.status,json.loads(raw) if raw else None
    except HTTPError as error:
        return error.code,None

admin=None;demo=None
try:
    status,admin=call(origin+'/realms/master/protocol/openid-connect/token',urlencode({
        'client_id':'admin-cli','grant_type':'password','username':private['KEYCLOAK_ADMIN_USERNAME'],
        'password':private['KEYCLOAK_ADMIN_PASSWORD']}).encode());assert status==200
    token=admin['access_token']
    status,users=call(origin+'/admin/realms/linesight/users?'+urlencode({'username':config['LINESIGHT_DEMO_USERNAME'],'exact':'true'}),token=token)
    assert status==200 and len(users)==1 and users[0]['username']==config['LINESIGHT_DEMO_USERNAME']
    user_id=users[0]['id'];sessions_url=origin+'/admin/realms/linesight/users/'+user_id+'/sessions'
    if args.phase=='revoke':
        fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
        assert fixture['demo_only'] and not fixture.get('target_session_revoked')
        before=json.loads(private_path.read_text(encoding='utf-8'))
        assert before['user_id']==user_id
        status,sessions=call(sessions_url,token=token);assert status==200
        added=[s for s in sessions if s['id'] not in before['session_ids']]
        assert len(added)==1,'Require exactly one new Android demo login; no sessions were revoked'
        target=added[0]
        assert list(target['clients'].values())==['linesight-demo'],'Unexpected client; no session was revoked'
        status,_=call(origin+'/admin/realms/linesight/sessions/'+target['id'],token=token,method='DELETE');assert status==204
        status,remaining=call(sessions_url,token=token);assert status==200
        assert target['id'] not in {s['id'] for s in remaining}
        fixture['target_session_revoked']=True;fixture['other_sessions_revoked']=False
    else:
        status,demo=call(issuer+'/protocol/openid-connect/token',urlencode({'grant_type':'password','client_id':'linesight-demo',
            'username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode());assert status==200
        token_demo=demo['access_token']
        status,me=call(api+'auth/me/',token=token_demo);assert status==200 and me['is_demo'] and me['home_workspace_id']==5
        base=api+'workspaces/5/'
        if args.phase=='prepare':
            if fixture_path.exists():
                raise AssertionError('Existing fixture preserved; do not reset acceptance task')
            status,templates=call(base+'templates/',token=token_demo);assert status==200 and templates
            template=templates[0]
            status,job=call(base+'jobs/',{'part_name':'DEMO · 会话恢复检验','printer':'Bambu Lab A1','quantity':2,
                'batch_code':'DEMO-REAUTH-'+uuid.uuid4().hex[:8],'template_id':template['id']},token_demo,key=uuid.uuid4().hex);assert status==201
            path=base+'jobs/'+job['id']+'/'
            for state in ['printing','inspection']:
                status,job=call(path,{'status':state,'version':job['version']},token_demo,'PATCH',uuid.uuid4().hex);assert status==200
            fixture={'demo_only':True,'original_jobs_modified':False,'before':job,'template':template}
            status,sessions=call(sessions_url,token=token);assert status==200
            private_path.write_text(json.dumps({'user_id':user_id,'session_ids':[s['id'] for s in sessions]}),encoding='utf-8')
        else:
            fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
            assert fixture['target_session_revoked']
            status,current=call(base+'jobs/'+fixture['before']['id']+'/',token=token_demo);assert status==200
            if args.phase=='recovered':
                assert current['version']==fixture['before']['version'] and current['status']=='inspection' and not current['inspections']
                fixture['no_automatic_submission_after_login']=True
            else:
                assert current['status']=='closed' and len(current['inspections'])==1
                assert current['inspections'][0]['note']=='Measured 12.05 mm'
                fixture['manual_submission_single_inspection']=True
            fixture['after_'+args.phase]=current
    fixture_path.write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'phase':args.phase,'task_id':fixture['before']['id'],'demo_only':True,'passed':True}))
finally:
    if demo:
        call(issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-demo','refresh_token':demo['refresh_token']}).encode())
    if admin:
        call(origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())

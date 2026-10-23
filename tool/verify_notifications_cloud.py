"""Exercise assignment notices and versioned reads in the isolated cloud demo team."""
import base64
import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
import uuid

root=Path(__file__).resolve().parents[1]
config=json.loads((root/'.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
issuer=config['LINESIGHT_OIDC_ISSUER']; api=config['LINESIGHT_API_BASE_URL']
sessions=[]
def identity(body):
    with urlopen(Request(issuer+'/protocol/openid-connect/token',data=urlencode(body).encode()),timeout=25) as response:
        result=json.load(response)
    sessions.append(result)
    return result

def call(session,method,path,body=None):
    headers={'Authorization':'Bearer '+session['access_token'],'Content-Type':'application/json'}
    if method in ['POST','PATCH']:headers['Idempotency-Key']=uuid.uuid4().hex
    with urlopen(Request(api+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method),timeout=25) as response:
        return response.status,json.load(response)

def login():
    return identity({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']})

try:
    session=login()
    _,me=call(session,'GET','auth/me/')
    _,workspaces=call(session,'GET','workspaces/')
    workspace=next(row for row in workspaces if row['id']==me['home_workspace_id'])
    assert me['is_demo'] and workspace['kind']=='demo'
    base=f"workspaces/{workspace['id']}/"
    _,members=call(session,'GET',base+'members/')
    payload=session['access_token'].split('.')[1]
    claims=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
    bridge='oidc_'+hashlib.sha256((claims['iss']+'\0'+claims['sub']).encode()).hexdigest()[:40]
    matches=[row for row in members if row['username']==bridge]
    assert len(matches)==1
    assignee=matches[0]['id']
    _,before=call(session,'GET',base+'jobs/')
    snapshot=lambda rows:{row['id']:hashlib.sha256(json.dumps(row,sort_keys=True).encode()).hexdigest() for row in rows}
    original=snapshot(before)
    status,job=call(session,'POST',base+'jobs/',{'part_name':'DEMO · 通知派工','printer':'Bambu Lab A1','quantity':1,'batch_code':'DEMO-NOTICE-'+uuid.uuid4().hex[:8],'assignee_id':assignee})
    assert status==201
    path=base+'jobs/'+job['id']+'/'
    def notice(current):
        _,rows=call(current,'GET',base+'notifications/')
        return next(row for row in rows if row['task_id']==job['id'])
    queued=notice(session);assert queued['status']=='queued' and queued['read'] is False
    read_path=base+'notifications/'+job['id']+'/read/'
    _,receipt=call(session,'POST',read_path,{'version':queued['version']})
    _,repeat=call(session,'POST',read_path,{'version':queued['version']})
    assert receipt==repeat and notice(session)['read'] is True
    _,job=call(session,'PATCH',path,{'status':'printing','version':job['version']})
    printing=notice(session);assert printing['status']=='printing' and printing['read'] is False
    _,stale=call(session,'POST',read_path,{'version':queued['version']})
    assert stale['read'] is False and notice(session)['read'] is False
    _,current=call(session,'POST',read_path,{'version':printing['version']})
    assert current['read'] is True
    second=login();assert notice(second)['read'] is True
    _,job=call(second,'PATCH',path,{'status':'inspection','version':job['version']})
    latest=notice(second);assert latest['read'] is False and latest['version']==job['version']
    _,after=call(second,'GET',base+'jobs/')
    assert {key:value for key,value in snapshot(after).items() if key in original}==original
    report={'demo_only':True,'workspace_id':workspace['id'],'task_id':job['id'],'created_task_only_modified':True,
        'original_jobs_unchanged':True,'assigned_queued_notified':True,'assigned_printing_notified':True,
        'read_replay_same_receipt':True,'old_receipt_does_not_hide_new_version':True,
        'read_persists_across_real_identity_sessions':True,'new_task_update_unread_again':True,
        'final_notice':latest,'final_status':job['status'],'final_version':job['version']}
    folder=root/'docs/product/linesight/acceptance/notification-batch'
    (folder/'live-notifications.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'task_id':job['id'],'version':job['version'],'original_jobs_unchanged':True}))
finally:
    for session in sessions:
        with urlopen(Request(issuer+'/protocol/openid-connect/logout',data=urlencode({'client_id':'linesight-demo','refresh_token':session['refresh_token']}).encode()),timeout=25) as response:
            assert response.status==204

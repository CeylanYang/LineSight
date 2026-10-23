"""Verify real Keycloak identities cannot substitute another workspace's objects."""
import hashlib
import json
from pathlib import Path
import secrets
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request,urlopen
import uuid
import verify_cloud_sessions as identity

folder=Path('docs/product/linesight/acceptance/access2-batch');folder.mkdir(parents=True,exist_ok=True)
config=identity.config

def request(path,token,body=None,method=None):
    headers={'Accept':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    if body is not None: headers['Content-Type']='application/json'
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,headers=headers,data=json.dumps(body).encode() if body is not None else None,method=method),timeout=25) as response:
            raw=response.read()
            return response.status,json.loads(raw) if 'json' in response.headers.get('Content-Type','') else raw
    except HTTPError as error:
        error.read();return error.code,None

admin=demo=ordinary=None;location=None;result={}
try:
    status,_,admin=identity.call(identity.origin+'/realms/master/protocol/openid-connect/token',urlencode({'client_id':'admin-cli','grant_type':'password','username':identity.private['KEYCLOAK_ADMIN_USERNAME'],'password':identity.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200
    username='scope-probe-'+uuid.uuid4().hex;password=secrets.token_urlsafe(32)
    status,headers,_=identity.call(identity.origin+'/admin/realms/linesight/users',{'username':username,'enabled':True,'firstName':'Scope','lastName':'Probe','email':username+'@example.invalid','credentials':[{'type':'password','value':password,'temporary':False}]},admin['access_token'])
    assert status==201;location=headers['Location']
    ordinary=identity.authorize(identity.browser(),username,password)
    status,_,demo=identity.grant({'grant_type':'password','client_id':'linesight-demo','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']});assert status==200
    status,me=request('auth/me/',ordinary['access_token']);assert status==200
    status,dm=request('auth/me/',demo['access_token']);assert status==200 and dm['is_demo']
    own=me['home_workspace_id'];foreign=dm['home_workspace_id'];assert own!=foreign
    fixture=json.loads(Path('docs/product/linesight/acceptance/closure-batch/live-workflow.json').read_text(encoding='utf-8'))
    assert fixture['workspace_id']==foreign
    job=fixture['job_id'];photo=fixture['states']['closed']['evidence'][0]['id']
    base=f'workspaces/{foreign}/';path=base+f'jobs/{job}/'
    checks=[]
    for suffix in ['jobs/','records/','metrics/','report/','report/?download=csv','templates/','members/','notifications/',f'jobs/{job}/',f'jobs/{job}/history/',f'jobs/{job}/evidence/{photo}/original/',f'jobs/{job}/evidence/{photo}/preview/']:
        status,_=request(base+suffix,ordinary['access_token']);assert status==404,(suffix,status)
        checks.append({'operation':'GET','resource':suffix.split('/')[0],'status':status})
    status,raw=request(path+f'evidence/{photo}/original/',demo['access_token']);assert status==200 and isinstance(raw,bytes) and len(raw)>100
    result['authorized_original_sha256']=hashlib.sha256(raw).hexdigest()
    status,_=request(path+f'evidence/{photo}/original/',None);assert status==401
    result['anonymous_photo_status']=status
    status,_=request(path,ordinary['access_token'],{'version':fixture['states']['closed']['version'],'status':'printing'},'PATCH');assert status==404
    status,_=request(base+f"exceptions/{fixture['issue_id']}/resolve/",ordinary['access_token'],{'version':1,'resolution':'Unauthorized probe'});assert status==404
    result['foreign_task_and_issue_writes_rejected']=True
    # Same member/workspace, but the photo is paired with a different real job.
    history=json.loads(Path('docs/product/linesight/acceptance/history-batch/live-history.json').read_text(encoding='utf-8'))
    assert history['workspace_id']==foreign and history['job_id']!=job
    for kind in ['original','preview']:
        status,_=request(base+f"jobs/{history['job_id']}/evidence/{photo}/{kind}/",demo['access_token']);assert status==404
    result['same_workspace_wrong_job_photo_rejected']=True
    for suffix in ['records/','report/','report/?download=csv']:
        separator='&' if '?' in suffix else '?'
        status,payload=request(f'workspaces/{own}/'+suffix+separator+urlencode({'workspace_id':foreign,'job_id':job,'inspection_id':fixture['states']['closed']['inspections'][0]['id']}),ordinary['access_token'])
        assert status==200
        serialized=json.dumps(payload).encode() if not isinstance(payload,bytes) else payload
        assert job.encode() not in serialized
    result['export_query_cannot_expand_workspace_scope']=True
    status,unchanged=request(path,demo['access_token']);assert status==200 and unchanged==fixture['states']['closed']
    result.update({'ordinary_pkce_identity':True,'cross_workspace_reads':checks,'foreign_demo_task_unchanged':True,'production_or_demo_passwords_changed':False,'physical_device_test':False})
finally:
    if ordinary:
        identity.call(identity.issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-android','refresh_token':ordinary['refresh_token']}).encode())
    if demo:
        identity.call(identity.issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-demo','refresh_token':demo['refresh_token']}).encode())
    if location:
        assert identity.call(location,token=admin['access_token'],method='DELETE')[0]==204
        result['provider_probe_deleted']=True
    if admin:
        identity.call(identity.origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
(folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'cross_workspace_reads':len(result['cross_workspace_reads']),'wrong_job_photo_rejected':True,'exports_scoped':True,'probe_deleted':result['provider_probe_deleted']}))

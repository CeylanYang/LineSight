"""Exercise the real demo SN lifecycle and capture server history for rendering."""
import hashlib
import io
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request,urlopen
import uuid
from PIL import Image

folder=Path('docs/product/linesight/acceptance/history-batch')
folder.mkdir(parents=True,exist_ok=True)
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
oidc=config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/'
with urlopen(Request(oidc+'token',data=urlencode({'grant_type':'password','client_id':'linesight-demo','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as response:
    tokens=json.load(response)

def call(path,body=None,method=None,key=None,authenticated=True):
    headers={'Content-Type':'application/json'}
    if authenticated: headers['Authorization']='Bearer '+tokens['access_token']
    if key: headers['Idempotency-Key']=key
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method),timeout=30) as response:
            return response.status,json.load(response)
    except HTTPError as error:
        return error.code,json.loads(error.read())

try:
    _,me=call('auth/me/'); assert me['is_demo']
    workspace=me['home_workspace_id']; base=f'workspaces/{workspace}/'
    stamp=uuid.uuid4().hex[:10]
    serials=[f'DEMO-HISTORY-{stamp}-01',f'DEMO-HISTORY-{stamp}-02']
    status,job=call(base+'jobs/',{'part_name':'DEMO · SN inspection history','printer':'A1','quantity':2,'batch_code':'DEMO-HISTORY-'+stamp,'tracking_mode':'serial','serial_numbers':serials},key=uuid.uuid4().hex)
    assert status==201,job
    path=base+f"jobs/{job['id']}/"
    for state in ['printing','inspection']:
        status,job=call(path,{'status':state,'version':job['version']},method='PATCH',key=uuid.uuid4().hex)
        assert status==200,job
    image=io.BytesIO();Image.new('RGB',(32,32),(70,125,220)).save(image,format='PNG');raw=image.getvalue()
    boundary='linesight-'+uuid.uuid4().hex
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="stage"\r\n\r\ninspection\r\n--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="demo-history.png"\r\nContent-Type: image/png\r\n\r\n'.encode()+raw+f'\r\n--{boundary}--\r\n'.encode())
    request=Request(config['LINESIGHT_API_BASE_URL']+path+'evidence/',data=body,headers={'Authorization':'Bearer '+tokens['access_token'],'Content-Type':'multipart/form-data; boundary='+boundary,'Idempotency-Key':hashlib.sha256((job['id']+stamp).encode()).hexdigest()})
    with urlopen(request,timeout=30) as response: photo=json.load(response)
    key=uuid.uuid4().hex
    payload={'version':job['version'],'verdict':'fail','note':'DEMO · surface mark on second piece','inspected_qty':2,'pass_qty':1,'fail_qty':1,'scrap_qty':0,'serial_results':dict(zip(serials,['pass','fail'])),'evidence_ids':[photo['id']]}
    status,failed=call(path+'inspection/',payload,key=key); assert status==201,failed
    assert call(path+'inspection/',payload,key=key)[1]==failed
    issue=failed['exceptions'][0]
    status,resolution=call(base+f"exceptions/{issue['id']}/resolve/",{'version':failed['version'],'resolution':'DEMO · reprinted and checked surface'},key=uuid.uuid4().hex)
    assert status==200,resolution
    status,finished=call(path+'inspection/',{'version':resolution['job_version'],'verdict':'pass','inspected_qty':2,'pass_qty':2,'fail_qty':0,'scrap_qty':0,'serial_results':dict.fromkeys(serials,'pass')},key=uuid.uuid4().hex)
    assert status==201 and finished['status']=='closed',finished
    _,events=call(path+'history/')
    checks=[e for e in events if e['object_type']=='inspection']
    assert [e['record']['round_no'] for e in checks]==[1,2]
    assert [e['record']['pass_qty'] for e in checks]==[1,2]
    assert len(events)==8 and all(e['job_id']==job['id'] and e['workspace_id']==workspace and e['actor_id'] for e in events)
    assert any(e['action']=='evidence.uploaded' and e['details']['stage']=='inspection' for e in events)
    assert len({e['id'] for e in events})==len(events)
    _,metrics=call(base+'metrics/?'+urlencode({'q':job['id']}))
    assert metrics['first_inspected_pieces']==2 and metrics['first_pass_pieces']==1 and metrics['final_released_pieces']==2
    foreign,_=call('workspaces/999999/jobs/'+job['id']+'/history/'); assert foreign==404
    anonymous,_=call(path+'history/',authenticated=False); assert anonymous==401
    fixture={'demo_only':True,'workspace_id':workspace,'job_id':job['id'],'events':events,'serial_numbers':serials,'inspections':finished['inspections']}
    (folder/'live-history.json').write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    result={'demo_only':True,'job_id':job['id'],'events':len(events),'actor_object_version_provenance':True,'evidence_stage_recorded':True,'two_inspection_rounds_preserved':True,'inspection_replay_without_duplicate_event':True,'serial_mode_first_denominator':2,'serial_mode_first_pass':1,'serial_mode_final_release':2,'anonymous_status':anonymous,'foreign_workspace_status':foreign}
    (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()

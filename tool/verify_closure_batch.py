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

folder=Path('docs/product/linesight/acceptance/closure-batch')
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
    stamp=uuid.uuid4().hex[:8]
    status,job=call(base+'jobs/',{'part_name':'DEMO · Closure photo comparison','printer':'A1','quantity':1,'batch_code':'DEMO-CLOSURE-'+stamp},key=uuid.uuid4().hex)
    assert status==201,job
    path=base+f"jobs/{job['id']}/"
    states={'queued':job}
    for state in ['printing','inspection']:
        status,job=call(path,{'status':state,'version':job['version']},method='PATCH',key=uuid.uuid4().hex)
        assert status==200,job
        states[state]=job
    status,job=call(path+'inspection/',{'version':job['version'],'verdict':'fail','note':'DEMO · generated surface mark reference','inspected_qty':1,'pass_qty':0,'fail_qty':1,'scrap_qty':0},key=uuid.uuid4().hex)
    assert status==201,job
    issue=job['exceptions'][0]
    source=Image.open('assets/parts/part-mount.webp').convert('RGB')
    from PIL import ImageDraw
    evidence=[]
    for stage in ['before','after']:
        picture=source.copy();draw=ImageDraw.Draw(picture)
        if stage=='before':
            w,h=picture.size
            draw.line([(w*.35,h*.4),(w*.6,h*.65)],fill='#ef4444',width=max(3,w//100))
        draw.rectangle((0,0,picture.width,25),fill='#15243c')
        draw.text((8,7),'DEMO REFERENCE / '+stage.upper(),fill='white')
        buffer=io.BytesIO(); picture.save(buffer,format='PNG');raw=buffer.getvalue()
        (folder/f'{stage}-source.png').write_bytes(raw)
        boundary='linesight-'+uuid.uuid4().hex
        fields={'stage':stage,'issue_id':str(issue['id'])}
        body=b''.join(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode() for key,value in fields.items())
        body+=f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="demo-{stage}.png"\r\nContent-Type: image/png\r\n\r\n'.encode()+raw+f'\r\n--{boundary}--\r\n'.encode()
        request=Request(config['LINESIGHT_API_BASE_URL']+path+'evidence/',data=body,headers={'Authorization':'Bearer '+tokens['access_token'],'Content-Type':'multipart/form-data; boundary='+boundary,'Idempotency-Key':hashlib.sha256(uuid.uuid4().bytes).hexdigest()})
        with urlopen(request,timeout=30) as response: photo=json.load(response)
        assert photo['id']
        evidence.append(photo)
    _,job=call(path);states['exception']=job
    status,resolution=call(base+f"exceptions/{issue['id']}/resolve/",{'version':job['version'],'resolution':'DEMO · surface mark removed for reinspection'},key=uuid.uuid4().hex)
    assert status==200,resolution
    _,job=call(path);states['reinspection']=job
    status,job=call(path+'inspection/',{'version':job['version'],'verdict':'pass','inspected_qty':1,'pass_qty':1,'fail_qty':0,'scrap_qty':0},key=uuid.uuid4().hex)
    assert status==201 and job['status']=='closed',job
    states['closed']=job
    assert {p['stage'] for p in job['evidence']}=={'before','after'}
    assert len(job['inspections'])==2
    fixture={'demo_only':True,'workspace_id':workspace,'job_id':job['id'],'issue_id':issue['id'],'states':states,'image_source':'Same bundled reference image; before has generated red mark. Neither is a photographed remediation.'}
    (folder/'live-workflow.json').write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    result={'demo_only':True,'job_id':job['id'],'queued_printing_inspection_exception_reinspection_closed':True,'before_after_issue_binding':True,'two_inspection_rounds':True,'generated_reference_images':True}
    (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()

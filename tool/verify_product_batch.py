import json, uuid, io, csv, hashlib
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError
from PIL import Image,ImageDraw
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text())
with urlopen(Request(config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/token',data=urlencode({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as r: tokens=json.load(r)
def call(method,path,body=None,raw=False):
    data=json.dumps(body).encode() if body is not None else None
    req=Request(config['LINESIGHT_API_BASE_URL']+path,data=data,method=method,headers={'Authorization':'Bearer '+tokens['access_token'],'Content-Type':'application/json','Idempotency-Key':uuid.uuid4().hex})
    try:
        with urlopen(req,timeout=30) as r: return r.status, r.read().decode('utf-8-sig') if raw else json.load(r)
    except HTTPError as e:return e.code,json.load(e)
try:
    _,me=call('GET','auth/me/'); assert me['is_demo']
    base=f"workspaces/{me['home_workspace_id']}/"
    _,templates=call('GET',base+'templates/'); template=templates[0]
    status,job=call('POST',base+'jobs/',{'part_name':'DEMO · 证据与数量批次验收','printer':'A1','quantity':10,'batch_code':'DEMO-20261023','template_id':template['id']});assert status==201,job
    path=base+f"jobs/{job['id']}/"
    for state in ('printing','inspection'):
        status,job=call('PATCH',path,{'version':job['version'],'status':state});assert status==200,job
    image=Image.new('RGB',(900,650),'#F5F7FB');d=ImageDraw.Draw(image);d.rounded_rectangle((180,120,720,530),radius=45,fill='#C9D9E8',outline='#246BFD',width=8);d.line([(400,150),(470,270),(430,350),(520,480)],fill='#CC4352',width=12)
    out=io.BytesIO();image.save(out,format='PNG'); photo=out.getvalue()
    def upload(stage,issue=None):
        boundary='LineSight'+uuid.uuid4().hex
        fields={'stage':stage,**({'issue_id':str(issue)} if issue else {})}
        body=b''.join((f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n').encode() for k,v in fields.items())
        body+=(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="demo.png"\r\nContent-Type: image/png\r\n\r\n').encode()+photo+(f'\r\n--{boundary}--\r\n').encode()
        req=Request(config['LINESIGHT_API_BASE_URL']+path+'evidence/',data=body,headers={'Authorization':'Bearer '+tokens['access_token'],'Content-Type':f'multipart/form-data; boundary={boundary}','Idempotency-Key':hashlib.sha256(body).hexdigest()})
        with urlopen(req,timeout=30) as r: assert r.status==201;return json.load(r)['id']
    evidence=upload('inspection')
    answers=[{'id':i['id'],'result':'pass','note':''} for i in template['items']]
    status,job=call('POST',path+'inspection/',{'version':job['version'],'verdict':'fail','note':'DEMO · 表面裂纹，待整改','inspected_qty':10,'pass_qty':8,'fail_qty':2,'scrap_qty':0,'answers':answers,'evidence_ids':[evidence],'category':'crack','severity':'major'});assert status==201,job
    issue=job['exceptions'][0]['id'];before=upload('before',issue);after=upload('after',issue)
    status,res=call('POST',base+f'exceptions/{issue}/resolve/',{'version':job['version'],'resolution':'DEMO · 修正参数并重新打印','next_status':'inspection'});assert status==200,res
    status,job=call('POST',path+'inspection/',{'version':res['job_version'],'verdict':'pass','note':'DEMO · 复检通过','inspected_qty':10,'pass_qty':10,'fail_qty':0,'scrap_qty':0,'answers':answers});assert status==201,job
    _,metrics=call('GET',base+f"metrics/?q={job['id']}");assert metrics['first_pass_rate']==.8 and metrics['final_release_rate']==1,metrics
    _,records=call('GET',base+f"records/?q={job['id']}");assert len(records)==2 and sum(len(r['evidence']) for r in records)==3,records
    status,csvtext=call('GET',base+f"report/?q={job['id']}&download=csv",raw=True);assert status==200
    table=dict(list(csv.reader(io.StringIO(csvtext)))[1:]);assert float(table['first_pass_rate'])==metrics['first_pass_rate']
    result={'job_id':job['id'],'template_version':template['version'],'two_rounds':True,'stage_photos':3,'first_pass_rate':.8,'final_release_rate':1,'csv_matches_metrics':True,'demo_only':True}
    Path('docs/product/linesight/acceptance/product-batch/live-api.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
finally:
    try:urlopen(Request(config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()
    except Exception:pass

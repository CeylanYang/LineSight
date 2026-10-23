"""Prepare an isolated demo task and verify invalid native forms wrote nothing."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('phase',choices=['prepare','verify'])
args=parser.parse_args()
folder=Path('docs/product/linesight/acceptance/forms-batch')
folder.mkdir(parents=True,exist_ok=True)
target=folder/'live-forms.json'
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
issuer=config['LINESIGHT_OIDC_ISSUER']
api=config['LINESIGHT_API_BASE_URL']

def call(url,body=None,token=None,method=None,key=None):
    headers={'Accept':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    if key: headers['Idempotency-Key']=key
    if isinstance(body,dict): headers['Content-Type']='application/json';body=json.dumps(body).encode()
    elif body is not None: headers['Content-Type']='application/x-www-form-urlencoded'
    with urlopen(Request(url,data=body,headers=headers,method=method),timeout=30) as response:
        raw=response.read()
        return response.status,json.loads(raw) if raw else None

session=None
try:
    _,session=call(issuer+'/protocol/openid-connect/token',urlencode({'grant_type':'password','client_id':'linesight-demo',
        'username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode())
    token=session['access_token']
    _,me=call(api+'auth/me/',token=token)
    assert me['is_demo'] and me['home_workspace_id']==5
    base=api+'workspaces/5/'
    if args.phase=='prepare':
        assert not target.exists(),'Preserve the existing acceptance task'
        _,templates=call(base+'templates/',token=token)
        _,job=call(base+'jobs/',{'part_name':'DEMO · 表单校验','printer':'Bambu Lab A1','quantity':2,
            'batch_code':'DEMO-FORMS-'+uuid.uuid4().hex[:8],'template_id':templates[0]['id']},token,key=uuid.uuid4().hex)
        for state in ['printing','inspection']:
            _,job=call(base+'jobs/'+job['id']+'/',{'status':state,'version':job['version']},token,'PATCH',uuid.uuid4().hex)
        data={'demo_only':True,'original_jobs_modified':False,'before':job,'templates_before':len(templates)}
    else:
        data=json.loads(target.read_text(encoding='utf-8'))
        _,job=call(base+'jobs/'+data['before']['id']+'/',token=token)
        _,templates=call(base+'templates/',token=token)
        assert job['version']==data['before']['version'] and job['status']=='inspection' and not job['inspections']
        assert len(templates)==data['templates_before']
        data.update(after=job,invalid_inspection_not_submitted=True,template_count_unchanged=True)
    target.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'phase':args.phase,'task_id':job['id'],'status':job['status'],'version':job['version'],'passed':True}))
finally:
    if session: call(issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-demo','refresh_token':session['refresh_token']}).encode())

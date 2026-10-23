"""Prepare and finish one isolated demo task for a real stale-inspection journey."""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('phase',choices=['prepare','advance','verify'])
args=parser.parse_args()
folder=Path('docs/product/linesight/acceptance/conflict-batch');folder.mkdir(parents=True,exist_ok=True)
fixture_path=folder/'live-conflict.json'
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
with urlopen(Request(config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/token',data=urlencode({
    'grant_type':'password','client_id':'linesight-demo','username':config['LINESIGHT_DEMO_USERNAME'],
    'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=30) as response:
    token=json.load(response)['access_token']
def call(path,body=None,method=None,key=None):
    headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'}
    if key: headers['Idempotency-Key']=key
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,headers=headers,
            data=json.dumps(body).encode() if body is not None else None,method=method),timeout=30) as response:
            return response.status,json.load(response)
    except HTTPError as failure:
        return failure.code,json.loads(failure.read())
status,me=call('auth/me/');assert status==200 and me['is_demo'] and me['home_workspace_id']==5
base='workspaces/5/'
if args.phase=='prepare':
    if fixture_path.exists():
        fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
        status,current=call(base+f"jobs/{fixture['before']['id']}/")
        assert status==200 and current['version']==fixture['before']['version'] and current['status']=='inspection','Fixture already advanced; existing data preserved'
    else:
        status,templates=call(base+'templates/');assert status==200 and templates
        template=templates[0]
        status,job=call(base+'jobs/',{'part_name':'DEMO · 支架终检','printer':'Bambu Lab A1',
            'quantity':2,'batch_code':'DEMO-REVIEW-'+uuid.uuid4().hex[:8],'template_id':template['id']},key=uuid.uuid4().hex)
        assert status==201
        path=base+f"jobs/{job['id']}/"
        for state in ['printing','inspection']:
            status,job=call(path,{'status':state,'version':job['version']},'PATCH',uuid.uuid4().hex);assert status==200
        fixture={'workspace_id':5,'before':job,'template':template,'original_jobs_modified':False,
                 'demo_only':True,'winner_key':uuid.uuid4().hex,'loser_key':uuid.uuid4().hex}
        fixture_path.write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'fixture_ready':True,'task_id':fixture['before']['id'],'version':fixture['before']['version']}))
else:
    fixture=json.loads(fixture_path.read_text(encoding='utf-8'))
    job=fixture['before'];path=base+f"jobs/{job['id']}/"
    assert job['part_name']=='DEMO · 支架终检' and job['batch_code'].startswith('DEMO-REVIEW-')
    payload={'version':job['version'],'verdict':'pass','note':'外观与装配尺寸复核完成',
             'inspected_qty':2,'pass_qty':2,'fail_qty':0,'scrap_qty':0,'template_id':fixture['template']['id'],
             'answers':[{'id':item['id'],'result':'pass','note':''} for item in fixture['template']['items']]}
    if args.phase=='advance':
        status,winner=call(path+'inspection/',payload,key=fixture['winner_key']);assert status==201
        fixture['winner']=winner
        status,rejected=call(path+'inspection/',{**payload,'note':'待核对的另一份检验'},key=fixture['loser_key'])
        assert status==409 and rejected['current']['status']=='closed'
        fixture['stale_request_status']=status;fixture['conflict_current']=rejected['current']
    status,current=call(path);assert status==200 and current['status']=='closed'
    assert len(current['inspections'])==1
    assert current['inspections'][0]['note']=='外观与装配尺寸复核完成'
    assert current['version']==fixture['winner']['version']
    fixture['verified_after_android'] = args.phase=='verify'
    fixture['only_one_inspection']=True;fixture['after']=current
    fixture_path.write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'phase':args.phase,'task_id':job['id'],'status':current['status'],
                      'version':current['version'],'inspection_count':len(current['inspections']),'stale_request_status':fixture['stale_request_status']}))

"""Read back the emulator's new demo task and prepare one new focus fixture."""
import csv
import io
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/native50-batch'
config=json.loads((root/'.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
identity=config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/'
def token_call(path,body):
    with urlopen(Request(identity+path,data=urlencode(body).encode()),timeout=25) as response:
        return json.load(response) if path=='token' else None
tokens=token_call('token',{'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']})
def call(path,body=None,key=None,method=None):
    headers={'Authorization':'Bearer '+tokens['access_token']}
    if body is not None:headers['Content-Type']='application/json'
    if key:headers['Idempotency-Key']=key
    with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method),timeout=30) as response:
        raw=response.read().decode('utf-8-sig')
        return raw if 'download=csv' in path else json.loads(raw)
try:
    me=call('auth/me/');assert me['is_demo']
    base=f"workspaces/{me['home_workspace_id']}/"
    target='0c23f42c-369e-4ea0-88fc-32982b2eff6f'
    path=base+f'jobs/{target}/'
    job=call(path);history=call(path+'history/')
    assert job['part_name']=='Native50-Quality-Bracket' and job['status']=='closed' and job['quantity']==2
    checks=job['inspections'];assert len(checks)==2
    first,second=sorted(checks,key=lambda c:c['round_no'])
    assert first['verdict']=='fail' and second['verdict']=='pass'
    assert first['fail_qty']==2 and second['pass_qty']==2
    assert len(first['answers'])==len(second['answers'])==4
    assert sum(a['result']=='fail' for a in first['answers'])==1
    assert all(a['result']=='pass' for a in second['answers'])
    assert first['template_snapshot']==second['template_snapshot']
    issue=job['exceptions'][0]
    assert issue['status']=='resolved' and issue['category']=='dimension' and issue['severity']=='major'
    assert issue['resolution']=='Reworked-diameter-and-checked-fit'
    assignments=[e for e in history if e['action']=='job.assigned'];assert len(assignments)==2
    assert assignments[-1]['details']['note']=='Shared-queue-diameter-repair'
    query='?'+urlencode({'q':target})
    metrics=call(base+'metrics/'+query);report=call(base+'report/'+query)
    rows=list(csv.reader(io.StringIO(call(base+'report/'+query+'&download=csv'))))
    table={row[0]:row[1] for row in rows if len(row)==2}
    assert metrics['task_ids']==[target] and metrics['first_pass_rate']==0 and metrics['final_release_rate']==1
    assert report['metrics']==metrics and float(table['first_pass_rate'])==0 and float(table['final_release_rate'])==1
    (folder/'live-task.json').write_text(json.dumps({'workspace_id':me['home_workspace_id'],'job':job,'history':history,'metrics':metrics,'report':report},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    result={'emulator_created_task_id':target,'two_rounds_preserved':True,'four_checklist_answers_each_round':True,'original_template_preserved':True,'handover_and_resolution_preserved':True,'metrics_report_csv_match':True,'first_pass_rate':0,'final_release_rate':1,'native_photo_capture_verified':False}
    (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n')
    # This second task is explicitly an API fixture, not an emulator-created task.
    seed=call(base+'jobs/',{'part_name':'Native51-Section-Focus','printer':'Native validation','quantity':1,'batch_code':'NATIVE51-FOCUS','request_id':'native51-focus-create-20261024'})
    seedpath=base+f"jobs/{seed['id']}/"
    for before,after in [('queued','printing'),('printing','inspection')]:
        if seed['status']==before:seed=call(seedpath,{'status':after,'version':seed['version']},'native51-focus-'+after+'-20261024','PATCH')
    if seed['status']=='inspection':seed=call(seedpath+'inspection/',{'version':seed['version'],'verdict':'fail','note':'Focus navigation fixture','inspected_qty':1,'pass_qty':0,'fail_qty':1,'scrap_qty':0},'native51-focus-fail-20261024')
    assert seed['status']=='exception'
    (folder/'focus-fixture.json').write_text(json.dumps({'workspace_id':me['home_workspace_id'],'job':seed,'origin':'real-cloud-api-fixture'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**result,'new_focus_fixture_id':seed['id']}))
finally:
    token_call('logout',{'client_id':'linesight-demo','refresh_token':tokens['refresh_token']})

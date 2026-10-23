"""Verify date drilldown and authenticated trace reads in the isolated demo."""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
oidc = config['LINESIGHT_OIDC_ISSUER'] + '/protocol/openid-connect/'
with urlopen(Request(oidc+'token',data=urlencode({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as response:
    tokens = json.load(response)
def read(path, authenticated=True):
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,headers={'Authorization':'Bearer '+tokens['access_token']} if authenticated else {}),timeout=25) as response:
            return response.status,json.load(response)
    except HTTPError as failure:
        return failure.code,None
try:
    _,me=read('auth/me/'); assert me['is_demo']
    workspace = me['home_workspace_id']; base=f'workspaces/{workspace}/'
    job_id = json.loads(Path('docs/product/linesight/acceptance/product-batch/live-api.json').read_text())['job_id']
    status,job=read(base+f'jobs/{job_id}/'); assert status==200
    first=min(job['inspections'],key=lambda row:row['round_no'])
    day=datetime.fromisoformat(first['created_at']).astimezone(timezone.utc).replace(hour=0,minute=0,second=0,microsecond=0)
    params={'q':job_id,'inspected_from':day.isoformat(),'inspected_to':(day+timedelta(days=1)).isoformat()}
    _,records=read(base+'records/?'+urlencode(params)); assert len(records)==2
    _,report=read(base+'report/?'+urlencode(params)); assert report['metrics']['first_pass_rate']==.8 and report['metrics']['final_release_rate']==1
    _,matched=read(base+'jobs/?'+urlencode({'q':job_id,'first_day':day.date().isoformat()})); assert [row['id'] for row in matched]==[job_id]
    _,other_day=read(base+'jobs/?'+urlencode({'q':job_id,'first_day':(day+timedelta(days=1)).date().isoformat()})); assert other_day==[]
    anonymous,_=read(base+f'jobs/{job_id}/',False); assert anonymous in (401,403)
    denied,_=read(f'workspaces/999999/jobs/{job_id}/'); assert denied==404
    output={'demo_only':True,'job_id':job_id,'date_range_rounds':2,'first_day_matches_actual_first_round':True,'next_day_excludes_task':True,'original_metrics_preserved':True,'anonymous_status':anonymous,'unauthorized_workspace_status':denied}
    folder=Path('docs/product/linesight/acceptance/trace-batch'); folder.mkdir(parents=True,exist_ok=True)
    (folder/'live-api.json').write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8'); print(json.dumps(output))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()

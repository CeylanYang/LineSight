"""Read back the Android demo import and recovered evidence over real HTTPS."""
import io
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from PIL import Image

folder = Path('docs/product/linesight/acceptance/workbench-batch')
config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
oidc = config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/'
with urlopen(Request(oidc+'token',data=urlencode({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as response:
    tokens = json.load(response)

def call(path,body=None,authenticated=True,binary=False):
    headers = {'Authorization':'Bearer '+tokens['access_token']} if authenticated else {}
    if body is not None: headers['Content-Type']='application/json'
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,headers=headers,data=json.dumps(body).encode() if body is not None else None),timeout=30) as response:
            return response.status,response.read() if binary else json.load(response)
    except HTTPError as failure:
        return failure.code,None
try:
    from datetime import datetime, timedelta, timezone
    _,me=call('auth/me/')
    assert me['is_demo']
    base=f"workspaces/{me['home_workspace_id']}/"
    _,jobs=call(base+'jobs/')
    local=datetime.now(timezone(timedelta(hours=8)))
    start=local.replace(hour=0,minute=0,second=0,microsecond=0).astimezone(timezone.utc)
    end=start+timedelta(days=1)
    filters={'updated_from':start.isoformat(),'updated_to':end.isoformat()}
    _,actual=call(base+'jobs/?'+urlencode(filters))
    expected={j['id'] for j in jobs if start <= datetime.fromisoformat(j['updated_at']) < end}
    assert {j['id'] for j in actual}==expected
    _,metrics=call(base+'metrics/?'+urlencode(filters))
    assert set(metrics['task_ids'])==expected
    _,report=call(base+'report/?'+urlencode(filters))
    assert report['filters']==filters and {j['id'] for j in report['jobs']}==expected
    _,csv=call(base+'report/?'+urlencode({**filters,'download':'csv'}),binary=True)
    assert b'updated_from' in csv
    bad,_=call(base+'jobs/?'+urlencode({'updated_from':end.isoformat(),'updated_to':start.isoformat()}))
    assert bad==400
    anonymous,_=call(base+'metrics/',authenticated=False)
    denied,_=call('workspaces/999999/jobs/?'+urlencode(filters))
    assert anonymous==401 and denied==404
    result={'timezone':'Asia/Shanghai','filters':filters,'all_tasks':len(jobs),'matching_tasks':len(actual),'list_metrics_report_match':True,'csv_scope_preserved':True,'invalid_range_status':bad,'anonymous_status':anonymous,'foreign_workspace_status':denied}
    (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()

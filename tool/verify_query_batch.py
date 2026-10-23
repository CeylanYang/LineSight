"""Read-only verification of shared task scope against the isolated cloud demo."""
import csv
import io
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
token_endpoint = config['LINESIGHT_OIDC_ISSUER'] + '/protocol/openid-connect/'
with urlopen(Request(token_endpoint + 'token', data=urlencode({'client_id':'linesight-demo', 'grant_type':'password', 'username':config['LINESIGHT_DEMO_USERNAME'], 'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()), timeout=25) as response:
    tokens = json.load(response)
def get(path, raw=False):
    with urlopen(Request(config['LINESIGHT_API_BASE_URL'] + path, headers={'Authorization':'Bearer ' + tokens['access_token']}), timeout=30) as response:
        return response.read().decode('utf-8-sig') if raw else json.load(response)
try:
    me = get('auth/me/')
    assert me['is_demo']
    base = f"workspaces/{me['home_workspace_id']}/"
    target = json.loads(Path('docs/product/linesight/acceptance/product-batch/live-api.json').read_text())['job_id']
    query = urlencode({'q':target, 'status':'closed', 'category':'crack', 'assignee':'unassigned'})
    jobs = get(base + 'jobs/?' + query)
    records = get(base + 'records/?' + query)
    metrics = get(base + 'metrics/?' + query)
    report = get(base + 'report/?' + query)
    rows = list(csv.reader(io.StringIO(get(base + 'report/?' + query + '&download=csv', raw=True))))
    table = {row[0]:row[1] for row in rows if len(row)==2}
    assert [row['id'] for row in jobs] == metrics['task_ids'] == [target]
    assert {row['task_id'] for row in records} == {target} and len(records) == 2
    assert report['metrics'] == metrics and [row['id'] for row in report['jobs']] == [target]
    assert metrics['first_pass_rate'] == .8 and metrics['final_release_rate'] == 1
    assert float(table['first_pass_rate']) == .8 and float(table['final_release_rate']) == 1
    assert report['source'] == 'cloud' and report['filters']['category'] == 'crack'
    assert report['report_id'] and len(report['jobs'][0]['evidence']) == 3
    output = {'demo_only':True, 'job_id':target, 'combined_filters':['task ID','status','category','unassigned'], 'shared_task_ids':True, 'two_rounds':True, 'first_pass_rate':.8, 'final_release_rate':1, 'csv_matches_metrics':True, 'report_has_evidence':3, 'report_provenance':True}
    folder = Path('docs/product/linesight/acceptance/query-batch'); folder.mkdir(parents=True, exist_ok=True)
    (folder/'live-api.json').write_text(json.dumps(output, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(output))
finally:
    urlopen(Request(token_endpoint+'logout', data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()), timeout=20).close()

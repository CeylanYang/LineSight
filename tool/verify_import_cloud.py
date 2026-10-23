"""Verify import deduplication using one synthetic record in the isolated demo team."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

root = Path(__file__).resolve().parents[1]
config = json.loads((root/'.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
issuer = config['LINESIGHT_OIDC_ISSUER']
api = config['LINESIGHT_API_BASE_URL']
with urlopen(Request(issuer+'/protocol/openid-connect/token', data=urlencode({
    'client_id': 'linesight-demo', 'grant_type': 'password',
    'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD'],
}).encode()), timeout=25) as response:
    session = json.load(response)

def call(method, path, body=None):
    headers = {'Authorization': 'Bearer '+session['access_token'], 'Content-Type': 'application/json'}
    with urlopen(Request(api+path, data=None if body is None else json.dumps(body).encode(),
                         headers=headers, method=method), timeout=25) as response:
        return response.status, json.load(response)

def snapshot(rows):
    return {row['id']: hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest() for row in rows}

try:
    _, me = call('GET', 'auth/me/')
    _, teams = call('GET', 'workspaces/')
    team = next(row for row in teams if row['id'] == me['home_workspace_id'])
    assert me['is_demo'] and team['kind'] == 'demo'
    base = f"workspaces/{team['id']}/"
    endpoint = base+'legacy-inspections/'
    _, jobs_before = call('GET', base+'jobs/')
    _, before = call('GET', endpoint)
    row = {'id': 'DEMO-IMPORT-'+uuid.uuid4().hex[:20], 'at': datetime.now(timezone.utc).isoformat(),
           'recipeName': 'DEMO · Device import verification', 'serial': 'DEMO-IMPORT',
           'passed': False, 'review': 'pass', 'sample': True}
    _, excluded = call('POST', endpoint, {'records': [row], 'include_samples': False})
    assert excluded == {'imported': 0, 'skipped': 1}
    _, unchanged = call('GET', endpoint)
    assert unchanged == before
    status, imported = call('POST', endpoint, {'records': [row], 'include_samples': True})
    assert status == 201 and imported == {'imported': 1, 'skipped': 0}
    _, repeated = call('POST', endpoint, {'records': [row], 'include_samples': True})
    assert repeated == {'imported': 0, 'skipped': 1}
    _, after = call('GET', endpoint)
    actual = next(item for item in after['records'] if item['id'] == row['id'])
    assert actual['sample'] is True and actual['original_passed'] is False and actual['passed'] is True
    assert after['count'] == before['count']+1 and after['sample_count'] == before['sample_count']+1
    assert len(before['records']) < 100, 'Cannot prove complete old-record preservation from truncated response'
    originals = snapshot(before['records'])
    assert {key: value for key, value in snapshot(after['records']).items() if key in originals} == originals
    _, jobs_after = call('GET', base+'jobs/')
    assert snapshot(jobs_after) == snapshot(jobs_before)
    report = {'demo_only': True, 'workspace_id': team['id'], 'synthetic_record_id': row['id'],
              'default_excludes_samples': True, 'explicit_sample_opt_in': True, 'repeat_import_deduplicated': True,
              'original_and_final_conclusions_preserved': True, 'previous_import_records_unchanged': True,
              'all_existing_jobs_unchanged': True, 'device_records_read_or_uploaded': False,
              'final_record': actual}
    output = root/'docs/product/linesight/acceptance/import-batch'
    output.mkdir(parents=True, exist_ok=True)
    (output/'live-import.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'synthetic_record_id': row['id'], 'existing_jobs_unchanged': True}))
finally:
    with urlopen(Request(issuer+'/protocol/openid-connect/logout', data=urlencode({
        'client_id': 'linesight-demo', 'refresh_token': session['refresh_token'],
    }).encode()), timeout=25) as response:
        assert response.status == 204

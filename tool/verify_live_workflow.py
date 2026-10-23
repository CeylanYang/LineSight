"""Concurrent HTTPS lifecycle verification, restricted to the isolated demo team."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text())
issuer = config['LINESIGHT_OIDC_ISSUER']
with urlopen(Request(issuer + '/protocol/openid-connect/token', data=urlencode({
    'client_id': 'linesight-demo', 'grant_type': 'password', 'username': config['LINESIGHT_DEMO_USERNAME'],
    'password': config['LINESIGHT_DEMO_PASSWORD']}).encode()), timeout=20) as response:
    tokens = json.load(response)


def call(method, path, body=None, key=None):
    headers = {'Authorization': 'Bearer ' + tokens['access_token'], 'Content-Type': 'application/json'}
    if key:
        headers['Idempotency-Key'] = key
    request = Request(config['LINESIGHT_API_BASE_URL'] + path,
                      data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        with urlopen(request, timeout=25) as response:
            return response.status, json.load(response)
    except HTTPError as response:
        return response.code, json.load(response)


try:
    _, profile = call('GET', 'auth/me/')
    _, workspaces = call('GET', 'workspaces/')
    workspace = next(w for w in workspaces if w['id'] == profile['home_workspace_id'])
    assert workspace['kind'] == 'demo' and profile['is_demo']
    base = f"workspaces/{workspace['id']}/"
    _, job = call('POST', base + 'jobs/', {'part_name': 'DEMO · 状态与并发验收', 'printer': 'A1', 'quantity': 10}, uuid.uuid4().hex)
    path = base + f"jobs/{job['id']}/"
    assert job['version'] == 1
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: call('PATCH', path, {'status': 'printing', 'version': 1}, uuid.uuid4().hex), range(2)))
    assert sorted(result[0] for result in results) == [200, 409], [r[0] for r in results]
    status, job = call('PATCH', path, {'status': 'inspection', 'version': 2}, uuid.uuid4().hex)
    assert status == 200 and job['version'] == 3
    key = uuid.uuid4().hex
    payload = {'verdict': 'fail', 'note': 'DEMO · 边缘裂纹', 'version': 3}
    status, failed = call('POST', path + 'inspection/', payload, key)
    assert status == 201 and failed['version'] == 4
    assert call('POST', path + 'inspection/', payload, key)[1] == failed
    assert call('PATCH', path, {'status': 'closed', 'version': 4}, uuid.uuid4().hex)[0] == 409
    assert call('PATCH', path, {'status': 'inspection', 'version': 4}, uuid.uuid4().hex)[0] == 409
    issue = failed['exceptions'][0]
    payload = {'resolution': 'DEMO · 调整参数后重新打印', 'version': 4}
    key = uuid.uuid4().hex
    status, resolved = call('POST', base + f"exceptions/{issue['id']}/resolve/", payload, key)
    assert status == 200 and resolved['job_version'] == 5
    assert call('POST', base + f"exceptions/{issue['id']}/resolve/", payload, key)[1] == resolved
    assert call('POST', base + f"exceptions/{issue['id']}/resolve/", {**payload, 'version': 5, 'resolution': 'overwrite'}, uuid.uuid4().hex)[0] == 409
    status, released = call('POST', path + 'inspection/', {'verdict': 'pass', 'version': 5, 'note': 'DEMO · 复检通过'}, uuid.uuid4().hex)
    assert status == 201 and released['status'] == 'closed' and len(released['inspections']) == 2
    assert call('PATCH', path, {'status': 'printing', 'version': 6}, uuid.uuid4().hex)[0] == 409
    _, events = call('GET', path + 'history/')
    assert [e['version'] for e in events] == [1, 2, 3, 4, 4, 5, 6]
    assert call('GET', base + 'members/')[1][0]['display_name'] == profile['display_name']
    report = {'job_id': job['id'], 'workspace_id': workspace['id'], 'demo_only': True,
        'concurrent_writers_one_success_one_conflict': True, 'inspection_idempotent': True,
        'unresolved_close_and_reinspect_rejected': True, 'resolution_idempotent_and_immutable': True,
        'reinspection_preserves_both_rounds': True, 'closed_reopen_rejected': True,
        'versioned_actor_history': True, 'customer_member_name': True}
    Path('docs/product/linesight/acceptance/sso/live-workflow-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
finally:
    with urlopen(Request(issuer + '/protocol/openid-connect/logout', data=urlencode({
        'client_id': 'linesight-demo', 'refresh_token': tokens['refresh_token']}).encode()), timeout=20) as response:
        response.read()

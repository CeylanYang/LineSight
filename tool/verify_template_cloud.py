"""Verify publication receipts, stale versions and immutable inspection snapshots via HTTPS."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import secrets
import uuid
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import verify_cloud_sessions as hosted

folder = Path('docs/product/linesight/acceptance/template-batch')
folder.mkdir(parents=True, exist_ok=True)

def run():
    status, _, admin = hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/token', urlencode({
        'client_id': 'admin-cli', 'grant_type': 'password',
        'username': hosted.private['KEYCLOAK_ADMIN_USERNAME'], 'password': hosted.private['KEYCLOAK_ADMIN_PASSWORD'],
    }).encode())
    assert status == 200, 'Provider administrator login failed'
    admin_api = hosted.origin+'/admin/realms/linesight/users'
    subject = tokens = None
    username = 'template-probe-'+uuid.uuid4().hex[:12]
    password = secrets.token_urlsafe(24)+'Aa7!'
    try:
        status, headers, _ = hosted.call(admin_api, {'username': username, 'enabled': True,
            'emailVerified': True, 'firstName': 'Template', 'lastName': 'Probe', 'email': username+'@example.invalid',
            'credentials': [{'type': 'password', 'temporary': False, 'value': password}]}, admin['access_token'])
        assert status == 201, 'Temporary provider identity creation failed'
        subject = headers['Location'].rsplit('/', 1)[1]
        tokens = hosted.authorize(hosted.browser(), username, password)
        def call(method, path, body=None, key=None):
            headers = {'Authorization': 'Bearer '+tokens['access_token'], 'Content-Type': 'application/json'}
            if key: headers['Idempotency-Key'] = key
            try:
                with urlopen(Request(hosted.api+path, data=None if body is None else json.dumps(body).encode(),
                        headers=headers, method=method), timeout=25) as response:
                    return response.status, json.load(response)
            except HTTPError as error:
                return error.code, json.load(error)
        status, me = call('GET', 'auth/me/')
        assert status == 200 and not me['is_demo']
        _, teams = call('GET', 'workspaces/')
        team = next(row for row in teams if row['id'] == me['home_workspace_id'])
        assert team['role'] == 'owner'
        base = f"workspaces/{team['id']}/"
        _, before = call('GET', base+'templates/')
        original = {row['id']: hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest() for row in before}
        body = {'name': 'DEMO · 模板版本验证', 'items': [
            {'id': 'size', 'label': '关键尺寸', 'required': True, 'allow_na': False},
            {'id': 'surface', 'label': '表面完整', 'required': False, 'allow_na': True},
            {'id': 'fit', 'label': '装配配合', 'required': True, 'allow_na': True},
        ]}
        key = uuid.uuid4().hex
        status, first = call('POST', base+'templates/', body, key)
        assert status == 201 and first['version'] == 1 and first['items'] == body['items']
        status, repeated = call('POST', base+'templates/', body, key)
        assert status == 201 and repeated == first
        status, conflict = call('POST', base+'templates/', {**body, 'name': 'Changed'}, key)
        assert status == 409 and conflict['code'] == 'idempotency_conflict'
        status, collision = call('POST', base+'templates/', body, uuid.uuid4().hex)
        assert status == 409 and collision['code'] == 'template_name_conflict'
        status, job = call('POST', base+'jobs/', {'part_name': 'DEMO · 模板快照验证', 'printer': 'Bambu Lab A1',
            'quantity': 1, 'batch_code': 'DEMO-TEMPLATE-'+uuid.uuid4().hex[:8], 'template_id': first['id']}, uuid.uuid4().hex)
        assert status == 201
        path = base+'jobs/'+job['id']+'/'
        for state in ['printing', 'inspection']:
            status, job = call('PATCH', path, {'status': state, 'version': job['version']}, uuid.uuid4().hex)
            assert status == 200
        status, inspected = call('POST', path+'inspection/', {'version': job['version'], 'verdict': 'pass',
            'inspected_qty': 1, 'pass_qty': 1, 'fail_qty': 0, 'scrap_qty': 0,
            'answers': [{'id': item['id'], 'result': 'pass', 'note': ''} for item in body['items']]}, uuid.uuid4().hex)
        assert status == 201
        update = {**body, 'base_template_id': first['id'], 'items': list(reversed(body['items']))}
        status, second = call('POST', base+'templates/', update, uuid.uuid4().hex)
        assert status == 201 and second['version'] == 2 and second['items'] == update['items']
        status, stale = call('POST', base+'templates/', update, uuid.uuid4().hex)
        assert status == 409 and stale['code'] == 'template_version_conflict' and stale['current'] == second
        concurrent_body = {**body, 'base_template_id': second['id']}
        with ThreadPoolExecutor(max_workers=2) as pool:
            concurrent = list(pool.map(lambda _: call('POST', base+'templates/', concurrent_body, uuid.uuid4().hex), range(2)))
        assert sorted(result[0] for result in concurrent) == [201, 409]
        third = next(result[1] for result in concurrent if result[0] == 201)
        assert third['version'] == 3
        status, replay = call('POST', base+'templates/', body, key)
        assert status == 201 and replay == first
        _, rows = call('GET', base+'templates/')
        assert len(rows) == len(before)+3
        for row in rows:
            if row['id'] in original:
                assert hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest() == original[row['id']]
        assert next(row for row in rows if row['id'] == first['id']) == first
        _, records = call('GET', base+'records/')
        record = next(row for row in records if row['task_id'] == job['id'])
        assert record['template_snapshot']['items'] == first['items'] and record['template_snapshot']['version'] == 1
        (folder/'live-template-fixture.json').write_text(json.dumps({'workspace_id': team['id'], 'versions': [first, second, third],
            'inspection_snapshot': record['template_snapshot'], 'source': 'HTTPS verification in a newly created isolated probe workspace; no existing user data changed.'}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        result = {'passed': True, 'native_pkce_provider_flow': True, 'new_isolated_probe_workspace': True,
            'same_key_has_one_publication': True, 'changed_body_same_key_rejected': True,
            'duplicate_name_requires_explicit_version': True, 'stale_version_rejected': True,
            'first_receipt_replays_after_new_version': True, 'ids_flags_order_preserved': True,
            'inspection_keeps_original_version_snapshot': True, 'existing_templates_unchanged': True,
            'concurrent_publishers_one_success_one_conflict': True, 'new_template_versions': 3, 'new_demo_tasks': 1}
    finally:
        if tokens:
            hosted.call(hosted.issuer+'/protocol/openid-connect/logout', urlencode({'client_id': 'linesight-android', 'refresh_token': tokens['refresh_token']}).encode())
        if subject:
            assert hosted.call(admin_api+'/'+subject, token=admin['access_token'], method='DELETE')[0] == 204
        hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/logout', urlencode({'client_id': 'admin-cli', 'refresh_token': admin['refresh_token']}).encode())
    result['temporary_provider_identity_deleted'] = True
    (folder/'live-template.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))

if __name__ == '__main__':
    run()

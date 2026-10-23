from concurrent.futures import ThreadPoolExecutor
"""Verify profile selection and immutable task metadata via actual HTTPS."""
import json
from pathlib import Path
import secrets
import uuid
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import verify_cloud_sessions as hosted

folder = Path('docs/product/linesight/acceptance/profile-management-batch')
folder.mkdir(parents=True, exist_ok=True)

def run():
    status, _, admin = hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/token', urlencode({
        'client_id': 'admin-cli', 'grant_type': 'password',
        'username': hosted.private['KEYCLOAK_ADMIN_USERNAME'], 'password': hosted.private['KEYCLOAK_ADMIN_PASSWORD'],
    }).encode())
    assert status == 200, 'Provider administrator login failed'
    admin_api = hosted.origin+'/admin/realms/linesight/users'
    subject = tokens = None
    username = 'profile-manage-probe-'+uuid.uuid4().hex[:12]
    password = secrets.token_urlsafe(24)+'Aa7!'
    try:
        status, headers, _ = hosted.call(admin_api, {'username': username, 'enabled': True,
            'emailVerified': True, 'firstName': 'Profile', 'lastName': 'Probe', 'email': username+'@example.invalid',
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
        status, profiles = call('GET', base+'printer-profiles/')
        assert status == 200 and all('revision' in p for p in profiles)
        _, templates = call('GET', base+'templates/')
        template = templates[0]
        source = {'name':'Managed profile probe','version':'probe-v1','source':'https://bambulab.com/en/a1','note':'Isolated verification','default_template_id':template['id']}
        create_key = 'profile-save-'+uuid.uuid4().hex
        status, profile = call('POST', base+'printer-profiles/', source, create_key)
        assert status == 201 and profile['revision'] == 1 and profile['default_template_id'] == template['id']
        status, replay = call('POST', base+'printer-profiles/', source, create_key)
        assert status == 201 and replay == profile
        status, _ = call('POST', base+'printer-profiles/', {**source,'note':'Changed'}, create_key)
        assert status == 409
        status, _ = call('POST', base+'printer-profiles/', source, 'profile-save-'+uuid.uuid4().hex)
        assert status == 409
        body = {'part_name':'Bound checklist probe','printer':profile['name'],'quantity':1,'profile_id':profile['id'],'profile_revision':1}
        task_key = 'profile-task-'+uuid.uuid4().hex
        status, first = call('POST', base+'jobs/', body, task_key)
        assert status == 201 and first['profile_version'] == 'probe-v1' and first['template']['id'] == template['id']
        update = {**source,'id':profile['id'],'revision':1,'version':'probe-v2','default_template_id':None}
        update_key = 'profile-save-'+uuid.uuid4().hex
        status, changed = call('POST', base+'printer-profiles/', update, update_key)
        assert status == 200 and changed['revision'] == 2 and changed['default_template_id'] is None
        status, old_receipt = call('POST', base+'printer-profiles/', source, create_key)
        assert status == 201 and old_receipt == profile
        status, old_task = call('POST', base+'jobs/', body, task_key)
        assert status == 200 and old_task['id'] == first['id'] and old_task['profile_version'] == 'probe-v1' and old_task['template']['id'] == template['id']
        status, stale = call('POST', base+'jobs/', body, 'profile-task-'+uuid.uuid4().hex)
        assert status == 409 and stale['current']['revision'] == 2
        status, second = call('POST', base+'jobs/', {**body,'profile_revision':2,'part_name':'Unbound checklist probe'}, 'profile-task-'+uuid.uuid4().hex)
        assert status == 201 and second['profile_version'] == 'probe-v2' and second['template'] is None
        with ThreadPoolExecutor(max_workers=2) as pool:
            races = list(pool.map(lambda version: call('POST', base+'printer-profiles/', {**update,'revision':2,'version':version}, 'profile-save-'+uuid.uuid4().hex), ['probe-v3-a','probe-v3-b']))
        assert sorted(status for status,_ in races) == [200,409]
        latest = next(row for status,row in races if status == 200)
        assert latest['revision'] == 3
        status, copy = call('POST', base+'printer-profiles/', {**source,'name':'Managed profile copy'}, 'profile-save-'+uuid.uuid4().hex)
        assert status == 201 and copy['id'] != profile['id'] and copy['default_template_id'] == template['id']
        _, rows = call('GET', base+'printer-profiles/')
        assert len(rows) == len(profiles)+2
        result = {'passed':True,'native_pkce_provider_flow':True,'new_isolated_probe_workspace':True,
            'same_key_returns_original_receipt':True,'same_key_altered_payload_rejected':True,'duplicate_name_rejected':True,
            'profile_default_template_applies':True,'old_task_keeps_profile_and_template':True,'stale_profile_task_rejected':True,
            'new_task_uses_updated_configuration':True,'concurrent_editors_one_success_one_conflict':True,
            'copy_creates_distinct_profile':True,'new_probe_profiles':2,'new_probe_tasks':2}
        (folder/'live-profile-fixture.json').write_text(json.dumps({'workspace_id':team['id'],'profile':profile,'latest':latest,'copy':copy,'old_task':old_task,'new_task':second,
            'source':'Actual HTTPS in a new isolated workspace; no existing user data changed.'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    finally:
        if tokens:
            hosted.call(hosted.issuer+'/protocol/openid-connect/logout', urlencode({'client_id': 'linesight-android', 'refresh_token': tokens['refresh_token']}).encode())
        if subject:
            assert hosted.call(admin_api+'/'+subject, token=admin['access_token'], method='DELETE')[0] == 204
        hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/logout', urlencode({'client_id': 'admin-cli', 'refresh_token': admin['refresh_token']}).encode())
    result['temporary_provider_identity_deleted'] = True
    (folder/'live-profile.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))

if __name__ == '__main__':
    run()

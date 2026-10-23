"""Verify profile selection and immutable task metadata via actual HTTPS."""
import json
from pathlib import Path
import secrets
import uuid
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import verify_cloud_sessions as hosted

folder = Path('docs/product/linesight/acceptance/profile-batch')
folder.mkdir(parents=True, exist_ok=True)

def run():
    status, _, admin = hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/token', urlencode({
        'client_id': 'admin-cli', 'grant_type': 'password',
        'username': hosted.private['KEYCLOAK_ADMIN_USERNAME'], 'password': hosted.private['KEYCLOAK_ADMIN_PASSWORD'],
    }).encode())
    assert status == 200, 'Provider administrator login failed'
    admin_api = hosted.origin+'/admin/realms/linesight/users'
    subject = tokens = None
    username = 'profile-probe-'+uuid.uuid4().hex[:12]
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
        assert status == 200 and {p['id'] for p in profiles} >= {'starter:a1','starter:p2s'}
        _, templates = call('GET', base+'templates/')
        template = templates[0]
        source = {'name':'Profile verification printer','version':'probe-v1','source':'https://bambulab.com/en/a1','note':'Isolated verification'}
        status, profile = call('POST', base+'printer-profiles/', source)
        assert status == 201
        body = {'part_name':'Profile snapshot probe','printer':profile['name'],'quantity':1,'profile_id':profile['id'],'template_id':template['id']}
        key = 'profile-task-'+uuid.uuid4().hex
        status, job = call('POST', base+'jobs/', body, key)
        assert status == 201 and job['profile_version'] == 'probe-v1' and job['template']['id'] == template['id']
        status, replay = call('POST', base+'jobs/', body, key)
        assert status == 200 and replay['id'] == job['id']
        status, changed = call('POST', base+'printer-profiles/', {**source,'version':'probe-v2','source':'https://bambulab.com/en/p2s'})
        assert status == 200
        status, reread = call('GET', base+'jobs/'+job['id']+'/')
        assert status == 200 and reread['profile_version'] == 'probe-v1' and reread['profile_source'] == source['source']
        status, replay = call('POST', base+'jobs/', body, key)
        assert status == 200 and replay['id'] == job['id'] and replay['profile_version'] == 'probe-v1'
        status, newer = call('POST', base+'jobs/', {**body,'part_name':'New configuration snapshot'}, 'profile-task-'+uuid.uuid4().hex)
        assert status == 201 and newer['profile_version'] == 'probe-v2'
        status, rejected = call('POST', base+'jobs/', {**body,'profile_id':'workspace:999999999'}, 'profile-task-'+uuid.uuid4().hex)
        assert status == 404
        result = {'passed':True,'native_pkce_provider_flow':True,'new_isolated_probe_workspace':True,
            'built_in_profiles_read':True,'task_uses_selected_profile':True,'explicit_template_pinned':True,
            'task_retry_does_not_duplicate':True,'old_job_keeps_profile_snapshot_after_update':True,
            'new_job_uses_updated_profile':True,'unknown_profile_rejected':True,'new_probe_tasks':2}
        (folder/'live-profile-fixture.json').write_text(json.dumps({'workspace_id':team['id'],'profile':profile,'old_task':reread,'new_task':newer,
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

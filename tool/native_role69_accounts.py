"""Provision/clean private disposable PKCE identities for native role acceptance."""
import argparse
import json
from pathlib import Path
import secrets
import uuid

import verify_cloud_sessions as kc
from verify_live_role_matrix import api, cleanup

STATE = Path.home() / 'LineSight-private/native-role69.json'


def administrator():
    status, _, token = kc.call(kc.origin + '/realms/master/protocol/openid-connect/token', kc.urlencode({
        'client_id': 'admin-cli', 'grant_type': 'password',
        'username': kc.private['KEYCLOAK_ADMIN_USERNAME'],
        'password': kc.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status == 200
    return token


def save(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state), encoding='utf-8')


def prepare():
    assert not STATE.exists(), 'Private state exists; inspect and resume/clean it before creating more users'
    admin = administrator()
    run = uuid.uuid4().hex[:10]
    state = {'team_name': 'Role56 Native69 ' + run, 'workspace': None,
             'subjects': [], 'locations': [], 'people': {}, 'run': run}
    save(state)
    try:
        for role in ['owner', 'manager', 'operator', 'viewer']:
            username = 'native69-' + run + '-' + role
            password = secrets.token_urlsafe(24)
            status, headers, _ = kc.call(kc.origin + '/admin/realms/linesight/users', {
                'username': username, 'enabled': True, 'firstName': 'Role56',
                'lastName': 'Native69 ' + role, 'email': username + '@example.invalid',
                'credentials': [{'type': 'password', 'value': password, 'temporary': False}]}, admin['access_token'])
            assert status == 201
            state['locations'].append(headers['Location'])
            state['subjects'].append(headers['Location'].rsplit('/', 1)[1])
            state['people'][role] = {'username': username, 'password': password}
            save(state)
            tokens = kc.authorize(kc.browser(), username, password)
            assert api('auth/me/', tokens['access_token'])[0] == 200
            state['people'][role]['tokens'] = tokens
            save(state)
        owner = state['people']['owner']['tokens']['access_token']
        status, team = api('workspaces/create/', owner, {'name': state['team_name']})
        assert status == 201
        state['workspace'] = team['id']
        save(state)
        for role in ['manager', 'operator', 'viewer']:
            status, invitation = api(f"workspaces/{state['workspace']}/invite/", owner, {'role': role})
            assert status == 201
            status, member = api('workspaces/redeem/', state['people'][role]['tokens']['access_token'], {'code': invitation['code']})
            assert status == 201 and member['role'] == role
        state['prepared'] = True
        save(state)
        print(json.dumps({'prepared': True, 'disposable_roles': 4, 'customer_data_changed': False}))
    finally:
        kc.call(kc.origin + '/realms/master/protocol/openid-connect/logout', kc.urlencode({
            'client_id': 'admin-cli', 'refresh_token': admin['refresh_token']}).encode())


def remove():
    state = json.loads(STATE.read_text())
    assert all(person['username'].startswith('native69-' + state['run'] + '-') for person in state['people'].values())
    admin = administrator()
    try:
        for location, person in zip(state['locations'], state['people'].values()):
            status, _, profile = kc.call(location, token=admin['access_token'])
            assert status == 200 and profile['username'] == person['username'], 'Disposable identity mismatch'
        result = cleanup(state['subjects'], state['workspace'], state['team_name'])
        for location in state['locations']:
            assert kc.call(location, token=admin['access_token'], method='DELETE')[0] == 204
    finally:
        kc.call(kc.origin + '/realms/master/protocol/openid-connect/logout', kc.urlencode({
            'client_id': 'admin-cli', 'refresh_token': admin['refresh_token']}).encode())
    result['disposable_identity_accounts_deleted'] = len(state['locations'])
    folder = Path('docs/product/linesight/acceptance/roles69-batch')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'cleanup.json').write_text(json.dumps(result, indent=2) + '\n')
    STATE.unlink()
    print(json.dumps(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'cleanup'])
    args = parser.parse_args()
    prepare() if args.action == 'prepare' else remove()

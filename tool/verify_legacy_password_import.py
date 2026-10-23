"""Verify Django Argon2 credentials against real Keycloak, then delete probe."""
import json
import secrets
import uuid
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from django.contrib.auth.hashers import Argon2PasswordHasher
from keycloak_legacy import argon2_credential

config = dict(line.split('=', 1) for line in Path('.artifact-work/sso/identity.env').read_text().splitlines() if '=' in line)
origin = 'https://47.111.81.94/sso'


def call(url, data=None, token=None, method=None):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if isinstance(data, dict):
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data).encode()
    elif data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    with urlopen(Request(url, data=data, headers=headers, method=method), timeout=20) as response:
        raw = response.read()
        return response.headers, json.loads(raw) if raw else None


_, auth = call(origin + '/realms/master/protocol/openid-connect/token', urlencode({
    'client_id': 'admin-cli', 'grant_type': 'password', 'username': config['KEYCLOAK_ADMIN_USERNAME'],
    'password': config['KEYCLOAK_ADMIN_PASSWORD']}).encode())
token = auth['access_token']
username, password = 'migration-probe-' + uuid.uuid4().hex, secrets.token_urlsafe(32)
hasher = Argon2PasswordHasher()
encoded = hasher.encode(password, hasher.salt())
endpoint = origin + '/admin/realms/linesight/users'
headers, _ = call(endpoint, {'username': username, 'enabled': True, 'firstName': 'Migration',
    'lastName': 'Probe', 'email': username + '@example.invalid',
    'credentials': [argon2_credential(encoded)]}, token)
location = headers['Location']
try:
    _, session = call(origin + '/realms/linesight/protocol/openid-connect/token', urlencode({
        'client_id': 'linesight-demo', 'grant_type': 'password', 'username': username, 'password': password}).encode())
    assert session['access_token']
    call(origin + '/realms/linesight/protocol/openid-connect/logout', urlencode({
        'client_id': 'linesight-demo', 'refresh_token': session['refresh_token']}).encode())
    report = {'django_argon2id_import': True, 'real_keycloak_password_login': True,
              'probe_session_logged_out': True}
finally:
    call(location, token=token, method='DELETE')
report['probe_deleted'] = True
Path('docs/product/linesight/acceptance/sso/legacy-password-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))

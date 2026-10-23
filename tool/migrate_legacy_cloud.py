"""Run as trusted host administrator after DB migrations, before OIDC cutover.

Provider attributes make a partially completed run safely resumable. Existing
unrelated usernames always abort; user supplied login claims never perform linking.
"""
import json
import os
import sys
import subprocess
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

try:
    import pysqlite3
    sys.modules['sqlite3'] = pysqlite3
except ImportError:
    pass

sys.path.insert(0, '/opt/linesight/backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'linesight.production_settings')
import django
django.setup()
from django.contrib.auth import get_user_model
from django.db import transaction
from collaboration.models import CloudIdentity, Membership, Workspace
from keycloak_legacy import argon2_credential

private = dict(line.split('=', 1) for line in Path('/opt/linesight-identity/identity.env').read_text().splitlines() if '=' in line)
origin = 'http://127.0.0.1:8081/sso'
issuer = 'https://47.111.81.94/sso/realms/linesight'


def call(path, data=None, token=None):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if isinstance(data, dict):
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data).encode()
    elif data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    with urlopen(Request(origin + path, data=data, headers=headers), timeout=20) as response:
        raw = response.read()
        return response.headers, json.loads(raw) if raw else None


_, auth = call('/realms/master/protocol/openid-connect/token', urlencode({
    'client_id': 'admin-cli', 'grant_type': 'password', 'username': private['KEYCLOAK_ADMIN_USERNAME'],
    'password': private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
token = auth['access_token']
endpoint = '/admin/realms/linesight/users'
users = list(get_user_model().objects.order_by('pk'))
# Validate every representation and namespace before creating anything.
pending = []
provider_credentials = None
for user in users:
    if CloudIdentity.objects.filter(user=user).exists():
        continue
    credential = argon2_credential(user.password)
    _, matches = call(endpoint + '?' + urlencode({'username': user.username, 'exact': 'true'}), token=token)
    if matches:
        # Recovery after an API rollback: Keycloak may have committed the import
        # already. Compare the exact trusted password representation on the host;
        # a coincidentally equal username is never sufficient for binding.
        if provider_credentials is None:
            query = "SELECT json_build_object('id', u.id, 'secret', c.secret_data, 'credential', c.credential_data) FROM user_entity u JOIN credential c ON c.user_id=u.id JOIN realm r ON r.id=u.realm_id WHERE r.name='linesight' AND c.type='password'"
            raw = subprocess.check_output(['podman', 'exec', 'linesight-identity_postgres_1',
                'psql', '-U', 'keycloak', '-d', 'keycloak', '-At', '-c', query], text=True)
            provider_credentials = {row['id']: row for row in map(json.loads, raw.splitlines())}
        stored = provider_credentials.get(matches[0]['id'])
        if not stored or json.loads(stored['secret']) != json.loads(credential['secretData']) or json.loads(stored['credential']) != json.loads(credential['credentialData']):
            raise RuntimeError('Existing identity credential mismatch; no automatic username linking')
    pending.append((user, credential, matches))
for user, credential, matches in pending:
    if matches:
        subject = matches[0]['id']
    else:
        headers, _ = call(endpoint, {'username': user.username, 'enabled': user.is_active,
            'firstName': user.first_name or user.username, 'lastName': user.last_name or 'LineSight',
            **({'email': user.email} if user.email else {}),
            'attributes': {'linesight_legacy_user_id': [str(user.pk)]}, 'credentials': [credential]}, token)
        subject = headers['Location'].rsplit('/', 1)[1]
    with transaction.atomic():
        membership = Membership.objects.filter(user=user).order_by('pk').first()
        if membership:
            home = membership.workspace
        else:
            home = Workspace.objects.create(name=f'{user.username} 的工作区'[:100], kind='personal')
            Membership.objects.create(user=user, workspace=home, role='owner')
        CloudIdentity.objects.create(user=user, issuer=issuer, subject=subject, home_workspace=home,
            display_name=user.get_full_name() or user.username)
assert CloudIdentity.objects.filter(user__in=users).count() == len(users)
print(json.dumps({'legacy_users_preserved': len(users), 'identities_provisioned': len(pending)}))

"""Host-side guarded original-UI/domain/SSO deployment. Never prints secrets.

Stage this file, config/service, site.tgz and the two tested backend files in
/tmp/linesight-stock142. Invoke with the production venv. Existing identity DB,
subjects and passwords are not recreated; every business row is checked.
"""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import sqlite3
import subprocess
import tarfile
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

STAGE = Path(__file__).resolve().parent
DOMAIN = '99ai.pronhubcn.com'
ORIGIN = 'https://' + DOMAIN
ISSUER = ORIGIN + '/sso/realms/linesight'
CADDY = Path('/etc/caddy/Caddyfile')
COMPOSE = Path('/opt/linesight-identity/compose.yaml')
ENV = Path('/etc/linesight/linesight.env')
BACKEND = Path('/opt/linesight/backend')
SITE = Path('/opt/linesight-extras/whatif-original-142b')
BACKUP = Path('/var/backups/linesight/stock142') / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
BACKUP.mkdir(parents=True, mode=0o700)
assert hashlib.sha256(CADDY.read_bytes()).hexdigest() == '8aea2f68be98d7c46dfe0d7a54b5a7b4737acbeaadc5e0fce479d7fd8d4396e8', 'Caddy changed; review live config'
EXPECTED = {'collaboration/oidc.py': 'f3a402d13c0945c099ae1cf0b652c21277f2bc56b9dea8add3018dabe9a2902c',
            'linesight/production_settings.py': 'e926dec5d1609d2a56908bdd8b2678119d406914a17a48bc1d2e253872b31803'}
for name, digest in EXPECTED.items():
    assert hashlib.sha256((BACKEND / name).read_bytes()).hexdigest() == digest, 'Concurrent backend change: ' + name


def run(*args, **kw):
    result = subprocess.run(args, capture_output=True, text=True, **kw)
    assert result.returncode == 0, 'Command failed: ' + args[0]  # output can contain private config
    return result.stdout


def env_read(path):
    return dict(line.split('=', 1) for line in path.read_text().splitlines() if line and not line.startswith('#') and '=' in line)


def env_update(path, values):
    lines = [line for line in path.read_text().splitlines() if line.split('=', 1)[0] not in values]
    path.write_text('\n'.join(lines) + '\n' + ''.join(f'{k}={v}\n' for k, v in values.items()))


def wait_ready(url, expected=200, headers=None):
    for _ in range(180):
        try:
            with urlopen(Request(url, headers=headers or {}), timeout=3) as response:
                if response.status == expected:
                    return json.load(response) if 'json' in response.headers.get('Content-Type', '') else True
        except Exception:
            time.sleep(1)
    raise AssertionError('Readiness failed')


def snapshot(db):
    return {name: list(db.execute('SELECT * FROM "' + name + '" ORDER BY rowid')) for (name,) in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}


saved_files = [CADDY, COMPOSE, ENV, Path('/etc/systemd/system/linesight-whatif.service')]
saved_files += [BACKEND / name for name in EXPECTED]
for index, path in enumerate(saved_files):
    shutil.copy2(path, BACKUP / str(index))
    os.chmod(BACKUP / str(index), 0o600)
with sqlite3.connect('/var/lib/linesight/linesight.sqlite3') as db, sqlite3.connect(BACKUP / 'business.sqlite3') as dest:
    db.backup(dest)
    before = snapshot(db)
os.chmod(BACKUP / 'business.sqlite3', 0o600)

assert not SITE.exists(), 'Immutable site already exists'
SITE.mkdir(mode=0o755)
with tarfile.open(STAGE / 'site.tgz') as archive:
    archive.extractall(SITE, filter='data')
assert (SITE / 'site/server.js').is_file()

private = env_read(Path('/opt/linesight-identity/identity.env'))
admin_token = None
new_client = None


def admin(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    request = Request('http://127.0.0.1:8081/sso/admin/' + path, data=body, method=method,
                      headers={'Authorization': 'Bearer ' + admin_token, 'Content-Type': 'application/json'})
    with urlopen(request, timeout=15) as response:
        content = response.read()
        return json.loads(content) if content else None


try:
    # Caddy only accepts the two explicit public hosts. Force the forwarding
    # host at the edge, allowing old IP clients and new domain clients to share
    # the same realm without trusting arbitrary caller-supplied host headers.
    compose = COMPOSE.read_text()
    assert 'KC_HOSTNAME: ${KEYCLOAK_PUBLIC_URL:' in compose
    compose = '\n'.join('      KC_HOSTNAME_STRICT: "false"' if 'KC_HOSTNAME: ' in line else line for line in compose.splitlines()) + '\n'
    COMPOSE.write_text(compose)
    caddy = CADDY.read_text()
    old_whatif = '''    handle /linesight/whatif* {
        request_body {
            max_size 64KB
        }
        @internal path /linesight/whatif/api-setup* /linesight/whatif/api-test*
        respond @internal 404
        reverse_proxy 127.0.0.1:3008
    }'''
    assert old_whatif in caddy
    new_routes = '''    redir /login /sso/realms/linesight/account/ 302
    handle /register {
        respond "registration_closed" 410
    }
    handle /sso/* {
        reverse_proxy 127.0.0.1:8081 {
            header_up X-Forwarded-Host 99ai.pronhubcn.com
            header_up X-Forwarded-Proto https
        }
    }
    handle /api/* {
        reverse_proxy 127.0.0.1:8000
    }
    handle_path /static/* {
        root * /srv/linesight/static
        file_server
    }
    handle /linesight/whatif* {
        request_body {
            max_size 64KB
        }
        header Cache-Control "no-store"
        reverse_proxy 127.0.0.1:3108
    }'''
    caddy = caddy.replace(old_whatif, new_routes)
    caddy = caddy.replace('''\t\treverse_proxy 127.0.0.1:8081
''', '''\t\treverse_proxy 127.0.0.1:8081 {
            header_up X-Forwarded-Host 47.111.81.94
            header_up X-Forwarded-Proto https
        }
''')
    CADDY.write_text(caddy)
    run('/usr/local/bin/caddy', 'validate', '--config', str(CADDY))
    run('systemctl', 'reload', 'caddy')
    run('/opt/linesight-identity/tools/bin/podman-compose', '--env-file', 'identity.env', 'up', '-d', '--no-deps', '--force-recreate', 'keycloak', cwd='/opt/linesight-identity', timeout=180)
    discovery = wait_ready(ISSUER + '/.well-known/openid-configuration')
    assert discovery['issuer'] == ISSUER
    legacy = wait_ready('https://47.111.81.94/sso/realms/linesight/.well-known/openid-configuration')
    assert legacy['issuer'] == 'https://47.111.81.94/sso/realms/linesight'
    data = urlencode({'client_id': 'admin-cli', 'grant_type': 'password', 'username': private['KEYCLOAK_ADMIN_USERNAME'],
                      'password': private['KEYCLOAK_ADMIN_PASSWORD']}).encode()
    with urlopen(Request('http://127.0.0.1:8081/sso/realms/master/protocol/openid-connect/token', data=data), timeout=15) as response:
        admin_token = json.load(response)['access_token']
    realm = admin('GET', 'realms/linesight')
    assert realm['registrationAllowed'] is False
    assert not realm.get('attributes', {}).get('frontendUrl'), 'Review realm URL override'
    existing = admin('GET', 'realms/linesight/clients?clientId=linesight-whatif')
    assert not existing, 'Client exists; preserve its current configuration'
    client_secret = secrets.token_urlsafe(48)
    admin('POST', 'realms/linesight/clients', {
        'clientId': 'linesight-whatif', 'name': 'WhatIfIBought', 'enabled': True,
        'protocol': 'openid-connect', 'publicClient': False, 'secret': client_secret,
        'standardFlowEnabled': True, 'implicitFlowEnabled': False, 'directAccessGrantsEnabled': False,
        'serviceAccountsEnabled': False, 'redirectUris': [ORIGIN + '/linesight/whatif/oauth2/callback'],
        'webOrigins': [ORIGIN], 'defaultClientScopes': ['profile', 'email'],
        'attributes': {'pkce.code.challenge.method': 'S256'}})
    new_client = admin('GET', 'realms/linesight/clients?clientId=linesight-whatif')[0]['id']
    auth_env = Path('/etc/linesight/whatif-auth.env')
    assert not auth_env.exists()
    auth_env.write_text('OAUTH2_PROXY_CLIENT_SECRET=' + client_secret + '\nOAUTH2_PROXY_COOKIE_SECRET=' + base64.urlsafe_b64encode(secrets.token_bytes(32)).decode() + '\n')
    auth_env.chmod(0o600)
    public_config = Path('/opt/linesight-extras/oauth2-proxy-7.15.5/whatif-auth.cfg')
    shutil.copy2(STAGE / 'oauth2-proxy.cfg', public_config)
    public_config.chmod(0o644)
    shutil.copy2(STAGE / 'linesight-whatif-auth.service', '/etc/systemd/system/linesight-whatif-auth.service')
    for name in EXPECTED:
        target = BACKEND / name
        stat = target.stat()
        shutil.copyfile(STAGE / Path(name).name, target)
        os.chmod(target, stat.st_mode & 0o777)
        os.chown(target, stat.st_uid, stat.st_gid)
    env_update(ENV, {'LINESIGHT_OIDC_ISSUER_ALIASES': ISSUER,
                     'LINESIGHT_ALLOWED_HOSTS': '47.111.81.94,127.0.0.1,localhost,' + DOMAIN})
    service_path = Path('/etc/systemd/system/linesight-whatif.service')
    service_path.write_text(service_path.read_text().replace('/opt/linesight-extras/whatif-8085/site', str(SITE / 'site')).replace('sample calculator', 'original responsive UI'))
    run('systemctl', 'daemon-reload')
    run('systemctl', 'restart', 'linesight', 'linesight-whatif')
    wait_ready('http://127.0.0.1:8000/', headers={'Host': DOMAIN, 'X-Forwarded-Proto': 'https'})
    wait_ready('http://127.0.0.1:3008/linesight/whatif')
    run('systemctl', 'enable', '--now', 'linesight-whatif-auth')
    wait_ready('http://127.0.0.1:3108/ping')
    with sqlite3.connect('/var/lib/linesight/linesight.sqlite3') as db:
        after = snapshot(db)
    assert after == before, 'Business rows changed unexpectedly'
    report = {'deployed': True, 'backup': str(BACKUP), 'site': str(SITE), 'original_ui': True,
              'oauth2_proxy': '7.15.5', 'canonical_issuer': ISSUER, 'legacy_issuer_compatible': True,
              'registration_allowed': False, 'business_tables_preserved': len(before), 'all_business_rows_preserved': True}
    (BACKUP / 'deployment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
except BaseException:
    if new_client and admin_token:
        try:
            admin('DELETE', 'realms/linesight/clients/' + new_client)
        except Exception:
            pass
    run('systemctl', 'disable', '--now', 'linesight-whatif-auth') if Path('/etc/systemd/system/linesight-whatif-auth.service').exists() else None
    for index, path in enumerate(saved_files):
        shutil.copyfile(BACKUP / str(index), path)
    run('/usr/local/bin/caddy', 'validate', '--config', str(CADDY))
    run('systemctl', 'reload', 'caddy')
    run('/opt/linesight-identity/tools/bin/podman-compose', '--env-file', 'identity.env', 'up', '-d', '--no-deps', '--force-recreate', 'keycloak', cwd='/opt/linesight-identity', timeout=180)
    run('systemctl', 'daemon-reload')
    run('systemctl', 'restart', 'linesight', 'linesight-whatif')
    print('Deployment failed; prior service/configuration restored. Private backup: ' + str(BACKUP))
    raise

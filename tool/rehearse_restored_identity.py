"""Boot an isolated restored Keycloak and exercise genuine bearer authentication.

Host-side only. All identity requests are restricted to the clone's loopback
listener. Production databases, users and sessions are never modified.
"""
import argparse
import base64
from http.cookiejar import CookieJar, DefaultCookiePolicy
from html.parser import HTMLParser
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import (Request, build_opener, HTTPCookieProcessor,
                            HTTPRedirectHandler, urlopen)

from rehearse_cloud_restore import Provider, sha, sqlite_manifest

LOCAL = 'http://127.0.0.1:18081/sso'
REDIRECT = 'com.linesight.app:/oauthredirect'


class LoopbackRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith(LOCAL + '/'):
            raise ValueError('Identity redirect left the isolated provider')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def env_file(path):
    return dict(line.split('=', 1) for line in path.read_text().splitlines()
                if line and not line.startswith('#') and '=' in line)


def backup_path(value):
    path = Path(value).resolve()
    if path.parent != Path('/var/backups/linesight/complete') or not re.fullmatch(r'\d{8}T\d{12}Z', path.name):
        raise ValueError('Use a dedicated timestamped backup directory')
    return path


def request(url, fields=None, token=None, method=None):
    # Fail closed rather than following a hostname back to the live provider.
    if not url.startswith(LOCAL + '/'):
        raise ValueError('Identity requests must target the isolated loopback clone')
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if isinstance(fields, dict):
        headers['Content-Type'] = 'application/json'
        fields = json.dumps(fields).encode()
    elif fields is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    try:
        with build_opener(LoopbackRedirect()).open(Request(url, data=fields, headers=headers, method=method), timeout=15) as response:
            raw = response.read()
            return response.status, response.headers, json.loads(raw) if raw else None
    except HTTPError as error:
        return error.code, error.headers, None


class LoginForm(HTMLParser):
    def __init__(self):
        super().__init__()
        self.action = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'form' and attrs.get('id') == 'kc-form-login':
            self.action = attrs['action']


def native_login(canonical, username, password):
    def localize(url):
        if url.startswith(canonical + '/'):
            return LOCAL + url[len(canonical):]
        if url.startswith(LOCAL + '/'):
            return url
        raise ValueError('Browser navigation left the isolated provider')

    class CloneRedirect(HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            if newurl.startswith(REDIRECT):
                return None
            return super().redirect_request(req, fp, code, msg, headers, localize(newurl))

    # This is a private loopback-only browser probe, with the restored canonical
    # HTTPS issuer retained. Secure cookies remain entirely on this host.
    cookies = CookieJar(DefaultCookiePolicy(secure_protocols=('http', 'https')))
    browser = build_opener(HTTPCookieProcessor(cookies), CloneRedirect())
    verifier, state = secrets.token_urlsafe(48), secrets.token_urlsafe(24)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    fields = {'client_id': 'linesight-android', 'response_type': 'code', 'redirect_uri': REDIRECT,
              'scope': 'openid profile email', 'state': state, 'code_challenge': challenge,
              'code_challenge_method': 'S256'}
    with browser.open(LOCAL + '/realms/linesight/protocol/openid-connect/auth?' + urlencode(fields), timeout=15) as response:
        form = LoginForm()
        form.feed(response.read().decode())
    assert form.action, 'Restored native login form missing'
    try:
        browser.open(Request(localize(form.action), data=urlencode({'username': username, 'password': password}).encode()), timeout=15)
        raise AssertionError('Native authorization redirect missing')
    except HTTPError as error:
        assert error.code == 302 and error.headers.get('Location', '').startswith(REDIRECT)
        result = parse_qs(urlparse(error.headers['Location']).query)
        assert result.get('state') == [state] and 'code' in result
    status, _, tokens = request(LOCAL + '/realms/linesight/protocol/openid-connect/token', urlencode({
        'client_id': 'linesight-android', 'grant_type': 'authorization_code',
        'code': result['code'][0], 'redirect_uri': REDIRECT, 'code_verifier': verifier}).encode())
    assert status == 200, 'Restored PKCE code exchange failed'
    return tokens


def verify_api(backup, demo_config):
    """A separate process loads the restored Django code, data and real IdP."""
    restored = backup / 'restored-identity'
    for key, value in env_file(backup / 'linesight.env').items():
        os.environ[key] = value.strip().strip('"').strip("'")
    os.environ['LINESIGHT_DATA_DIR'] = str(restored)
    os.environ['DJANGO_SETTINGS_MODULE'] = 'linesight.production_settings'
    sys.path.insert(0, str(backup / 'backend'))
    try:
        import pysqlite3
        sys.modules['sqlite3'] = pysqlite3
    except ImportError:
        pass
    import django
    django.setup()
    from django.conf import settings
    from rest_framework.test import APIClient
    from collaboration.models import Membership, Evidence, CloudIdentity
    from collaboration.oidc import verify_access_token
    assert Path(settings.DATABASES['default']['NAME']).resolve() == restored / 'linesight.sqlite3'
    settings.ALLOWED_HOSTS = ['testserver']
    canonical = settings.LINESIGHT_OIDC_ISSUER.rsplit('/realms/', 1)[0]
    settings.LINESIGHT_OIDC_JWKS_URL = LOCAL + '/realms/linesight/protocol/openid-connect/certs'
    settings.LINESIGHT_OIDC_INTROSPECTION_URL = LOCAL + '/realms/linesight/protocol/openid-connect/token/introspect'
    private = env_file(backup / 'identity.env')
    config = json.loads(demo_config.read_text(encoding='utf-8-sig'))
    token_url = LOCAL + '/realms/linesight/protocol/openid-connect/token'
    status, _, admin = request(LOCAL + '/realms/master/protocol/openid-connect/token', urlencode({
        'client_id': 'admin-cli', 'grant_type': 'password',
        'username': private['KEYCLOAK_ADMIN_USERNAME'], 'password': private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status == 200, 'Restored administrative credentials rejected'
    admin_url = LOCAL + '/admin/realms/linesight'
    location = None
    sessions = []
    client = APIClient()

    def api(path, token, method='get', body=None):
        client.credentials(HTTP_AUTHORIZATION='Bearer ' + token)
        return getattr(client, method)(path, data=body, format='json', secure=True)

    try:
        providers = request(admin_url + '/authentication/authenticator-providers', token=admin['access_token'])[2]
        assert any(p['id'] == 'linesight-nfc-ticket' for p in providers), 'Restored NFC SPI missing'
        demo_before = {(str(row.pk),row.subject,row.home_workspace_id) for row in CloudIdentity.objects.filter(is_demo=True)}
        status, _, demo = request(token_url, urlencode({'client_id': 'linesight-demo', 'grant_type': 'password',
            'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD']}).encode())
        assert status == 200, 'Restored demo credentials rejected'
        sessions.append(('linesight-demo', demo))
        me = api('/api/v1/auth/me/', demo['access_token'])
        assert me.status_code == 200 and me.data['is_demo']
        workspace = me.data['home_workspace_id']
        assert (me.data['id'], verify_access_token(demo['access_token'])['sub'], workspace) in demo_before
        base = f'/api/v1/workspaces/{workspace}/'
        for path in ['jobs/', 'records/', 'report/']:
            assert api(base + path, demo['access_token']).status_code == 200
        username, password = 'restore-probe-' + secrets.token_hex(8), secrets.token_urlsafe(32)
        status, headers, _ = request(admin_url + '/users', {'username': username, 'enabled': True,
            'firstName': 'Restore', 'lastName': 'Probe', 'email': username + '@example.invalid', 'emailVerified':True,
            'credentials': [{'type': 'password', 'value': password, 'temporary': False}]}, admin['access_token'])
        assert status == 201
        # Location is only used as an opaque ID; never navigate to the live URL.
        location = admin_url + '/users/' + headers['Location'].rsplit('/', 1)[1]
        normal = native_login(canonical, username, password)
        sessions.append(('linesight-android', normal))
        owner = api('/api/v1/auth/me/', normal['access_token'])
        assert owner.status_code == 200 and not owner.data['is_demo']
        assert api(base + 'jobs/', normal['access_token']).status_code == 404
        identity = CloudIdentity.objects.get(pk=owner.data['id'])
        photo = Evidence.objects.select_related('job').first()
        assert photo is not None, 'No evidence available in restored snapshot'
        member = Membership.objects.create(workspace=photo.job.workspace, user=identity.user, role='viewer')
        photo_base = f'/api/v1/workspaces/{photo.job.workspace_id}/'
        assert api(photo_base + 'report/', normal['access_token']).status_code == 200
        response = api(photo_base + f'jobs/{photo.job_id}/evidence/{photo.pk}/original/', normal['access_token'])
        assert response.status_code == 200
        assert hashlib.sha256(b''.join(response.streaming_content)).hexdigest() == sha(restored / 'media' / photo.image.name)
        assert api(photo_base + 'jobs/', normal['access_token'], 'post', {'part_name':'Denied clone write','printer':'A1','quantity':1}).status_code == 403
        member.delete()
        assert api(photo_base + 'report/', normal['access_token']).status_code == 404
        assert api(photo_base + f'jobs/{photo.job_id}/evidence/{photo.pk}/original/', normal['access_token']).status_code == 404
        for client_id, tokens in list(sessions):
            status, _, fresh = request(token_url, urlencode({'client_id': client_id, 'grant_type':'refresh_token','refresh_token':tokens['refresh_token']}).encode())
            assert status == 200 and fresh['refresh_token'] != tokens['refresh_token']
            assert api('/api/v1/auth/me/', fresh['access_token']).status_code == 200
            status, _, _ = request(LOCAL + '/realms/linesight/protocol/openid-connect/logout', urlencode({'client_id':client_id,'refresh_token':fresh['refresh_token']}).encode())
            assert status in (200,204)
            assert api('/api/v1/auth/me/', fresh['access_token']).status_code == 401
            assert request(token_url, urlencode({'client_id':client_id,'grant_type':'refresh_token','refresh_token':fresh['refresh_token']}).encode())[0] == 400
        return {'restored_admin_login':True,'restored_demo_password_login':True,
            'restored_demo_subject_and_workspace_preserved':True,'native_pkce_login':True,
            'native_probe_created_in_clone_only':True,'real_bearer_jwt_and_introspection':True,
            'demo_jobs_records_report_read':True,'authorized_photo_bytes_identical':True,
            'viewer_write_status':403,'outsider_status':404,'removed_member_photo_and_report_status':404,
            'native_and_demo_refresh_rotation':True,'native_and_demo_logout_access_and_refresh_revoked':True,
            'restored_nfc_spi_loaded':True,'nfc_login_exercised':False,
            'identity_transport':'Host loopback HTTP; canonical HTTPS issuer preserved; no public clone listener',
            'force_authenticate_used':False,'production_users_or_sessions_modified':False}
    finally:
        if location:
            request(location, token=admin['access_token'], method='DELETE')
        for client_id, tokens in sessions + [('admin-cli', admin)]:
            realm = 'master' if client_id == 'admin-cli' else 'linesight'
            request(LOCAL + '/realms/' + realm + '/protocol/openid-connect/logout', urlencode({'client_id':client_id,'refresh_token':tokens['refresh_token']}).encode())


def run(backup, demo_config):
    os.umask(0o077)
    import sqlite3
    manifest = json.loads((backup / 'private-manifest.json').read_text())
    assert manifest['identity_runtime_files'], 'Back up runtime extensions before rehearsal'
    for name, digest in manifest['identity_runtime_files'].items():
        assert sha(backup / name) == digest
    assert any(name.startswith('providers/') for name in manifest['identity_runtime_files'])
    restored = backup / 'restored-identity'
    assert not restored.exists(), 'Preserve previous rehearsal state; use a fresh backup'
    restored.mkdir()
    shutil.copy2(backup / 'linesight.sqlite3', restored / 'linesight.sqlite3')
    shutil.copytree(backup / 'media', restored / 'media')
    with sqlite3.connect(restored / 'linesight.sqlite3') as db:
        assert sqlite_manifest(db) == manifest['sqlite']
        assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
    for name, digest in manifest['media'].items():
        assert sha(restored / 'media' / name) == digest
    provider = Provider()
    database = 'linesight_restore_auth_' + backup.name.lower()
    container = 'linesight-restore-auth-' + backup.name.lower()
    private = env_file(backup / 'identity.env')
    runtime = backup / 'clone-runtime.env'
    result = {}

    def exercise(database):
        values = {'KC_DB':'postgres','KC_DB_URL':f'jdbc:postgresql://postgres:5432/{database}',
            'KC_DB_USERNAME':provider.user,'KC_DB_PASSWORD':private['KEYCLOAK_DB_PASSWORD'],
            'KC_HOSTNAME':private['KEYCLOAK_PUBLIC_URL'],'KC_HTTP_ENABLED':'true','KC_HTTP_HOST':'0.0.0.0',
            'KC_HTTP_PORT':'8080','KC_HTTP_RELATIVE_PATH':'/sso','KC_PROXY_HEADERS':'xforwarded',
            'JAVA_OPTS_KC_HEAP':'-Xms128m -Xmx256m',
            'LINESIGHT_NFC_TICKET_SECRET':private['LINESIGHT_NFC_TICKET_SECRET']}
        runtime.write_text(''.join(f'{key}={value}\n' for key,value in values.items()))
        inspected = json.loads(subprocess.check_output(['podman','inspect','linesight-identity_keycloak_1']))[0]
        image = inspected['Image']
        network = next(iter(inspected['NetworkSettings']['Networks']))
        # Root is confined to an ephemeral private container so 0600 backup JARs
        # remain private without changing permissions on the preserved backup.
        try:
            subprocess.run(['podman','run','-d','--name',container,'--user','0','--memory','512m','--cpus','1',
                '--network',network,'--env-file',str(runtime),'-p','127.0.0.1:18081:8080',
                '-v',str(backup/'providers')+':/opt/keycloak/providers:ro',image,'start'],
                check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=40)
            deadline = time.monotonic()+180
            while True:
                try:
                    status,_,discovery=request(LOCAL+'/realms/linesight/.well-known/openid-configuration')
                    if status==200:
                        assert discovery['issuer']==private['KEYCLOAK_PUBLIC_URL'].rstrip('/')+'/realms/linesight'
                        break
                except (URLError,TimeoutError,ConnectionError):
                    pass
                if time.monotonic()>deadline:
                    raise RuntimeError('Restored identity startup timed out')
                state=json.loads(subprocess.check_output(['podman','inspect',container]))[0]['State']
                assert state['Running'],'Restored provider exited before discovery'
                time.sleep(1)
            output=subprocess.check_output([sys.executable,str(Path(__file__).resolve()),str(backup),
                '--demo-config',str(demo_config),'--verify-api'],text=True,timeout=180)
            result.update(json.loads(output.strip().splitlines()[-1]))
            result['container_image_id']=image
        finally:
            exists=subprocess.run(['podman','container','exists',container]).returncode==0
            if exists:
                subprocess.run(['podman','rm','-f',container],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=40)
            runtime.unlink(missing_ok=True)

    restored_manifest=provider.restore(backup/'identity.dump',database,exercise)
    assert restored_manifest==manifest['provider']
    assert provider.sql(provider.database,f"SELECT count(*) FROM pg_database WHERE datname='{database}'")=='0'
    result.update(backup=backup.name,sqlite_tables=len(manifest['sqlite']),provider_tables=len(manifest['provider']),
        media_files=len(manifest['media']),rows_identical_before_login=True,
        identity_runtime_files=manifest['identity_runtime_files'],temporary_container_and_database_removed=True,
        production_replaced=False)
    (backup/'identity-rehearsal-report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('backup',type=backup_path)
    parser.add_argument('--demo-config',type=Path,required=True)
    parser.add_argument('--verify-api',action='store_true')
    args=parser.parse_args()
    if os.name!='posix' or os.geteuid()!=0:
        raise RuntimeError('Run only as root on the backup host')
    if args.verify_api:
        print(json.dumps(verify_api(args.backup,args.demo_config)))
    else:
        run(args.backup,args.demo_config)

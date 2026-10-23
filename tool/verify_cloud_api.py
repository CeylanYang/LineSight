"""Real Keycloak PKCE and demo flows against the deployed HTTPS API."""
import base64
import hashlib
import html
from html.parser import HTMLParser
from http.cookiejar import CookieJar
import json
from pathlib import Path
import secrets
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse, parse_qs
from urllib.request import Request, build_opener, HTTPCookieProcessor, HTTPRedirectHandler, urlopen
import uuid

config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text())
private = dict(line.split('=', 1) for line in Path('.artifact-work/sso/identity.env').read_text().splitlines() if '=' in line)
issuer = config['LINESIGHT_OIDC_ISSUER']
origin = issuer.split('/realms/')[0]
api = config['LINESIGHT_API_BASE_URL']


def call(url, data=None, token=None, method=None):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if isinstance(data, dict):
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data).encode()
    elif data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    try:
        with urlopen(Request(url, data=data, headers=headers, method=method), timeout=20) as response:
            raw = response.read()
            return response.status, response.headers, json.loads(raw) if raw else None
    except HTTPError as error:
        return error.code, error.headers, None


def grant(fields):
    return call(issuer + '/protocol/openid-connect/token', urlencode(fields).encode())


status, _, demo = grant({'client_id': 'linesight-demo', 'grant_type': 'password',
    'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD']})
assert status == 200
status, _, profile = call(api + 'auth/me/', token=demo['access_token'])
assert status == 200 and profile['is_demo']
status, _, workspaces = call(api + 'workspaces/', token=demo['access_token'])
assert status == 200 and workspaces and all(w['kind'] == 'demo' for w in workspaces)
demo_workspace = workspaces[0]['id']
assert call(api + 'workspaces/create/', {'name': 'forbidden'}, demo['access_token'])[0] == 403
assert call(api + 'workspaces/2147483647/jobs/', token=demo['access_token'])[0] == 404
assert call(api + 'auth/me/', {'display_name': 'forbidden'}, demo['access_token'], 'PATCH')[0] == 403
call(issuer + '/protocol/openid-connect/logout', urlencode({'client_id': 'linesight-demo', 'refresh_token': demo['refresh_token']}).encode())
assert call(api + 'auth/me/', token=demo['access_token'])[0] == 401
assert call(api + 'auth/login/', {'username': config['LINESIGHT_DEMO_USERNAME'], 'password': 'unused'})[0] == 410

status, _, admin = call(origin + '/realms/master/protocol/openid-connect/token', urlencode({
    'client_id': 'admin-cli', 'grant_type': 'password', 'username': private['KEYCLOAK_ADMIN_USERNAME'],
    'password': private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
assert status == 200
username, password = 'acceptance-' + uuid.uuid4().hex, secrets.token_urlsafe(32)
status, headers, _ = call(origin + '/admin/realms/linesight/users', {'username': username, 'enabled': True,
    'firstName': 'Acceptance', 'lastName': 'User', 'email': username + '@example.invalid',
    'credentials': [{'type': 'password', 'value': password, 'temporary': False}]}, admin['access_token'])
assert status == 201
location = headers['Location']
subject = location.rsplit('/', 1)[1]
report = {}
try:
    verifier, state = secrets.token_urlsafe(48), secrets.token_urlsafe(24)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    redirect = 'com.linesight.app:/oauthredirect'
    class NativeRedirect(HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            if newurl.startswith('com.linesight.app:'):
                return None
            return super().redirect_request(req, fp, code, msg, headers, newurl)
    class LoginForm(HTMLParser):
        action = None
        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if tag == 'form' and attrs.get('id') == 'kc-form-login':
                self.action = attrs['action']
    browser = build_opener(HTTPCookieProcessor(CookieJar()), NativeRedirect())
    url = issuer + '/protocol/openid-connect/auth?' + urlencode({'client_id': 'linesight-android',
        'response_type': 'code', 'redirect_uri': redirect, 'scope': 'openid profile email',
        'state': state, 'code_challenge': challenge, 'code_challenge_method': 'S256'})
    with browser.open(url, timeout=20) as response:
        form = LoginForm(); form.feed(response.read().decode())
    assert form.action
    try:
        browser.open(Request(html.unescape(form.action), data=urlencode({'username': username, 'password': password}).encode()), timeout=20)
        raise AssertionError('Expected native redirect')
    except HTTPError as response:
        assert response.code == 302
        params = parse_qs(urlparse(response.headers['Location']).query)
    assert params['state'] == [state]
    status, _, tokens = grant({'grant_type': 'authorization_code', 'client_id': 'linesight-android',
        'code': params['code'][0], 'redirect_uri': redirect, 'code_verifier': verifier})
    assert status == 200
    status, _, personal = call(api + 'auth/me/', token=tokens['access_token'])
    assert status == 200 and not personal['is_demo'], status
    status, _, homes = call(api + 'workspaces/', token=tokens['access_token'])
    assert status == 200 and len(homes) == 1 and homes[0]['kind'] == 'personal'
    assert call(api + f'workspaces/{demo_workspace}/jobs/', token=tokens['access_token'])[0] == 404
    status, _, team = call(api + 'workspaces/create/', {'name': 'DEMO · SSO acceptance'}, tokens['access_token'])
    assert status == 201
    assert len(call(api + 'workspaces/', token=tokens['access_token'])[2]) == 2
    call(issuer + '/protocol/openid-connect/logout', urlencode({'client_id': 'linesight-android', 'refresh_token': tokens['refresh_token']}).encode())
    assert call(api + 'auth/me/', token=tokens['access_token'])[0] == 401
    assert grant({'grant_type': 'authorization_code', 'client_id': 'linesight-android',
        'code': params['code'][0], 'redirect_uri': redirect, 'code_verifier': verifier})[0] == 400
    report = {'demo_api_login': True, 'demo_isolated': True, 'demo_profile_immutable': True,
        'legacy_login_disabled': True, 'normal_native_pkce_login': True, 'authorization_code_single_use': True,
        'personal_home_created': True, 'same_identity_multiple_workspaces': True,
        'normal_account_cannot_access_demo': True, 'api_logout_revokes_immediately': True,
        'probe_subject': subject, 'probe_home': homes[0]['id'], 'probe_team': team['id']}
finally:
    assert call(location, token=admin['access_token'], method='DELETE')[0] == 204
report['provider_probe_deleted'] = True
Path('docs/product/linesight/acceptance/sso/api-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))

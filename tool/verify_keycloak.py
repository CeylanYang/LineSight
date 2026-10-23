"""Exercise the deployed provider without printing tokens, passwords or secrets."""
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import jwt

folder = Path('.artifact-work/sso')
config = json.loads((folder / 'demo-build.json').read_text())
private = dict(line.split('=', 1) for line in (folder / 'identity.env').read_text().splitlines() if '=' in line)
issuer = config['LINESIGHT_OIDC_ISSUER']


def post(action, data):
    try:
        with urlopen(Request(issuer + '/protocol/openid-connect/' + action,
                            data=urlencode(data).encode(), headers={'Content-Type': 'application/x-www-form-urlencoded'}), timeout=15) as response:
            body = response.read()
            return response.status, json.loads(body) if body else {}
    except HTTPError as error:
        body = json.load(error)
        return error.code, {k: body.get(k) for k in ('error', 'error_description')}


with urlopen(issuer + '/.well-known/openid-configuration', timeout=15) as response:
    discovery = json.load(response)
assert discovery['issuer'] == issuer
status, tokens = post('token', {'client_id': 'linesight-demo', 'grant_type': 'password',
    'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD'], 'scope': 'openid profile email'})
assert status == 200, (status, tokens)
key = jwt.PyJWKClient(discovery['jwks_uri']).get_signing_key_from_jwt(tokens['access_token'])
claims = jwt.decode(tokens['access_token'], key.key, algorithms=['RS256'], issuer=issuer, audience='linesight-api')
assert claims['azp'] == 'linesight-demo' and 'demo' in claims['realm_access']['roles']
introspection = {'client_id': 'linesight-api', 'client_secret': private['LINESIGHT_OIDC_CLIENT_SECRET']}
status, active = post('token/introspect', {**introspection, 'token': tokens['access_token']})
assert status == 200 and active['active'] is True
status, refreshed = post('token', {'client_id': 'linesight-demo', 'grant_type': 'refresh_token', 'refresh_token': tokens['refresh_token']})
assert status == 200 and refreshed['refresh_token'] != tokens['refresh_token']
status, _ = post('logout', {'client_id': 'linesight-demo', 'refresh_token': refreshed['refresh_token']})
assert status in (200, 204)
status, inactive = post('token/introspect', {**introspection, 'token': refreshed['access_token']})
assert status == 200 and inactive['active'] is False
status, _ = post('token', {'client_id': 'linesight-demo', 'grant_type': 'refresh_token', 'refresh_token': refreshed['refresh_token']})
assert status == 400
report = {'issuer': issuer, 'provider': 'Keycloak 26.8.1', 'discovery_https': True,
          'demo_login': True, 'rs256_signature_audience_issuer': True,
          'demo_role': True, 'introspection_active': True, 'refresh_rotated': True,
          'logout_revoked_access': True, 'logout_revoked_refresh': True}
output = Path('docs/product/linesight/acceptance/sso')
output.mkdir(parents=True, exist_ok=True)
(output/'provider-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(report, ensure_ascii=False))

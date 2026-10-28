"""Public domain/registration/authentication smoke checks; no credentials."""
import json
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener

ORIGIN = 'https://99ai.pronhubcn.com'
ISSUER = ORIGIN + '/sso/realms/linesight'


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def request(path, data=None):
    try:
        response = build_opener(NoRedirect()).open(Request(ORIGIN + path, data=data), timeout=15)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read()


for path in ('/linesight/whatif', '/linesight/whatif/api/stock-data?ticker=AAPL&date=2020-01-01'):
    status, headers, _ = request(path)
    assert status == 302
    assert urlparse(urljoin(ORIGIN, headers['Location'])).hostname == '99ai.pronhubcn.com'
assert request('/register')[0] == 410
assert request('/api/v1/auth/register/', b'username=must-not-register')[0] == 410
status, _, content = request('/sso/realms/linesight/.well-known/openid-configuration')
assert status == 200
discovery = json.loads(content)
assert discovery['issuer'] == ISSUER
for field in ('authorization_endpoint', 'token_endpoint', 'end_session_endpoint', 'jwks_uri'):
    assert discovery[field].startswith(ISSUER + '/')
print(json.dumps({'domain_discovery': True, 'stock_page_requires_login': True,
                  'stock_api_requires_login': True, 'public_registration_closed': True}))

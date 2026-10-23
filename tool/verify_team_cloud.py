"""Read-only verification of server-authenticated member identity in the isolated demo team."""
import base64
import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parents[1]
config = json.loads((root/'.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
issuer = config['LINESIGHT_OIDC_ISSUER']
api = config['LINESIGHT_API_BASE_URL']
with urlopen(Request(issuer+'/protocol/openid-connect/token', data=urlencode({
    'client_id': 'linesight-demo', 'grant_type': 'password',
    'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD'],
}).encode()), timeout=25) as response:
    session = json.load(response)

def get(path):
    with urlopen(Request(api+path, headers={'Authorization': 'Bearer '+session['access_token']}), timeout=25) as response:
        assert response.status == 200
        return json.load(response)

try:
    me = get('auth/me/')
    teams = get('workspaces/')
    team = next(row for row in teams if row['id'] == me['home_workspace_id'])
    assert me['is_demo'] and team['kind'] == 'demo'
    rows = get('workspaces/{}/members/'.format(team['id']))
    claims = session['access_token'].split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(claims+'='*((-len(claims))%4)))
    bridge = 'oidc_'+hashlib.sha256((claims['iss']+'\0'+claims['sub']).encode()).hexdigest()[:40]
    assert all(type(row['is_self']) is bool for row in rows)
    selected = [row for row in rows if row['is_self']]
    assert len(selected) == 1 and selected[0]['username'] == bridge
    assert all(row['is_self'] == (row['username'] == bridge) for row in rows)
    report = {'passed': True, 'https_reads': 3, 'demo_workspace_only': True,
              'exactly_one_authenticated_self': True, 'independent_issuer_subject_bridge_match': True,
              'all_members_have_boolean_self_flag': True, 'business_writes': 0}
    folder = root/'docs/product/linesight/acceptance/team-batch'
    (folder/'live-team.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))
finally:
    with urlopen(Request(issuer+'/protocol/openid-connect/logout', data=urlencode({
        'client_id': 'linesight-demo', 'refresh_token': session['refresh_token'],
    }).encode()), timeout=25) as response:
        assert response.status == 204

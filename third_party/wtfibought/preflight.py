"""Read-only deployment checks with no credentials in the receipt."""
from pathlib import Path
import hashlib
import json
import subprocess
import urllib.error
import urllib.request

report = {'services': {}, 'checks': {}}
for name in ['feed', 'sim', 'agent', 'redis']:
    result = subprocess.run(['systemctl', 'is-active', '--quiet', 'linesight-wiib-' + name])
    assert result.returncode == 0, 'Service is not active: ' + name
    report['services'][name] = 'active'
for path, method, header, expected in [
        ('/api/auth/login/local', 'POST', {}, 410),
        ('/api/auth/register', 'POST', {}, 410),
        ('/api/auth/linesight', 'POST', {}, 401),
        ('/api/auth/linesight', 'POST', {'X-Forwarded-Access-Token':'e30.e30.e30'}, 401)]:
    request = urllib.request.Request('http://127.0.0.1:18080' + path,
                                    data=b'{}', headers=header, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=10)
        status = response.status
        response.close()
    except urllib.error.HTTPError as error:
        status = error.code
    assert status == expected, 'Authentication boundary failed for ' + path
report['checks']['local_registration_and_admin_closed'] = True
report['checks']['missing_and_unsigned_jwt_denied'] = True
for path in ['/linesight/whatif/', '/linesight/whatif/logo.png',
             '/linesight/whatif/manifest.webmanifest', '/linesight/whatif/portfolio']:
    request = urllib.request.Request('http://127.0.0.1:3009' + path,
                                    headers={'Host':'99ai.pronhubcn.com'})
    with urllib.request.urlopen(request, timeout=10) as response:
        assert response.status == 200
        content = response.read()
        assert len(content) > 100, 'Empty upstream response for public Host'
        if path.endswith('/') or path.endswith('/portfolio'):
            assert b'/linesight/whatif/assets/' in content
report['checks']['mounted_static_and_deep_links'] = True
for url in ['https://99ai.pronhubcn.com/api/v1/app-config/',
            'https://99ai.pronhubcn.com/linesight/']:
    with urllib.request.urlopen(url, timeout=15) as response:
        assert response.status == 200
report['checks']['existing_portal_and_runtime_config_available'] = True
root = Path('/opt/linesight-extras/wtfibought-144/source')
report['jars'] = {name:hashlib.sha256((root / ('wiib-' + name) / 'target' /
    ('wiib-' + name + '-0.0.1-SNAPSHOT.jar')).read_bytes()).hexdigest()
    for name in ['feed','sim','agent']}
Path('/var/tmp/linesight-wtf144/preflight.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))

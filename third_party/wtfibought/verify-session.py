"""Local authenticated dependency checks; native session arrives on stdin only."""
import json
import sys
import urllib.request

token = json.load(sys.stdin)['token']
report = {}
for name, port in [('feed', 18081), ('sim', 18080), ('agent', 18082)]:
    request = urllib.request.Request(f'http://127.0.0.1:{port}/actuator/health',
                                     headers={'satoken': token})
    with urllib.request.urlopen(request, timeout=10) as response:
        body = json.load(response)
    assert body.get('status') == 'UP', name + ' dependency health is not UP'
    report[name] = 'UP'
print(json.dumps(report))

"""Read existing demo evidence for the photo viewer; no business writes."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid

root = Path(__file__).resolve().parents[1]
config = json.loads((root/'.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
issuer = config['LINESIGHT_OIDC_ISSUER']
api = config['LINESIGHT_API_BASE_URL']
with urlopen(Request(issuer+'/protocol/openid-connect/token', data=urlencode({
    'client_id': 'linesight-demo', 'grant_type': 'password',
    'username': config['LINESIGHT_DEMO_USERNAME'], 'password': config['LINESIGHT_DEMO_PASSWORD'],
}).encode()), timeout=25) as response:
    session = json.load(response)

def call(method, path, body=None):
    headers = {'Authorization': 'Bearer '+session['access_token'], 'Content-Type': 'application/json'}
    with urlopen(Request(api+path, data=None if body is None else json.dumps(body).encode(),
                         headers=headers, method=method), timeout=25) as response:
        return response.status, json.load(response)

def snapshot(rows):
    return {row['id']: hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest() for row in rows}

try:
    _, me = call('GET', 'auth/me/')
    _, teams = call('GET', 'workspaces/')
    team = next(row for row in teams if row['id'] == me['home_workspace_id'])
    assert me['is_demo'] and team['kind'] == 'demo'
    base = f"workspaces/{team['id']}/jobs/"
    job_id = '608e72c3-7591-45d7-a86d-8ddfc7d8abbd'
    _, job = call('GET', base+job_id+'/')
    before = hashlib.sha256(json.dumps(job, sort_keys=True).encode()).hexdigest()
    photos = job['evidence']
    assert len(photos) >= 2
    chosen = [next(photo for photo in photos if photo['stage'] == stage) for stage in ['before', 'after']]
    folder = root/'docs/product/linesight/acceptance/evidence-batch'
    folder.mkdir(parents=True, exist_ok=True)
    files = []
    for photo in chosen:
        for mode in ['original', 'preview']:
            path = base+job_id+f"/evidence/{photo['id']}/{mode}/"
            with urlopen(Request(api+path, headers={'Authorization': 'Bearer '+session['access_token']}), timeout=30) as response:
                data = response.read()
                assert response.status == 200 and response.headers['Content-Type'].startswith('image/')
            from PIL import Image
            import io
            with Image.open(io.BytesIO(data)) as image:
                image.verify()
            name = f"photo-{photo['id']}-{'source' if mode == 'original' else 'processed'}.png"
            (folder/name).write_bytes(data)
            files.append({'photo_id': photo['id'], 'mode': mode, 'file': name, 'sha256': hashlib.sha256(data).hexdigest()})
    _, after = call('GET', base+job_id+'/')
    assert before == hashlib.sha256(json.dumps(after, sort_keys=True).encode()).hexdigest()
    fixture = {'workspace_id': team['id'], 'job_id': job_id, 'photos': chosen, 'files': files,
        'source': 'Existing cloud demo evidence originally generated from reference images; no physical camera capture.'}
    (folder/'viewer-fixture.json').write_text(json.dumps(fixture, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (folder/'live-evidence.json').write_text(json.dumps({'demo_only': True, 'business_writes': 0,
        'original_and_contour_downloads': 4, 'task_unchanged': True, 'files': files}, indent=2)+'\n')
    print(json.dumps({'passed': True, 'downloads': 4, 'business_writes': 0}))
finally:
    with urlopen(Request(issuer+'/protocol/openid-connect/logout', data=urlencode({
        'client_id': 'linesight-demo', 'refresh_token': session['refresh_token'],
    }).encode()), timeout=25) as response:
        assert response.status == 204

"""Sign and publish public document/config revisions using the existing OTA key.

No credentials belong in this file or the public configuration. Image bytes are
immutable, SHA-256 addressed, and uploaded before the signed configuration.
"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.request

from ota_release import ROOT, PRIVATE, signed


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def activate(stage):
    stage = Path(stage)
    envelope = (stage / 'app-config.json').read_bytes()
    revision = json.loads(base64.b64decode(json.loads(envelope)['payload']))['revision']
    destination = Path('/var/lib/linesight/runtime/app-config.json')
    if destination.exists():
        previous = json.loads(base64.b64decode(json.loads(destination.read_bytes())['payload']))
        assert revision > previous['revision'], 'Revision must increase'
    source = Path('/opt/linesight/backend/collaboration')
    caddy = Path('/etc/caddy/Caddyfile')
    files = [source / 'ota.py', source / 'urls.py', caddy, destination]
    old = {str(path): path.read_bytes() if path.exists() else None for path in files}
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/backups/linesight/runtime') / stamp
    backup.mkdir(parents=True, mode=0o700)
    for number, path in enumerate(files):
        if old[str(path)] is not None:
            (backup / str(number)).write_bytes(old[str(path)])
    (backup / 'paths.json').write_text(json.dumps([str(path) for path in files]))
    content = Path('/srv/linesight/content')
    content.mkdir(parents=True, exist_ok=True)
    for image in (stage / 'content').glob('*.png'):
        assert image.name == digest(image) + '.png'
        target = content / image.name
        if target.exists():
            assert digest(target) == image.stem
        else:
            shutil.copyfile(image, target)
            target.chmod(0o644)
    try:
        ota = (source / 'ota.py').read_text()
        if 'def runtime_config(' not in ota:
            ota += '\n\n' + (stage / 'runtime-route.py.txt').read_text()
            (source / 'ota.py').write_text(ota)
        urls = (source / 'urls.py').read_text()
        if "path('app-config/', ota.runtime_config)" not in urls:
            assert 'ota' in urls and 'urlpatterns = [' in urls
            urls = urls.replace('urlpatterns = [', "urlpatterns = [\n    path('app-config/', ota.runtime_config),", 1)
            (source / 'urls.py').write_text(urls)
        config = caddy.read_text()
        if '# LINESIGHT PUBLIC CONTENT' not in config:
            marker = '\thandle /sso/* {'
            assert config.count(marker) == 1
            block = '\t# LINESIGHT PUBLIC CONTENT\n\thandle_path /content/* {\n\t\troot * /srv/linesight/content\n\t\theader Cache-Control "public, max-age=31536000, immutable"\n\t\tfile_server\n\t}\n'
            config = config.replace(marker, block + marker, 1)
            domain = '    respond /health "ready" 200'
            assert domain in config
            block = '    handle_path /content/* {\n        root * /srv/linesight/content\n        header Cache-Control "public, max-age=31536000, immutable"\n        file_server\n    }\n'
            config = config.replace(domain, block + domain, 1)
            caddy.write_text(config)
        subprocess.run(['/usr/local/bin/caddy', 'validate', '--config', str(caddy)], check=True, capture_output=True)
        subprocess.run(['systemctl', 'restart', 'linesight'], check=True)
        # Confirm the read route exists before making a new signed revision live.
        for attempt in range(20):
            try:
                request = urllib.request.Request('http://127.0.0.1:8000/api/v1/app-config/', headers={'Host': '47.111.81.94'})
                with urllib.request.urlopen(request, timeout=4) as response:
                    assert response.status in (200, 204)
                break
            except Exception:
                if attempt == 19:
                    raise
                time.sleep(.5)
        subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        pending = destination.with_suffix('.pending')
        pending.write_bytes(envelope)
        pending.chmod(0o644)
        os.replace(pending, destination)
        with urllib.request.urlopen(request, timeout=10) as response:
            assert response.read() == envelope
    except BaseException:
        for path in files:
            previous = old[str(path)]
            if previous is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(previous)
        subprocess.run(['systemctl', 'restart', 'linesight'], check=False)
        subprocess.run(['systemctl', 'reload', 'caddy'], check=False)
        raise
    print(json.dumps({'revision': revision, 'config_sha256': hashlib.sha256(envelope).hexdigest(),
                      'backup': str(backup), 'identity_or_database_changes': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'deploy/runtime/app-config.json')
    parser.add_argument('--revision', type=int, required=True)
    parser.add_argument('--days', type=int, default=180)
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    assert args.revision > 1 and 1 <= args.days <= 365
    # Refuse to publish under a different key than the installed trust anchor.
    from cryptography.hazmat.primitives import serialization
    key = serialization.load_pem_private_key(PRIVATE.read_bytes(), password=None)
    public = base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
    assert public in (ROOT / 'lib/ota_key.dart').read_text(), 'Signing key differs from app trust anchor'
    data = json.loads(args.config.read_text(encoding='utf-8'))
    data['revision'] = args.revision
    data['expires'] = (datetime.now(timezone.utc) + timedelta(days=args.days)).isoformat()
    stage = ROOT / '.artifact-work/runtime' / str(args.revision)
    (stage / 'content').mkdir(parents=True, exist_ok=True)
    for reference, filename in [(row, row['asset']) for row in data['documents']] + [(data['report'], 'linesight_embossed_seal.png')]:
        image = ROOT / 'assets/templates' / filename
        assert image.resolve().parent == (ROOT / 'assets/templates').resolve()
        name = digest(image) + '.png'
        shutil.copyfile(image, stage / 'content' / name)
        reference.update(image_url='/content/' + name, sha256=digest(image))
    (stage / 'app-config.json').write_text(json.dumps(signed(data), separators=(',', ':')), encoding='utf-8')
    route = (ROOT / 'backend/collaboration/ota.py').read_text()
    route = route[route.index('@require_GET\ndef runtime_config'):route.index('@require_GET\ndef artifact')]
    (stage / 'runtime-route.py.txt').write_text(route)
    (stage / 'activate.py').write_text('from pathlib import Path\n' +
      'import argparse,base64,hashlib,json,os,shutil,subprocess,time,urllib.request\nfrom datetime import datetime,timezone\n' +
      __import__('inspect').getsource(digest) + '\n' + __import__('inspect').getsource(activate) + '\nactivate(__import__("sys").argv[1])\n')
    if not args.publish:
        print(json.dumps({'prepared': str(stage), 'revision': args.revision}))
        return
    options = ['-o', 'BatchMode=yes', '-i', str(Path.home() / '.ssh/linesight-ali-baot.pem')]
    host = 'root@47.111.81.94'
    remote = '/var/tmp/linesight-runtime-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    subprocess.run(['ssh', *options, host, 'install -d -m 700 ' + remote], check=True)
    subprocess.run(['scp', *options, '-r', str(stage) + '/.', host + ':' + remote + '/'], check=True)
    result = subprocess.run(['ssh', *options, host, '/opt/linesight/venv/bin/python ' + remote + '/activate.py ' + remote], capture_output=True, text=True, check=True)
    print(result.stdout.strip())
    if args.evidence:
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(result.stdout, encoding='utf-8')


if __name__ == '__main__':
    main()

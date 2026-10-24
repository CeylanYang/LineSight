"""Verify the public HTTPS config signature and every pinned image from this host."""
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://47.111.81.94'


def fetch(path):
    return subprocess.check_output(['curl.exe', '--noproxy', '*', '--fail', '--silent', '--show-error',
                                    '--max-time', '60', BASE + path])


def main():
    envelope_bytes = fetch('/api/v1/app-config/')
    envelope = json.loads(envelope_bytes)
    public = re.search(r"otaPublicKey = '([^']+)'", (ROOT / 'lib/ota_key.dart').read_text())[1]
    payload = base64.b64decode(envelope['payload'])
    Ed25519PublicKey.from_public_bytes(base64.b64decode(public)).verify(base64.b64decode(envelope['signature']), payload)
    data = json.loads(payload)
    images = []
    for reference in data['documents'] + [data['report']]:
        path = reference['image_url']
        assert re.fullmatch(r'/content/[a-f0-9]{64}\.png', path)
        raw = fetch(path)
        assert hashlib.sha256(raw).hexdigest() == reference['sha256'] and raw.startswith(b'\x89PNG\r\n\x1a\n')
        images.append({'url': BASE + path, 'sha256': reference['sha256'], 'bytes': len(raw)})
    result = {'revision': data['revision'], 'signature_verified': True, 'public_https': True,
              'config_sha256': hashlib.sha256(envelope_bytes).hexdigest(), 'images': images,
              'vantage': 'local Windows host via curl, public DNS and trusted HTTPS'}
    folder = ROOT / 'docs/product/linesight/acceptance/cloud82-batch'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'runtime-public-verification.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Verified public signed config revision', data['revision'], 'and', len(images), 'pinned images')


if __name__ == '__main__':
    main()

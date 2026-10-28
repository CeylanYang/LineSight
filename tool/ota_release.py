"""Signed self-hosted Android OTA publishing (no public write endpoint).

init-key: private key stays in the protected user vault; back it up securely.
base: save the delivered APK's immutable native/assets fingerprint.
pack: refuse native/assets/engine drift, extract each ABI's libapp.so and sign.
rollback: publish a higher-sequence signed command reverting to the base APK.
upload: scp immutable payloads first, atomically replace manifest last.
"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = Path(os.environ.get('LINESIGHT_OTA_SIGNING_KEY', str(Path.home() / 'LineSight-private/ota-signing-v2/patch-signing.pem')))
ABIS = ('arm64-v8a', 'x86_64')


def apk_fingerprint(apk):
    with zipfile.ZipFile(apk) as z:
        # Only Dart AOT may change. Bind native code, resources, assets and
        # manifest exactly. Engine matching is enforced by libflutter.so too.
        return {n: hashlib.sha256(z.read(n)).hexdigest() for n in sorted(z.namelist())
                if not n.endswith('/') and not n.startswith('META-INF/')
                and not re.fullmatch(r'lib/[^/]+/libapp\.so', n)}


def signing_key():
    if not PRIVATE.is_file():
        raise SystemExit('Original OTA signing key is missing. Restore its protected backup; do not generate a replacement key for existing APKs.')
    try:
        key = serialization.load_pem_private_key(PRIVATE.read_bytes(), password=None)
        if not isinstance(key, Ed25519PrivateKey):
            raise ValueError('Wrong key type')
        anchor = re.search(r"otaPublicKey = '([^']+)'", (ROOT / 'lib/ota_key.dart').read_text(encoding='utf-8'))
        if anchor is None:
            raise ValueError('Missing trust anchor')
        expected = base64.b64decode(anchor[1], validate=True)
        actual = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        if expected != actual:
            raise ValueError('Trust anchor mismatch')
    except (OSError, ValueError, TypeError):
        raise SystemExit('OTA signing key is unreadable or does not match the app trust anchor. Restore the original key; no patch was signed.') from None
    return key


def signed(data, key=None):
    key = signing_key() if key is None else key
    payload = json.dumps(data, sort_keys=True, separators=(',', ':')).encode()
    return {'payload': base64.b64encode(payload).decode(),
            'signature': base64.b64encode(key.sign(payload)).decode()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['init-key', 'base', 'pack', 'rollback', 'upload'])
    p.add_argument('--apk', type=Path)
    p.add_argument('--track', choices=['preview', 'production'], default='preview')
    p.add_argument('--base', type=int, default=8078)
    p.add_argument('--sequence', type=int)
    p.add_argument('--days', type=int, default=90)
    p.add_argument('--ssh-key', type=Path, default=Path(r'C:\Users\29668\.ssh\linesight-ali-baot.pem'))
    args = p.parse_args()
    if args.command == 'init-key':
        PRIVATE.parent.mkdir(parents=True, exist_ok=True)
        if not PRIVATE.exists() and (ROOT / 'lib/ota_key.dart').exists():
            raise SystemExit('Restore the existing private key from backup. Key rotation requires a new base APK.')
        if not PRIVATE.exists():
            key = Ed25519PrivateKey.generate()
            PRIVATE.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        key = serialization.load_pem_private_key(PRIVATE.read_bytes(), password=None)
        public = base64.b64encode(key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        if (ROOT / 'lib/ota_key.dart').exists() and public not in (ROOT / 'lib/ota_key.dart').read_text():
            raise SystemExit('Private key differs from the committed trust anchor. Refusing silent key rotation.')
        (ROOT / 'lib/ota_key.dart').write_text(
            '// OTA trust anchor. Private key is never bundled in the app.\n'
            f"const otaPublicKey = '{public}';\n", encoding='utf8')
        print('OTA key ready; private key remains outside source control.')
        return
    folder = ROOT / '.artifact-work/ota' / args.track / str(args.base)
    folder.mkdir(parents=True, exist_ok=True)
    record = folder / 'base.json'
    if args.command == 'base':
        fingerprint = apk_fingerprint(args.apk)
        if record.exists() and json.loads(record.read_text()) != fingerprint:
            raise SystemExit('Base already frozen. Use a new Android versionCode.')
        record.write_text(json.dumps(fingerprint, indent=2) + '\n')
        print('Frozen native/assets/engine fingerprint:', len(fingerprint), 'entries')
        return
    if args.command in ('pack', 'rollback'):
        key = signing_key()
        assert args.sequence and args.sequence > 0, 'A positive increasing sequence is required'
        if args.command == 'pack':
            assert apk_fingerprint(args.apk) == json.loads(record.read_text()), \
                'Native, assets, engine or APK metadata changed: distribute a new base APK'
        for abi in ABIS:
            target = folder / abi
            target.mkdir(exist_ok=True)
            manifest = target / 'manifest.json'
            if manifest.exists():
                old = json.loads(base64.b64decode(json.loads(manifest.read_text())['payload']))
                assert args.sequence > old['sequence'], 'Sequence must increase (including rollback)'
            data = {'schema': 1, 'track': args.track, 'base': args.base, 'abi': abi,
                    'sequence': args.sequence, 'action': 'rollback' if args.command == 'rollback' else 'patch',
                    'expires': (datetime.now(timezone.utc) + timedelta(days=args.days)).isoformat()}
            if args.command == 'pack':
                with zipfile.ZipFile(args.apk) as z:
                    payload = z.read(f'lib/{abi}/libapp.so')
                digest = hashlib.sha256(payload).hexdigest()
                (target / (digest + '.so')).write_bytes(payload)
                data.update(sha256=digest, size=len(payload))
            manifest.write_text(json.dumps(signed(data, key), separators=(',', ':')) + '\n')
        print('Prepared signed', args.command, 'sequence', args.sequence, 'for both ABIs')
        return
    ssh = ['ssh', '-i', str(args.ssh_key), '-o', 'BatchMode=yes', 'root@47.111.81.94']
    for abi in ABIS:
        local = folder / abi
        remote = f'/var/lib/linesight/ota/{args.track}/{args.base}/{abi}'
        subprocess.run(ssh + [f'install -d -m 755 {remote}'], check=True, timeout=25)
        outer = json.loads((local / 'manifest.json').read_text())
        data = json.loads(base64.b64decode(outer['payload']))
        admission = f"from pathlib import Path;import json,base64;p=Path('{remote}/manifest.json');old=json.loads(p.read_text()) if p.exists() else None;assert old is None or json.loads(base64.b64decode(old['payload']))['sequence'] < {data['sequence']} or old == {outer!r}, 'Remote sequence would go backwards'"
        subprocess.run(ssh + ['python3 -'], input=admission, text=True, check=True, timeout=25)
        for name in ([data['sha256'] + '.so'] if data['action'] == 'patch' else []) + ['manifest.json']:
            dest = name + '.uploading'
            subprocess.run(['scp', '-i', str(args.ssh_key), '-o', 'BatchMode=yes',
                str(local / name), f'root@47.111.81.94:{remote}/{dest}'], check=True, timeout=120)
            # Fail before activating metadata if transfer is incomplete.
            digest = hashlib.sha256((local / name).read_bytes()).hexdigest()
            code = f"from pathlib import Path;import hashlib,os;p=Path('{remote}/{dest}');assert hashlib.sha256(p.read_bytes()).hexdigest()=='{digest}';os.chmod(p,0o644);os.replace(p,Path('{remote}/{name}'))"
            subprocess.run(ssh + ['python3 -'], input=code, text=True, check=True, timeout=25)
    print('Published atomically:', args.track, args.base)


if __name__ == '__main__':
    main()

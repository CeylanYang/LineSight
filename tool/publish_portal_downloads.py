"""Publish reviewed portal files and receipt-verified APKs, with rollback backups."""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile


LEGACY = 'LineSight-1.1.20-arm64-v8a.apk'
REDIRECT = '/linesight/downloads/LineSight-legacy-upgrade.apk'


def digest(path):
    with Path(path).open('rb') as stream:
        value = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def activate(stage):
    assert os.geteuid() == 0
    stage = Path(stage)
    manifest = json.loads((stage / 'manifest.json').read_text())
    root = Path('/srv/boji-portal')
    config = Path('/etc/caddy/Caddyfile')
    old_config = config.read_bytes()
    for name, expected in manifest['previous'].items():
        assert digest(root / name) == expected, 'Live portal changed: ' + name
    for name, expected in manifest['files'].items():
        assert digest(stage / name) == expected, 'Staged hash mismatch: ' + name
        target = root / name
        if name.endswith('.apk') and target.exists():
            assert digest(target) == expected, 'Immutable APK collision'
    aliases = manifest['aliases']
    for name in aliases:
        target = root / name
        assert not target.exists() or target.is_symlink(), 'Alias is a regular file'
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/backups/linesight/portal-downloads') / stamp
    backup.mkdir(parents=True, mode=0o700)
    (backup / 'Caddyfile').write_bytes(old_config)
    changed = {}
    for name in manifest['files']:
        target = root / name
        changed[name] = target.exists()
        if target.exists():
            saved = backup / name
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(target), str(saved))
    old_aliases = {name: os.readlink(str(root / name)) if (root / name).is_symlink()
                   else None for name in aliases}
    (backup / 'aliases.json').write_text(json.dumps(old_aliases))
    updated = old_config.decode()
    ip_marker = '\t# BEGIN BOJI PORTAL\n'
    domain_marker = '\n99ai.pronhubcn.com {\n'
    assert updated.count(ip_marker) == 1 and updated.count(domain_marker) == 1
    ip_rules = ''.join('\tredir /' + prefix + '/downloads/' + LEGACY + ' ' + REDIRECT + ' 302\n'
                       for prefix in ('linesight', 'boji'))
    domain_rules = ''.join('    redir ' + prefix + '/downloads/' + LEGACY + ' ' + REDIRECT + ' 302\n'
                           for prefix in ('', '/linesight'))
    if ip_rules not in updated:
        updated = updated.replace(ip_marker, ip_marker + ip_rules)
    if domain_rules not in updated:
        updated = updated.replace(domain_marker, domain_marker + domain_rules)
    try:
        for name in manifest['files']:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            pending = target.with_name(target.name + '.pending')
            shutil.copyfile(str(stage / name), str(pending))
            pending.chmod(0o644)
            os.replace(str(pending), str(target))
        for name, link in aliases.items():
            target = root / name
            pending = target.with_name(target.name + '.pending')
            pending.symlink_to(link)
            os.replace(str(pending), str(target))
        config.write_text(updated)
        subprocess.run(['/usr/local/bin/caddy', 'validate', '--config', str(config)],
                       check=True, capture_output=True)
        subprocess.run(['systemctl', 'reload', 'caddy'], check=True, capture_output=True)
    except BaseException:
        config.write_bytes(old_config)
        for name, existed in changed.items():
            target = root / name
            if existed:
                shutil.copyfile(str(backup / name), str(target))
            elif target.exists():
                target.unlink()
        for name, old in old_aliases.items():
            target = root / name
            if target.is_symlink():
                target.unlink()
            if old is not None:
                target.symlink_to(old)
        subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
        raise
    result = {'backup': str(backup), 'files': manifest['files'],
              'aliases': aliases, 'legacy_download_redirect': REDIRECT,
              'legacy_apk_preserved': (root / 'downloads' / LEGACY).is_file(),
              'caddy_validated_reloaded': True}
    (backup / 'receipt.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


def publish(args):
    repo = Path(__file__).resolve().parents[1]
    delivery = Path(args.delivery)
    receipt = json.loads((delivery / 'delivery.json').read_text(encoding='utf-8-sig'))
    version = receipt['version'].split('+')[0]
    revision = receipt['content_revision']
    assert re.fullmatch(r'\d+\.\d+\.\d+', version) and isinstance(revision, int) and revision >= 0
    release_name = 'LineSight-' + version + '-content' + str(revision)
    identity = str(Path.home() / '.ssh' / 'linesight-ali-baot.pem')
    host = 'root@47.111.81.94'
    options = ['-o', 'BatchMode=yes', '-i', identity]
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    remote_stage = '/var/tmp/linesight-portal-' + stamp
    with tempfile.TemporaryDirectory(prefix='linesight-portal-') as temporary:
        stage = Path(temporary)
        sources = {'index.html': repo / 'deploy/portal/index.html',
                   'app.js': repo / 'deploy/portal/app.js',
                   'assets/product/screen-12-content4.webp': repo / 'deploy/portal/screen-12-content4.webp'}
        for code in ['WI-QC-014', 'CL-PR-006']:
            sources['downloads/LineSight-' + code + '.pdf'] = delivery / ('LineSight-' + code + '.pdf')
        for artifact in receipt['artifacts']:
            source = delivery / artifact['file']
            assert digest(source) == artifact['sha256'] and source.stat().st_size == artifact['bytes']
            track = 'production' if '-production.apk' in artifact['file'] else 'preview'
            sources['downloads/' + release_name + '-' + track + '.apk'] = source
        manifest = {'files': {}, 'previous': {
            'index.html': '9d505b536e4123189cb08808c05d0ff508aafee7530a5489ec070c5a6bb62cf8',
            'app.js': 'defd82ffcd4c4cf5fea3c46d0f871dd10e0a588b2b84177842a8497699ee5665'}}
        if args.previous_deployment:
            previous = json.loads(Path(args.previous_deployment).read_text(encoding='utf-8'))
            manifest['previous'] = {name: previous['files'][name] for name in ['index.html', 'app.js']}
        manifest['aliases'] = {
            'downloads/LineSight-Android.apk': release_name + '-production.apk',
            'downloads/LineSight-legacy-upgrade.apk': release_name + '-preview.apk',
        }
        for name, source in sources.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(source), str(target))
            manifest['files'][name] = digest(target)
        (stage / 'manifest.json').write_text(json.dumps(manifest))
        shutil.copyfile(__file__, str(stage / 'publish.py'))
        subprocess.run(['ssh', *options, host, 'install -d -m 700 ' + remote_stage], check=True)
        subprocess.run(['scp', *options, '-r', str(stage) + '/.', host + ':' + remote_stage + '/'], check=True)
        result = subprocess.run(['ssh', *options, host,
            '/opt/linesight/venv/bin/python ' + remote_stage + '/publish.py --remote-stage ' + remote_stage],
            capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        print(result.stdout)
        if args.evidence:
            evidence = Path(args.evidence)
            evidence.parent.mkdir(parents=True, exist_ok=True)
            evidence.write_text(result.stdout, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remote-stage')
    parser.add_argument('--delivery')
    parser.add_argument('--evidence')
    parser.add_argument('--previous-deployment', help='Previous receipt for live-file concurrent-change checks')
    args = parser.parse_args()
    if args.remote_stage:
        activate(args.remote_stage)
    else:
        assert args.delivery, '--delivery required'
        publish(args)

"""Publish reviewed mobile CSS and HTML with concurrent-change checks and rollback."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def activate(stage):
    stage = Path(stage)
    root = Path('/srv/boji-portal')
    manifest = json.loads((stage / 'manifest.json').read_text())
    assert set(manifest['files']) == {'index.html', 'mobile.css'}
    assert digest(root / 'index.html') == manifest['previous_index'], 'Live index changed'
    assert not (root / 'mobile.css').exists(), 'Mobile CSS already deployed'
    for name, expected in manifest['files'].items():
        assert digest(stage / name) == expected
    backup = Path('/var/backups/linesight/portal-mobile') / stage.name
    backup.mkdir(parents=True, mode=0o700)
    shutil.copy2(root / 'index.html', backup / 'index.html')
    try:
        # Publish stylesheet first so the new HTML can never reference a missing file.
        for name in ['mobile.css', 'index.html']:
            target = root / name
            pending = target.with_name(name + '.mobile-pending')
            shutil.copyfile(stage / name, pending)
            pending.chmod(0o644)
            os.replace(pending, target)
        for name, expected in manifest['files'].items():
            assert digest(root / name) == expected
    except BaseException:
        shutil.copyfile(backup / 'index.html', root / 'index.html')
        # Leave the unreferenced additive stylesheet for investigation.
        raise
    receipt = {'backup': str(backup), 'files': manifest['files'],
               'previous_index': manifest['previous_index'], 'downloads_modified': False,
               'auth_or_server_config_modified': False}
    (backup / 'receipt.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt))

def publish():
    root = Path(__file__).resolve().parents[1]
    candidate = root / 'docs/product/linesight/acceptance/portal71-batch/candidate/validation.json'
    checks = json.loads(candidate.read_text(encoding='utf-8'))
    assert [r['width'] for r in checks] == [320, 390, 700, 1440]
    options = ['-o', 'BatchMode=yes', '-i', str(Path.home() / '.ssh/linesight-ali-baot.pem')]
    host = 'root@47.111.81.94'
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    remote = '/var/tmp/linesight-mobile-' + stamp
    with tempfile.TemporaryDirectory(prefix='linesight-mobile-') as tmp:
        stage = Path(tmp)
        previous = json.loads((root / 'docs/product/linesight/acceptance/ota67-batch/portal-deployment.json').read_text())
        manifest = {'files': {}, 'previous_index': previous['files']['index.html']}
        for name in ['index.html', 'mobile.css']:
            shutil.copyfile(root / 'deploy/portal' / name, stage / name)
            manifest['files'][name] = digest(stage / name)
        (stage / 'manifest.json').write_text(json.dumps(manifest))
        shutil.copyfile(__file__, stage / 'publish.py')
        subprocess.run(['ssh', *options, host, 'install -d -m 700 ' + remote], check=True)
        subprocess.run(['scp', *options, '-r', str(stage) + '/.', host + ':' + remote + '/'], check=True)
        result = subprocess.run(['ssh', *options, host,
            '/opt/linesight/venv/bin/python ' + remote + '/publish.py --activate ' + remote],
            capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        receipt = json.loads(result.stdout)
        evidence = candidate.parent.parent / 'deployment.json'
        evidence.write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--activate')
    args = parser.parse_args()
    activate(args.activate) if args.activate else publish()

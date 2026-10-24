"""Package the accepted local handoff; do not publish or include credentials."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = Path('D:/ENT207/deliverables/LineSight-1.1.55-closeout')
DEST.mkdir(parents=True, exist_ok=True)
artifacts = []
for track, expected in [
    ('production', '546e621026c6e0196e7c50e9ec2a74708c6dec68924ea868017a901ecb432b4d'),
    ('preview', 'cc3ae4fb45740a564dafba91aee8722d84f51d9be8f4b16ae8fbadfa762d36ae'),
]:
    name = f'LineSight-1.1.55-8079-{track}.apk'
    source = ROOT / '.artifact-work/release' / name
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
    target = DEST / name
    if target.exists():
        assert hashlib.sha256(target.read_bytes()).hexdigest() == expected
    else:
        shutil.copy2(source, target)
    assert hashlib.sha256(target.read_bytes()).hexdigest() == expected
    artifacts.append({'file': name, 'track': track, 'sha256': expected, 'bytes': target.stat().st_size})

docs = ROOT / 'docs/product/linesight'
for source, name in [
    (docs / 'CLOSEOUT_20261024.md', '开发收尾与功能清单.md'),
    (docs / 'DELIVERY_STATUS_20261024.md', '交付状态.md'),
    (docs / 'OTA.md', 'OTA说明.md'),
    (docs / 'acceptance/upgrade75-batch/upgrade.json', 'production-upgrade.json'),
    (docs / 'acceptance/upgrade77-batch/upgrade.json', 'preview-upgrade.json'),
    (docs / 'acceptance/roles78-batch/validation.json', 'four-role-navigation.json'),
    (docs / 'acceptance/roles78-batch/cleanup.json', 'temporary-account-cleanup.json'),
    (docs / 'acceptance/ota79-batch/validation.json', 'dart-ota-rollback.json'),
]:
    shutil.copy2(source, DEST / name)

receipt = {'version': '1.1.55+8079', 'content_revision': 5,
           'status': 'development_closeout_local_acceptance_handoff',
           'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'artifacts': artifacts, 'website_published_version': '1.1.54+8078',
           'public_release_changed': False, 'public_ota_changed': False,
           'customer_credentials_included': False, 'hardware_acceptance_complete': False,
           'scope_and_pending': '开发收尾与功能清单.md'}
(DEST / 'delivery.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'delivery': str(DEST), 'version': receipt['version'],
                  'verified_apks': len(artifacts), 'credentials_included': False}, ensure_ascii=False))

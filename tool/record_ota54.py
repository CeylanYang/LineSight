"""Verify OTA acceptance evidence and record a credential-free release receipt."""
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess

import requests
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

root = Path(__file__).resolve().parents[1]
folder = root / 'docs/product/linesight/acceptance/ota54-batch'
assert '+453: All tests passed!' in (root / '.artifact-work/ota-full-final.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root / '.artifact-work/ota-analyze.log').read_text(encoding='utf-8-sig')
backend = (root / '.artifact-work/ota-backend.log').read_text(encoding='utf-8-sig')
assert 'Ran 97 tests' in backend and '\nOK\n' in backend
for name, expected in [('322-ota-base-emulator', '内容版本 0'),
                       ('323-ota-ready-emulator', '下次启动生效'),
                       ('324-ota-account-retained-emulator', 'lsuser01'),
                       ('325-ota-applied-emulator', '内容版本 1'),
                       ('326-ota-rollback-emulator', '内容版本 0'),
                       ('327-ota-auto-restored-emulator', '内容版本 1')]:
    assert expected in (folder / 'ui' / (name + '.xml')).read_text(encoding='utf8')
    assert (folder / 'png' / (name + '.png')).is_file()
adb = [r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe', '-s', 'emulator-5554']
log = subprocess.check_output(adb + ['logcat', '-d'], text=True, encoding='utf8', errors='replace')
log = '\n'.join(line for line in log.splitlines() if 'FlutterPatcher/' in line)
assert 'patch ota-3 ready' in log and 'status=PATCHED patch=ota-3' in log
(folder / 'native-ota.txt').write_text(log + '\n', encoding='utf8')
package = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
stamp = re.search(r'lastUpdateTime=(.+)', package).group(1).strip()
assert stamp == '2026-10-24 05:44:43', 'Unexpected reinstall during code-push acceptance'
public = re.search(r"'([^']+)'", (root / 'lib/ota_key.dart').read_text()).group(1)
public = Ed25519PublicKey.from_public_bytes(base64.b64decode(public))
remote = []
for abi in ['arm64-v8a', 'x86_64']:
    response = requests.get(f'https://47.111.81.94/api/v1/ota/preview/8078/{abi}/manifest.json', timeout=20)
    response.raise_for_status()
    envelope = response.json()
    public.verify(base64.b64decode(envelope['signature']), base64.b64decode(envelope['payload']))
    manifest = json.loads(base64.b64decode(envelope['payload']))
    assert manifest['sequence'] == 3 and manifest['base'] == 8078 and manifest['abi'] == abi
    remote.append(manifest)
    assert requests.get(f'https://47.111.81.94/api/v1/ota/production/8078/{abi}/manifest.json', timeout=20).status_code == 204
(folder / 'published.json').write_text(json.dumps(remote, indent=2) + '\n')
delivery = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.54')
artifacts = []
for track, cert in [('preview', '235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),
                    ('production', '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    assert 'BUILD SUCCESSFUL' in (root / f'.artifact-work/sso/ota54-{track}-build.log').read_text(encoding='utf-8-sig')
    assert cert in (root / f'.artifact-work/sso/ota54-{track}-signature.log').read_text(encoding='utf-8-sig')
    apk = delivery / f'LineSight-1.1.54-8078-{track}.apk'
    artifacts.append({'file': apk.name, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                      'bytes': apk.stat().st_size, 'certificate_sha256': cert})
report = {'version': '1.1.54+8078', 'module': 'flutter_patcher 0.1.4', 'self_hosted': True,
          'flutter_tests': 453, 'backend_tests': 97, 'analyze_clean': True,
          'native_track': 'preview', 'native_abi': 'x86_64', 'native_api': 34,
          'manual_check_download_apply_verified': True, 'automatic_startup_download_apply_verified': True,
          'signed_remote_rollback_verified': True, 'sequence_replay_and_signature_tests_passed': True,
          'account_and_team_retained': True, 'apk_last_update_time_unchanged': stamp,
          'no_apk_reinstallation_during_patch_flow': True, 'physical_devices_tested': False,
          'automatic_crash_rollback_tested': False, 'production_runtime_tested': False,
          'production_channel_has_no_test_patch': True, 'new_png': 6, 'artifacts': artifacts}
(folder / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))

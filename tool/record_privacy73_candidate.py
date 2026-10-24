"""Freeze a signed native-privacy candidate without publishing or changing OTA bases."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile
from ota_release import apk_fingerprint

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/privacy73-batch'
source = ROOT / '.artifact-work/release/LineSight-1.1.55-8079-production.apk'
candidate = json.loads((OUT / 'candidate-production.json').read_text())
assert candidate['direct_calls_absent'] and candidate['direct_call_counts'] == {}
assert hashlib.sha256(source.read_bytes()).hexdigest() == candidate['apk_sha256']
signature = (ROOT / '.artifact-work/sso/privacy73-production-signature.log').read_text()
cert = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)[1]
assert cert == '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2'
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
log = (ROOT / '.artifact-work/privacy73-dart.log').read_text(encoding='utf-8-sig')
assert '+11: All tests passed!' in log
analysis = (ROOT / '.artifact-work/privacy73-analyze.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in analysis
old = json.loads((ROOT / '.artifact-work/ota/production/8078/base.json').read_text())
new = apk_fingerprint(source)
assert old != new, 'Expected native drift requiring a new APK'
with zipfile.ZipFile(source) as apk:
    for name in apk.namelist():
        if re.fullmatch(r'classes\d*\.dex', name):
            assert not any(marker in apk.read(name) for marker in
                           [b'IntegrationTestPlugin', b'StorageAuditInstrumentation',
                            b'OtaBootAudit', b'NativePrivacyAudit'])
delivery = Path('D:/ENT207/deliverables/LineSight-1.1.55-candidate')
delivery.mkdir(parents=True, exist_ok=True)
target = delivery / source.name
assert not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() == candidate['apk_sha256']
shutil.copyfile(source, target)
result = {'status': 'candidate_pending_native_acceptance', 'version': '1.1.55+8079',
          'track': 'production', 'content_revision': 5, 'file': source.name,
          'bytes': target.stat().st_size, 'sha256': candidate['apk_sha256'],
          'certificate_sha256': cert, 'direct_dex_log_check_passed': True,
          'audit_code_absent': True, 'targeted_flutter_tests_passed': 11,
          'flutter_analysis_passed': True,
          'incompatible_with_8078_ota_base': True,
          'native_assets_entries_changed': sum(old.get(n) != new.get(n) for n in set(old) | set(new)),
          'publicly_published': False, 'ota_base_or_manifests_changed': False,
          'remaining': ['native startup and browser login callback', 'native OTA crash guard regression',
                        'preview-signature APK', 'full Flutter suite and version screenshot updates',
                        'native libraries and Android crash-log privacy audit']}
(OUT / 'candidate.json').write_text(json.dumps(result, indent=2) + '\n')
(delivery / 'candidate.json').write_text(json.dumps(result, indent=2) + '\n')
(OUT / 'targeted-tests.txt').write_text('\n'.join(line.rstrip() for line in log.splitlines()
    if re.match(r'^\d\d:\d\d ', line)) + '\n', encoding='utf-8')
(OUT / 'analysis.txt').write_text('\n'.join(line.rstrip() for line in analysis.splitlines()[-2:]) + '\n', encoding='utf-8')
print(json.dumps({'candidate': str(target), 'sha256': result['sha256'],
                  'native_acceptance_pending': True, '8078_ota_refused_by_fingerprint': True}))

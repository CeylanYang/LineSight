"""Record full-test and dual-signature candidates; keep native acceptance pending."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from PIL import Image, ImageChops
from ota_release import apk_fingerprint

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/privacy74-batch'
OUT.mkdir(parents=True, exist_ok=True)
log = (ROOT / '.artifact-work/privacy74-full-tests-final.log').read_text(encoding='utf-8-sig')
match = re.search(r'^\d\d:\d\d \+(\d+): All tests passed!', log, re.M)
assert match and int(match[1]) == 474
old_log = (ROOT / '.artifact-work/privacy74-full-tests.log').read_text(encoding='utf-8-sig')
assert '+466 -8: Some tests failed.' in old_log

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

images = []
for current in sorted((ROOT / 'docs/product/linesight/acceptance/version-components/1.1.55').glob('*.png')):
    old_batch = 'template-batch' if current.name.startswith('181-') else 'diagnostics-batch'
    previous = ROOT / 'docs/product/linesight/acceptance' / old_batch / 'png' / current.name
    committed = subprocess.check_output(['git', 'show', 'HEAD:' + previous.relative_to(ROOT).as_posix()], cwd=ROOT)
    assert previous.read_bytes() == committed, 'Historical screenshot modified'
    a, b = Image.open(previous).convert('RGB'), Image.open(current).convert('RGB')
    assert a.size == b.size
    difference = ImageChops.difference(a, b)
    bounds = difference.getbbox()
    assert bounds and bounds[2] - bounds[0] <= 10 and bounds[3] - bounds[1] <= 15
    images.append({'file': current.name, 'previous_sha256': digest(previous),
                   'current_sha256': digest(current), 'pixel_difference_bounds': bounds})
assert len(images) == 8
delivery = Path('D:/ENT207/deliverables/LineSight-1.1.55-candidate')
artifacts = []
fingerprints = []
for track, certificate in [
    ('production', '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2'),
    ('preview', '235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),
]:
    source = ROOT / f'.artifact-work/release/LineSight-1.1.55-8079-{track}.apk'
    assert not (ROOT / f'.artifact-work/ota/{track}/8079/base.json').exists()
    fingerprints.append(apk_fingerprint(source))
    if track == 'production':
        audit = json.loads((ROOT / 'docs/product/linesight/acceptance/privacy73-batch/candidate-production.json').read_text())
        signature_log = ROOT / '.artifact-work/sso/privacy73-production-signature.log'
    else:
        audit = json.loads((ROOT / '.artifact-work/sso/privacy74-preview-native-logs.json').read_text())
        signature_log = ROOT / '.artifact-work/sso/privacy74-preview-signature.log'
    assert audit['direct_calls_absent'] and audit['direct_call_counts'] == {}
    assert digest(source) == audit['apk_sha256']
    signature = signature_log.read_text()
    assert 'Signer #1 certificate SHA-256 digest: ' + certificate in signature
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
    target = delivery / source.name
    assert not target.exists() or digest(target) == digest(source)
    shutil.copyfile(source, target)
    artifacts.append({'track': track, 'file': target.name, 'bytes': target.stat().st_size,
                      'sha256': digest(target), 'certificate_sha256': certificate,
                      'direct_dex_log_check_passed': True})
    (OUT / (track + '-log-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
assert fingerprints[0] == fingerprints[1], 'Native/resources/assets/engine must match across signatures'
old_base = json.loads((ROOT / '.artifact-work/ota/production/8078/base.json').read_text())
render_entries = [name for name in old_base if name.startswith('assets/flutter_assets/') or name.endswith('/libflutter.so')]
assert render_entries and all(old_base[name] == fingerprints[0].get(name) for name in render_entries)
report = {'version': '1.1.55+8079', 'content_revision': 5,
          'status': 'candidate_pending_native_acceptance', 'flutter_tests_passed': 474,
          'initial_run': {'passed': 466, 'version_golden_failures': 8},
          'version_images': images, 'historical_images_unchanged': True,
          'artifacts': artifacts, 'published': False, 'new_ota_base_frozen': False,
          'native_resources_assets_engine_equal_across_tracks': True,
          'flutter_assets_and_engine_equal_to_8078': True,
          'remaining': ['native startup, browser callback and upgrade/session retention for both signatures',
                        'native OTA crash guard regression', 'native library and Android crash-log privacy',
                        'other delivery requirements remain in DELIVERY_STATUS_20261024.md']}
(OUT / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
(delivery / 'candidate-set.json').write_text(json.dumps(report, indent=2) + '\n')
summary = [line.rstrip() for line in log.splitlines() if re.search(r'All tests passed!', line)]
(OUT / 'full-test-result.txt').write_text('\n'.join(summary) + '\n')
print(json.dumps({'tests_passed': 474, 'candidate_tracks': [a['track'] for a in artifacts],
                  'historical_images_preserved': True, 'native_acceptance_pending': True}))

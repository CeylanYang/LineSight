"""Verify and package the 1.1.20 brand reveal APKs and changed source files."""
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
release = Path(r'C:\Users\29668\LineSight-releases\1.1.20')
destination = Path(r'D:\ENT207\deliverables\LineSight-1.1.20')
sdk = Path(r'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.0.0')
java = Path(r'C:\Program Files\Java\jdk-21\bin\java.exe')

def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True, encoding='utf-8', errors='replace')

def certificate(apk):
    signed = run(java, '-jar', sdk / 'lib/apksigner.jar', 'verify', '--verbose', '--print-certs', apk)
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signed
    return re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', signed).group(1), signed

previous_cert, _ = certificate(Path(r'C:\Users\29668\LineSight-releases\1.1.19\LineSight-1.1.19-x86_64.apk'))
report = {
    'version': '1.1.20', 'source': str(root), 'based_on': '1.1.19',
    'reference_sha256': '300c6be3903afe68ddd80150753ad1d628ff5bdec0b0b1692dd4ff1117c1a173',
    'particle_count': 910, 'reveal_ms': 2800, 'diagonal_reflections': False,
    'host_tests': 100, 'analysis': 'No issues found',
    'android_tests': '2 scenarios passed; runner additionally counts teardown',
    'physical_motor_and_phone_fps': 'not measured', 'artifacts': {},
}
assert 'All tests passed!' in (release / 'reports/host-tests.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (release / 'reports/analyze.log').read_text(encoding='utf-8-sig')
assert 'All tests passed.' in (release / 'reports/android-journey-final.log').read_text(encoding='utf-8-sig')

for arch, code in [('arm64-v8a', 6024), ('x86_64', 8024)]:
    source = root / f'build/app/outputs/flutter-apk/app-{arch}-release.apk'
    apk = release / f'LineSight-1.1.20-{arch}.apk'
    shutil.copy2(source, apk)
    badging = run(sdk / 'aapt.exe', 'dump', 'badging', apk)
    permissions = run(sdk / 'aapt.exe', 'dump', 'permissions', apk)
    cert, signed = certificate(apk)
    assert cert == previous_cert
    assert "name='com.example.linesight_flutter'" in badging
    assert "versionName='1.1.20'" in badging
    assert f"versionCode='{code}'" in badging
    assert "sdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging
    assert 'application-debuggable' not in badging
    assert 'android.permission.INTERNET' in permissions and 'android.permission.VIBRATE' in permissions
    with zipfile.ZipFile(apk) as archive:
        assert archive.read('assets/flutter_assets/assets/brand/reveal_logo.png') == (root / 'assets/brand/reveal_logo.png').read_bytes()
        assert b'https://47.111.81.94/api/v1/' in archive.read(f'lib/{arch}/libapp.so')
    for label, content in [('badging', badging), ('permissions', permissions), ('signature', signed)]:
        (release / f'reports/{arch}-{label}.txt').write_text(content, encoding='utf-8')
    report['artifacts'][apk.name] = {
        'bytes': apk.stat().st_size, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
        'version_code': code, 'certificate_sha256': cert,
        'matches_previous_signature': True, 'embedded_endpoint_preserved': True,
    }

changes = [
    'lib/main.dart', 'lib/ui.dart', 'lib/screens/startup.dart',
    'lib/brand_reveal.dart', 'lib/brand_particles.dart', 'assets/brand/reveal_logo.png',
    'pubspec.yaml', 'pubspec.lock', 'android/app/src/main/AndroidManifest.xml',
    'android/app/src/main/kotlin/com/example/linesight_flutter/MainActivity.kt',
    'android/app/src/main/kotlin/com/example/linesight_flutter/LineSightHaptics.kt',
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
    'android/app/src/main/res/drawable/splash_empty.xml',
    'android/app/src/main/res/values/styles.xml', 'android/app/src/main/res/values-night/styles.xml',
    'test/brand_startup_test.dart', 'test/startup_layout_test.dart',
    'integration_test/brand_reveal_journey_test.dart', 'integration_test/startup_ui_journey_test.dart',
    'tool/import_brand_reveal.py', 'tool/package_brand_release.py', 'tool/capture_brand_launch.py',
    'docs/BRAND_REVEAL.md', 'docs/CURRENT_DEVELOPMENT.md', 'README.md',
]
with zipfile.ZipFile(release / 'source-changes.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in changes:
        archive.write(root / name, name)
report['source_files_sha256'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in changes}
(release / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
shutil.copy2(root / 'docs/BRAND_REVEAL.md', release / 'IMPLEMENTATION.md')
destination.mkdir(parents=True, exist_ok=True)
for path in release.iterdir():
    if path.is_file(): shutil.copy2(path, destination / path.name)
shutil.copytree(release / 'screenshots', destination / 'screenshots', dirs_exist_ok=True)
print(json.dumps(report, ensure_ascii=False, indent=2))

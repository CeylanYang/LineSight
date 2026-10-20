import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sdk = Path(r'C:\Users\29668\AppData\Local\Android\Sdk')
build_tools = sdk / 'build-tools/36.0.0'
evidence = root / 'build/language-evidence'
evidence.mkdir(parents=True, exist_ok=True)
results = {}

def signature(path):
    return subprocess.run([r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe', '-jar', str(build_tools / 'lib/apksigner.jar'), 'verify', '--verbose', '--print-certs', str(path)], capture_output=True, text=True, check=True).stdout

baseline = signature(Path(r'C:\Users\29668\LineSight-releases\1.1.9\LineSight-1.1.9-x86_64.apk'))
certificate = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', baseline).group(1)
for arch, code in [('arm64-v8a', 2012), ('x86_64', 4012)]:
    apk = root / 'build/app/outputs/flutter-apk' / f'app-{arch}-release.apk'
    badging = subprocess.run([str(build_tools / 'aapt.exe'), 'dump', 'badging', str(apk)], capture_output=True, text=True, check=True).stdout
    permissions = subprocess.run([str(build_tools / 'aapt.exe'), 'dump', 'permissions', str(apk)], capture_output=True, text=True, check=True).stdout
    signed = signature(apk)
    assert "name='com.example.linesight_flutter'" in badging
    assert "versionName='1.1.10'" in badging
    assert f"versionCode='{code}'" in badging
    assert "sdkVersion:'24'" in badging
    assert "targetSdkVersion:'36'" in badging
    assert 'android.permission.INTERNET' not in permissions
    assert 'application-debuggable' not in badging
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signed
    assert re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', signed).group(1) == certificate
    (evidence / f'{arch}-badging.txt').write_text(badging, encoding='utf-8')
    (evidence / f'{arch}-permissions.txt').write_text(permissions, encoding='utf-8')
    (evidence / f'{arch}-signature.txt').write_text(signed, encoding='utf-8')
    with apk.open('rb') as stream:
        digest=hashlib.file_digest(stream, 'sha256').hexdigest().upper()
    results[arch]={'version':'1.1.10','code':code,'bytes':apk.stat().st_size,'sha256':digest,'min_sdk':24,'target_sdk':36,'internet':False,'debuggable':False,'certificate_matches_1_1_9':True}
(evidence / 'apk-verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(results, indent=2))

"""Verify content4 signatures, unchanged native base, and native OTA evidence."""
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from PIL import Image
from ota_release import apk_fingerprint


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / 'docs/product/linesight/acceptance/startup64-batch'
    assert '+464: All tests passed!' in (root / '.artifact-work/startup64-full.log').read_text(encoding='utf-8-sig')
    assert 'No issues found!' in (root / '.artifact-work/startup64-analyze.log').read_text(encoding='utf-8-sig')
    for name, expected in [
        ('349-startup64-first-login-emulator', '登录'),
        ('350-startup64-ready-emulator', '更新已准备好，下次启动生效'),
        ('352-startup64-applied-emulator', '内容版本 4'),
        ('351-startup64-demo-retained-emulator', '演示团队'),
    ]:
        tree = ET.parse(folder / 'ui' / (name + '.xml'))
        labels = '\n'.join(n.get('text', '') + n.get('content-desc', '') for n in tree.iter('node'))
        assert expected in labels
        with Image.open(folder / 'png' / (name + '.png')) as picture:
            assert picture.size == (412, 824)
    adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
    assert subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu']).strip() == b'1'
    package = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
    first_install = re.search(r'firstInstallTime=([^\r\n]+)', package)[1].strip()
    timestamp = re.search(r'lastUpdateTime=([^\r\n]+)', package)[1].strip()
    assert timestamp == first_install
    assert subprocess.check_output(adb + ['emu', 'avd', 'name']).splitlines()[0].strip() == b'LineSightProductionFreshValidation'
    first_launch = json.loads((folder / 'first-launch.json').read_text())
    assert first_launch['first_launch_passed'] and first_launch['observed_seconds_until_navigation'] < 45
    native_log = subprocess.check_output(adb + ['logcat', '-d', '-s', 'FlutterPatcher/Diag:D', '*:S'],
                                         text=True, encoding='utf-8', errors='replace')
    assert 'status=PATCHED patch=ota-3' in native_log
    # Raw platform logs are deliberately not retained.
    public = re.search(r"otaPublicKey = '([^']+)'", (root / 'lib/ota_key.dart').read_text())[1]
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public))
    delivery = Path('D:/ENT207/deliverables/LineSight-1.1.54-content4')
    delivery.mkdir(parents=True, exist_ok=True)
    manifests = []
    artifacts = []
    for track, sequence in [('preview', 6), ('production', 3)]:
        apk = root / f'.artifact-work/release/LineSight-1.1.54-8078-{track}.apk'
        baseline = json.loads((root / f'.artifact-work/ota/{track}/8078/base.json').read_text())
        assert apk_fingerprint(apk) == baseline
        signature = (root / f'.artifact-work/sso/startup64-{track}-signature.log').read_text(encoding='utf-8-sig')
        assert 'DOES NOT VERIFY' not in signature
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)[1]
        upload = (root / f'.artifact-work/startup64-{track}-upload.log').read_text(encoding='utf-8-sig')
        assert f'Published atomically: {track} 8078' in upload
        with zipfile.ZipFile(apk) as archive:
            for abi in ['arm64-v8a', 'x86_64']:
                patch = root / f'.artifact-work/ota/{track}/8078/{abi}'
                envelope = json.loads((patch / 'manifest.json').read_text())
                payload = base64.b64decode(envelope['payload'])
                key.verify(base64.b64decode(envelope['signature']), payload)
                data = json.loads(payload)
                assert (data['sequence'], data['base'], data['track'], data['abi']) == (sequence, 8078, track, abi)
                raw = (patch / (data['sha256'] + '.so')).read_bytes()
                assert len(raw) == data['size'] and hashlib.sha256(raw).hexdigest() == data['sha256']
                assert raw == archive.read(f'lib/{abi}/libapp.so')
                manifests.append(data)
        shutil.copy2(apk, delivery / apk.name)
        artifacts.append({'file': apk.name, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                          'bytes': apk.stat().st_size, 'certificate_sha256': certificate})
    result = {
        'version': '1.1.54+8078', 'content_revision': 4, 'flutter_tests': 464,
        'new_startup_reply_timeout_tests': 1, 'analyze_clean': True,
        'source_fix_commit': '2b53114', 'native_assets_engine_unchanged': True,
        'preview_ota6_published': True, 'preview_content4_runtime_verified': False,
        'production_ota3_runtime_verified': True, 'production_ota3_published': True,
        'production_first_launch': first_launch,
        'demo_session_restored_after_patch': True,
        'production_runtime_verified': True, 'native_fault_injection_of_dart_handlers': False,
        'observed_last_update_time': timestamp, 'app_reinstalled': False, 'app_data_cleared': False,
        'native_plugin_direct_logging_fully_audited': False, 'physical_devices_verified': False,
        'manifests': manifests, 'artifacts': artifacts,
    }
    for path in [folder / 'validation.json', delivery / 'delivery.json']:
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (delivery / '更新说明.md').write_text(
        '# LineSight 1.1.54 内容更新 4\n\n'
        '修复开屏原生可见回调不返回时无限等待的问题；首帧完成后等待回调最多两秒，正常动画、后台暂停和触觉设置保留。\n\n'
        '已有 8078 会自动下载，下次冷启动生效；可在“我的 → 应用更新”检查内容版本 4。无需卸载或重装。\n\n'
        '旧版请按原签名选择 preview 或 production 包覆盖升级。遇到签名不一致时停止，保留原 App。\n\n'
        '464 项 Flutter 测试及静态检查通过；正式签名包已在全新模拟器验证首次启动、演示登录及正式 OTA 冷启动。真机、其他原生日志及完整角色验收仍待完成。\n',
        encoding='utf-8')
    print(json.dumps({'tests': 464, 'verified_manifests': len(manifests), 'delivery': str(delivery)}))


if __name__ == '__main__':
    main()

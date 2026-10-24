"""Verify content3 signatures, unchanged native base, and native OTA evidence."""
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
    folder = root / 'docs/product/linesight/acceptance/runtime62-batch'
    assert '+463: All tests passed!' in (root / '.artifact-work/privacy62-full.log').read_text(encoding='utf-8-sig')
    assert 'No issues found!' in (root / '.artifact-work/privacy62-analyze.log').read_text(encoding='utf-8-sig')
    for name, expected in [
        ('343-runtime62-ready-emulator', '更新已准备好，下次启动生效'),
        ('344-runtime62-applied-emulator', '内容版本 3'),
        ('345-runtime62-demo-retained-emulator', '演示团队'),
    ]:
        tree = ET.parse(folder / 'ui' / (name + '.xml'))
        labels = '\n'.join(n.get('text', '') + n.get('content-desc', '') for n in tree.iter('node'))
        assert expected in labels
        with Image.open(folder / 'png' / (name + '.png')) as picture:
            assert picture.size == (412, 824)
    adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
    assert subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu']).strip() == b'1'
    package = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
    timestamp = re.search(r'lastUpdateTime=([^\r\n]+)', package)[1].strip()
    assert timestamp == '2026-10-24 05:44:43'
    native_log = subprocess.check_output(adb + ['logcat', '-d', '-s', 'FlutterPatcher/Diag:D', '*:S'],
                                         text=True, encoding='utf-8', errors='replace')
    assert 'status=PATCHED patch=ota-5' in native_log
    # Raw platform logs are deliberately not retained.
    public = re.search(r"otaPublicKey = '([^']+)'", (root / 'lib/ota_key.dart').read_text())[1]
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public))
    delivery = Path('D:/ENT207/deliverables/LineSight-1.1.54-content3')
    delivery.mkdir(parents=True, exist_ok=True)
    manifests = []
    artifacts = []
    for track, sequence in [('preview', 5), ('production', 2)]:
        apk = root / f'.artifact-work/release/LineSight-1.1.54-8078-{track}.apk'
        baseline = json.loads((root / f'.artifact-work/ota/{track}/8078/base.json').read_text())
        assert apk_fingerprint(apk) == baseline
        signature = (root / f'.artifact-work/sso/privacy62-{track}-signature.log').read_text(encoding='utf-8-sig')
        assert 'DOES NOT VERIFY' not in signature
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)[1]
        upload = (root / f'.artifact-work/privacy62-{track}-upload.log').read_text(encoding='utf-8-sig')
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
        'version': '1.1.54+8078', 'content_revision': 3, 'flutter_tests': 463,
        'new_runtime_privacy_tests': 4, 'analyze_clean': True,
        'source_fix_commit': '92c779d', 'native_assets_engine_unchanged': True,
        'preview_ota5_runtime_verified': True, 'production_ota2_published': True,
        'demo_session_restored_after_patch': True,
        'host_emulator_exit_before_final_capture': int((root / '.artifact-work/runtime62-emulator-exit.txt').read_text().strip()),
        'production_runtime_verified': False, 'native_fault_injection_of_dart_handlers': False,
        'observed_last_update_time': timestamp, 'app_reinstalled': False, 'app_data_cleared': False,
        'native_plugin_direct_logging_fully_audited': False, 'physical_devices_verified': False,
        'manifests': manifests, 'artifacts': artifacts,
    }
    for path in [folder / 'validation.json', delivery / 'delivery.json']:
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (delivery / '更新说明.md').write_text(
        '# LineSight 1.1.54 内容更新 3\n\n'
        '正式版本的 Flutter 框架错误和未捕获异步错误仅记录固定类别及来源，不输出原始异常、插件详情或诊断上下文。\n\n'
        '已有 8078 会自动下载，下次冷启动生效；可在“我的 → 应用更新”检查内容版本 3。无需卸载或重装。\n\n'
        '旧版请按原签名选择 preview 或 production 包覆盖升级。遇到签名不一致时停止，保留原 App。\n\n'
        '463 项 Flutter 测试及静态检查通过，预览 OTA 已验证冷启动。其他原生插件直接日志、正式渠道运行和真机功能仍待验收。\n',
        encoding='utf-8')
    print(json.dumps({'tests': 463, 'verified_manifests': len(manifests), 'delivery': str(delivery)}))


if __name__ == '__main__':
    main()

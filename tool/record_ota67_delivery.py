"""Freeze normal content5 APK/OTA evidence; never reads local fault APKs."""
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
from ota_release import apk_fingerprint


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / 'docs/product/linesight/acceptance/ota67-batch'
    assert '+466: All tests passed!' in (root / '.artifact-work/ota67-full.log').read_text(encoding='utf-8-sig')
    assert 'No issues found!' in (root / '.artifact-work/ota67-analyze.log').read_text(encoding='utf-8-sig')
    faults = json.loads((folder / 'validation.json').read_text())
    assert len(faults['cases']) == 2 and all(row['blacklisted'] and row['base_navigation_recovered'] for row in faults['cases'])
    adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
    assert subprocess.check_output(adb + ['emu', 'avd', 'name']).splitlines()[0].strip() == b'LineSightProductionFreshValidation'
    package = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
    installed = re.search(r'firstInstallTime=([^\r\n]+)', package)[1].strip()
    updated = re.search(r'lastUpdateTime=([^\r\n]+)', package)[1].strip()
    assert installed == updated == '2026-10-24 08:42:22'
    logs = subprocess.check_output(adb + ['logcat', '-d', '-s', 'FlutterPatcher/Diag:D', '*:S'], text=True)
    assert 'status=PATCHED patch=ota-4' in logs
    for name, expected in [('373-ota67-ready-emulator', '更新已准备好，下次启动生效'),
                           ('374-ota67-demo-retained-emulator', '演示团队'),
                           ('375-ota67-applied-emulator', '内容版本 5')]:
        tree = ET.parse(folder / 'ui' / (name + '.xml'))
        text = '\n'.join(node.get('text', '') + node.get('content-desc', '') for node in tree.iter('node'))
        assert expected in text, name
    public = re.search(r"otaPublicKey = '([^']+)'", (root / 'lib/ota_key.dart').read_text())[1]
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public))
    delivery = Path('D:/ENT207/deliverables/LineSight-1.1.54-content5')
    delivery.mkdir(exist_ok=True)
    artifacts = []
    manifests = []
    for track, sequence in [('preview', 7), ('production', 4)]:
        assert f'Published atomically: {track} 8078' in (root / f'.artifact-work/ota67-{track}-upload.log').read_text(encoding='utf-8-sig')
        apk = root / f'.artifact-work/release/LineSight-1.1.54-8078-{track}.apk'
        baseline = json.loads((root / f'.artifact-work/ota/{track}/8078/base.json').read_text())
        assert apk_fingerprint(apk) == baseline
        signature = (root / f'.artifact-work/sso/ota67-{track}-signature.log').read_text(encoding='utf-8-sig')
        certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)[1]
        assert certificate == {'preview': '235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e',
                               'production': '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2'}[track]
        with zipfile.ZipFile(apk) as archive:
            for abi in ['arm64-v8a', 'x86_64']:
                patch = root / f'.artifact-work/ota/{track}/8078/{abi}'
                envelope = json.loads((patch / 'manifest.json').read_text())
                raw = base64.b64decode(envelope['payload'])
                key.verify(base64.b64decode(envelope['signature']), raw)
                data = json.loads(raw)
                assert (data['sequence'], data['track'], data['abi'], data['action']) == (sequence, track, abi, 'patch')
                payload = (patch / (data['sha256'] + '.so')).read_bytes()
                assert hashlib.sha256(payload).hexdigest() == data['sha256'] and len(payload) == data['size']
                assert payload == archive.read(f'lib/{abi}/libapp.so')
                assert data['sha256'] != faults['fault_sha256']
                assert b'LS_OTA67_RAW_SECRET_CANARY' not in payload
                assert b'OTA boot fault acceptance' not in payload
                manifests.append(data)
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        target = delivery / apk.name
        if target.exists():
            assert hashlib.sha256(target.read_bytes()).hexdigest() == digest, 'Never overwrite frozen delivery'
        else:
            shutil.copy2(apk, target)
        artifacts.append({'file': apk.name, 'sha256': digest, 'bytes': apk.stat().st_size,
                          'certificate_sha256': certificate})
    receipt = {'version': '1.1.54+8078', 'content_revision': 5, 'source_fix_commit': 'd60477a',
               'flutter_tests': 466, 'analyze_clean': True, 'native_assets_engine_unchanged': True,
               'preview_ota7_published': True, 'production_ota4_published': True,
               'production_content5_runtime_verified': True, 'preview_content5_runtime_verified': False,
               'startup_dart_fault_rollback_verified': True, 'native_process_fatal_crash_or_anr_verified': False,
               'physical_devices_verified': False, 'customer_data_changed': False,
               'first_install_time': installed, 'last_update_time': updated,
               'app_reinstalled': False, 'app_data_cleared': False,
               'artifacts': artifacts, 'manifests': manifests}
    for target in [folder / 'delivery.json', delivery / 'delivery.json']:
        target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (delivery / '更新说明.md').write_text(
        '# LineSight 1.1.54 内容更新 5\n\n'
        '修复 OTA 启动错误报告可能输出原始异常的问题，同时保留模块的故障回滚与黑名单。\n\n'
        '已有 8078 会后台下载，下次冷启动生效。首次安装按原签名选择 preview 或 production。\n\n'
        '466 项 Flutter 测试及静态检查通过；独立模拟器实际框架/异步启动故障回退通过，正式 OTA4 运行通过。'
        '原生致命崩溃/ANR、其他插件直接日志和真机硬件仍待验收。\n', encoding='utf-8')
    print(json.dumps({'delivery': str(delivery), 'content': 5, 'artifacts': len(artifacts)}))


if __name__ == '__main__':
    main()

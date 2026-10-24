"""Local-only bad-AOT boot rollback on a dedicated disposable-data AVD."""
import hashlib
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

from ota_release import apk_fingerprint

ROOT = Path(__file__).resolve().parents[1]
ADB = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
PACKAGE = 'com.example.linesight_flutter'
FOLDER = ROOT / 'docs/product/linesight/acceptance/ota67-batch'
SYSTEM_DIALOGS = []


def adb(*parts):
    return subprocess.check_output(ADB + list(parts), timeout=90).decode('utf-8', errors='replace')


def ui(action, value=None):
    command = [sys.executable, str(ROOT / 'tool/release_android_ui.py'), action]
    if value:
        command.append(value)
    if action == 'capture':
        command += ['--batch', 'ota67-batch']
    return subprocess.check_output(command, cwd=ROOT, timeout=60).decode('utf-8', errors='replace')


def wait_ui(label):
    started = time.monotonic()
    while time.monotonic() - started < 60:
        try:
            state = ui('inspect')
            if 'Bluetooth keeps stopping' in state and 'Close app' in state:
                SYSTEM_DIALOGS.append('Android Bluetooth keeps stopping; dismissed Close app')
                ui('tap', 'Close app')
                continue
            if label in state:
                return
        except subprocess.CalledProcessError:
            pass
    raise AssertionError('Current UI did not reach ' + label)


def audit(mode):
    output = adb('shell', 'am', 'instrument', '-w', '-e', 'otaMode', mode,
                 PACKAGE + '.test/com.linesight.acceptance.StorageAuditInstrumentation')
    match = re.search(r'LINESIGHT_OTA_BOOT=(\{[^\r\n]+\})', output)
    assert match, output
    return json.loads(match[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-installed', action='store_true', help='Keep existing baseline after interrupted acceptance')
    args = parser.parse_args()
    assert adb('emu', 'avd', 'name').splitlines()[0].strip() == 'LineSightOtaFaultValidation'
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == '1'
    apk = ROOT / '.artifact-work/ota67-fault/LineSight-1.1.54-8078-production.apk'
    frozen = json.loads((ROOT / '.artifact-work/ota/production/8078/base.json').read_text())
    assert apk_fingerprint(apk) == frozen, 'Fault must retain actual delivered native/assets/engine'
    mapping = (ROOT / 'build/app/outputs/mapping/release/mapping.txt').read_text(encoding='utf-8')
    assert 'com.flutter_patcher.flutter_patcher.PatchManager -> o3.n:' in mapping
    assert re.search(r'ApplyResult applyPatch\(java.util.Map\).* -> b\n', mapping)
    source = ROOT / '.artifact-work/ota67-fault/fault-x86_64.so'
    with zipfile.ZipFile(apk) as archive:
        source.write_bytes(archive.read('lib/x86_64/libapp.so'))
    FOLDER.mkdir(parents=True, exist_ok=True)
    installed = subprocess.run(ADB + ['shell', 'pm', 'path', PACKAGE], capture_output=True, timeout=30)
    assert installed.returncode in (0, 1)
    baseline = Path('D:/ENT207/deliverables/LineSight-1.1.54-content4/LineSight-1.1.54-8078-production.apk')
    assert hashlib.sha256(baseline.read_bytes()).hexdigest() == '085a869f1c2e158d18cc4cce2f1a95dadb6ecf6d49729c21db763da6fb425292'
    if installed.stdout.strip():
        assert args.resume_installed, 'Use explicit resume; never reinstall or wipe to rerun'
        device_apk = installed.stdout.decode().strip().removeprefix('package:')
        assert adb('shell', 'sha256sum', device_apk).split()[0] == hashlib.sha256(baseline.read_bytes()).hexdigest()
    else:
        assert 'Success' in adb('install', str(baseline))
        assert 'Success' in adb('install', str(ROOT / '.artifact-work/ota67-fault/LineSight-storage-audit-production.apk'))
    adb('push', str(source), '/data/local/tmp/linesight-ota-boot-fault.so')
    adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
    wait_ui('工作台')
    results = []
    for index, mode in enumerate(['framework', 'asynchronous']):
        adb('shell', 'am', 'force-stop', PACKAGE)
        staged = audit(mode)
        assert staged['patch_exists'] and 'ok=true' in staged['install_result'], staged
        adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        wait_ui('OTA boot fault acceptance')
        pid = adb('shell', 'pidof', PACKAGE).strip()
        assert pid.isdigit()
        logs = adb('logcat', '-d', '--pid=' + pid)
        assert 'LS_OTA67_RAW_SECRET_CANARY' not in logs, 'Raw synthetic private data reached native logs'
        expected = 'LINESIGHT_ERROR source=' + mode + ' category=' + ('state' if mode == 'framework' else 'platform')
        assert expected in logs and 'circuit tripped!' in logs, 'Native boot guard did not receive sanitized failure'
        ui('capture', str(369 + index * 2) + '-ota67-' + mode + '-fault-emulator')
        adb('shell', 'am', 'force-stop', PACKAGE)
        inspected = audit('inspect')
        version = 'local-ota67-' + mode
        assert not inspected['patch_exists'], inspected
        assert any(row['version'] == version and row['reason'] == 'BOOT_CRASH' for row in inspected['blacklist']), inspected
        blocked = audit(mode)
        assert not blocked['patch_exists'] and 'blacklisted' in blocked['install_result'].lower(), blocked
        adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        wait_ui('工作台')
        ui('capture', str(370 + index * 2) + '-ota67-' + mode + '-recovered-emulator')
        results.append({'mode': mode, 'native_fixed_failure': expected,
                        'raw_canary_in_process_logs': False, 'process_log_lines_checked': len(logs.splitlines()),
                        'fault_payload_removed': True, 'blacklisted': True,
                        'same_fault_reapply_rejected': True, 'base_navigation_recovered': True,
                        'audit': inspected})
        (FOLDER / 'fault-results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    receipt = {'cases': results, 'native_assets_engine_identical': True,
               'fault_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
               'avd': 'LineSightOtaFaultValidation', 'api': 34, 'abi': 'x86_64',
               'app_reinstalled': False, 'app_data_cleared': False,
               'public_fault_patch_published': False, 'customer_accounts_used': False,
               'system_dialogs_dismissed_during_run': SYSTEM_DIALOGS,
               'os_native_crash_or_anr_injected': False}
    (FOLDER / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'cases_passed': len(results), 'local_only': True}))


if __name__ == '__main__':
    main()

"""Dedicated-AVD post-first-frame SIGSEGV rollback; never changes public OTA."""
import hashlib
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

from verify_ota_boot_fault import ADB, PACKAGE, adb, audit

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'docs/product/linesight/acceptance/native68-batch'
PREFS = '/data/user/0/' + PACKAGE + '/shared_prefs/flutter_patcher_prefs.xml'


def ui(action, value=None):
    command = [sys.executable, str(ROOT / 'tool/release_android_ui.py'), action]
    if value:
        command.append(value)
    if action == 'capture':
        command += ['--batch', 'native68-batch']
    return subprocess.check_output(command, cwd=ROOT, timeout=60).decode('utf-8', errors='replace')


def wait_ui(label):
    started = time.monotonic()
    while time.monotonic() - started < 60:
        state = ui('inspect')
        if 'Bluetooth keeps stopping' in state and 'Close app' in state:
            ui('tap', 'Close app')
        elif label in state:
            return
    raise AssertionError('Current UI missing: ' + label)


def preferences():
    tree = ET.fromstring(adb('shell', 'cat', PREFS))
    return {node.get('name'): node.text if node.tag == 'string' else node.get('value') for node in tree}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-after-crash', type=int, help='Verify preserved exact crashed PID without reinjection')
    args = parser.parse_args()
    assert adb('emu', 'avd', 'name').splitlines()[0].strip() == 'LineSightOtaFaultValidation'
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == '1'
    baseline = Path('D:/ENT207/deliverables/LineSight-1.1.54-content4/LineSight-1.1.54-8078-production.apk')
    installed = adb('shell', 'pm', 'path', PACKAGE).strip().removeprefix('package:')
    assert adb('shell', 'sha256sum', installed).split()[0] == hashlib.sha256(baseline.read_bytes()).hexdigest()
    delivery = Path('D:/ENT207/deliverables/LineSight-1.1.54-content5')
    receipt = json.loads((delivery / 'delivery.json').read_text())
    artifact = next(row for row in receipt['artifacts'] if '-production.apk' in row['file'])
    apk = delivery / artifact['file']
    assert hashlib.sha256(apk.read_bytes()).hexdigest() == artifact['sha256']
    with zipfile.ZipFile(apk) as archive:
        payload = archive.read('lib/x86_64/libapp.so')
    md5 = hashlib.md5(payload).hexdigest()
    source = ROOT / '.artifact-work/native68-local.so'
    source.write_bytes(payload)
    FOLDER.mkdir(parents=True, exist_ok=True)
    assert not (FOLDER / 'validation.json').exists(), 'Inspect preserved completed evidence before rerun'
    if not args.resume_after_crash:
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('push', str(source), '/data/local/tmp/linesight-ota-boot-fault.so')
        staged = audit('framework')
        assert staged['patch_exists'] and 'ok=true' in staged['install_result'], staged
        adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        wait_ui('工作台')
        ui('capture', '376-native68-patched-emulator')
    # ADB root is restricted to this userdebug test emulator, then reverted.
    adb('root')
    adb('wait-for-device')
    assert adb('shell', 'id', '-u').strip() == '0'
    assert adb('shell', 'sha256sum', '/data/user/0/' + PACKAGE + '/files/flutter_patcher/libapp_patch.so').split()[0] == hashlib.sha256(payload).hexdigest()
    before = preferences()
    assert json.loads(before['last_boot_diagnostic'])['status'] == 'PATCHED'
    assert before['patch_loading'] == 'false', 'Must test after first frame, not its loading fallback'
    assert not any(row['version'] == 'local-ota67-framework' and row['md5'] == md5
                   for row in json.loads(before.get('patch_blacklist', '[]')))
    # Control: an intentional user force-stop must retain the healthy patch.
    if not args.resume_after_crash:
        adb('shell', 'am', 'force-stop', PACKAGE)
        adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        wait_ui('工作台')
    control = preferences()
    assert json.loads(control['last_boot_diagnostic'])['status'] == 'PATCHED'
    assert control['patch_loading'] == 'false'
    pid = str(args.resume_after_crash) if args.resume_after_crash else adb('shell', 'pidof', PACKAGE).strip()
    assert pid.isdigit() and control['last_booting_pid'] == pid
    if not args.resume_after_crash:
        assert adb('shell', 'cat', '/proc/' + pid + '/cmdline').rstrip('\0') == PACKAGE
        # Signal only the exact verified app PID, never the emulator or host process.
        adb('shell', 'kill', '-11', pid)
        started = time.monotonic()
        while time.monotonic() - started < 30:
            live = subprocess.run(ADB + ['shell', 'pidof', PACKAGE], capture_output=True, timeout=15)
            if pid not in live.stdout.decode().split():
                break
            time.sleep(.5)
        else:
            raise AssertionError('SIGSEGV did not terminate the verified app process')
    exits = adb('shell', 'dumpsys', 'activity', 'exit-info', PACKAGE)
    (ROOT / '.artifact-work/native68-exit-info.txt').write_text(exits, encoding='utf-8')
    # Keep only this app's matching exit record, not unrelated system histories.
    records = re.split(r'(?=\s*ApplicationExitInfo #)', exits)
    matching = [record for record in records if re.search(r'\bpid=' + pid + r'\b', record)]
    assert len(matching) == 1, 'Need authoritative Android exit record for exact PID'
    record = matching[0]
    assert re.search(r'reason=5\s*\((?:APP )?CRASH\s*\(?NATIVE\)?\)', record), record
    assert re.search(r'status=11\b', record), record
    inspected = audit('inspect')
    after = preferences()
    diagnostic = json.loads(after['last_boot_diagnostic'])
    assert diagnostic['status'] == 'DROPPED_CIRCUIT_BREAKER', diagnostic
    assert not inspected['patch_exists']
    assert any(row['version'] == 'local-ota67-framework' and row['md5'] == md5 and row['reason'] == 'BOOT_CRASH'
               for row in inspected['blacklist'])
    blocked = audit('framework')
    assert not blocked['patch_exists'] and 'blacklisted' in blocked['install_result'].lower()
    adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
    wait_ui('工作台')
    ui('capture', '377-native68-recovered-emulator')
    logs = adb('logcat', '-d', '-s', 'FlutterPatcher/Guard:V', '*:S')
    assert 'patch boot failure recorded (CRASH_NATIVE)' in logs
    result = {'avd': 'LineSightOtaFaultValidation', 'api': 34, 'abi': 'x86_64',
              'app_version': '1.1.54+8078', 'patch_content': 5,
              'patch_sha256': hashlib.sha256(payload).hexdigest(), 'patch_md5': md5,
              'crashed_pid': int(pid), 'signal': 'SIGSEGV', 'signal_number': 11,
              'android_exit_reason': 'CRASH_NATIVE', 'android_exit_reason_code': 5,
              'first_frame_success_before_crash': True, 'force_stop_control_retained_patch': True,
              'rollback_diagnostic': diagnostic, 'patch_removed': True, 'blacklisted': True,
              'same_patch_reapply_rejected': True, 'base_navigation_recovered': True,
              'app_reinstalled': False, 'app_data_cleared': False,
              'customer_accounts_used': False, 'public_patch_changed': False,
              'root_access': 'dedicated userdebug emulator only, reverted after acceptance',
              'anr_injected': False, 'other_android_api_or_physical_device_verified': False}
    adb('unroot')
    adb('wait-for-device')
    assert adb('shell', 'id', '-u').strip() != '0'
    (FOLDER / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'native_sigsegv_rollback_passed': True, 'pid': int(pid)}))


if __name__ == '__main__':
    try:
        main()
    finally:
        # Also restore temporary root when a verification assertion interrupts.
        try:
            if adb('emu', 'avd', 'name').splitlines()[0].strip() == 'LineSightOtaFaultValidation':
                if adb('shell', 'id', '-u').strip() == '0':
                    adb('unroot')
                    adb('wait-for-device')
        except (subprocess.SubprocessError, IndexError):
            pass

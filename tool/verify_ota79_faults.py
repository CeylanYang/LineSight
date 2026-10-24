"""Candidate-only Dart boot fault rollback on preserved dedicated emulator data."""
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

from ota_release import apk_fingerprint

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/ota79-batch'
STAGED = ROOT / '.artifact-work/ota79-fault'
ADB = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
PACKAGE = 'com.example.linesight_flutter'
PREFS = '/data/user/0/' + PACKAGE + '/shared_prefs/flutter_patcher_prefs.xml'


def adb(*parts):
    return subprocess.check_output(ADB + list(parts), timeout=90).decode('utf-8', errors='replace')


def ui(action, value=None):
    cmd = [sys.executable, 'tool/release_android_ui.py', action]
    if value:
        cmd.append(value)
    if action == 'capture':
        cmd += ['--batch', 'ota79-batch']
    return subprocess.check_output(cmd, cwd=ROOT, timeout=60).decode('utf-8')


def wait_ui(label):
    started = time.monotonic()
    while time.monotonic() - started < 90:
        try:
            current = ui('inspect')
        except subprocess.CalledProcessError:
            time.sleep(1)
            continue
        if label in current:
            return
        if 'Bluetooth keeps stopping' in current and 'Close app' in current:
            ui('tap', 'Close app')
        time.sleep(1)
    raise AssertionError('Expected native page was not reached')


def preferences():
    return {n.get('name'): n.text if n.tag == 'string' else n.get('value')
            for n in ET.fromstring(adb('shell', 'cat', PREFS))}


def audit(mode, manager, method):
    output = adb('shell', 'am', 'instrument', '-w', '-e', 'otaMode', mode,
                 '-e', 'otaManagerClass', manager, '-e', 'otaApplyMethod', method,
                 '-e', 'otaTargetVersionCode', '8079',
                 PACKAGE + '.test/com.linesight.acceptance.StorageAuditInstrumentation')
    match = re.search(r'LINESIGHT_OTA_BOOT=(\{[^\r\n]+\})', output)
    assert match, 'Native audit result missing'
    return json.loads(match[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-running-framework', action='store_true',
                        help='Continue the same live fault after a transient UI dump failure; never reinstall it')
    args = parser.parse_args()
    assert adb('emu', 'avd', 'name').splitlines()[0] == 'LineSightOtaFaultValidation'
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == '1'
    assert not (OUT / 'validation.json').exists(), 'Completed evidence must not be overwritten'
    candidate = ROOT / '.artifact-work/release/LineSight-1.1.55-8079-production.apk'
    fault = STAGED / candidate.name
    assert apk_fingerprint(fault) == apk_fingerprint(candidate), 'Fault differs from actual candidate native/assets/engine'
    mapping = (STAGED / 'mapping.txt').read_text(encoding='utf-8')
    section = re.search(r'^com\.flutter_patcher\.flutter_patcher\.PatchManager -> ([^:]+):\n(.*?)(?=^[^\s#].* -> [^:]+:\n|\Z)', mapping, re.M | re.S)
    assert section
    manager = section[1]
    methods = set(re.findall(r'ApplyResult applyPatch\(java.util.Map\).* -> (\w+)', section[2]))
    assert len(methods) == 1
    method = methods.pop()
    installed = adb('shell', 'pm', 'path', PACKAGE).strip().removeprefix('package:')
    assert installed
    original = adb('shell', 'dumpsys', 'package', PACKAGE)
    first_install = re.search(r'firstInstallTime=([^\r\n]+)', original)[1].strip()
    existing_hash = adb('shell', 'sha256sum', installed).split()[0]
    candidate_hash = hashlib.sha256(candidate.read_bytes()).hexdigest()
    frozen = json.loads((ROOT / 'docs/product/linesight/acceptance/privacy73-batch/candidate-production.json').read_text())
    assert candidate_hash == frozen['apk_sha256'], 'Candidate differs from the signed accepted artifact'
    old_base = Path('D:/ENT207/deliverables/LineSight-1.1.54-content4/LineSight-1.1.54-8078-production.apk')
    assert existing_hash in [candidate_hash, hashlib.sha256(old_base.read_bytes()).hexdigest()]
    if args.resume_running_framework:
        assert existing_hash == candidate_hash
        wait_ui('OTA boot fault acceptance')
    elif existing_hash != candidate_hash:
        assert 'Success' in adb('install', '-r', str(candidate))
    if not args.resume_running_framework:
        assert 'Success' in adb('install', '-r', str(STAGED / 'LineSight-storage-audit-production.apk'))
    after = adb('shell', 'dumpsys', 'package', PACKAGE)
    assert re.search(r'firstInstallTime=([^\r\n]+)', after)[1].strip() == first_install
    assert 'versionCode=8079 ' in after
    device_apk = adb('shell', 'pm', 'path', PACKAGE).strip().removeprefix('package:')
    assert adb('shell', 'sha256sum', device_apk).split()[0] == candidate_hash
    with zipfile.ZipFile(fault) as archive:
        payload = archive.read('lib/x86_64/libapp.so')
    source = STAGED / 'fault-x86_64.so'
    source.write_bytes(payload)
    adb('push', str(source), '/data/local/tmp/linesight-ota-boot-fault.so')
    adb('root')
    adb('wait-for-device')
    assert adb('shell', 'id', '-u').strip() == '0'
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for index, mode in enumerate(['framework', 'asynchronous']):
        print(json.dumps({'stage': mode + ':install'}), flush=True)
        if not (args.resume_running_framework and mode == 'framework'):
            adb('shell', 'am', 'force-stop', PACKAGE)
            staged = audit(mode, manager, method)
            assert staged['patch_exists'] and 'ok=true' in staged['install_result']
            ui('launch')
        wait_ui('OTA boot fault acceptance')
        pid = adb('shell', 'pidof', PACKAGE).strip()
        assert pid.isdigit()
        logs = adb('logcat', '-d', '--pid=' + pid)
        assert 'LS_OTA67_RAW_SECRET_CANARY' not in logs
        # Read while fault process is alive: starting instrumentation would overwrite boot diagnostics.
        prefs = preferences()
        diagnostic = json.loads(prefs['last_boot_diagnostic'])
        expected = 'LINESIGHT_ERROR source=' + mode + ' category=' + ('state' if mode == 'framework' else 'platform')
        assert diagnostic['status'] == 'DROPPED_CIRCUIT_BREAKER'
        assert expected in diagnostic['message']
        assert 'LS_OTA67_RAW_SECRET_CANARY' not in json.dumps(diagnostic)
        ui('capture', str(460 + index * 2) + '-ota79-' + mode + '-fault-emulator')
        adb('shell', 'am', 'force-stop', PACKAGE)
        inspected = audit('inspect', manager, method)
        version = 'local-ota67-' + mode
        assert not inspected['patch_exists']
        assert any(r['version'] == version and r['reason'] == 'BOOT_CRASH' for r in inspected['blacklist'])
        blocked = audit(mode, manager, method)
        assert not blocked['patch_exists'] and 'blacklisted' in blocked['install_result'].lower()
        ui('launch')
        wait_ui('工作台')
        ui('capture', str(461 + index * 2) + '-ota79-' + mode + '-recovered-emulator')
        results.append({'mode': mode, 'boot_diagnostic_before_instrumentation': diagnostic,
                        'sanitized_category_observed': expected, 'raw_canary_in_process_logs': False,
                        'patch_removed': True, 'blacklisted': True, 'same_patch_reapply_rejected': True,
                        'base_navigation_recovered': True})
        (OUT / 'fault-results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    receipt = {'version': '1.1.55+8079', 'track': 'production', 'avd': 'LineSightOtaFaultValidation',
               'api': 34, 'abi': 'x86_64', 'candidate_apk_sha256': candidate_hash,
               'fault_apk_sha256': hashlib.sha256(fault.read_bytes()).hexdigest(),
               'fault_aot_sha256': hashlib.sha256(payload).hexdigest(),
               'fault_native_assets_engine_match_candidate': True, 'cases': results,
               'data_cleared': False, 'uninstall_used': False, 'first_install_time_retained': True,
               'customer_accounts_used': False, 'public_patch_changed': False,
               'native_sigsegv_reverified': False, 'anr_reverified': False,
               'resumed_live_framework_after_transient_ui_failure': args.resume_running_framework,
               'root_access': 'dedicated userdebug emulator only; reverted in finally'}
    (OUT / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'candidate_dart_fault_rollback_passed': True, 'cases': len(results)}), flush=True)


if __name__ == '__main__':
    try:
        main()
    finally:
        try:
            if adb('emu', 'avd', 'name').splitlines()[0] == 'LineSightOtaFaultValidation':
                if adb('shell', 'id', '-u').strip() == '0':
                    adb('unroot')
                    adb('wait-for-device')
                    assert adb('shell', 'id', '-u').strip() != '0'
        except subprocess.SubprocessError:
            pass

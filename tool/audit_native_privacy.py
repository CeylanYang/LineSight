"""Exercise native AppAuth faults and record canary counts, never raw logcat."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import threading

from ota_release import apk_fingerprint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
    assert subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu']).strip() == b'1'
    root = Path(__file__).resolve().parents[1]
    installed_path = subprocess.check_output(adb + ['shell', 'pm', 'path', 'com.example.linesight_flutter'], text=True).strip()
    assert installed_path.startswith('package:/data/app/') and '\n' not in installed_path
    installed = root / '.artifact-work/native61-installed.apk'
    subprocess.run(adb + ['pull', installed_path.removeprefix('package:'), str(installed)], capture_output=True, check=True)
    baseline = json.loads((root / '.artifact-work/ota/preview/8078/base.json').read_text())
    assert apk_fingerprint(installed) == baseline, 'Installed APK differs from frozen native/assets baseline'
    logcat = subprocess.Popen(adb + ['logcat', '-T', '1', '-v', 'threadtime'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    lines = []
    def collect():
        for raw in logcat.stdout:
            lines.append(raw.decode('utf-8', errors='replace'))
    reader = threading.Thread(target=collect, daemon=True)
    reader.start()
    try:
        result = subprocess.run(adb + ['shell', 'am', 'instrument', '-w', '-r', '-e', 'privacy', 'true',
            'com.example.linesight_flutter.test/com.linesight.acceptance.StorageAuditInstrumentation'],
            capture_output=True, timeout=100, check=True)
    finally:
        logcat.terminate()
        logcat.wait(timeout=10)
        reader.join(timeout=10)
    reports = [line.split('LINESIGHT_NATIVE_PRIVACY=', 1)[1] for line in result.stdout.decode('utf-8', errors='replace').splitlines()
               if 'LINESIGHT_NATIVE_PRIVACY=' in line]
    if len(reports) != 1:
        raise RuntimeError('Native privacy instrumentation did not produce a complete report; raw output withheld.')
    report = json.loads(reports[0])
    assert [case['mode'] for case in report['cases']] == ['oauth', 'malformed', 'transport']
    assert all(case['callback_contains_synthetic_marker'] for case in report['cases'])
    report['installed_apk_sha256'] = hashlib.sha256(installed.read_bytes()).hexdigest()
    report['frozen_native_assets_match'] = True
    package_info = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
    report['installed_version'] = re.search(r'versionName=(\S+)', package_info)[1]
    report['last_update_time'] = re.search(r'lastUpdateTime=([^\r\n]+)', package_info)[1].strip()
    own = [line for line in lines if re.match(r'^\S+\s+\S+\s+' + str(report['pid']) + r'\s', line)]
    report['captured_process_log_lines'] = len(own)
    assert own, 'No logcat from instrumented process captured'
    report['canary_occurrences'] = {mode: sum(('LS_NATIVE61_' + mode.upper() + '_CANARY') in line for line in own)
                                   for mode in ['oauth', 'malformed', 'transport']}
    report['raw_logs_saved'] = False
    report['passed'] = not any(report['canary_occurrences'].values())
    report['scope'] = 'Shipped R8 AppAuth 0.11.1 token error handling under current emulator log levels; not Dart unhandled errors, all plugins, elevated debug logging, or OS crash dumps'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': report['passed'], 'cases': len(report['cases']),
                      'captured_process_log_lines': len(own), 'canary_occurrences': report['canary_occurrences']}))
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

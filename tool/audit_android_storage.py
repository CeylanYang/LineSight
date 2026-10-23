"""Collect sanitized storage evidence through a separate same-signature APK."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', default='emulator-5554')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--seed', action='store_true')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    parser.error('This acceptance helper targets emulators only.')
adb = [r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe', '-s', args.serial]
assert subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu']).strip() == b'1'
command = ['shell', 'am', 'instrument', '-w', '-r']
if args.seed:
    command += ['-e', 'seed', 'true']
command += ['com.example.linesight_flutter.test/com.linesight.acceptance.StorageAuditInstrumentation']
result = subprocess.run(adb + command, capture_output=True, timeout=90)
result.check_returncode()
lines = result.stdout.decode('utf-8', errors='replace').splitlines()
reports = [line.split('LINESIGHT_STORAGE_AUDIT=', 1)[1] for line in lines if 'LINESIGHT_STORAGE_AUDIT=' in line]
if len(reports) != 1:
    raise RuntimeError('Native storage audit failed; no report was accepted.')
report = json.loads(reports[0])
assert report['package'] == 'com.example.linesight_flutter'
assert report['probe_exists']
assert all(value['integrity'] == 'ok' for value in report['databases'].values())
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'version': report['version_name'], 'code': report['version_code'],
                  'persistent_files': len(report['persisted_files']),
                  'databases': len(report['databases']), 'output': str(args.output)}))

"""Preserved-data signed APK upgrade; capture genuine demo/session evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ADB = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']

def run(*args):
    return subprocess.check_output(ADB + list(args), timeout=60).decode(errors='replace')

def package():
    text = run('shell', 'dumpsys', 'package', 'com.example.linesight_flutter')
    return {'version_code': int(re.search(r'versionCode=(\d+)', text)[1]),
            'version_name': re.search(r'versionName=(\S+)', text)[1],
            'first_install_time': re.search(r'firstInstallTime=([^\r\n]+)', text)[1].strip(),
            'last_update_time': re.search(r'lastUpdateTime=([^\r\n]+)', text)[1].strip()}

def ui(action, value=None):
    command = [sys.executable, str(ROOT / 'tool/release_android_ui.py'), action]
    if value: command.append(value)
    if action == 'capture': command += ['--batch', args.batch]
    return subprocess.check_output(command, cwd=ROOT, timeout=60).decode('utf-8', errors='replace')

def demo():
    text = ui('inspect')
    assert all(label in text for label in ['演示团队', '待质检 13', '异常处理中 3', '已关闭 13'])
    return {'workspace': '演示团队', 'awaiting': 13, 'exception': 3, 'closed': 13}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=['baseline', 'install', 'record'])
parser.add_argument('--track', choices=['production', 'preview'], default='production')
parser.add_argument('--batch', default='upgrade75-batch')
parser.add_argument('--first', type=int, default=404)
args = parser.parse_args()
assert re.fullmatch(r'upgrade[0-9]+-batch', args.batch)
OUT = ROOT / 'docs/product/linesight/acceptance' / args.batch
OUT.mkdir(parents=True, exist_ok=True)
expected_avd = 'LineSightProductionFreshValidation' if args.track == 'production' else 'LineSightApi34Validation'
assert run('emu', 'avd', 'name').splitlines()[0] == expected_avd
prefix = args.batch.removesuffix('-batch')
if args.action == 'baseline':
    assert not (OUT / 'before.json').exists()
    before = {'package': package(), 'demo': demo()}
    assert before['package']['version_code'] == 8078
    ui('capture', f'{args.first}-{prefix}-before-emulator')
    (OUT / 'before.json').write_text(json.dumps(before, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'baseline_recorded': True, 'version': 8078, 'demo_tasks': 29}))
else:
    before = json.loads((OUT / 'before.json').read_text(encoding='utf-8'))
    if args.action == 'install':
        assert package() == before['package']
        apk = ROOT / f'.artifact-work/release/LineSight-1.1.55-8079-{args.track}.apk'
        receipt = 'docs/product/linesight/acceptance/privacy73-batch/candidate-production.json' if args.track == 'production' else '.artifact-work/sso/privacy74-preview-native-logs.json'
        candidate = json.loads((ROOT / receipt).read_text())
        assert hashlib.sha256(apk.read_bytes()).hexdigest() == candidate['apk_sha256']
        result = subprocess.run(ADB + ['install', '-r', str(apk)], capture_output=True, timeout=150)
        assert result.returncode == 0 and b'Success' in result.stdout, 'Preserved-data installation did not succeed'
        after = package()
        assert after['version_code'] == 8079
        assert after['first_install_time'] == before['package']['first_install_time']
        (OUT / 'installed.json').write_text(json.dumps(after, indent=2) + '\n')
        print(json.dumps({'preserved_data_upgrade_installed': True, 'version': 8079,
                          'first_install_time_unchanged': True}))
    else:
        after = package()
        assert after['version_code'] == 8079 and after['version_name'] == '1.1.55'
        assert after['first_install_time'] == before['package']['first_install_time']
        assert demo() == before['demo']
        ui('capture', f'{args.first + 2}-{prefix}-demo-retained-emulator')
        result = {'track': args.track, 'before': before, 'after_package': after,
                  'demo_session_and_29_task_counts_retained': True, 'data_cleared': False,
                  'uninstall_used': False, 'browser_login_callback_verified': False,
                  'preview_upgrade_verified': args.track == 'preview', 'ota_crash_guard_reverified': False}
        (OUT / 'upgrade.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({'upgrade_navigation_and_session_passed': True, 'track': args.track}))

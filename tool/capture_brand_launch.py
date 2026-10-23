"""Capture a normal release cold launch using adb, preserving installed app data."""
import hashlib
import json
import subprocess
import time
from pathlib import Path

adb = Path(r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe')
release = Path(r'C:\Users\29668\LineSight-releases\1.1.20')
apk = release / 'LineSight-1.1.20-x86_64.apk'
package = 'com.example.linesight_flutter'
commands = [str(adb), '-s', 'emulator-5554']

def run(*args):
    return subprocess.check_output(commands + list(args), text=True, encoding='utf-8', errors='replace')

before = run('shell', 'cmd', 'package', 'list', 'packages', '-U', package).strip()
installed = run('install', '-r', str(apk))
assert 'Success' in installed
after = run('shell', 'cmd', 'package', 'list', 'packages', '-U', package).strip()
assert before == after
(release / 'reports/release-install.txt').write_text(installed + before + '\n' + after, encoding='utf-8')
run('shell', 'am', 'force-stop', package)
record = subprocess.Popen(commands + ['shell', 'screenrecord', '--bit-rate', '6000000', '--time-limit', '16', '/sdcard/linesight-brand-1.1.20.mp4'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
time.sleep(.8)
launch = run('shell', 'am', 'start', '-W', '-n', f'{package}/.MainActivity')
record.wait(timeout=24)
assert record.returncode == 0, record.stderr.read().decode(errors='replace')
run('pull', '/sdcard/linesight-brand-1.1.20.mp4', str(release / 'cold-start.mp4'))
(release / 'reports/cold-launch.txt').write_text(launch, encoding='utf-8')
pid = run('shell', 'pidof', package).strip()
(release / 'reports/cold-launch-logcat.txt').write_text(run('logcat', '-d', '--pid', pid), encoding='utf-8')
screen = subprocess.check_output(commands + ['exec-out', 'screencap', '-p'])
(release / 'screenshots/release-login.png').write_bytes(screen)
installed_path = run('shell', 'pm', 'path', package).strip().removeprefix('package:')
pulled = release / 'reports/installed-base.apk'
run('pull', installed_path, str(pulled))
digest = hashlib.sha256(pulled.read_bytes()).hexdigest()
assert digest == hashlib.sha256(apk.read_bytes()).hexdigest()
assert 'Status: ok' in launch and 'LaunchState: COLD' in launch
report = {'uid_before': before, 'uid_after': after, 'package_retained': before == after,
          'installed_sha256': digest, 'installed_bytes_match': True, 'cold_launch': launch}
(release / 'reports/installed-release.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))

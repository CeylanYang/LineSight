"""Time a first launch on the dedicated fresh production AVD, without clearing data."""
import json
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
assert subprocess.check_output(adb + ['emu', 'avd', 'name']).splitlines()[0].strip() == b'LineSightProductionFreshValidation'
running = subprocess.run(adb + ['shell', 'pidof', 'com.example.linesight_flutter'], capture_output=True)
assert running.returncode in (0, 1) and not running.stdout.strip(), 'App already running; this would not prove first launch'
started = time.monotonic()
subprocess.run(adb + ['shell', 'am', 'start', '-n', 'com.example.linesight_flutter/.MainActivity'],
               capture_output=True, check=True, timeout=20)
observations = 0
while time.monotonic() - started < 45:
    state = subprocess.run([sys.executable, str(root / 'tool/release_android_ui.py'), 'inspect'],
                           cwd=root, capture_output=True, timeout=50)
    state.check_returncode()
    observations += 1
    text = state.stdout.decode('utf-8', errors='replace')
    if all(label in text for label in ['登录', '工作台', '我的']):
        elapsed = time.monotonic() - started
        assert elapsed < 45
        folder = root / 'docs/product/linesight/acceptance/startup64-batch'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'first-launch.json').write_text(json.dumps({
            'avd': 'LineSightProductionFreshValidation', 'first_launch_passed': True,
            'observed_seconds_until_navigation': round(elapsed, 2),
            'observation_count': observations, 'cold_relaunch_used': False,
            'app_data_cleared': False,
        }, indent=2) + '\n', encoding='utf-8')
        subprocess.run([sys.executable, str(root / 'tool/release_android_ui.py'),
                        'capture', '349-startup64-first-login-emulator', '--batch', 'startup64-batch'],
                       cwd=root, check=True, timeout=60)
        print(json.dumps({'first_launch_navigation_seconds': round(elapsed, 2)}))
        break
else:
    raise SystemExit('First production launch did not reach navigation within 45 seconds; do not mark acceptance passed.')

"""Capture preview candidate version and retained session after a cold start."""
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/upgrade77-batch'
ADB = str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe')


def ui(action, value=None):
    command = [sys.executable, 'tool/release_android_ui.py', action]
    if value:
        command.append(value)
    if action == 'capture':
        command += ['--batch', 'upgrade77-batch']
    return subprocess.check_output(command, cwd=ROOT, timeout=60).decode('utf-8')


result = json.loads((OUT / 'upgrade.json').read_text(encoding='utf-8'))
assert result['track'] == 'preview' and result['after_package']['version_code'] == 8079
ui('tap', '我的')
ui('swipe')
ui('tap', '应用更新')
text = ui('inspect')
assert 'LineSight 1.1.55' in text and '内容版本 5' in text
ui('capture', '423-upgrade77-version-emulator')
subprocess.run([ADB, '-s', 'emulator-5554', 'shell', 'am', 'force-stop',
                'com.example.linesight_flutter'], check=True, timeout=30)
ui('launch')
for attempt in range(8):
    text = ui('inspect')
    if all(s in text for s in ['演示团队', '待质检 13', '异常处理中 3', '已关闭 13']):
        break
    time.sleep(2)
else:
    raise AssertionError('Cold-start demo session not observed')
ui('capture', '424-upgrade77-coldstart-emulator')
result.update(cold_start_demo_session_retained=True, version_page_verified=True,
              version_page='LineSight 1.1.55 / 内容版本 5', runtime_gpu='host AMD Radeon 780M',
              public_release_changed=False)
(OUT / 'upgrade.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'preview_version_ui': True, 'cold_start_demo_retained': True}))

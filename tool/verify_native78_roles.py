"""Run four-role native navigation against disposable cloud identities."""
import json
from pathlib import Path
import subprocess
import sys
import time

import native_role69_browser as browser
import native_role69_accounts as accounts

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/roles78-batch'


def ui(action, value=None):
    cmd = [sys.executable, 'tool/release_android_ui.py', action]
    if value:
        cmd.append(value)
    return subprocess.check_output(cmd, cwd=ROOT, timeout=60).decode('utf-8')


def wait_for(label):
    for _ in range(12):
        text = ui('inspect')
        if label in text:
            return text
        time.sleep(2)
    raise AssertionError('Expected native page was not reached')


def logout():
    ui('tap', '我的')
    ui('swipe')
    ui('tap', '退出登录')
    ui('tap', '确认')
    wait_for('登录后查看任务与检验记录')


assert browser.run('emu', 'avd', 'name').splitlines()[0] == b'LineSightApi34Validation'
package = browser.run('shell', 'dumpsys', 'package', 'com.example.linesight_flutter')
assert b'versionCode=8079 ' in package
assert not accounts.STATE.exists(), 'Existing private identity state must be resolved first'
assert not OUT.exists(), 'Use a fresh batch rather than overwriting prior role evidence'
OUT.mkdir(parents=True)
completed = []
stage = 'prepare'
failed = None
try:
    accounts.prepare('roles78-batch')
    state = json.loads(accounts.STATE.read_text())
    logout()
    for role in ['owner', 'manager', 'operator', 'viewer']:
        stage = role + ':login'
        print(json.dumps({'stage': stage}), flush=True)
        ui('tap', '登录')
        wait_for('进入演示团队')
        ui('tap', '登录')
        for _ in range(12):
            current = browser.nodes()
            if all(any(n.get('resource-id') == name and n.get('class') == 'android.widget.EditText'
                       for n in current) for name in ['username', 'password']):
                break
            time.sleep(2)
        else:
            raise AssertionError('Hosted credential fields did not load')
        subprocess.run([sys.executable, 'tool/native_role69_browser.py', 'fill', role],
                       cwd=ROOT, check=True, timeout=90)
        subprocess.run([sys.executable, 'tool/native_role69_browser.py', 'tap', 'kc-login'],
                       cwd=ROOT, check=True, timeout=60)
        wait_for('@' + state['people'][role]['username'])
        stage = role + ':pages'
        subprocess.run([sys.executable, 'tool/verify_native69_pages.py', role,
                        '--batch', 'roles78-batch', '--first', '430'],
                       cwd=ROOT, check=True, timeout=480)
        completed.append(role)
        stage = role + ':logout'
        logout()
        print(json.dumps({'completed_role': role}), flush=True)
except Exception as error:
    failed = type(error).__name__
    print(json.dumps({'failed_stage': stage, 'error_type': failed}), flush=True)
finally:
    if accounts.STATE.exists():
        accounts.remove()
    result = {'candidate_version_code': 8079, 'track': 'preview', 'completed_roles': completed,
              'all_four_roles_passed': len(completed) == 4 and failed is None,
              'failure_stage': stage if failed else None, 'failure_type': failed,
              'customer_data_modified': False, 'cleanup_evidence': 'cleanup.json',
              'raw_credentials_saved_in_evidence': False}
    (OUT / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
if failed:
    sys.exit(1)

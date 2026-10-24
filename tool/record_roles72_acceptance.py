"""Record actual widget results and disposable cleanup; native gate stays open."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/roles72-batch'
log = (ROOT / '.artifact-work/roles72-widget.log').read_text(encoding='utf-8-sig')
assert '+8: All tests passed!' in log
for language in ['en', 'zh']:
    for role in ['owner', 'manager', 'operator', 'viewer']:
        assert f'{language} {role} configuration and team route permissions at 360px' in log
cleanup = json.loads((OUT / 'cleanup.json').read_text())
assert cleanup['disposable_identity_accounts_deleted'] == 4
assert cleanup['disposable_api_users_deleted'] == 4
assert cleanup['disposable_workspaces_deleted'] == 5
assert cleanup['customer_teams_modified'] is False
assert not (Path.home() / 'LineSight-private/native-role69.json').exists()
adb = Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'
devices = subprocess.check_output([str(adb), 'devices']).decode()
assert 'emulator-' not in devices
(OUT / 'widget-tests.txt').write_text(log, encoding='utf-8')
result = {
    'widget_tests_passed': 8, 'languages': ['en', 'zh'], 'width': 360,
    'roles': ['owner', 'manager', 'operator', 'viewer'],
    'coverage': ['profile/template management controls', 'task creation entry permissions',
                 'configuration and template task-form return routes',
                 'team invitation and member menu permissions', 'zero submitted mutations'],
    'test_sha256': hashlib.sha256((ROOT / 'test/cloud_role_navigation_test.dart').read_bytes()).hexdigest(),
    'native_roles_complete': False,
    'native_attempt': 'Same preserved AVD booted; emulator and QEMU host processes disappeared before hosted login. Cause undetermined.',
    'emulators_connected_after_attempt': False, 'cleanup': cleanup,
    'app_code_or_apk_changed': False,
}
(OUT / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'widget_tests_passed': 8, 'native_roles_complete': False, 'cleanup_verified': True}))

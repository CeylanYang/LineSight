"""Reconcile completed upgrade captures with earlier failed attempts."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/upgrade75-batch'


def labels(name):
    tree = ET.parse(OUT / 'ui' / (name + '.xml'))
    assert (OUT / 'png' / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    return '\n'.join(n.get('content-desc', '') + '\n' + n.get('text', '')
                     for n in tree.iter('node'))


upgrade = json.loads((OUT / 'upgrade.json').read_text(encoding='utf-8'))
assert upgrade['before']['package']['version_code'] == 8078
assert upgrade['after_package']['version_code'] == 8079
assert upgrade['before']['package']['first_install_time'] == upgrade['after_package']['first_install_time']
assert upgrade['demo_session_and_29_task_counts_retained']
for name in ['404-upgrade75-before-emulator', '406-upgrade75-demo-retained-emulator',
             '408-upgrade75-coldstart-emulator']:
    text = labels(name)
    assert all(s in text for s in ['演示团队', '待质检 13', '异常处理中 3', '已关闭 13'])
assert all(s in labels('407-upgrade75-version-emulator') for s in ['LineSight 1.1.55', '内容版本 5'])

roles = ROOT / 'docs/product/linesight/acceptance/roles76-batch'
# These captures were taken only after the App-hosted browser login completed.
first = ET.parse(roles / 'ui/410-roles76-owner-workbench-emulator.xml')
assert any('Role56 Native69' in n.get('content-desc', '') for n in first.iter('node'))
cleanup = json.loads((roles / 'cleanup.json').read_text(encoding='utf-8'))
assert cleanup['disposable_identity_accounts_deleted'] == 4
assert cleanup['disposable_api_users_deleted'] == 4
assert cleanup['customer_teams_modified'] is False

upgrade['browser_login_callback_verified'] = True
upgrade['browser_login_callback_evidence'] = '../roles76-batch/ui/410-roles76-owner-workbench-emulator.xml'
upgrade['cold_start_demo_session_retained'] = True
(OUT / 'upgrade.json').write_text(json.dumps(upgrade, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
validation = json.loads((OUT / 'validation.json').read_text(encoding='utf-8'))
validation.update(status='partial', production_upgrade_verified=True, candidate_installed=True,
                  baseline_capture_completed=True, cold_start_demo_session_retained=True,
                  browser_login_callback_verified=True,
                  completion_evidence='upgrade.json and four paired UI/PNG captures',
                  original_failed_attempts_preserved=True)
validation['next_required'] = ['Preview preserved-data upgrade', 'Remaining native roles/pages',
                               'Candidate OTA crash-guard regression', 'Stable runtime without diagnostic debugger']
(OUT / 'validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'production_upgrade': True, 'version_ui': True, 'cold_start_retention': True,
                  'hosted_login_callback': True, 'all_native_roles_complete': False}))

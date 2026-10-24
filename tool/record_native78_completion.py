"""Verify role evidence completeness and supplement preview upgrade receipt."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/roles78-batch'
result = json.loads((OUT / 'validation.json').read_text(encoding='utf-8'))
assert result['all_four_roles_passed']
assert result['completed_roles'] == ['owner', 'manager', 'operator', 'viewer']
for role in result['completed_roles']:
    page = json.loads((OUT / (role + '-pages.json')).read_text(encoding='utf-8'))
    assert page['role'] == role and page['native_hosted_login_identity_verified']
    assert page['return_to_profile_verified'] and page['workspace_selected']
    assert page['task_creation_control'] == (role != 'viewer')
    assert page['production_configuration_controls'] == (role in ['owner', 'manager'])
    assert page['invite_and_member_menu'] == (role == 'owner')
    assert page['task_or_template_submitted'] is False
    assert len(page['screenshots']) == 6
    for name in page['screenshots']:
        assert (OUT / 'png' / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        assert ET.parse(OUT / 'ui' / (name + '.xml')).getroot().tag == 'hierarchy'
cleanup = json.loads((OUT / 'cleanup.json').read_text())
assert cleanup['disposable_identity_accounts_deleted'] == 4
assert cleanup['disposable_api_users_deleted'] == 4
assert cleanup['disposable_workspaces_deleted'] == 5
assert cleanup['customer_teams_modified'] is False
upgrade_path = ROOT / 'docs/product/linesight/acceptance/upgrade77-batch/upgrade.json'
upgrade = json.loads(upgrade_path.read_text(encoding='utf-8'))
assert upgrade['track'] == 'preview'
assert upgrade['after_package']['version_code'] == 8079
upgrade.update(browser_login_callback_verified=True,
               browser_login_callback_evidence='../roles78-batch/validation.json')
upgrade_path.write_text(json.dumps(upgrade, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'native_roles': 4, 'paired_page_captures': 24, 'cleanup_verified': True,
                  'preview_callback': True, 'all_secondary_pages_verified': False}))

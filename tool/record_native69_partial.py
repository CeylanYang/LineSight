"""Validate retained native owner evidence without claiming four-role completion."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'docs/product/linesight/acceptance/roles69-batch'
CHECKS = {
    378: ['@native69-f3e70fc5a1-owner', 'Role56 Native69 f3e70fc5a1'],
    379: ['生成邀请码', '显示菜单'],
    380: ['新建任务'],
    381: ['创建打印配置'],
    382: ['复制打印配置', '使用此配置创建任务'],
    383: ['发布检查模板'],
}
records = []
for number, labels in CHECKS.items():
    paths = list((FOLDER / 'ui').glob(str(number) + '-*.xml'))
    assert len(paths) == 1
    xml = paths[0]
    tree = ET.parse(xml)
    nodes = list(tree.iter('node'))
    for label in labels:
        matches = [n for n in nodes if label in
                   [n.get('text')] + n.get('content-desc', '').split('\n')]
        assert matches, (number, label)
        if number != 378:
            assert any(n.get('enabled') == 'true' and n.get('clickable') == 'true'
                       for n in matches), (number, label)
    png = FOLDER / 'png' / (xml.stem + '.png')
    assert png.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    records.append({'capture': xml.stem, 'verified_labels': labels,
                    'xml_sha256': hashlib.sha256(xml.read_bytes()).hexdigest(),
                    'png_sha256': hashlib.sha256(png.read_bytes()).hexdigest()})
cleanup = json.loads((FOLDER / 'cleanup.json').read_text())
assert cleanup['disposable_identity_accounts_deleted'] == 4
assert cleanup['disposable_api_users_deleted'] == 4
assert cleanup['disposable_workspaces_deleted'] == 5
assert cleanup['customer_teams_modified'] is False
result = {
    'status': 'partial', 'role': 'owner',
    'login_method': 'App secondary login, hosted Keycloak and AppAuth callback',
    'evidence': records, 'cleanup': cleanup,
    'interruption': 'Emulator host exited twice; subsequent adb reported offline. Cause undetermined.',
    'remaining': ['owner template detail and return path', 'manager pages',
                  'operator pages', 'viewer pages', 'native live revocation'],
    'all_roles_passed': False,
}
(FOLDER / 'partial-validation.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'retained_captures_validated': len(records),
                  'all_roles_passed': False, 'temporary_accounts_cleaned': True}))

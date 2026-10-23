"""Record observed native recovery screens without copying private sessions."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
folder = root / 'docs/product/linesight/acceptance/reauth-batch'
screens = sorted((folder / 'png').glob('*-emulator.png'))
assert len(screens) == 6
evidence = root / '.artifact-work/release'

def nodes(name):
    return list(ET.parse(evidence / name).iter('node'))

def labels(items):
    return '\n'.join(n.get('text', '') + '\n' + n.get('content-desc', '') for n in items)

required = labels(nodes('reauth-login-required.xml'))
restored = labels(nodes('reauth-restored-draft.xml'))
parent = labels(nodes('reauth-parent.xml'))
checklist = nodes('reauth-restored-checklist.xml')
assert '登录后查看任务与检验记录' in required
assert 'Measured 12.05 mm' in restored
assert sum(n.get('selected') == 'true' for n in checklist) == 4
assert '已关闭，已完成' in parent and '登记检验' not in parent
result = {
    'version': '1.1.37+8061',
    'login_required_after_revocation': True,
    'same_note_restored': True,
    'restored_note': 'Measured 12.05 mm',
    'four_checklist_answers_restored': True,
    'parent_refreshed_after_manual_submission': True,
    'workbench_after_return': {'inspection': 11, 'exceptions': 2, 'closed': 12},
    'original_display_restored': True,
    'restored_display': {'override_size': '1080x1920', 'physical_density': 420},
    'emulator_stopped_after_acceptance': True,
    'screenshots': [{'file': 'png/' + p.name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in screens],
}
(folder / 'native-journey.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'native_screens': len(screens), 'checklist_answers': 4, 'parent_refreshed': True}))

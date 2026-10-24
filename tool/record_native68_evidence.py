"""Archive only the exact native exit/control records and bounded UI evidence."""
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / 'docs/product/linesight/acceptance/native68-batch'
    receipt = json.loads((folder / 'validation.json').read_text())
    text = (root / '.artifact-work/native68-exit-info.txt').read_text(encoding='utf-8')
    records = re.split(r'(?=\s*ApplicationExitInfo #)', text)
    crash = next(record for record in records if re.search(r'\bpid=' + str(receipt['crashed_pid']) + r'\b', record))
    assert 'reason=5 (APP CRASH(NATIVE))' in crash and 'status=11' in crash
    control = next(record for record in records if 'reason=10 (USER REQUESTED)' in record and 'FORCE STOP' in record)
    result = {'crash_exit': [line.strip() for line in crash.splitlines() if 'timestamp=' in line or 'process=' in line],
              'normal_close_control_exit': [line.strip() for line in control.splitlines() if 'timestamp=' in line or 'process=' in line],
              'screens': []}
    for name in ['376-native68-patched-emulator', '377-native68-recovered-emulator']:
        picture = folder / 'png' / (name + '.png')
        hierarchy = folder / 'ui' / (name + '.xml')
        with Image.open(picture) as loaded:
            assert loaded.size == (412, 824)
        tree = ET.parse(hierarchy)
        labels = '\n'.join(node.get('text', '') + node.get('content-desc', '') for node in tree.iter('node'))
        assert all(label in labels for label in ['工作台', '检测记录', '配方中心', '我的'])
        result['screens'].append({'name': name, 'png_sha256': hashlib.sha256(picture.read_bytes()).hexdigest(),
                                  'xml_sha256': hashlib.sha256(hierarchy.read_bytes()).hexdigest()})
    (folder / 'exit-and-ui-evidence.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'exact_pid_exit_verified': receipt['crashed_pid'], 'screens_checked': 2}))


if __name__ == '__main__':
    main()

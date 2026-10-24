"""Operate only observed Android browser controls; keep credentials out of output."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import uuid
import xml.etree.ElementTree as ET

ADB = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']


def run(*parts):
    result = subprocess.run(ADB + list(parts), capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError('Android UI command failed; command arguments suppressed')
    return result.stdout


def tap(node):
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds'))))
    x1, y1, x2, y2 = bounds
    run('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))


def nodes():
    remote = '/sdcard/native-role69-' + uuid.uuid4().hex + '.xml'
    try:
        run('shell', 'uiautomator', 'dump', remote)
        return list(ET.fromstring(run('exec-out', 'cat', remote)).iter('node'))
    finally:
        run('shell', 'rm', '-f', remote)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'tap', 'fill'])
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    assert run('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    current = nodes()
    if args.action == 'inspect':
        for node in current:
            label = node.get('text') or node.get('content-desc')
            if label:
                if node.get('password') == 'true':
                    label = '<password field>'
                elif '://' in label or '/realms/' in label:
                    label = '<address omitted>'
                print(node.get('class'), node.get('resource-id'), node.get('bounds'), label[:100])
    elif args.action == 'tap':
        matches = [node for node in current if args.value in [node.get('text'), node.get('content-desc'), node.get('resource-id')]]
        assert matches, 'Observed action missing'
        tap(next((node for node in matches if node.get('clickable') == 'true'), matches[0]))
    else:
        assert args.value in ['owner', 'manager', 'operator', 'viewer']
        state = json.loads((Path.home() / 'LineSight-private/native-role69.json').read_text())
        assert state.get('prepared')
        person = state['people'][args.value]
        for name in ['username', 'password']:
            current = nodes()
            fields = [node for node in current if node.get('resource-id') == name and node.get('class') == 'android.widget.EditText']
            assert len(fields) == 1, 'Observed credential field missing: ' + name
            if name == 'password':
                assert fields[0].get('password') == 'true'
            tap(fields[0])
            run('shell', 'input', 'keyevent', '123')
            # Fresh hosted form must be empty; never select/copy saved passwords.
            assert not fields[0].get('text'), 'Hosted credential field is already populated'
            run('shell', 'input', 'text', person[name])
        run('shell', 'input', 'keyevent', '4')
        print(json.dumps({'filled_role': args.value, 'credentials_printed': False}))


if __name__ == '__main__':
    main()

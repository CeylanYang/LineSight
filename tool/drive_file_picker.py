"""Drive the Android system picker for integration_test/file_roundtrip_test.dart.

Run alongside the Flutter test, with its output redirected to build/file-roundtrip.log.
Only interacts with the emulator's DocumentsUI and the test's generated filenames.
"""
import os
import argparse
import re
import subprocess
import time
from pathlib import Path
from xml.etree import ElementTree as ET

ADB = str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe')
parser = argparse.ArgumentParser()
parser.add_argument('--log', default='build/file-roundtrip.log')
parser.add_argument('--timeout', type=int, default=480,
                    help='Workflow deadline in seconds, including app build/start')
options = parser.parse_args()
if options.timeout < 30:
    parser.error('--timeout must be at least 30 seconds')
LOG = Path(options.log)

def adb(*args):
    return subprocess.check_output([ADB, '-s', 'emulator-5554', *args], timeout=15)

def nodes():
    result = adb('shell', 'uiautomator', 'dump', '/sdcard/linesight-picker.xml')
    if b'dumped to' not in result:
        return []  # Never act on a stale tree after an Android dump failure.
    return list(ET.fromstring(adb('shell', 'cat', '/sdcard/linesight-picker.xml')).iter('node'))

def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))

handled = set()
delayed = set()
deadline = time.monotonic() + options.timeout
while time.monotonic() < deadline:
    content = LOG.read_text(encoding='utf-8', errors='replace') if LOG.exists() else ''
    stages = re.findall(r'PICKER_STAGE:(\w+)(?::([^\r\n]+))?', content)
    if not stages:
        time.sleep(1)
        continue
    stage, filename = stages[-1]
    if stage == 'DONE':
        print('Native picker workflow completed.', flush=True)
        break
    if stage in handled:
        time.sleep(1)
        continue
    window = nodes()
    native = [n for n in window if 'documentsui' in n.attrib.get('package', '')]
    if not native:
        time.sleep(1)
        continue
    if stage == 'CANCEL':
        adb('shell', 'input', 'keyevent', '4')
        handled.add(stage)
    elif stage.startswith('SAVE'):
        save = next((n for n in native if n.attrib.get('text', '').upper() in ('SAVE', '保存') and n.attrib.get('enabled') == 'true'), None)
        if save is not None:
            if stage == 'SAVE_LOCKED':
                print('Keeping the native picker open for 35 seconds.', flush=True)
                time.sleep(35)
                # Re-read the actual button bounds before acting.
                save = None
                retry_until = time.monotonic() + 20
                while save is None and time.monotonic() < retry_until:
                    save = next((n for n in nodes() if n.attrib.get('text', '').upper() in ('SAVE', '保存') and n.attrib.get('enabled') == 'true'), None)
                if save is None:
                    raise RuntimeError('Unable to locate the live save button after locking.')
            tap(save)
            handled.add(stage)
    elif stage.startswith('OPEN'):
        item = next((n for n in native if n.attrib.get('text') == filename and n.attrib.get('class') == 'android.widget.TextView' and n.attrib.get('enabled') == 'true'), None)
        if item is not None:
            if stage == 'OPEN_LOCKED' and stage not in delayed:
                print('Keeping the open picker active for 35 seconds.', flush=True)
                time.sleep(35)
                delayed.add(stage)
                # The prior XML belongs to an earlier frame; re-find the item.
                continue
            tap(item)
            handled.add(stage)
        else:
            downloads = next((n for n in native if n.attrib.get('text') in ('Downloads', '下载')), None)
            if downloads is not None:
                tap(downloads)
    print(f'Picker phase: {stage}; handled: {stage in handled}', flush=True)
    time.sleep(1)
else:
    raise SystemExit('Picker automation timed out; inspect the test log and native UI.')

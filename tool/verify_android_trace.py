"""Exercise external Android task links against the installed normal app."""
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

adb = r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe'
package = 'com.example.linesight_flutter'
folder = Path('docs/product/linesight/acceptance/trace-batch')
link = 'linesight://task/5/af04e1fb-168c-465e-b77a-fec1d1854653'

def run(*args):
    return subprocess.check_output([adb, '-s', 'emulator-5554', *args], timeout=25)

def ui():
    result = run('shell', 'uiautomator', 'dump', '/sdcard/linesight-trace.xml')
    if b'UI hier' not in result:
        raise ValueError('Android semantics not ready')
    return ET.fromstring(run('exec-out', 'cat', '/sdcard/linesight-trace.xml'))

def labels(root):
    return [node.get('text', '')+'\n'+node.get('content-desc', '') for node in root.iter('node')]

def wait(text):
    deadline = time.monotonic()+45
    while time.monotonic() < deadline:
        try:
            root = ui()
        except (ValueError, ET.ParseError, subprocess.CalledProcessError):
            time.sleep(1)
            continue
        if any(text in value for value in labels(root)):
            return root
        time.sleep(1)
    raise AssertionError('Android screen missing '+text)

def tap(root, text):
    matches = [node for node in root.iter('node') if text in (node.get('text',''), node.get('content-desc',''))]
    if not matches:
        matches = [node for node in root.iter('node') if text in node.get('content-desc','').split('\n')]
    assert matches, text
    clickable = [node for node in matches if node.get('clickable') == 'true']
    node = (clickable or matches)[-1]
    x1,y1,x2,y2 = map(int,re.findall(r'\d+',node.get('bounds')))
    run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))

def capture(name):
    (folder/'png'/f'{name}.png').write_bytes(run('exec-out','screencap','-p'))

def start(uri):
    run('shell','am','start','-a','android.intent.action.VIEW','-d',uri,package)

run('shell','am','force-stop',package)
start(link)
root = wait('登录后查看任务与检验记录')
assert not any('DEMO · 证据与数量批次验收' in value for value in labels(root))
capture('49-normal-cold-link-login-gate')
tap(root,'登录')
root = wait('进入演示团队')
tap(root,'进入演示团队')
root = wait('DEMO · 证据与数量批次验收')
capture('50-normal-external-link-authorized-task')
start(link)
wait('DEMO · 证据与数量批次验收')
start(link.replace('/5/','/999999/'))
root = wait('当前账户无法访问该任务')
assert not any('DEMO · 证据与数量批次验收' in value for value in labels(root))
capture('51-normal-warm-link-membership-denied')
print(json.dumps({'cold_external_login_gate':True,'normal_demo_login_to_task':True,'warm_external_task':True,'warm_external_membership_denied':True}))

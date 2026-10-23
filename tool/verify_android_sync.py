"""Verify a normal main APK upgrade without uninstalling or clearing app data."""
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

adb=r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe'
package='com.example.linesight_flutter'
folder=Path('docs/product/linesight/acceptance/sync-batch')
job=json.loads((folder/'android-journey.json').read_text())['job_id']
def run(*args):
    return subprocess.check_output([adb,'-s','emulator-5554',*args],timeout=40)
def version():
    data=run('shell','dumpsys','package',package).decode()
    return int(re.search(r'versionCode=(\d+)',data)[1])
def uid():
    return re.search(r'uid:(\d+)',run('shell','pm','list','packages','-U',package).decode())[1]
def ui():
    output=run('shell','uiautomator','dump','/sdcard/linesight-sync-normal.xml')
    if b'UI hier' not in output: raise ValueError('Semantics not ready')
    return ET.fromstring(run('exec-out','cat','/sdcard/linesight-sync-normal.xml'))
def labels(root):
    return [node.get('text','')+'\n'+node.get('content-desc','') for node in root.iter('node')]
def wait(text,scroll=False):
    deadline=time.monotonic()+50
    while time.monotonic()<deadline:
        try:
            root=ui()
            if any(text in label for label in labels(root)): return root
            if scroll: run('shell','input','swipe','540','1510','540','720','350')
        except (ValueError,ET.ParseError,subprocess.CalledProcessError): pass
        time.sleep(1)
    raise AssertionError('Android screen missing '+text)
def tap(root,text):
    rows=[node for node in root.iter('node') if text in (node.get('text',''),node.get('content-desc',''))]
    if not rows: rows=[node for node in root.iter('node') if text in node.get('content-desc','').split('\n')]
    assert rows,text
    clickable=[node for node in rows if node.get('clickable')=='true']
    node=(clickable or rows)[-1]
    x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
    run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
def capture(name):
    (folder/'png'/f'{name}.png').write_bytes(run('exec-out','screencap','-p'))
def launch():
    run('shell','am','force-stop',package)
    run('shell','am','start','-n',package+'/.MainActivity')

before,previous_uid=version(),uid()
assert before==8039,before
result=run('install','-r','.artifact-work/sso/sync8040.apk')
assert b'Success' in result,result
assert version()==8040
assert uid()==previous_uid
launch()
root=wait('登录')
tap(root,'登录')
root=wait('进入演示团队')
tap(root,'进入演示团队')
root=wait('演示团队')
tap(root,'我的')
root=wait('同步与草稿',scroll=True)
tap(root,'同步与草稿')
root=wait(job,scroll=True)
assert any('已上传，待关联检验' in label for label in labels(root))
capture('60-normal-upgrade-receipt-preserved')
tap(root,'同步诊断')
wait('连接正常')
capture('61-normal-main-sync-diagnostics')
launch()
wait('演示团队')
capture('62-normal-cold-session-restored')
output={'before_version':before,'after_version':8040,'package_uid_preserved':True,'normal_install_r_succeeded':True,'encrypted_outbox_receipt_preserved':True,'normal_diagnostics_connected':True,'normal_cold_session_restored':True,'uninstall_or_clear_used':False}
(folder/'normal-android.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps(output))

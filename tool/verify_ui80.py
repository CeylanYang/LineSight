"""Preserved-data upgrade and read-only UI smoke check on the dedicated emulator."""
import hashlib
import json
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/ui80-batch'
ADB = [r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe', '-s', 'emulator-5554']
APP = 'com.example.linesight_flutter'
APK = ROOT / '.artifact-work/release/LineSight-1.1.56-8080-production.apk'


def adb(*args):
    return subprocess.check_output(ADB + list(args), timeout=90)


def package():
    raw = adb('shell', 'dumpsys', 'package', APP).decode('utf-8')
    return {key: re.search(pattern, raw).group(1).strip() for key, pattern in {
        'version_code': r'versionCode=(\d+)',
        'version_name': r'versionName=([^\r\n]+)',
        'first_install_time': r'firstInstallTime=([^\r\n]+)',
    }.items()}


def dump():
    remote = f'/sdcard/linesight-ui80-{uuid.uuid4().hex}.xml'
    try:
        adb('shell', 'uiautomator', 'dump', remote)
        raw = adb('exec-out', 'cat', remote)
        return raw, ET.fromstring(raw)
    finally:
        adb('shell', 'rm', '-f', remote)


def matches(tree, label):
    return [n for n in tree.iter('node') if label in [n.get('text'), n.get('content-desc')]
            or label in n.get('content-desc', '').split('\n')]


def wait_for(*labels):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        try:
            raw, tree = dump()
        except (ET.ParseError, subprocess.CalledProcessError):
            time.sleep(1)
            continue
        if all(matches(tree, label) for label in labels):
            return raw, tree
        time.sleep(1)
    raise RuntimeError(f'Expected UI missing: {labels}')


def tap(label):
    _, tree = wait_for(label)
    nodes = matches(tree, label)
    selected = next((n for n in nodes if n.get('clickable') == 'true'), nodes[0])
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', selected.get('bounds')))
    adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))


def capture(name, *labels):
    raw, _ = wait_for(*labels)
    for folder in ['png', 'ui']:
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    (OUT / 'ui' / f'{name}.xml').write_bytes(raw)
    (OUT / 'png' / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    print(f'Captured {name}', flush=True)


def main():
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
    assert APK.is_file()
    navigation_resume = '--resume-navigation' in sys.argv
    resumed = '--resume-installed' in sys.argv or navigation_resume
    if resumed:
        upgrade = json.loads((OUT / 'upgrade.json').read_text(encoding='utf-8'))
        before, after = upgrade['before'], package()
        assert after == upgrade['after']
    else:
        before = package()
        assert before['version_code'] == '8079', 'Use the preserved 8079 production AVD'
        adb('shell', 'am', 'force-stop', APP)
        assert b'Success' in adb('install', '-r', str(APK))
        after = package()
    assert after['version_code'] == '8080'
    assert after['first_install_time'] == before['first_install_time']
    (OUT / 'upgrade.json').write_text(json.dumps({'before': before, 'after': after}, indent=2) + '\n', encoding='utf-8')
    adb('shell', 'am', 'start', '-n', f'{APP}/.MainActivity')
    if not navigation_resume:
        capture('460-ui80-login-emulator', '登录工作区', '登录', '刷卡登录', '进入演示团队')
        tap('进入演示团队')
        capture('461-ui80-workbench-emulator', '在线质检', '扫码追溯', '新建任务', '质量报告',
                '待检任务', '异常处理', '检测记录', '打印配置', '检查模板', '团队成员', '我的卡片', '同步与草稿')
    else:
        assert (OUT / 'ui/460-ui80-login-emulator.xml').is_file()
        assert (OUT / 'ui/461-ui80-workbench-emulator.xml').is_file()
    tap('生产')
    capture('462-ui80-production-emulator', '生产任务', '新建任务')
    _, tree = dump()
    assert any(n.get('class') == 'android.widget.EditText' for n in tree.iter('node'))
    tap('配置')
    capture('463-ui80-configuration-emulator', '打印配置', '检查模板')
    tap('检查模板')
    capture('464-ui80-templates-emulator', '检查模板')
    tap('质检')
    capture('465-ui80-inspection-emulator', '待检任务', '检测记录', '质量报告')
    tap('质量报告')
    capture('466-ui80-report-emulator', '导出与报告', '筛选范围')
    tap('我的')
    capture('467-ui80-my-emulator', '我的卡片', '账户与安全')
    tap('工作台')
    capture('468-ui80-return-emulator', '在线质检', '我的待办')
    receipt = {
        'version': '1.1.56+8080', 'content_revision': 6,
        'before': before, 'after': after,
        'apk_sha256': hashlib.sha256(APK.read_bytes()).hexdigest(),
        'install_mode': 'adb install -r', 'data_cleared': False,
        'demo_login_from_initial_panel': True, 'customer_account_used': False,
        'business_forms_submitted': False, 'paired_screenshots_xml': 9,
        'resumed_after_initial_ui_dump_failure': resumed,
        'navigation_resume_after_hint_text_not_exposed_in_semantics': navigation_resume,
        'scope': 'single Android API 34 x86_64 preserved emulator, navigation smoke check',
    }
    (OUT / 'native-validation.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'native_ui_check': 'passed', 'paired_captures': 9}), flush=True)


if __name__ == '__main__':
    main()

"""Native role-specific controls and return paths after real hosted login."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def ui(action, value=None):
    command = [sys.executable, str(ROOT / 'tool/release_android_ui.py'), action]
    if value:
        command.append(value)
    if action == 'capture':
        command += ['--batch', 'roles69-batch']
    return subprocess.check_output(command, cwd=ROOT, timeout=60).decode('utf-8', errors='replace')


def action(label, allowed):
    ui('inspect')
    tree = ET.parse(ROOT / '.artifact-work/release/current-window.xml')
    matches = [node for node in tree.iter('node') if label in
               [node.get('text')] + node.get('content-desc', '').split('\n')]
    assert bool(matches) == allowed, (label, allowed)
    if allowed:
        assert any(node.get('enabled') == 'true' and node.get('clickable') == 'true' for node in matches), label


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('role', choices=['owner', 'manager', 'operator', 'viewer'])
    parser.add_argument('--resume-template', action='store_true', help='Keep this run\'s existing first four page captures after host exit')
    args = parser.parse_args()
    role = args.role
    state = json.loads((Path.home() / 'LineSight-private/native-role69.json').read_text())
    folder = ROOT / 'docs/product/linesight/acceptance/roles69-batch'
    folder.mkdir(parents=True, exist_ok=True)
    first = 380 + ['owner', 'manager', 'operator', 'viewer'].index(role) * 6
    screenshots = []

    def capture(suffix, offset):
        name = str(first + offset) + '-roles69-' + role + '-' + suffix + '-emulator'
        ui('capture', name)
        screenshots.append(name)

    current = ui('inspect')
    for _ in range(4):
        if '我的' in current and '配方中心' in current:
            break
        ui('back')
        current = ui('inspect')
    ui('tap', '我的')
    current = ui('inspect')
    assert '@' + state['people'][role]['username'] in current, 'Wrong signed-in identity'
    if state['team_name'] not in current:
        ui('tap', '工作区')
        ui('tap', state['team_name'])
    current = ui('inspect')
    assert state['team_name'] in current
    if args.resume_template:
        for offset, suffix in enumerate(['workbench', 'profiles', 'profile-detail', 'templates']):
            name = str(first + offset) + '-roles69-' + role + '-' + suffix + '-emulator'
            assert (folder / 'ui' / (name + '.xml')).is_file()
            screenshots.append(name)
        ui('tap', '配方中心')
        ui('tap', '检查模板')
    else:
        ui('tap', '工作台')
        action('新建任务', role != 'viewer')
        capture('workbench', 0)
        ui('tap', '配方中心')
        ui('tap', '打印配置')
        action('创建打印配置', role in ['owner', 'manager'])
        capture('profiles', 1)
        ui('tap', 'Bambu Lab A1')
        action('复制打印配置', role in ['owner', 'manager'])
        action('使用此配置创建任务', role != 'viewer')
        capture('profile-detail', 2)
        ui('back')
        ui('back')
        ui('tap', '检查模板')
        action('发布检查模板', role in ['owner', 'manager'])
        capture('templates', 3)
    ui('tap', '尺寸与装配检查')
    ui('swipe')
    action('复制模板', role in ['owner', 'manager'])
    action('使用此模板创建任务', role != 'viewer')
    capture('template-detail', 4)
    ui('back')
    ui('back')
    ui('tap', '我的')
    ui('tap', '团队成员')
    action('生成邀请码', role == 'owner')
    action('显示菜单', role == 'owner')
    capture('team', 5)
    ui('back')
    current = ui('inspect')
    assert '@' + state['people'][role]['username'] in current
    result = {'role': role, 'native_hosted_login_identity_verified': True,
              'workspace_selected': True, 'task_creation_control': role != 'viewer',
              'production_configuration_controls': role in ['owner', 'manager'],
              'invite_and_member_menu': role == 'owner', 'return_to_profile_verified': True,
              'task_or_template_submitted': False, 'screenshots': screenshots}
    result['resumed_template_after_host_exit'] = args.resume_template
    (folder / (role + '-pages.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'role_pages_passed': role, 'screenshots': len(screenshots)}))


if __name__ == '__main__':
    main()

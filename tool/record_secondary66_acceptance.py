"""Record the bounded production content4 secondary-page native acceptance."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageOps, ImageDraw


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / 'docs/product/linesight/acceptance/secondary66-batch'
    expected = {
        '353-secondary66-configuration-emulator': ['配方中心', '打印配置', '检查模板'],
        '354-secondary66-profile-detail-emulator': ['Bambu Lab A1', 'starter-v1', '使用此配置创建任务'],
        '355-secondary66-prefilled-create-emulator': ['新建任务', 'Bambu Lab A1', '尺寸与装配检查 · v1'],
        '356-secondary66-create-return-emulator': ['Bambu Lab A1', '使用此配置创建任务'],
        '357-secondary66-templates-emulator': ['检查模板', '3 个模板', '通用外观检查'],
        '358-secondary66-template-detail-emulator': ['尺寸与装配检查', '4 检查项', '允许不适用'],
        '359-secondary66-account-emulator': ['账户与安全', 'LineSight Demo', '我的卡片'],
        '360-secondary66-cards-emulator': ['我的卡片', '还没有绑定卡片'],
        '361-secondary66-nfc-unavailable-emulator': ['绑定卡片', '此手机不支持NFC', '取消'],
        '362-secondary66-nfc-cancel-return-emulator': ['我的卡片', '还没有绑定卡片'],
        '363-secondary66-local-import-gate-emulator': ['目标团队 · 演示团队', '授权读取记录', '授权并预览'],
        '364-secondary66-team-emulator': ['团队与权限', '1 名成员', '操作成员'],
        '365-secondary66-content4-emulator': ['LineSight 1.1.54', '内容版本 4', '已是最新内容'],
        '366-secondary66-final-workbench-emulator': ['演示团队', '待质检 13', '异常处理中 3', '已关闭 13'],
    }
    records = []
    sheet = Image.new('RGB', (4 * 206, 4 * 436), 'white')
    draw = ImageDraw.Draw(sheet)
    for index, (name, labels) in enumerate(expected.items()):
        xml = folder / 'ui' / (name + '.xml')
        tree = ET.parse(xml)
        text = '\n'.join(node.get('text', '') + node.get('content-desc', '') for node in tree.iter('node'))
        assert all(label in text for label in labels), (name, labels)
        if name.startswith('364-'):
            assert all(label not in text for label in ['生成邀请码', '移除成员', '修改角色'])
        picture = folder / 'png' / (name + '.png')
        with Image.open(picture) as loaded:
            assert loaded.size == (412, 824)
            sheet.paste(ImageOps.contain(loaded.convert('RGB'), (206, 412)),
                        ((index % 4) * 206, (index // 4) * 436 + 24))
        draw.text(((index % 4) * 206 + 5, (index // 4) * 436 + 4), name.split('-')[0], fill='black')
        records.append({'name': name, 'required_labels': labels,
                        'png_sha256': hashlib.sha256(picture.read_bytes()).hexdigest(),
                        'xml_sha256': hashlib.sha256(xml.read_bytes()).hexdigest()})
    sheet.save(root / '.artifact-work/secondary66-contact.png')
    adb = [str(Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'), '-s', 'emulator-5554']
    assert subprocess.check_output(adb + ['emu', 'avd', 'name']).splitlines()[0].strip() == b'LineSightProductionFreshValidation'
    package = subprocess.check_output(adb + ['shell', 'dumpsys', 'package', 'com.example.linesight_flutter'], text=True)
    installed = re.search(r'firstInstallTime=([^\r\n]+)', package)[1].strip()
    updated = re.search(r'lastUpdateTime=([^\r\n]+)', package)[1].strip()
    assert installed == updated == '2026-10-24 08:42:22'
    result = {'version': '1.1.54+8078', 'content_revision': 4, 'channel': 'production',
              'avd': 'LineSightProductionFreshValidation', 'first_install_time': installed,
              'last_update_time': updated, 'app_data_cleared': False, 'app_reinstalled': False,
              'team': 'independent demo', 'task_submitted': False,
              'all_roles_verified': False, 'real_nfc_verified': False,
              'emulator_host_exit_count': 1, 'host_exit_root_cause_proven': False,
              'checks': records}
    (folder / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'screens_checked': len(records), 'channel': 'production', 'content': 4}))


if __name__ == '__main__':
    main()

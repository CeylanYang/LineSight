"""Package only the selected UI release artifacts and public validation evidence."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = Path('D:/ENT207/deliverables/LineSight-1.1.56-ui')
EVIDENCE = ROOT / 'docs/product/linesight/acceptance/ui80-batch'


def main():
    native = json.loads((EVIDENCE / 'native-validation.json').read_text(encoding='utf-8'))
    assert native['after']['version_code'] == '8080'
    assert native['paired_screenshots_xml'] == 9
    regression = (ROOT / '.artifact-work/ui80-regression.log').read_text(encoding='utf-8')
    analyze = (ROOT / '.artifact-work/ui80-analyze-clean.log').read_text(encoding='utf-8')
    assert '+487: All tests passed!' in regression
    assert 'No issues found!' in analyze
    DEST.mkdir(parents=True, exist_ok=True)
    apks = []
    for track, expected in [
        ('production', '7bc771728f5192f22c58963cbe0fb99c446c0d878f9b2cbca495928b8d5dd6f7'),
        ('preview', 'f476feb19c3118cb6a0f47da2acaeb3614dce18f8e211b17b8f37a76dda17eba'),
    ]:
        source = ROOT / '.artifact-work/release' / f'LineSight-1.1.56-8080-{track}.apk'
        assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
        target = DEST / source.name
        if target.exists():
            assert hashlib.sha256(target.read_bytes()).hexdigest() == expected
        else:
            shutil.copy2(source, target)
        apks.append({'file': source.name, 'track': track, 'sha256': expected, 'bytes': target.stat().st_size})
        shutil.copy2(ROOT / f'.artifact-work/sso/ui80-{track}-native-logs.json', EVIDENCE / f'{track}-native-log-audit.json')
        shutil.copy2(ROOT / f'.artifact-work/sso/ui80-{track}-signature.log', EVIDENCE / f'{track}-signature.log')
    assert native['apk_sha256'] == apks[0]['sha256']
    shutil.copy2(ROOT / 'docs/product/linesight/UI_DELIVERY_20261024.md', DEST / '界面改动与验证.md')
    shutil.copy2(EVIDENCE / 'native-validation.json', DEST / 'native-validation.json')
    for source, name in [
        (ROOT / '.artifact-work/ui80-regression.log', 'flutter-regression.log'),
        (ROOT / '.artifact-work/ui80-analyze-clean.log', 'flutter-analyze.log'),
    ]:
        shutil.copy2(source, EVIDENCE / name)
    for folder in ['png', 'ui']:
        output = DEST / '模拟器截图' / folder
        output.mkdir(parents=True, exist_ok=True)
        for source in sorted((EVIDENCE / folder).glob('4*-ui80-*-emulator.*')):
            shutil.copy2(source, output / source.name)
    receipt = {
        'version': '1.1.56+8080', 'content_revision': 6,
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'flutter_tests_passed': 487, 'analyze_clean': True,
        'native_validation': native, 'apks': apks,
        'website_published_version': '1.1.54+8078',
        'website_and_public_ota_changed': False,
        'customer_credentials_included': False,
    }
    (DEST / 'delivery.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DEST / '安装说明.md').write_text('''# LineSight 1.1.56

本目录提供正式签名和早期预览签名兼容包，功能相同。已使用正式版本时安装 production；早期预览安装使用 preview 覆盖升级。保留现有应用数据，安装前请核对已有安装使用的签名轨道。

本轮调整登录入口、工作台宫格、生产/质检/配置导航及主要处理按钮。详细改动见《界面改动与验证.md》。模拟器截图对应正式签名包；组件测试另覆盖中英文和角色权限。

本目录是本地交付包。官网与公开 OTA 本轮未更新。
''', encoding='utf-8')
    print(json.dumps({'delivery': str(DEST), 'version': receipt['version'], 'verified_apks': len(apks)}, ensure_ascii=False))


if __name__ == '__main__':
    main()

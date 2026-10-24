"""Verify and package the two signed template-interaction delivery APKs."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = Path('D:/ENT207/deliverables/LineSight-1.1.57-templates')
EVIDENCE = ROOT / 'docs/product/linesight/acceptance/templates81-batch'


def main():
    regression = (ROOT / '.artifact-work/templates81-regression.log').read_text(encoding='utf-8')
    matches = re.findall(r'\+(\d+): All tests passed!', regression)
    assert matches and int(matches[-1]) == 495
    analyze = (ROOT / '.artifact-work/templates81-analyze.log').read_text(encoding='utf-8')
    assert 'No issues found!' in analyze
    DEST.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    artifacts = []
    for track, certificate in [
        ('production', '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2'),
        ('preview', '235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),
    ]:
        name = f'LineSight-1.1.57-8081-{track}.apk'
        source = ROOT / '.artifact-work/release' / name
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        signature = ROOT / f'.artifact-work/sso/templates81-{track}-signature.log'
        assert f'Signer #1 certificate SHA-256 digest: {certificate}' in signature.read_text(encoding='utf-8')
        audit_path = ROOT / f'.artifact-work/sso/templates81-{track}-native-logs.json'
        audit = json.loads(audit_path.read_text(encoding='utf-8'))
        assert audit['apk_sha256'] == digest and audit['direct_calls_absent'] is True
        target = DEST / name
        if target.exists():
            assert hashlib.sha256(target.read_bytes()).hexdigest() == digest
        else:
            shutil.copy2(source, target)
        artifacts.append({'file': name, 'sha256': digest, 'bytes': target.stat().st_size,
                          'certificate_sha256': certificate})
        shutil.copy2(signature, EVIDENCE / f'{track}-signature.log')
        shutil.copy2(audit_path, EVIDENCE / f'{track}-native-log-audit.json')
    for suffix, output in [('regression', 'flutter-regression.log'), ('analyze', 'flutter-analyze.log')]:
        shutil.copy2(ROOT / f'.artifact-work/templates81-{suffix}.log', EVIDENCE / output)
    validation_logs = DEST / '验证日志'
    validation_logs.mkdir(exist_ok=True)
    logs = []
    for name in ['flutter-regression.log', 'flutter-analyze.log', 'production-signature.log', 'preview-signature.log']:
        source = EVIDENCE / name
        shutil.copy2(source, validation_logs / name)
        logs.append({'file': name, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
    shutil.copy2(ROOT / 'docs/product/linesight/TEMPLATE_INTERACTION_20261024.md', DEST / '检查模板改动与验证.md')
    shots = DEST / '组件截图'
    shots.mkdir(exist_ok=True)
    for source in (EVIDENCE / 'png').glob('81-*.png'):
        shutil.copy2(source, shots / source.name)
    receipt = {
        'version': '1.1.57+8081', 'content_revision': 7,
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'flutter_tests_passed': 495, 'analyze_clean': True, 'apks': artifacts,
        'screenshots': 'Flutter component tests with test fixtures',
        'android_runtime_validation': 'not run: emulator launch rejected by automatic approval review',
        'automatic_review_reason': 'blocked by policy',
        'customer_credentials_included': False, 'website_and_public_ota_changed': False,
        'website_published_version': '1.1.54+8078',
        'validation_logs': logs,
    }
    validation = {key: value for key, value in receipt.items() if key != 'source_commit'}
    (EVIDENCE / 'validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DEST / 'delivery.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DEST / '安装说明.md').write_text('''# LineSight 1.1.57

正式版本使用 production 包覆盖升级；早期预览签名安装使用 preview 包。两个包功能相同，请选择与已有安装签名一致的包并保留应用数据。

进入“配置 → 检查模板”，可直接搜索、交互预览或用于任务。预览可选择检查结果、填写异常说明、重置和切换版本；编辑器顶部也可预览当前修改。

本目录是本地安装包交付，官网与公开 OTA 未更新。组件截图使用测试数据，本轮未取得模拟器或真机验收结论。
''', encoding='utf-8')
    print(json.dumps({'delivery': str(DEST), 'version': receipt['version'], 'verified_apks': len(artifacts)}, ensure_ascii=False))


if __name__ == '__main__':
    main()

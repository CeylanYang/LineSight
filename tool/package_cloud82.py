"""Package the reviewed cloud-content/report release and its verification receipts."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = Path('D:/ENT207/deliverables/LineSight-1.1.58-cloud')
EVIDENCE = ROOT / 'docs/product/linesight/acceptance/cloud82-batch'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    tests = (ROOT / '.artifact-work/cloud82-regression.log').read_text(encoding='utf-8')
    result = re.findall(r'\+(\d+): All tests passed!', tests)
    assert result and int(result[-1]) >= 501
    assert 'No issues found!' in (ROOT / '.artifact-work/cloud82-analyze.log').read_text(encoding='utf-8')
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    artifacts = []
    for track, certificate in [('production', '2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2'),
                               ('preview', '235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e')]:
        name = f'LineSight-1.1.58-8082-{track}.apk'
        source = ROOT / '.artifact-work/release' / name
        signature = ROOT / f'.artifact-work/sso/cloud82-{track}-signature.log'
        assert f'Signer #1 certificate SHA-256 digest: {certificate}' in signature.read_text(encoding='utf-8')
        audit_file = ROOT / f'.artifact-work/sso/cloud82-{track}-native-logs.json'
        audit = json.loads(audit_file.read_text(encoding='utf-8'))
        assert audit['apk_sha256'] == sha(source) and audit['direct_calls_absent'] is True
        shutil.copy2(source, DEST / name)
        shutil.copy2(signature, EVIDENCE / f'{track}-signature.log')
        shutil.copy2(audit_file, EVIDENCE / f'{track}-native-log-audit.json')
        artifacts.append({'file': name, 'sha256': sha(source), 'bytes': source.stat().st_size,
                          'certificate_sha256': certificate})
    for local, output in [('cloud82-regression.log','flutter-regression.log'),('cloud82-analyze.log','flutter-analyze.log'),('cloud82-backend.log','backend-tests.log')]:
        shutil.copy2(ROOT / '.artifact-work' / local, EVIDENCE / output)
    for source, name in [('appearance.pdf','LineSight-WI-QC-014.pdf'),('changeover.pdf','LineSight-CL-PR-006.pdf'),('quality-report.pdf','LineSight-quality-report-sample.pdf')]:
        shutil.copy2(ROOT / '.artifact-work/cloud82/pdf' / source, DEST / name)
    pdf_evidence = EVIDENCE / 'pdf-render'
    pdf_evidence.mkdir(exist_ok=True)
    for source in (ROOT / '.artifact-work/cloud82/pdf').glob('*-new-*.png'):
        shutil.copy2(source, pdf_evidence / source.name)
    for source in [ROOT / 'docs/product/linesight/CLOUD_CONTENT_20261024.md', ROOT / 'design/special/README.md']:
        shutil.copy2(source, DEST / source.name)
    logs = DEST / '验证日志'
    logs.mkdir(exist_ok=True)
    for source in EVIDENCE.glob('*.log'):
        shutil.copy2(source, logs / source.name)
    receipt = {'version': '1.1.58+8082', 'content_revision': 8,
        'source_commit': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'flutter_tests_passed': int(result[-1]), 'analyze_clean': True, 'backend_tests_passed': 5,
        'artifacts': artifacts, 'public_config_revision': 2,
        'pdf_visual_review': 'Both procedures one A4 page each; sample report three A4 pages; all pages rendered and reviewed.',
        'special_edition': 'Switch and isolated shell/workspace ready; full custom UI pending design.',
        'android_runtime_validation': 'Not run in this release; prior emulator launch was rejected by automatic approval review (blocked by policy).',
        'new_base_install_required': True, 'customer_credentials_included': False}
    (DEST / 'delivery.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (EVIDENCE / 'validation.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (DEST / '安装说明.md').write_text('''# LineSight 1.1.58

使用 production 包覆盖正式版；早期体验版使用 preview 包覆盖，保留应用数据。官网也提供这两种下载。

本次增加插件和内置文档字体，需要先安装一次新基础包；后续已支持的配置、模板和素材走云端下发，兼容 Dart 代码更新后台下载、下次冷启动生效。

设置中的「特供版」默认关闭，关闭为大字版；开启进入特供版容器。完整特供界面在独立工作区继续绘制。

进入「质检 → 作业文件」使用两份标准文档；记录详情可直接导出检验记录，质量报告页可保存 PDF、打印和导出 CSV。团队落款为 LineSight Inc. / LineSight 质量团队。

本轮通过组件、回归、PDF 渲染及公开 HTTPS 核验，尚未取得模拟器或真机运行验收。文件保存、打印、官网外部浏览器、相机与 NFC 需要设备验证。
''',encoding='utf-8')
    print(json.dumps({'delivery': str(DEST), 'version': receipt['version'], 'apks': len(artifacts)},ensure_ascii=False))


if __name__ == '__main__':
    main()

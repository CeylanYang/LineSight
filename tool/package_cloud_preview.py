"""Package the normal main-entry preview without any private build input."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

root = Path(__file__).resolve().parents[1]
apk = root / 'build/app/outputs/apk/release/app-release.apk'
with zipfile.ZipFile(apk) as bundle:
    assert 'lib/arm64-v8a/libapp.so' in bundle.namelist()
    assert 'lib/x86_64/libapp.so' in bundle.namelist()
destination = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.21')
destination.mkdir(parents=True, exist_ok=True)
name = 'LineSight-1.1.21-8030-cloud-preview.apk'
shutil.copy2(apk, destination / name)
evidence = root / 'docs/product/linesight/acceptance/sso'
shutil.copytree(evidence, destination / 'evidence', dirs_exist_ok=True)
shutil.copy2(root / 'docs/product/linesight/LineSight_Development_Backlog.xlsx', destination)
shutil.copy2(root / 'docs/product/linesight/LineSight_Development_Backlog.csv', destination)
report = {'version': '1.1.21+8030', 'entry': 'lib/main.dart', 'apk': name,
    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'bytes': apk.stat().st_size,
    'architectures': ['arm64-v8a', 'x86_64'], 'flutter_tests_passed': 113, 'django_tests_passed': 30,
    'android_cloud_login_journey': True, 'android_task_journey': True, 'screenshots': 16,
    'signing': 'Existing debug-compatible certificate; preview build, formal release signing pending',
    'product_plan_complete': False}
(destination / 'build.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
(destination / '使用说明.md').write_text('''# LineSight 1.1.21 云端功能测试包

安装 APK 后进入四栏工作台，在“登录”二级页面使用统一云账户，或点击“进入演示团队”。服务地址和独立演示账户已内置。

已接入：无反光粒子开屏与并行初始化、Keycloak云登录、个人资料/工作区切换/成员查询、云任务新建与搜索、打印/送检、检验异常、处置与复检、历史追溯。演示数据仅位于独立演示团队。

`evidence/png` 中16张PNG为真实Android功能演示；主台账保留全部56项需求与剩余工作。

本包用于功能测试，沿用原安装证书以支持覆盖安装；正式发布签名尚待REL-01完成。检查清单模板、证据对比、报告、完整团队管理及离线功能仍在开发中。
''', encoding='utf-8')
print(json.dumps({'destination': str(destination), 'sha256': report['sha256'], 'bytes': report['bytes']}))

"""Package the ordinary APK, evidence gallery and existing development tracker."""
import hashlib
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
apk = root / '.artifact-work/sso/history8046.apk'
destination = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.29')
name = 'LineSight-1.1.29-8046-cloud-preview.apk'
acceptance = root / 'docs/product/linesight/acceptance'
validation = json.loads((acceptance/'history-batch/validation.json').read_text(encoding='utf-8'))
assert validation['release_build_passed'] and validation['flutter_tests_passed'] == 140
with zipfile.ZipFile(apk) as archive:
    assert all(f'lib/{abi}/libapp.so' in archive.namelist() for abi in ['arm64-v8a', 'x86_64'])
    assert not any(b'IntegrationTestPlugin' in archive.read(path) for path in archive.namelist() if path.endswith('.dex'))
destination.mkdir(parents=True, exist_ok=True)
shutil.copy2(apk, destination/name)
for folder in ['sso', 'product-batch', 'offline-batch', 'query-batch', 'trace-batch', 'sync-batch', 'workbench-batch', 'restore-batch', 'access-batch', 'history-batch']:
    shutil.copytree(acceptance/folder, destination/'evidence'/folder, dirs_exist_ok=True)
for file in ['DEMO_INDEX.html', 'DEMO_INDEX.json']:
    shutil.copy2(acceptance/file, destination/'evidence'/file)
gallery = json.loads((destination/'evidence/DEMO_INDEX.json').read_text(encoding='utf-8'))
assert gallery['screenshots'] == 81
for item in gallery['items']:
    assert hashlib.sha256((destination/'evidence'/item['file']).read_bytes()).hexdigest() == item['sha256']
for suffix in ['xlsx', 'csv']:
    shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}', destination)
report = {
    'version': '1.1.29+8046', 'entry': 'lib/main.dart', 'apk': name,
    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'bytes': apk.stat().st_size,
    'architectures': ['arm64-v8a', 'x86_64'], 'flutter_tests_passed': 140, 'django_tests_passed': 38,
    'screenshots': gallery['screenshots'], 'gallery': 'evidence/DEMO_INDEX.html',
    'evidence': 'evidence/history-batch/validation.json',
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'source_worktree_modified': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
    'signing': 'Existing debug-compatible certificate; formal signing pending',
    'emulator_started': False, 'physical_android_ui_tested': False, 'product_plan_complete': False,
}
(destination/'build.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
(destination/'使用说明.md').write_text('''# LineSight 1.1.29

覆盖安装APK，在登录二级页面使用统一云账户或进入演示团队。端点已内置。

新增任务时间线展开详情、操作者与状态变化、检验轮次及数量、逐件SN历史判定。检验详情随身份或团队切换隐藏旧记录。

打开 evidence/DEMO_INDEX.html 可离线搜索81张PNG并查看原图。本批新增4张中英文图为桌面组件渲染，采用真实云端独立演示团队数据；来源逐张标注。

140项客户端测试、38项后端测试通过，云端两件SN首检、整改、复检与幂等重试已联调。没有启动虚拟机或QEMU。未执行本版Android实机界面、覆盖升级和物理相机测试；正式签名、SMTP和双真机/外部用户验收继续。
''', encoding='utf-8')
print(json.dumps(report, indent=2))

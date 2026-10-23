"""Package the ordinary APK, evidence gallery and existing development tracker."""
import hashlib
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
apk = root / '.artifact-work/sso/feedback8048.apk'
destination = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.30')
name = 'LineSight-1.1.30-8048-cloud-preview.apk'
acceptance = root / 'docs/product/linesight/acceptance'
validation = json.loads((acceptance/'feedback-batch/validation.json').read_text(encoding='utf-8'))
assert validation['release_build_passed'] and validation['flutter_tests_passed'] == 149
with zipfile.ZipFile(apk) as archive:
    assert all(f'lib/{abi}/libapp.so' in archive.namelist() for abi in ['arm64-v8a', 'x86_64'])
    assert not any(b'IntegrationTestPlugin' in archive.read(path) for path in archive.namelist() if path.endswith('.dex'))
destination.mkdir(parents=True, exist_ok=True)
shutil.copy2(apk, destination/name)
for folder in ['sso', 'product-batch', 'offline-batch', 'query-batch', 'trace-batch', 'sync-batch', 'workbench-batch', 'restore-batch', 'access-batch', 'history-batch', 'feedback-batch']:
    shutil.copytree(acceptance/folder, destination/'evidence'/folder, dirs_exist_ok=True)
for file in ['DEMO_INDEX.html', 'DEMO_INDEX.json']:
    shutil.copy2(acceptance/file, destination/'evidence'/file)
gallery = json.loads((destination/'evidence/DEMO_INDEX.json').read_text(encoding='utf-8'))
assert gallery['screenshots'] == 85
for item in gallery['items']:
    assert hashlib.sha256((destination/'evidence'/item['file']).read_bytes()).hexdigest() == item['sha256']
for suffix in ['xlsx', 'csv']:
    shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}', destination)
report = {
    'version': '1.1.30+8048', 'entry': 'lib/main.dart', 'apk': name,
    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'bytes': apk.stat().st_size,
    'architectures': ['arm64-v8a', 'x86_64'], 'flutter_tests_passed': 149, 'previous_backend_baseline_tests_passed': 38, 'backend_changed': False,
    'screenshots': gallery['screenshots'], 'gallery': 'evidence/DEMO_INDEX.html',
    'evidence': 'evidence/feedback-batch/validation.json',
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'source_worktree_modified': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
    'signing': 'Existing debug-compatible certificate; formal signing pending',
    'emulator_started': False, 'physical_android_ui_tested': False, 'product_plan_complete': False,
}
(destination/'build.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
(destination/'使用说明.md').write_text("""# LineSight 1.1.30

覆盖安装APK，登录位于二级页面，端点与独立演示账户已内置。

新增任务、详情、记录、报告和图片的统一错误恢复；断网重试保留筛选，401登录、403刷新权限、404返回、409只读刷新。报告未加载时不显示0统计，失败与空数据分别显示。

打开 evidence/DEMO_INDEX.html 可搜索85张PNG。本批4张为360宽桌面组件渲染，使用受控错误夹具，来源逐张标注。

149项客户端测试及静态分析通过；后端未改动，沿用38项已验证基线。未启动虚拟机/模拟器/QEMU，也未安装卸载或清除数据。Android实机、覆盖升级、物理相机、正式签名、SMTP及双真机/外部用户验收继续。
""", encoding='utf-8')
print(json.dumps(report, indent=2))

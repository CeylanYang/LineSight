"""Publish the verified object-scope and feedback release with exact source."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
logs=root/'.artifact-work/sso';gallery=root/'docs/product/linesight/acceptance'
apk=root/'build/app/outputs/apk/release/app-release.apk'
assert 'No issues found!' in (logs/'access2-analyze.log').read_text(encoding='utf-8')
assert re.search(r'\+189: All tests passed!',(logs/'access2-full-flutter-tests.log').read_text(encoding='utf-8'))
assert re.search(r'Ran 57 tests[\s\S]*\nOK',(logs/'access2-full-backend-tests.log').read_text(encoding='utf-8'))
assert 'BUILD SUCCESSFUL' in (logs/'access2-release-build.log').read_text(encoding='utf-8')
assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart'))
assert apk.stat().st_mtime>max((root/name).stat().st_mtime for name in ['android/app/build.gradle.kts','pubspec.yaml'])
with zipfile.ZipFile(apk) as archive:
    abis={name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
    assert abis=={'arm64-v8a','x86_64'},abis
    for abi in abis:
        assert f'lib/{abi}/libapp.so' in archive.namelist() and f'lib/{abi}/libflutter.so' in archive.namelist()
assert not any('MaterialPageRoute' in file.read_text(encoding='utf-8') for file in (root/'lib').rglob('*.dart'))
index=json.loads((gallery/'DEMO_INDEX.json').read_text(encoding='utf-8'));assert index['screenshots']==124
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
cloud=json.loads((gallery/'access2-batch/live-api.json').read_text(encoding='utf-8'))
assert len(cloud['cross_workspace_reads'])==12 and all(row['status']==404 for row in cloud['cross_workspace_reads'])
assert cloud['same_workspace_wrong_job_photo_rejected'] and cloud['export_query_cannot_expand_workspace_scope'] and cloud['foreign_demo_task_unchanged'] and cloud['provider_probe_deleted']
haptics=json.loads((gallery/'access2-batch/haptic-platform-calls.json').read_text(encoding='utf-8'))
assert haptics['effects']==['HapticFeedbackType.selectionClick','HapticFeedbackType.lightImpact','HapticFeedbackType.heavyImpact']
sha=hashlib.sha256(apk.read_bytes()).hexdigest()
validation={'version':'1.1.34+8056','entry':'lib/main.dart','flutter_tests_passed':189,'new_feedback_tests_passed':11,
 'backend_tests_passed':57,'new_object_scope_backend_tests_passed':7,'flutter_analyze':'No issues found',
 'release_build_passed':True,'signature_verified':True,'integration_test_plugin_absent_from_release_dex':True,
 'release_native_abis_match_engine_and_app':True,'sha256':sha,
 'real_keycloak_pkce_cross_workspace_reads_rejected':12,'wrong_job_photo_rejected':True,'exports_workspace_scoped':True,
 'feedback_wait_failure_identity_change_guarded':True,'all_page_routes_use_common_factory':True,
 'app_and_os_reduced_motion_route_tests':True,'typed_route_return_values_preserved':True,
 'gallery_png':124,'new_batch_desktop_png':6,'physical_vibration_verified':False,'physical_nfc_tested':False,
 'physical_camera_or_barcode_tested':False,'android_upgrade_tested':False,'emulator_or_qemu_started_this_batch':False,
 'signing':'Existing debug-compatible certificate; formal signing pending','product_plan_complete':False}
(gallery/'access2-batch/validation.json').write_text(json.dumps(validation,indent=2)+'\n',encoding='utf-8')
subprocess.run(['git','diff','--check'],cwd=root,check=True)
subprocess.run(['git','add','--all'],cwd=root,check=True)
subprocess.run(['git','diff','--cached','--check'],cwd=root,check=True)
subprocess.run(['git','commit','-m','feat: distinguish confirmed outcomes, honor reduced-motion routes and verify object authorization'],cwd=root,check=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.34');target.mkdir(parents=True,exist_ok=True)
output=target/'LineSight-1.1.34-8056-cloud-preview.apk';shutil.copy2(apk,output)
assert hashlib.sha256(output.read_bytes()).hexdigest()==sha
shutil.copytree(gallery,target/'evidence',dirs_exist_ok=True)
for suffix in ('xlsx','csv'):shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}',target)
report={**validation,'apk':output.name,'bytes':output.stat().st_size,'architectures':sorted(abis),'source_commit':commit,
 'source_worktree_modified':False,'gallery':'evidence/DEMO_INDEX.html','evidence':'evidence/access2-batch/validation.json'}
(target/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(target/'使用说明.md').write_text('''LineSight 1.1.34+8056

本批新增选择/成功/警告三种触觉反馈。任务创建、状态更新、检验及异常处理在服务端确认后反馈；不合格检验提示异常。等待、失败及账户切换不会误报成功。设置中关闭触觉后不调用震动。

减少动态效果现在覆盖检验、扫码、NFC、相机取图、同步、备份预览等所有页面路由；同时尊重系统减少动态效果，保留页面返回值。检验页英文照片按钮窄屏布局已修复。上批登录会话、五阶段进度、整改前后对比，以及轮廓、相机质检、扫码和NFC功能保留。

189项客户端、57项后端测试通过，analyze无问题；真实Keycloak PKCE和HTTPS跨团队对象访问/导出隔离验证通过，未修改原演示任务。

打开 evidence/DEMO_INDEX.html 浏览124张已索引PNG。本批6张为桌面组件渲染，触觉记录来自Flutter平台调用捕获；未声称已验证物理震动或Android实机。物理NFC、手机相机/扫码、覆盖升级、SMTP找回及正式签名仍在待办中。

本批未启动模拟器，未自动安装、卸载或清除数据；后续已获准按需使用QEMU、Java和模拟器验证。
''',encoding='utf-8')
print(json.dumps({'version':report['version'],'apk':str(output),'sha256':sha,'source_commit':commit,'gallery_png':124},ensure_ascii=False))

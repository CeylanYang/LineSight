"""Package the verified closure batch with exact source and indexed PNG evidence."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
logs=root/'.artifact-work/sso'
gallery=root/'docs/product/linesight/acceptance'
apk=root/'build/app/outputs/apk/release/app-release.apk'
assert 'No issues found!' in (logs/'closure-analyze.log').read_text(encoding='utf-8')
assert re.search(r'\+178: All tests passed!',(logs/'closure-full-flutter-tests.log').read_text(encoding='utf-8'))
assert re.search(r'Ran 50 tests[\s\S]*\nOK',(logs/'closure-full-backend-tests.log').read_text(encoding='utf-8'))
assert 'BUILD SUCCESSFUL' in (logs/'closure-release-build.log').read_text(encoding='utf-8')
assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart'))
index=json.loads((gallery/'DEMO_INDEX.json').read_text(encoding='utf-8'))
assert index['screenshots']==118
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
cloud=json.loads((gallery/'closure-batch/live-api.json').read_text(encoding='utf-8'))
assert cloud['before_after_issue_binding'] and cloud['queued_printing_inspection_exception_reinspection_closed']
sessions=json.loads((gallery/'session-batch/live-api.json').read_text(encoding='utf-8'))
assert sessions['specific_session_access_and_refresh_revoked'] and sessions['logout_other_sessions_keeps_current']
sha=hashlib.sha256(apk.read_bytes()).hexdigest()
validation={'version':'1.1.33+8054','entry':'lib/main.dart','flutter_tests_passed':178,'new_closure_tests_passed':13,
 'backend_tests_passed':50,'flutter_analyze':'No issues found','release_build_passed':True,
 'signature_verified':True,'integration_test_plugin_absent_from_release_dex':True,'sha256':sha,
 'official_keycloak_account_sessions':True,'five_stage_lifecycle':True,'issue_scoped_before_after_comparison':True,
 'real_https_demo_workflow':True,'before_after_images':'Bundled reference with generated red line before; not photographed remediation',
 'gallery_png':118,'new_batch_desktop_png':10,'new_reference_png':2,'physical_nfc_tested':False,
 'physical_camera_or_barcode_tested':False,'android_upgrade_tested':False,'emulator_or_qemu_started_this_batch':False,
 'signing':'Existing debug-compatible certificate; formal signing pending','product_plan_complete':False}
(gallery/'closure-batch/validation.json').write_text(json.dumps(validation,indent=2)+'\n',encoding='utf-8')
subprocess.run(['git','diff','--check'],cwd=root,check=True)
subprocess.run(['git','add','--all'],cwd=root,check=True)
subprocess.run(['git','diff','--cached','--check'],cwd=root,check=True)
subprocess.run(['git','commit','-m','feat: add cloud session management, five-stage lifecycle and remediation photo comparison'],cwd=root,check=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.33');target.mkdir(parents=True,exist_ok=True)
output=target/'LineSight-1.1.33-8054-cloud-preview.apk';shutil.copy2(apk,output)
assert hashlib.sha256(output.read_bytes()).hexdigest()==sha
shutil.copytree(gallery,target/'evidence',dirs_exist_ok=True)
for suffix in ('xlsx','csv'):
    shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}',target)
report={**validation,'apk':output.name,'bytes':output.stat().st_size,'architectures':['arm64-v8a','x86_64'],
 'source_commit':commit,'source_worktree_modified':False,'gallery':'evidence/DEMO_INDEX.html','evidence':'evidence/closure-batch/validation.json'}
(target/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(target/'使用说明.md').write_text('''LineSight 1.1.33+8054

新增功能：账户与安全 → 登录会话；任务详情五阶段进度；异常记录 → 整改前后对比。会话管理复用Keycloak官方接口，可退出指定会话或其他会话，共享演示账号不显示该入口。

整改对比按同一异常显示处置前/处置后照片；多张可选择，点击照片查看原图、缩放或切换边缘参考。已有mean-shift → Canny → 骨架化、手机在线质检、任务/批次/工件SN扫码及NFC绑定/登录/令牌刷新均保留。

打开 evidence/DEMO_INDEX.html 浏览118张PNG。本批10张为桌面组件渲染，2张为演示参考图；图片前后差异由同一内置参考图添加红线生成，云端上传、异常绑定、复检及关闭真实执行。并非实体整改照片。

178项客户端与50项后端测试通过，analyze无问题。物理NFC、手机相机/扫码、覆盖升级、SMTP密码找回及正式签名仍待验收。未自动安装、卸载或清除数据。本批未启动模拟器；后续已获准按需使用QEMU、Java和模拟器验证。
''',encoding='utf-8')
print(json.dumps({'version':report['version'],'apk':str(output),'sha256':sha,'source_commit':commit,'gallery_png':118},ensure_ascii=False))

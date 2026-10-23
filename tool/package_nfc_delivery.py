"""Publish the verified local APK, public evidence, and exact source commit."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
apk=root/'build/app/outputs/apk/release/app-release.apk'
logs=root/'.artifact-work/sso'
assert 'No issues found!' in (logs/'nfc-analyze.log').read_text(encoding='utf-8')
assert re.search(r'\+165: All tests passed!',(logs/'nfc-full-flutter-tests.log').read_text(encoding='utf-8'))
assert re.search(r'Ran 50 tests[\s\S]*\nOK',(logs/'nfc-full-backend-tests.log').read_text(encoding='utf-8'))
build=(logs/'nfc-release-build.log').read_text(encoding='utf-8')
assert 'BUILD SUCCESSFUL' in build
assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart')),'APK predates app source'
gallery=root/'docs/product/linesight/acceptance'
index=json.loads((gallery/'DEMO_INDEX.json').read_text(encoding='utf-8'))
assert index['screenshots']==106
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
cloud=json.loads((gallery/'nfc-batch/live-api.json').read_text(encoding='utf-8'))
assert cloud['server_keycloak_login'] and cloud['refresh_rotation'] and cloud['unbind_access_and_refresh_rejected']
sha=hashlib.sha256(apk.read_bytes()).hexdigest()
validation={'version':'1.1.32+8052','entry':'lib/main.dart','flutter_tests_passed':165,'new_nfc_tests_passed':10,
 'backend_tests_passed':50,'new_nfc_backend_tests_passed':8,'flutter_analyze':'No issues found',
 'release_build_passed':True,'signature_verified':True,'integration_test_plugin_absent_from_release_dex':True,
 'sha256':sha,'keycloak_nfc_https_login_refresh_logout_revoke_verified':True,'card_fixture':'Generated card code and device key; no physical phone/card',
 'normal_native_client_password_grant_enabled':False,'gallery_png':106,'new_nfc_desktop_png':8,
 'physical_nfc_tested':False,'physical_camera_or_barcode_tested':False,'android_upgrade_tested':False,
 'emulator_or_qemu_started':False,'signing':'Existing debug-compatible certificate; formal signing pending','product_plan_complete':False}
(gallery/'nfc-batch/validation.json').write_text(json.dumps(validation,indent=2)+'\n',encoding='utf-8')
subprocess.run(['git','diff','--check'],cwd=root,check=True)
subprocess.run(['git','add','--all'],cwd=root,check=True)
subprocess.run(['git','diff','--cached','--check'],cwd=root,check=True)
subprocess.run(['git','commit','-m','feat: deliver device-bound NFC login with Keycloak token rotation and card management'],cwd=root,check=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip(),'Delivery source must be clean'
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.32')
target.mkdir(parents=True,exist_ok=True)
output=target/'LineSight-1.1.32-8052-cloud-preview.apk'
shutil.copy2(apk,output)
assert hashlib.sha256(output.read_bytes()).hexdigest()==sha
shutil.copytree(gallery,target/'evidence',dirs_exist_ok=True)
for suffix in ('xlsx','csv'):
    shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}',target)
report={**validation,'apk':output.name,'bytes':output.stat().st_size,'architectures':['arm64-v8a','x86_64'],
 'source_commit':commit,'source_worktree_modified':False,'gallery':'evidence/DEMO_INDEX.html','evidence':'evidence/nfc-batch/validation.json'}
(target/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(target/'使用说明.md').write_text('''LineSight 1.1.32+8052

本批包含 mean-shift → Canny → 骨架化轮廓、手机摄像头在线质检、任务／批次／工件SN扫码，以及NFC卡片绑定、登录、令牌刷新与解绑。后台与Keycloak认证扩展已更新。

先在统一登录页使用账户登录，然后进入“我的 → 账户与安全 → 我的卡片”绑定卡片。退出后可从同一登录页选择“刷卡登录”。卡片绑定当前账户和本机，换手机需先使用账户登录再绑定。空白、已格式化且可写的NDEF卡可选初始化；已有卡片内容保留。

工作台中打开“在线质检”使用手机相机查看轮廓；任务照片也使用对应原图计算轮廓。“扫码追溯”可扫描批次、工件SN或任务二维码。可打印演示码位于 evidence/vision-batch/，对应独立演示团队的真实任务。

打开 evidence/DEMO_INDEX.html 浏览106张PNG，来源分别标注。新增NFC图片为桌面组件渲染，云端认证证据使用生成的卡片／设备密钥。物理NFC卡、手机相机、实际扫码及覆盖升级仍待真机验证。APK使用现有调试兼容证书，正式签名继续准备。本批未自动安装、卸载或清除数据，未启动虚拟机、模拟器或QEMU。
''',encoding='utf-8')
print(json.dumps({'version':report['version'],'apk':str(output),'sha256':sha,'source_commit':commit,'gallery_png':106},ensure_ascii=False))

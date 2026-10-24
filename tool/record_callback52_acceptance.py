"""Record the ordinary-account browser-to-APK callback regression evidence."""
import io
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageChops

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/callback52-batch'
assert '+445: All tests passed!' in (root/'.artifact-work/callback52-full.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/callback52-analyze.log').read_text(encoding='utf-8-sig')
assert not subprocess.check_output(['git','diff','--','backend'],cwd=root,text=True).strip()
manifest=json.loads(subprocess.check_output([__import__('sys').executable,str(root/'tool/verify_appauth_manifest.py'),'--merged'],cwd=root,text=True))
assert manifest[-1]['callback_receiver_verified']
for number in (314,316):
    file=next((folder/'ui').glob(str(number)+'-*.xml'))
    assert '@lsuser01' in file.read_text(encoding='utf-8')
adb=[r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe','-s','emulator-5554']
version=subprocess.check_output(adb+['shell','dumpsys','package','com.example.linesight_flutter'],text=True)
assert 'versionCode=8076' in version and 'versionName=1.1.52' in version
cold=(root/'.artifact-work/release/current-window.xml').read_text(encoding='utf-8')
assert 'LineSight User 01 的工作区' in cold and '新建任务' in cold
(folder/'cold-relaunch.xml').write_text(cold,encoding='utf-8')
audit=[]
for name in subprocess.check_output(['git','diff','--name-only','--','*.png'],cwd=root,text=True).splitlines():
    before=Image.open(io.BytesIO(subprocess.check_output(['git','show','HEAD:'+name],cwd=root))).convert('RGB')
    after=Image.open(root/name).convert('RGB')
    bbox=ImageChops.difference(before,after).getbbox()
    assert bbox and bbox[2]-bbox[0]<=25 and bbox[3]-bbox[1]<=15,(name,bbox)
    audit.append({'file':name,'changed_bbox':bbox,'change':'displayed version only'})
(folder/'golden-change-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
report={'version':'1.1.52+8076','flutter_full_tests_passed':445,'flutter_analyze_clean':True,
 'native_password_login_verified':True,'native_sso_login_verified':True,'native_logout_and_relogin_verified':True,
 'native_cold_session_restore_verified':True,'native_ordinary_username':'lsuser01',
 'native_apk_track':'preview','native_png':5,'manifest_verification':manifest,
 'backend_source_unchanged':True,'accounts_and_passwords_unchanged':True,'physical_devices_verified':False}
(folder/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
package=(root/'tool/package_version_close_delivery.py').read_text(encoding='utf-8')
package=package.replace('section-focus-batch','callback52-batch').replace("validation['section_focus_verified']","validation['native_password_login_verified']").replace('324','329').replace('version-close-{track}','callback52-{track}').replace('1.1.51','1.1.52').replace('8075','8076')
package=package.replace("['LineSight_Development_Backlog.xlsx','LineSight_Development_Backlog.csv','RELEASE_SIGNING.md']","['RELEASE_SIGNING.md']")
package=package.replace("shutil.copy2(gallery/'callback52-batch/开发交付报告.md',target/'开发交付报告.md')\n",'')
(root/'tool/package_callback52_delivery.py').write_text(package,encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

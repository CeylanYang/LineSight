"""Verify first-grant camera navigation on the existing emulator, preserving app data."""
import json
from pathlib import Path
import subprocess
import sys
import time

root=Path(__file__).resolve().parents[1]
adb=[r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe','-s','emulator-5554']
assert subprocess.check_output(adb+['shell','getprop','ro.kernel.qemu']).strip()==b'1'
assert b'versionCode=8059' in subprocess.check_output(adb+['shell','dumpsys','package','com.example.linesight_flutter'])
def ui(action,value=None):
    command=[sys.executable,str(root/'tool/release_android_ui.py'),action]
    if value is not None: command.append(value)
    return subprocess.check_output(command,cwd=root,encoding='utf-8',timeout=50)
def wait(label):
    deadline=time.monotonic()+55
    while time.monotonic()<deadline:
        try:
            current=ui('inspect')
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            time.sleep(1)
            continue
        if label in current: return current
        time.sleep(1)
    raise AssertionError('Expected Android state did not appear: '+label)

subprocess.run(adb+['shell','pm','revoke','com.example.linesight_flutter','android.permission.CAMERA'],check=True,capture_output=True)
ui('launch')
wait('在线质检')
ui('tap','在线质检')
wait('开启相机')
ui('tap','开启相机')
wait('While using the app')
ui('capture','92-camera-permission-dialog-emulator')
started=time.monotonic()
ui('tap','While using the app')
wait('暂停提取轮廓')
result=wait('实时轮廓')
ui('capture','93-camera-first-grant-preview-emulator')
ui('swipe')
wait('实时轮廓')
ui('capture','94-camera-first-grant-contours-emulator')
ui('back')
wait('扫码追溯')
report={'package':'com.example.linesight_flutter','version_code':8059,'emulator':True,
        'permission_revoked_only':True,'app_data_cleared':False,'open_camera_taps':1,
        'native_permission_dialog_seen':True,'allow_while_using_taps':1,
        'preview_opened_without_second_tap':True,'cloud_contour_result_seen':True,
        'back_returns_to_workbench':True,'seconds_from_grant_to_result':round(time.monotonic()-started,2),
        'camera_source':'Android emulator synthetic camera; no physical camera acceptance',
        'ui_frame_latency_label':result.split('实时轮廓')[-1].strip()}
(root/'docs/product/linesight/acceptance/release-batch/camera-permission-journey.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

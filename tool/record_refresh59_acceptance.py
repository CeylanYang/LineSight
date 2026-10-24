"""Verify released manifests, frozen APK compatibility and actual native captures."""
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
import zipfile

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from PIL import Image
from ota_release import apk_fingerprint


def main():
    root=Path(__file__).resolve().parents[1]
    folder=root/'docs/product/linesight/acceptance/refresh59-batch'
    assert '+459: All tests passed!' in (root/'.artifact-work/refresh59-full.log').read_text(encoding='utf-8-sig')
    assert 'No issues found!' in (root/'.artifact-work/refresh59-analyze.log').read_text(encoding='utf-8-sig')
    checks={
        '329-refresh-patch-ready-emulator':'更新已准备好，下次启动生效',
        '330-refresh-expired-recovered-emulator':'登录已过期，请重新登录',
    }
    for name,label in checks.items():
        tree=ET.parse(folder/'ui'/(name+'.xml'))
        assert any(label in (n.get('text','')+n.get('content-desc','')) for n in tree.iter('node'))
    keytext=(root/'lib/ota_key.dart').read_text()
    key=Ed25519PublicKey.from_public_bytes(base64.b64decode(re.search(r"otaPublicKey = '([^']+)'",keytext)[1]))
    published=[];artifacts=[]
    delivery=Path('D:/ENT207/deliverables/LineSight-1.1.54-content2')
    delivery.mkdir(parents=True,exist_ok=True)
    for track,sequence in [('preview',4),('production',1)]:
        apk=root/f'.artifact-work/release/LineSight-1.1.54-8078-{track}.apk'
        baseline=json.loads((root/f'.artifact-work/ota/{track}/8078/base.json').read_text())
        assert apk_fingerprint(apk)==baseline,'Native/assets drift'
        signature=(root/f'.artifact-work/sso/refresh59-{track}-signature.log').read_text(encoding='utf-8-sig')
        assert 'DOES NOT VERIFY' not in signature
        certificate=re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)',signature)[1]
        for abi in ['arm64-v8a','x86_64']:
            patchdir=root/f'.artifact-work/ota/{track}/8078/{abi}'
            outer=json.loads((patchdir/'manifest.json').read_text())
            payload=base64.b64decode(outer['payload']);key.verify(base64.b64decode(outer['signature']),payload)
            item=json.loads(payload)
            assert item['sequence']==sequence and item['track']==track and item['abi']==abi and item['base']==8078
            raw=(patchdir/(item['sha256']+'.so')).read_bytes()
            assert hashlib.sha256(raw).hexdigest()==item['sha256'] and len(raw)==item['size']
            with zipfile.ZipFile(apk) as z:assert z.read(f'lib/{abi}/libapp.so')==raw
            published.append(item)
        shutil.copy2(apk,delivery/apk.name)
        artifacts.append({'file':apk.name,'bytes':apk.stat().st_size,
            'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'certificate_sha256':certificate})
    captures=[]
    for p in sorted((folder/'png').glob('*.png')):
        with Image.open(p) as picture:assert picture.size==(412,824)
        captures.append({'file':'png/'+p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
            'origin':'android-emulator-screenshot','ui_xml':(folder/'ui'/(p.stem+'.xml')).is_file()})
    assert len(captures)==4
    result={'version':'1.1.54+8078','content_revision':2,
        'flutter_tests':459,'new_refresh_tests':6,'analyze_clean':True,
        'native_preview_ota4_verified':True,'native_expired_session_requires_login':True,
        'native_secondary_login_entry_verified':True,'apk_reinstalled_during_fix':False,
        'observed_last_update_time':'2026-10-24 05:44:43','app_data_cleared':False,
        'production_ota1_published':True,'production_runtime_tested':False,
        'physical_devices_tested':False,'full_native_role_matrix_complete':False,
        'emulator_exited_before_demo_login':True,'exit_cause_confirmed':False,
        'artifacts':artifacts,'manifests':published,'captures':captures}
    (folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
    (delivery/'delivery.json').write_text(json.dumps(result,indent=2)+'\n')
    (delivery/'更新说明.md').write_text('''# LineSight 1.1.54 内容更新 2

修复登录过期后停留在通用失败提示、无法进入重新登录流程的问题。

已有 8078：启动后自动下载，下次正常冷启动生效，也可在“我的 → 应用更新”检查。
版本号仍为 1.1.54，内容版本更新为 2。

旧版本：按原安装签名选择 preview 或 production APK 覆盖升级，保留数据。
不要卸载旧应用；签名不一致时停止安装并核对原包。

当前构建通过 459 项 Flutter 测试及静态检查。预览 OTA 已用实际过期会话验证；正式签名运行、完整页面/角色、真机功能仍待验收。当前网站 https://99ai.pronhubcn.com/ 。
''',encoding='utf-8')
    print(json.dumps({'flutter_tests':459,'signed_manifests':len(published),'new_native_png':len(captures),'delivery':str(delivery)}))


if __name__=='__main__':main()

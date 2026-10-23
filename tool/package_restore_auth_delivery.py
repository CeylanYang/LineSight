"""Package public recovery evidence without copying private backup material."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-recovery-20261024')
public=root/'docs/product/linesight/acceptance/restore-auth-batch'
validation=json.loads((public/'validation.json').read_text())
assert validation['isolated_real_identity_restore_verified'] and validation['encrypted_off_host_copy_verified']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
files={f'evidence/{p.name}':p for p in public.iterdir() if p.suffix in ['.json','.md']}
for name in ['LineSight_Development_Backlog.xlsx','LineSight_Development_Backlog.csv']:
    files[name]=root/'docs/product/linesight'/name
files['operations/RESTORE.md']=root/'deploy/sso/RESTORE.md'
for name in ['export_cloud_backup.py','rehearse_cloud_restore.py','rehearse_restored_identity.py','test_restore_guards.py','verify_backup_host.py']:
    files['tools/'+name]=root/'tool'/name
target.mkdir(parents=True,exist_ok=True)
manifest={}
for name,source in files.items():
    destination=target/name
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,destination)
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    assert hashlib.sha256(destination.read_bytes()).hexdigest()==digest
    manifest[name]={'bytes':source.stat().st_size,'sha256':digest}
readme='''# 云端恢复交付 · 2026-10-24

本批完成真实身份恢复、业务数据与权限验证、加密异机副本取回及隔离解包。

- 主台账：`LineSight_Development_Backlog.xlsx`，REL-02已验收。
- 验证报告：`evidence/README.md`。
- 恢复操作：`operations/RESTORE.md`，配套脚本位于`tools/`。
- 现有APK：[预览兼容升级版](../cloud-preview-1.1.38/LineSight-1.1.38-8062-preview.apk)、[正式签名版](../cloud-preview-1.1.38/LineSight-1.1.38-8062-production.apk)。请选择与已有安装签名相同的一轨覆盖升级，保留数据。
- [171张功能PNG索引](../cloud-preview-1.1.38/evidence/DEMO_INDEX.html)。本批没有新增界面或APK。

生产切换、另一台服务器启动身份服务、完整NFC恢复登录、自动异机复制及保留周期仍待后续。密钥与加密备份保持在本机私有目录，不包含在交付中。
'''
(target/'使用说明.md').write_text(readme,encoding='utf-8')
manifest['使用说明.md']={'bytes':(target/'使用说明.md').stat().st_size,'sha256':hashlib.sha256((target/'使用说明.md').read_bytes()).hexdigest()}
result={**validation,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'files':manifest}
(target/'delivery.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
assert all((target/name).exists() for name in manifest)
print(json.dumps({'delivery':str(target),'files':len(manifest),'source_commit':result['source_commit']},ensure_ascii=False))

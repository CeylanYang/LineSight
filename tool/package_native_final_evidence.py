"""Attach native evidence to the unchanged 1.1.47 signed delivery."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
target = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.47')
gallery = root / 'docs/product/linesight/acceptance'
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()
validation = json.loads((gallery / 'native-final-batch/validation.json').read_text(encoding='utf-8'))
index = json.loads((gallery / 'DEMO_INDEX.json').read_text(encoding='utf-8'))
assert index['screenshots'] == 289 and len(validation['screenshots']) == 12
manifest = json.loads((target / 'build.json').read_text(encoding='utf-8'))
for artifact in manifest['artifacts']:
    assert hashlib.sha256((target / artifact['file']).read_bytes()).hexdigest() == artifact['sha256']
for row in index['items']:
    assert hashlib.sha256((gallery / row['file']).read_bytes()).hexdigest() == row['sha256']
shutil.copytree(gallery, target / 'evidence', dirs_exist_ok=True)
for name in ['LineSight_Development_Backlog.xlsx', 'LineSight_Development_Backlog.csv']:
    shutil.copy2(root / 'docs/product/linesight' / name, target / name)
    assert (target / name).read_bytes() == (root / 'docs/product/linesight' / name).read_bytes()
for row in index['items']:
    assert hashlib.sha256((target / 'evidence' / row['file']).read_bytes()).hexdigest() == row['sha256']
manifest.update({
    'gallery_png': index['screenshots'],
    'native_navigation_evidence': 'evidence/native-final-batch/validation.json',
    'native_navigation_png_added': 12,
    'native_full_acceptance_complete': False,
    'evidence_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
})
(target / 'build.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
readme = target / '使用说明.md'
content = readme.read_text(encoding='utf-8')
marker = '## 原生导航验证补充（2026-10-24）'
if marker not in content:
    content += '\n\n' + marker + '\n\nAPK 保持 1.1.47+8071，两种签名文件均未重编译或替换。新增 12 张 Android 14 模拟器原生截图，覆盖二级登录、配置选择往返、模板创建任务与本机认证入口。详细范围及未完成项见 evidence/native-final-batch/README.md；素材索引现有 289 张 PNG。完整原生及物理设备验收仍未完成。\n'
    readme.write_text(content, encoding='utf-8')
print(json.dumps({'delivery': str(target), 'gallery_png': index['screenshots'], 'native_png_added': 12, 'apks_unchanged': True}, ensure_ascii=False))

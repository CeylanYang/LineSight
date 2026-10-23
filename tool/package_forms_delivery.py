"""Package the two verified signing tracks without private material or audit APKs."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
def log_text(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8')
gallery=root/'docs/product/linesight/acceptance'
validation=json.loads((gallery/'forms-batch/validation.json').read_text(encoding='utf-8'))
assert validation['preview_upgrade_verified'] and validation['production_signature_verified'] and validation['native_forms_verified']
assert '+220: All tests passed!' in (root/'.artifact-work/sso/forms-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/forms-analyze.log').read_text(encoding='utf-8')
index=json.loads((gallery/'DEMO_INDEX.json').read_text(encoding='utf-8'))
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
artifacts=[]
for track in ['preview','production']:
    assert 'BUILD SUCCESSFUL' in log_text(root/f'.artifact-work/sso/forms-{track}-build.log')
    apk=root/f'.artifact-work/release/LineSight-1.1.38-8062-{track}.apk'
    assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart'))
    assert apk.stat().st_mtime>max((root/name).stat().st_mtime for name in ['android/app/build.gradle.kts','pubspec.yaml'])
    with zipfile.ZipFile(apk) as archive:
        abis={name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
        assert abis=={'arm64-v8a','x86_64'}
        for abi in abis: assert f'lib/{abi}/libflutter.so' in archive.namelist() and f'lib/{abi}/libapp.so' in archive.namelist()
        for name in archive.namelist():
            if name.endswith('.dex'):
                dex=archive.read(name)
                assert b'IntegrationTestPlugin' not in dex and b'StorageAuditInstrumentation' not in dex
    artifacts.append({'file':apk.name,'track':track,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'bytes':apk.stat().st_size})
subprocess.run(['git','diff','--check'],cwd=root,check=True)
subprocess.run(['git','add','--all'],cwd=root,check=True)
subprocess.run(['git','diff','--cached','--check'],cwd=root,check=True)
subprocess.run(['git','commit','-m','feat: validate business forms and locate missing inputs'],cwd=root,check=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.38');target.mkdir(parents=True,exist_ok=True)
for artifact in artifacts: shutil.copy2(root/'.artifact-work/release'/artifact['file'],target/artifact['file'])
shutil.copytree(gallery,target/'evidence',dirs_exist_ok=True)
for name in ['LineSight_Development_Backlog.xlsx','LineSight_Development_Backlog.csv','RELEASE_SIGNING.md']:
    shutil.copy2(root/'docs/product/linesight'/name,target/name)
(target/'build.json').write_text(json.dumps({**validation,'source_commit':commit,'source_worktree_modified':False,'artifacts':artifacts,'gallery_png':index['screenshots']},indent=2)+'\n',encoding='utf-8')
shutil.copy2(gallery/'forms-batch/README.md',target/'使用说明.md')
print(json.dumps({'delivery':str(target),'source_commit':commit,'artifacts':artifacts,'gallery_png':index['screenshots']},ensure_ascii=False))

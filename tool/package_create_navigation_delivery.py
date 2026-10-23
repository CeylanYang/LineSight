"""Package both signed customer tracks and receipt navigation evidence."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
gallery=root/'docs/product/linesight/acceptance'
validation=json.loads((gallery/'create-navigation-batch/validation.json').read_text())
assert validation['confirmed_create_replaces_form_with_task_detail'] and validation['flutter_full_tests_passed']==409
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
index=json.loads((gallery/'DEMO_INDEX.json').read_text())
assert index['screenshots']==291
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
artifacts=[]
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),
                   ('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    def log(kind):
        raw=(root/f'.artifact-work/sso/create-navigation-{track}-{kind}.log').read_bytes()
        return raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8')
    assert 'BUILD SUCCESSFUL' in log('build')
    assert cert in log('signature') and 'Verifies' in log('signature')
    apk=root/f'.artifact-work/release/LineSight-1.1.48-8072-{track}.apk'
    assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart'))
    assert apk.stat().st_mtime>(root/'pubspec.yaml').stat().st_mtime
    with zipfile.ZipFile(apk) as archive:
        abis={name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
        assert abis=={'arm64-v8a','x86_64'}
        for name in archive.namelist():
            if name.endswith('.dex'):
                data=archive.read(name)
                assert b'IntegrationTestPlugin' not in data and b'StorageAuditInstrumentation' not in data
    artifacts.append({'file':apk.name,'track':track,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
                      'bytes':apk.stat().st_size,'certificate_sha256':cert})
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.48')
target.mkdir(parents=True,exist_ok=True)
for artifact in artifacts:
    output=target/artifact['file']
    shutil.copy2(root/'.artifact-work/release'/artifact['file'],output)
    assert hashlib.sha256(output.read_bytes()).hexdigest()==artifact['sha256']
shutil.copytree(gallery,target/'evidence',dirs_exist_ok=True)
for name in ['LineSight_Development_Backlog.xlsx','LineSight_Development_Backlog.csv','RELEASE_SIGNING.md']:
    source=root/'docs/product/linesight'/name
    shutil.copy2(source,target/name)
    assert (target/name).read_bytes()==source.read_bytes()
for row in index['items']:
    assert hashlib.sha256((target/'evidence'/row['file']).read_bytes()).hexdigest()==row['sha256']
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
(target/'build.json').write_text(json.dumps({**validation,'source_commit':commit,'source_worktree_modified':False,
                                          'artifacts':artifacts,'gallery_png':index['screenshots']},indent=2)+'\n')
shutil.copy2(gallery/'create-navigation-batch/README.md',target/'使用说明.md')
print(json.dumps({'delivery':str(target),'source_commit':commit,'artifacts':artifacts,'gallery_png':index['screenshots']},ensure_ascii=False))

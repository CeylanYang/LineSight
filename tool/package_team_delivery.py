"""Package both customer signing tracks and the verified PNG gallery."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
gallery=root/'docs/product/linesight/acceptance'
validation=json.loads((gallery/'team-batch/validation.json').read_text())
assert validation['live_https_team_verified'] and validation['flutter_full_tests_passed']==328
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
index=json.loads((gallery/'DEMO_INDEX.json').read_text())
for row in index['items']:
    assert hashlib.sha256((gallery/row['file']).read_bytes()).hexdigest()==row['sha256']
artifacts=[]
for track in ['preview','production']:
    raw=(root/f'.artifact-work/sso/team-{track}-build.log').read_bytes()
    log=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8')
    assert 'BUILD SUCCESSFUL' in log
    apk=root/f'.artifact-work/release/LineSight-1.1.44-8068-{track}.apk'
    assert apk.stat().st_mtime>max(file.stat().st_mtime for file in (root/'lib').rglob('*.dart'))
    assert apk.stat().st_mtime>(root/'pubspec.yaml').stat().st_mtime
    with zipfile.ZipFile(apk) as archive:
        abis={name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
        assert abis=={'arm64-v8a','x86_64'}
        for name in archive.namelist():
            if name.endswith('.dex'):
                data=archive.read(name)
                assert b'IntegrationTestPlugin' not in data and b'StorageAuditInstrumentation' not in data
    artifacts.append({'file':apk.name,'track':track,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'bytes':apk.stat().st_size})
target=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.44')
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
(target/'build.json').write_text(json.dumps({**validation,'source_commit':commit,'source_worktree_modified':False,'artifacts':artifacts,'gallery_png':index['screenshots']},indent=2)+'\n')
shutil.copy2(gallery/'team-batch/README.md',target/'使用说明.md')
print(json.dumps({'delivery':str(target),'source_commit':commit,'artifacts':artifacts,'gallery_png':index['screenshots']},ensure_ascii=False))

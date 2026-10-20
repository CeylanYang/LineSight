import hashlib
import json
import shutil
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
release = Path(r'C:\Users\29668\LineSight-releases\1.1.10')
release.mkdir(parents=True, exist_ok=True)
reports = release / 'reports'
reports.mkdir(exist_ok=True)

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()

for arch in ('arm64-v8a', 'x86_64'):
    source = root / 'build/app/outputs/flutter-apk' / f'app-{arch}-release.apk'
    assert source.is_file(), source
    shutil.copy2(source, release / f'LineSight-1.1.10-{arch}.apk')

for log in root.glob('*.log'):
    shutil.copy2(log, reports / log.name)
evidence = root / 'build/language-evidence'
for path in evidence.rglob('*'):
    if path.is_file():
        dest = reports / 'language-evidence' / path.relative_to(evidence)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)

excluded = {'build', '.dart_tool', '.gradle', '.git', 'local.properties', '.flutter-plugins-dependencies'}
files = [p for p in root.rglob('*') if p.is_file() and not excluded.intersection(p.relative_to(root).parts) and p.suffix != '.log']
archive = release / 'LineSight-1.1.10-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for path in sorted(files):
        output.write(path, path.relative_to(root).as_posix())

with zipfile.ZipFile(archive) as snapshot:
    for path in files:
        assert snapshot.read(path.relative_to(root).as_posix()) == path.read_bytes()

with zipfile.ZipFile(r'C:\Users\29668\LineSight-releases\1.1.9\LineSight-1.1.9-source.zip') as baseline:
    names = set(baseline.namelist())
    changed = []
    for path in sorted(files):
        name = path.relative_to(root).as_posix()
        if name not in names or baseline.read(name) != path.read_bytes():
            changed.append({'path': name, 'kind': 'modified' if name in names else 'added', 'sha256': sha(path)})
    (reports / 'source-changes.json').write_text(json.dumps(changed, ensure_ascii=False, indent=2), encoding='utf-8')

checksums = {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in release.iterdir() if p.suffix in ('.apk', '.zip')}
(release / 'checksums.json').write_text(json.dumps(checksums, indent=2), encoding='utf-8')
manifest = [{'path': p.relative_to(release).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(reports.rglob('*')) if p.is_file()]
(release / 'evidence-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps({'source_files': len(files), 'changed_files': len(changed), 'checksums': checksums}, indent=2))

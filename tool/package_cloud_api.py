"""Bundle only backend source for the existing backed-up deployment driver."""
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
source = root / 'backend'
target = root / '.artifact-work/sso/cloud-api.tar.gz'
with tarfile.open(target, 'w:gz') as archive:
    for file in source.rglob('*.py'):
        if '__pycache__' not in file.parts:
            archive.add(file, arcname=file.relative_to(source))
    archive.add(source / 'requirements.txt', arcname='requirements.txt')
print('Backend source bundle ready')

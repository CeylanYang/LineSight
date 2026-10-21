"""Create a reproducible distribution archive after validating build hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT=Path(__file__).resolve().parent


def package(output: Path):
    manifest=json.loads((ROOT/'build-manifest.json').read_text(encoding='utf-8'))
    files={file['file']:file for file in manifest['files']}
    actual={file.relative_to(ROOT/'dist').as_posix() for file in (ROOT/'dist').rglob('*') if file.is_file()}
    if set(files)!=actual:
        raise ValueError('Build manifest does not match dist. Run npm run build.')
    entries={}
    for name,metadata in files.items():
        data=(ROOT/'dist'/name).read_bytes()
        if hashlib.sha256(data).hexdigest()!=metadata['sha256'] or len(data)!=metadata['bytes']:
            raise ValueError(f'Build hash mismatch: {name}')
        entries['dist/'+name]=data
    for name in ['START-HERE.txt','DEPLOY.md','build-manifest.json']:
        entries[name]=(ROOT/name).read_bytes()
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name,data in sorted(entries.items()):
            info=zipfile.ZipInfo(name,date_time=(2026,10,21,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            info.create_system=3
            info.external_attr=0o100644 << 16
            archive.writestr(info,data,compresslevel=9)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('Archive CRC verification failed')
    result={'artifact':'deliverables/week6/'+output.name,'version':manifest['version'],
            'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'dist_files':len(files),'dist_bytes':sum(f['bytes'] for f in files.values()),
            'archive_entries':len(entries),'manifest_verified':True,'zip_crc_verified':True}
    evidence=ROOT.parent/'docs/week6/web-demo/delivery.json'
    evidence.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT.parent/'deliverables/week6/LineSight-web-demo.zip')
    package(parser.parse_args().output.resolve())

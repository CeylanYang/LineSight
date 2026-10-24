"""Encrypt a complete backup on the cloud host, or verify its private off-host copy.

The key is never written to a public report. Verification decrypts in memory and
checks every archived file, SQLite rows, foreign keys, and evidence fingerprints.
"""
import argparse
from contextlib import closing
import hashlib
import io
import json
import os
import re
from pathlib import Path, PurePosixPath, PureWindowsPath
import sqlite3
import tarfile
import tempfile

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from rehearse_cloud_restore import sha, sqlite_manifest
from rehearse_restored_identity import backup_path

MAGIC=b'LSBK01'


def archive_members(archive):
    members=archive.getmembers()
    names=[m.name for m in members]
    if len(names)!=len(set(names)):
        raise ValueError('Duplicate archive member')
    for member in members:
        name=member.name
        if (PurePosixPath(name).is_absolute() or PureWindowsPath(name).drive
                or '\\' in name or '..' in PurePosixPath(name).parts
                or not (member.isfile() or member.isdir())):
            raise ValueError('Unsafe archive member')
    return members


def decrypted_bytes(archive_path, key_file):
    if archive_path.stat().st_size>256*1024*1024:
        raise ValueError('Use streaming verification for archives larger than 256 MiB')
    key=key_file.read_bytes()
    if len(key)!=32: raise ValueError('Expected a 32-byte key')
    data=archive_path.read_bytes()
    if not data.startswith(MAGIC): raise ValueError('Unknown archive format')
    return AESGCM(key).decrypt(data[len(MAGIC):len(MAGIC)+12],data[len(MAGIC)+12:],MAGIC)


def encrypt(backup, key_file):
    if os.name!='posix' or os.geteuid()!=0:
        raise RuntimeError('Encryption runs only on the root backup host')
    backup=backup_path(backup)
    key_file=key_file.resolve()
    if key_file.parent!=Path('/root/linesight-restore-private') or not re.fullmatch(r'export-key(?:-\d{8}T\d{12}Z)?\.bin',key_file.name):
        raise ValueError('Use the private temporary export key path')
    key=key_file.read_bytes()
    assert len(key)==32
    members=['linesight.sqlite3','identity.dump','private-manifest.json','linesight.env',
        'identity.env','compose.yaml','rehearse_cloud_restore.py','rehearse_restored_identity.py',
        'report.json','backend','media','realm','providers']
    # Daily snapshots have not necessarily been used for an identity rehearsal.
    # Include that evidence only when it actually exists.
    if (backup/'identity-rehearsal-report.json').is_file():
        members.append('identity-rehearsal-report.json')
    if (backup/'deployment').is_dir():
        members.append('deployment')
    files={}
    for name in members:
        path=backup/name
        assert path.exists(), 'Complete backup component missing: '+name
        for item in ([path] if path.is_file() else path.rglob('*')):
            assert not item.is_symlink(), 'Portable backup cannot contain symlinks'
            if item.is_file():
                files[item.relative_to(backup).as_posix()]={'bytes':item.stat().st_size,'sha256':sha(item)}
    output=backup/'portable-backup.lsbk'
    assert not output.exists(),'Preserve the previous encrypted copy'
    os.umask(0o077)
    nonce=os.urandom(12)
    cipher=Cipher(algorithms.AES(key),modes.GCM(nonce)).encryptor()
    cipher.authenticate_additional_data(MAGIC)
    class Sink:
        def __init__(self,stream): self.stream=stream
        def write(self,data): self.stream.write(cipher.update(data)); return len(data)
        def flush(self): self.stream.flush()
    try:
        with output.open('xb') as stream:
            stream.write(MAGIC+nonce)
            with tarfile.open(fileobj=Sink(stream),mode='w|gz') as archive:
                for name in members:
                    archive.add(backup/name,arcname=name,recursive=True)
                raw=json.dumps({'format':'LineSight portable cloud backup v1','backup':backup.name,'files':files},sort_keys=True).encode()
                info=tarfile.TarInfo('OFFHOST_MANIFEST.json'); info.size=len(raw);info.mode=0o600
                archive.addfile(info,io.BytesIO(raw))
            stream.write(cipher.finalize());stream.write(cipher.tag)
            stream.flush();os.fsync(stream.fileno())
        result={'backup':backup.name,'encryption':'AES-256-GCM','archive_sha256':sha(output),
            'archive_bytes':output.stat().st_size,'files':len(files),'key_in_archive':False}
        (backup/'portable-backup-report.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result))
    finally:
        key_file.unlink(missing_ok=True)


def verify(archive_path, key_file, report_file):
    archive_path,key_file=archive_path.resolve(),key_file.resolve()
    raw=decrypted_bytes(archive_path,key_file)
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
        members=archive_members(archive)
        inventory=json.load(archive.extractfile('OFFHOST_MANIFEST.json'))
        actual={m.name:m for m in members if m.isfile() and m.name!='OFFHOST_MANIFEST.json'}
        assert actual.keys()==inventory['files'].keys()
        for name,expected in inventory['files'].items():
            stream=archive.extractfile(actual[name])
            assert actual[name].size==expected['bytes'] and hashlib.file_digest(stream,'sha256').hexdigest()==expected['sha256'],name
        manifest=json.load(archive.extractfile('private-manifest.json'))
        for group in ['media','identity_runtime_files','deployment_files']:
            for name,digest in manifest.get(group,{}).items():
                target='media/'+name if group=='media' else name
                assert inventory['files'][target]['sha256']==digest
        cloud_report=json.load(archive.extractfile('report.json'))
        for name,digest in cloud_report['artifacts_sha256'].items():
            assert inventory['files'][name]['sha256']==digest
        with tempfile.TemporaryDirectory(prefix='verify-',dir=archive_path.parent) as directory:
            database=Path(directory)/'linesight.sqlite3'
            database.write_bytes(archive.extractfile('linesight.sqlite3').read())
            with closing(sqlite3.connect(f'file:{database.as_posix()}?mode=ro',uri=True)) as db:
                assert db.execute('PRAGMA integrity_check').fetchone()==('ok',)
                assert not db.execute('PRAGMA foreign_key_check').fetchall()
                assert sqlite_manifest(db)==manifest['sqlite']
    result={'backup':inventory['backup'],'off_host_copy_verified':True,
        'encryption':'AES-256-GCM','authentication_tag_verified':True,'archive_sha256':sha(archive_path),
        'archive_bytes':archive_path.stat().st_size,'all_file_hashes_verified':True,'files':len(actual),
        'sqlite_tables':len(manifest['sqlite']),'sqlite_rows_identical':True,'foreign_keys_valid':True,
        'provider_dump_hash_verified':True,'provider_tables_in_manifest':len(manifest['provider']),
        'media_files_verified':len(manifest['media']),'identity_runtime_files_verified':len(manifest['identity_runtime_files']),
        'deployment_config_files_verified':len(manifest.get('deployment_files',{})),
        'private_keys_or_databases_in_public_delivery':False,'decrypted_archive_retained':False,
        'off_host_restore_boot_exercised':False}
    report_file.parent.mkdir(parents=True,exist_ok=True)
    report_file.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))


def decrypt(archive_path, key_file, output):
    """Restore verified files only into a new, canonical backup directory."""
    if os.name!='posix' or os.geteuid()!=0:
        raise RuntimeError('Restore extraction runs only on the root backup host')
    output=backup_path(output)
    if output.exists(): raise ValueError('Restore target already exists')
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='restore-check-',dir=archive_path.resolve().parent) as directory:
        verify(archive_path,key_file,Path(directory)/'verification.json')
    # Authenticate a second read before writing any restored files.
    raw=decrypted_bytes(archive_path,key_file)
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
        members=archive_members(archive)
        output.mkdir(mode=0o700)
        for member in members:
            target=output/member.name
            if member.isdir(): target.mkdir(mode=0o700,parents=True,exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
                with target.open('xb') as stream:
                    import shutil
                    shutil.copyfileobj(archive.extractfile(member),stream)
                target.chmod(0o600)
    print(json.dumps({'restored_backup':output.name,'verified_extraction':True,'production_cutover':False}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['encrypt','verify','decrypt'])
    parser.add_argument('target',type=Path)
    parser.add_argument('--key-file',type=Path,required=True)
    parser.add_argument('--report',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.action=='encrypt': encrypt(args.target,args.key_file)
    elif args.action=='verify':
        if args.report is None:parser.error('--report is required for verification')
        verify(args.target,args.key_file,args.report)
    else:
        if args.output is None:parser.error('--output is required for extraction')
        decrypt(args.target,args.key_file,args.output)

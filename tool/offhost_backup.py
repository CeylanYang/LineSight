"""Pull a fresh encrypted cloud snapshot; no credentials enter public reports."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from export_cloud_backup import verify
from backup_retention import expire

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = Path.home() / 'LineSight-private' / 'cloud-backups'
SSH_KEY = Path.home() / '.ssh' / 'linesight-ali-baot.pem'
HOST = 'root@47.111.81.94'
REMOTE = '/opt/linesight-identity/api-cutover'
STAMP = re.compile(r'\d{8}T\d{12}Z')


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=600, **kwargs)
    if result.returncode:
        # Remote output may contain configuration. Keep failure reports generic.
        raise RuntimeError(f'{Path(args[0]).name} failed ({result.returncode}); no retention performed')
    return result.stdout


def execute():
    PRIVATE.mkdir(parents=True, exist_ok=True)
    # Windows user-only ACL, inherited by snapshots, keys, temporary plaintext DB.
    sid = run(['whoami', '/user', '/fo', 'csv', '/nh']).strip().split(',')[-1].strip('"')
    run(['icacls', str(PRIVATE), '/inheritance:r', '/grant:r',
         f'*{sid}:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F'])
    keys = PRIVATE / 'keys'; keys.mkdir(exist_ok=True)
    ssh = ['ssh', '-i', str(SSH_KEY), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', HOST]
    scp = ['scp', '-i', str(SSH_KEY), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
    # Server-side scheduled backup already uses the same snapshot implementation.
    raw = run(ssh + [f'/opt/linesight/venv/bin/python {REMOTE}/rehearse_cloud_restore.py --backup-only'])
    report = json.loads(raw)
    stamp = report['at']
    if not STAMP.fullmatch(stamp) or report['backup'] != f'/var/backups/linesight/complete/{stamp}':
        raise ValueError('Unexpected server snapshot path')
    destination = PRIVATE / stamp; destination.mkdir()
    key = keys / f'{stamp}.bin'
    with key.open('xb') as stream:
        stream.write(os.urandom(32))
    remote_key = f'/root/linesight-restore-private/export-key-{stamp}.bin'
    # Snapshot-specific names also permit a separate manual exporter safely.
    run(ssh + [f'test ! -e {remote_key}'])
    try:
        run(scp + [str(key), f'{HOST}:{remote_key}'])
        run(ssh + [f'chmod 600 {remote_key}'])
        run(ssh + [f'/opt/linesight/venv/bin/python {REMOTE}/export_cloud_backup.py encrypt {report["backup"]} --key-file {remote_key}'])
        archive = destination / 'portable-backup.lsbk'
        run(scp + [f'{HOST}:{report["backup"]}/portable-backup.lsbk', str(archive) + '.partial'])
        Path(str(archive) + '.partial').replace(archive)
        verification = destination / 'verification.json'
        verify(archive, key, verification)
        result = json.loads(verification.read_text())
        # A server recovery point may expire only after receipt of an actually
        # verified off-host copy. Failed/partial transfers never create receipts.
        run(scp + [str(verification), f'{HOST}:{report["backup"]}/offhost-verified.json'])
        remote_retention = json.loads(run(ssh + [
            f'/opt/linesight/venv/bin/python {REMOTE}/backup_retention.py --server --apply']))
        local_retention = expire(PRIVATE, apply=True)
        result.update(completed_at=dt.datetime.now(dt.timezone.utc).isoformat(),
                      automatic_offhost_copy=True, local_retention=local_retention,
                      remote_retention=remote_retention)
        latest = PRIVATE / 'last-success.json'
        temp = latest.with_suffix('.tmp'); temp.write_text(json.dumps(result, indent=2), encoding='utf-8')
        temp.replace(latest)
        print(json.dumps(result))
    finally:
        run(ssh + [f'rm -f -- {remote_key}'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    PRIVATE.mkdir(parents=True, exist_ok=True)
    # Lock is process-owned; a crash does not strand a stale lock file.
    import msvcrt
    with (PRIVATE / 'pull.lock').open('a+b') as lock:
        lock.seek(0); lock.write(b'0'); lock.flush(); lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        execute()

"""Expire verified recovery points: 30 days + 8 weekly + 12 monthly anchors.

Only snapshots with verified off-host copies qualify. Rehearsals, incomplete
snapshots, unknown files, links and the latest seven distinct days are preserved.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import shutil

STAMP = re.compile(r'\d{8}T\d{12}Z')


def select_expired(stamps, now):
    dated = {s: dt.datetime.strptime(s, '%Y%m%dT%H%M%S%fZ').replace(tzinfo=dt.timezone.utc)
             for s in stamps if STAMP.fullmatch(s)}
    ordered = sorted(dated, reverse=True)
    keep = set()
    days, weeks, months = set(), set(), set()
    for stamp in ordered:
        moment = dated[stamp]
        day = moment.date()
        week = moment.isocalendar()[:2]
        month = (moment.year, moment.month)
        if day not in days and len(days) < 7:
            keep.add(stamp); days.add(day)
        if week not in weeks and len(weeks) < 8:
            keep.add(stamp); weeks.add(week)
        if month not in months and len(months) < 12:
            keep.add(stamp); months.add(month)
        if now - moment <= dt.timedelta(days=30):
            keep.add(stamp)
    return sorted(set(dated) - keep)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def linked(path):
    return path.is_symlink() or bool(getattr(path.lstat(), 'st_file_attributes', 0) & 0x400)


def expire(root, *, server=False, apply=False, now=None):
    root = Path(root)
    if linked(root) or root.resolve() != root.absolute():
        raise ValueError('Backup root must be a canonical directory')
    root = root.resolve()
    now = now or dt.datetime.now(dt.timezone.utc)
    eligible = {}
    snapshots = [p for p in root.iterdir() if STAMP.fullmatch(p.name)]
    # Only complete, verified recovery points can replace another anchor.
    stamps = []
    for folder in snapshots:
        if linked(folder) or not folder.is_dir() or folder.resolve().parent != root:
            continue
        if any(linked(p) for p in folder.rglob('*')):
            continue
        report = folder / ('offhost-verified.json' if server else 'verification.json')
        archive = folder / 'portable-backup.lsbk'
        if not report.is_file() or not archive.is_file():
            continue
        try:
            data = json.loads(report.read_text(encoding='utf-8-sig'))
            if (data.get('backup') != folder.name or data.get('off_host_copy_verified') is not True
                    or data.get('all_file_hashes_verified') is not True
                    or data.get('authentication_tag_verified') is not True
                    or data.get('archive_sha256') != digest(archive)):
                continue
        except (ValueError, OSError):
            continue
        if server:
            source = folder / 'report.json'
            if not source.is_file():
                continue
            try:
                if json.loads(source.read_text()).get('mode') != 'backup':
                    continue
            except (ValueError, OSError):
                continue
            if any(p.name.startswith('restored') or 'rehearsal' in p.name for p in folder.iterdir()):
                continue
        else:
            if {p.name for p in folder.iterdir()} != {'portable-backup.lsbk', 'verification.json'}:
                continue
            key = root / 'keys' / (folder.name + '.bin')
            if not key.is_file() or linked(root/'keys') or linked(key):
                continue
        stamps.append(folder.name)
        eligible[folder.name] = folder
    candidates = select_expired(stamps, now)
    removed = []
    if apply:
        for stamp in candidates:
            folder = eligible[stamp]
            # Revalidate resolved deletion targets immediately before deletion.
            if linked(folder) or folder.resolve().parent != root:
                raise ValueError('Snapshot path changed')
            shutil.rmtree(folder)
            if not server:
                key = root/'keys'/(stamp+'.bin')
                if key.resolve().parent != (root/'keys').resolve():
                    raise ValueError('Key path changed')
                key.unlink()
            removed.append(stamp)
    usage = shutil.disk_usage(root)
    return {'policy':'30 days, 8 weekly, 12 monthly, latest 7 distinct days',
            'verified_eligible':len(eligible), 'expiry_candidates':candidates, 'removed':removed,
            'applied':apply,'free_bytes':usage.free,
            'capacity_warning':usage.free < 2*1024**3 or usage.free/usage.total < .15}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    root = Path('/var/backups/linesight/complete') if args.server else Path.home()/'LineSight-private/cloud-backups'
    print(json.dumps(expire(root, server=args.server, apply=args.apply)))

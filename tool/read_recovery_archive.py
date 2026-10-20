"""Verify a LineSight LSR diagnostic export and optionally extract raw cells.

Usage: python tool/read_recovery_archive.py original.lsr [--extract NEW_DIRECTORY]
No database is modified. Extracted filenames are generated, never taken from keys.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import tempfile
import sys

MAX_FILE = 256 * 1024 * 1024
MAX_LINE = 1024 * 1024


def verify(source, output=None):
    """Return metadata and per-cell hashes after checking the entire file."""
    source = Path(source)
    if source.stat().st_size > MAX_FILE:
        raise ValueError('Archive exceeds the 256 MiB limit')
    if output is not None:
        output = Path(output).resolve()
        if not output.is_dir():
            raise ValueError('Extraction scratch directory must exist')
    digest = hashlib.sha256()
    payload_bytes = total_raw = 0
    metadata = None
    active = None
    current_file = None
    cells = []
    identities = set()
    try:
        with source.open('rb') as stream:
            magic = stream.readline(MAX_LINE + 1)
            if magic != b'LINESIGHT-RECOVERY/1\n':
                raise ValueError('Unsupported LSR header')
            digest.update(magic)
            payload_bytes += len(magic)
            while True:
                raw = stream.readline(MAX_LINE + 1)
                if not raw or len(raw) > MAX_LINE or not raw.endswith(b'\n'):
                    raise ValueError('Missing, oversized or incomplete record')
                if payload_bytes + len(raw) > MAX_FILE:
                    raise ValueError('Archive grew beyond the file-size limit')
                row = json.loads(raw.decode('utf-8'))
                if not isinstance(row, dict):
                    raise ValueError('Record must be an object')
                kind = row.get('type')
                if kind == 'checksum':
                    if metadata is None or active is not None:
                        raise ValueError('Incomplete archive or cell')
                    if (row.get('algorithm') != 'SHA-256'
                            or row.get('bytes') != payload_bytes
                            or row.get('sha256') != digest.hexdigest()):
                        raise ValueError('Payload checksum or length mismatch')
                    if stream.read(1):
                        raise ValueError('Unexpected bytes after checksum')
                    if metadata.get('bytes') != total_raw:
                        raise ValueError('Original byte count does not match metadata')
                    return {'snapshot': metadata, 'raw_bytes': total_raw,
                            'payload_sha256': digest.hexdigest(), 'cells': cells}
                digest.update(raw)
                payload_bytes += len(raw)
                if metadata is None:
                    if kind != 'manifest' or not isinstance(row.get('snapshot'), dict):
                        raise ValueError('Missing manifest')
                    metadata = row['snapshot']
                    if type(metadata.get('bytes')) is not int or metadata['bytes'] < 0:
                        raise ValueError('Invalid raw size in manifest')
                    continue
                if kind == 'cell':
                    if active is not None or row.get('table') not in ('state', 'chunks'):
                        raise ValueError('Invalid cell ordering or table')
                    size = row.get('bytes')
                    if type(size) is not int or not 0 <= size <= MAX_FILE:
                        raise ValueError('Invalid cell size')
                    if row['table'] == 'state':
                        if not isinstance(row.get('key'), str):
                            raise ValueError('Missing state key')
                        identity = ('state', row['key'])
                    else:
                        if not isinstance(row.get('owner'), str) or type(row.get('part')) is not int:
                            raise ValueError('Missing chunk owner or part')
                        identity = ('chunks', row['owner'], row['part'])
                    if identity in identities:
                        raise ValueError('Duplicate raw cell')
                    identities.add(identity)
                    active = dict(row)
                    active.pop('type')
                    active['file'] = f'cell-{len(cells):06d}.bin'
                    cell_digest = hashlib.sha256()
                    cell_bytes = segment = 0
                    if output is not None:
                        current_file = (output / active['file']).open('xb')
                elif kind == 'segment':
                    if active is None or type(row.get('index')) is not int or row['index'] != segment:
                        raise ValueError('Missing cell or out-of-order segment')
                    if not isinstance(row.get('base64'), str):
                        raise ValueError('Missing segment bytes')
                    block = base64.b64decode(row['base64'], validate=True)
                    if not 0 < len(block) <= 64 * 1024:
                        raise ValueError('Invalid segment size')
                    segment += 1
                    cell_bytes += len(block)
                    if cell_bytes > active['bytes']:
                        raise ValueError('Cell exceeds declared length')
                    cell_digest.update(block)
                    if current_file is not None:
                        current_file.write(block)
                elif kind == 'endCell':
                    if (active is None or type(row.get('segments')) is not int
                            or row['segments'] != segment or cell_bytes != active['bytes']):
                        raise ValueError('Incomplete raw cell')
                    if current_file is not None:
                        current_file.close()
                        current_file = None
                    active['sha256'] = cell_digest.hexdigest()
                    total_raw += cell_bytes
                    cells.append(active)
                    active = None
                else:
                    raise ValueError('Unexpected record type')
    finally:
        if current_file is not None:
            current_file.close()


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--extract', type=Path,
                        help='New directory for exact raw cells and index.json')
    args = parser.parse_args()
    if args.extract is None:
        report = verify(args.archive)
    else:
        destination = args.extract.resolve()
        if destination.exists():
            parser.error('Extraction destination already exists; choose a new directory')
        if not destination.parent.is_dir():
            parser.error('Extraction parent directory does not exist')
        # Only this newly issued temporary directory is automatically cleaned up.
        with tempfile.TemporaryDirectory(prefix='linesight-lsr-', dir=destination.parent) as scratch:
            scratch_path = Path(scratch).resolve()
            if scratch_path.parent != destination.parent:
                raise ValueError('Scratch directory is outside the selected parent')
            report = verify(args.archive, scratch_path)
            (scratch_path / 'index.json').write_text(
                json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            destination.mkdir()  # Refuses to overwrite an existing destination.
            for item in scratch_path.iterdir():
                target = destination / item.name
                if item.resolve().parent != scratch_path or target.resolve().parent != destination:
                    raise ValueError('Extraction path escaped its owned directory')
                item.rename(target)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

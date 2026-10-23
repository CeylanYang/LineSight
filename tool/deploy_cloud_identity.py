"""Host-side reversible OIDC API cutover. Run with the production Python venv."""
import datetime
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time
from urllib.request import Request, urlopen

staging = Path(__file__).resolve().parent
backend = Path('/opt/linesight/backend')
envfile = Path('/etc/linesight/linesight.env')
database = Path('/var/lib/linesight/linesight.sqlite3')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = Path('/var/backups/linesight/identity') / ('api-' + stamp)
backup.mkdir(mode=0o700)


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def snapshot(path):
    with sqlite3.connect(path) as db:
        names = [row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        return {name: ([row[1] for row in db.execute(f'PRAGMA table_info("{name}")')],
                       list(db.execute(f'SELECT * FROM "{name}"'))) for name in names}


run(sys.executable, '-m', 'pip', 'install', 'PyJWT[crypto]==2.15.1', '--quiet')
shutil.copytree(backend, backup / 'backend')
shutil.copy2(envfile, backup / 'linesight.env')
run('systemctl', 'stop', 'linesight')
try:
    with sqlite3.connect(database) as source, sqlite3.connect(backup / 'linesight.sqlite3') as dest:
        source.backup(dest)
    before = snapshot(backup / 'linesight.sqlite3')
    with tarfile.open(staging / 'cloud-api.tar.gz') as bundle:
        bundle.extractall(backend, filter='data')
    for line in envfile.read_text().splitlines():
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            os.environ[key] = value.strip().strip('"').strip("'")
    os.environ['DJANGO_SETTINGS_MODULE'] = 'linesight.production_settings'
    run(sys.executable, str(backend / 'manage.py'), 'migrate', '--fake-initial', cwd=backend)
    run(sys.executable, str(staging / 'migrate_legacy_cloud.py'), cwd=backend)
    # Every original row/column must survive the migration exactly.
    with sqlite3.connect(database) as db:
        for name, (columns, rows) in before.items():
            if name == 'django_migrations':
                continue
            selected = ','.join('"' + col + '"' for col in columns)
            actual = set(db.execute(f'SELECT {selected} FROM "{name}"'))
            assert all(row in actual for row in rows), 'Original data changed in ' + name
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
    private = dict(line.split('=', 1) for line in Path('/opt/linesight-identity/identity.env').read_text().splitlines() if '=' in line)
    newvars = {'LINESIGHT_OIDC_ISSUER': 'https://47.111.81.94/sso/realms/linesight',
               'LINESIGHT_OIDC_CLIENT_SECRET': private['LINESIGHT_OIDC_CLIENT_SECRET']}
    lines = [line for line in envfile.read_text().splitlines() if line.split('=', 1)[0] not in newvars]
    envfile.write_text('\n'.join(lines) + '\n' + ''.join(f'{k}={v}\n' for k, v in newvars.items()))
    os.chmod(envfile, 0o640)
    run('chown', 'linesight:linesight', str(database))
    run('chown', '-R', 'root:linesight', str(backend))
    run('systemctl', 'start', 'linesight')
    for attempt in range(15):
        try:
            with urlopen(Request('http://127.0.0.1:8000/', headers={'Host': '47.111.81.94', 'X-Forwarded-Proto': 'https'}), timeout=3) as response:
                assert json.load(response)['status'] == 'ready'
            break
        except Exception:
            if attempt == 14:
                raise
            time.sleep(1)
    report = {'backup': str(backup), 'old_tables_preserved': len(before), 'all_original_rows_preserved': True,
              'foreign_keys_valid': True, 'api_health': True, 'oidc_enabled': True}
    (backup / 'deployment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
except BaseException:
    run('systemctl', 'stop', 'linesight')
    backend.rename(backup / 'failed-backend')
    shutil.copytree(backup / 'backend', backend)
    shutil.copy2(backup / 'linesight.env', envfile)
    shutil.copy2(backup / 'linesight.sqlite3', database)
    run('chown', 'linesight:linesight', str(database))
    run('chown', '-R', 'root:linesight', str(backend))
    run('systemctl', 'start', 'linesight')
    print('API cutover failed; source, database and environment restored.', file=sys.stderr)
    raise

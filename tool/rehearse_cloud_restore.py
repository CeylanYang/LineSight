"""Root-only cloud snapshots and isolated restore rehearsal; never replaces live data.

Run with /opt/linesight/venv/bin/python. Public JSON contains counts/hashes only.
Private backups include credentials and are retained under a mode-0700 directory.
"""
import argparse
from contextlib import closing
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
from urllib.request import Request, urlopen


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def media_path(root, name):
    path = (root / name).resolve()
    if not name or not path.is_relative_to(root.resolve()) or path == root.resolve():
        raise ValueError('Evidence path escapes the media directory')
    return path


def sqlite_manifest(db):
    output = {}
    for (table,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
        # Table names come from the schema and are still quoted as identifiers.
        quoted = table.replace('"', '""')
        rows = db.execute(f'SELECT * FROM "{quoted}"').fetchall()
        encoded = sorted(json.dumps(row, ensure_ascii=False, default=lambda value: value.hex()) for row in rows)
        output[table] = {'count': len(rows), 'sha256': hashlib.sha256('\n'.join(encoded).encode()).hexdigest()}
    return output


class Provider:
    container = 'linesight-identity_postgres_1'

    def __init__(self):
        self.user = subprocess.check_output(['podman', 'exec', self.container, 'printenv', 'POSTGRES_USER'], text=True).strip()
        self.database = subprocess.check_output(['podman', 'exec', self.container, 'printenv', 'POSTGRES_DB'], text=True).strip()
        if not all(re.fullmatch(r'[A-Za-z0-9_]+', value) for value in (self.user, self.database)):
            raise ValueError('Unexpected provider database identifier')

    def command(self, program, *args):
        return ['podman', 'exec', '-i', self.container, program, '-U', self.user, *args]

    def sql(self, database, sql):
        return subprocess.check_output(self.command('psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-d', database, '-c', sql), text=True).strip()

    def manifest(self, database, snapshot=None):
        prefix = f"BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET TRANSACTION SNAPSHOT '{snapshot}';" if snapshot else ''
        tables = self.sql(database, prefix + "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;" + ('COMMIT;' if snapshot else '')).splitlines()
        queries = []
        for table in tables:
            if not re.fullmatch(r'[A-Za-z0-9_]+', table):
                raise ValueError('Unexpected provider table identifier')
            queries.append(f"SELECT json_build_object('table','{table}','count',count(*),'md5',md5(COALESCE(string_agg(row_to_json(t)::text,E'\\n' ORDER BY row_to_json(t)::text COLLATE \"C\"),''))) FROM public.\"{table}\" t;")
        data = self.sql(database, prefix + '\n'.join(queries) + ('COMMIT;' if snapshot else ''))
        return {row['table']: {k: v for k, v in row.items() if k != 'table'} for row in map(json.loads, data.splitlines())}

    def backup(self, destination):
        exporter = subprocess.Popen(self.command('psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-d', self.database), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            exporter.stdin.write('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT pg_export_snapshot();\n')
            exporter.stdin.flush()
            snapshot = exporter.stdout.readline().strip()
            if not re.fullmatch(r'[0-9A-Fa-f-]+', snapshot):
                raise RuntimeError('Could not acquire a provider snapshot')
            with destination.open('wb') as stream:
                subprocess.run(self.command('pg_dump', '-d', self.database, '-Fc', '--no-owner', '--no-acl', '--snapshot=' + snapshot), stdout=stream, check=True)
            return self.manifest(self.database, snapshot)
        finally:
            if exporter.poll() is None:
                exporter.stdin.write('ROLLBACK;\n\\q\n')
                exporter.stdin.flush()
            exporter.communicate(timeout=20)
            if exporter.returncode:
                raise RuntimeError('Provider snapshot transaction failed')

    def restore(self, dump, database, exercise=None):
        if not re.fullmatch(r'linesight_restore_[0-9a-z_]+', database) or database == self.database:
            raise ValueError('Restore target must be a dedicated rehearsal database')
        self.sql(self.database, f'CREATE DATABASE "{database}";')
        try:
            with dump.open('rb') as stream:
                subprocess.run(self.command('pg_restore', '-d', database, '--exit-on-error', '--no-owner', '--no-acl'), stdin=stream, check=True)
            restored = self.manifest(database)
            if exercise is not None:
                exercise(database)
            return restored
        finally:
            self.sql(self.database, f'DROP DATABASE "{database}";')


def verify_restored_api(directory):
    # This process binds Django to the clone before importing any models.
    directory = directory.resolve()
    if (not directory.is_relative_to(Path('/var/backups/linesight/complete'))
            or directory.name != 'restored'
            or not re.fullmatch(r'[0-9]{8}T[0-9]{12}Z', directory.parent.name)):
        raise ValueError('API verification is restricted to isolated rehearsal copies')
    for line in Path('/etc/linesight/linesight.env').read_text().splitlines():
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            os.environ[key] = value.strip().strip('"').strip("'")
    os.environ['LINESIGHT_DATA_DIR'] = str(directory)
    os.environ['DJANGO_SETTINGS_MODULE'] = 'linesight.production_settings'
    sys.path.insert(0, '/opt/linesight/backend')
    # Match the production manage.py/wsgi SQLite adapter on this host.
    try:
        import pysqlite3
        sys.modules['sqlite3'] = pysqlite3
    except ImportError:
        pass
    import django
    django.setup()
    from django.conf import settings
    from django.core.management import call_command
    from django.contrib.auth import get_user_model
    from rest_framework.test import APIClient
    from collaboration.models import Membership, Evidence, CloudIdentity, ProductionJob
    assert Path(settings.DATABASES['default']['NAME']).resolve() == (directory / 'linesight.sqlite3').resolve()
    call_command('migrate', verbosity=0, interactive=False)
    settings.ALLOWED_HOSTS = ['testserver']
    owner = Membership.objects.filter(role='owner', workspace__jobs__evidence__isnull=False).select_related('user').distinct().first()
    assert owner is not None
    base = f'/api/v1/workspaces/{owner.workspace_id}/'
    client = APIClient(); client.force_authenticate(owner.user)
    assert client.get(base + 'jobs/', secure=True).status_code == 200
    assert client.get(base + 'records/', secure=True).status_code == 200
    assert client.get(base + 'report/', secure=True).status_code == 200
    photo = Evidence.objects.filter(job__workspace_id=owner.workspace_id).first()
    photo_checked = False
    if photo:
        response = client.get(base + f'jobs/{photo.job_id}/evidence/{photo.pk}/original/', secure=True)
        assert response.status_code == 200
        actual = hashlib.sha256(b''.join(response.streaming_content)).hexdigest()
        assert actual == sha(media_path(directory / 'media', photo.image.name))
        photo_checked = True
    # Synthetic users exist in the clone only; snapshot equality is verified first.
    viewer = get_user_model().objects.create_user(username='restore_rehearsal_viewer')
    outsider = get_user_model().objects.create_user(username='restore_rehearsal_outsider')
    Membership.objects.create(workspace_id=owner.workspace_id, user=viewer, role='viewer')
    client.force_authenticate(viewer)
    assert client.get(base + 'jobs/', secure=True).status_code == 200
    assert client.post(base + 'jobs/', {'part_name':'Denied clone write','printer':'A1','quantity':1}, format='json', secure=True).status_code == 403
    client.force_authenticate(outsider)
    assert client.get(base + 'jobs/', secure=True).status_code == 404
    client.force_authenticate(None)
    assert client.get(base + 'jobs/', secure=True).status_code == 401
    assert CloudIdentity.objects.filter(is_demo=True).exists()
    return {'restored_jobs': ProductionJob.objects.count(), 'owner_read': True, 'viewer_read': True, 'viewer_write_status':403, 'outsider_status':404, 'anonymous_status':401, 'authenticated_photo_read':photo_checked, 'oidc_transport':'Membership/API checks use force_authenticate on clone; provider boot/login not exercised.'}


def copy_deployment_config(backup, sources):
    """Copy an explicit configuration allowlist; never follow key-file links."""
    fingerprints = {}
    base = (backup/'deployment').resolve()
    base.mkdir(mode=0o700)
    for name, source in sources.items():
        source = Path(source)
        target = base/name
        if (Path(name).is_absolute() or '..' in Path(name).parts
                or not target.resolve().is_relative_to(base)):
            raise ValueError('Deployment backup path escapes its root')
        if source.is_symlink() or not source.is_file():
            raise ValueError('Required deployment configuration missing or linked')
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copyfile(source, target); target.chmod(0o600)
        if sha(source) != sha(target):
            raise RuntimeError('Deployment configuration changed while copying')
        fingerprints[target.relative_to(backup).as_posix()] = sha(target)
    return fingerprints


def deployment_config_sources():
    sources = {'caddy/Caddyfile':'/etc/caddy/Caddyfile'}
    if Path('/etc/linesight-postfix-stage.json').is_file():
        sources.update({
            'postfix/main.cf':'/etc/postfix/main.cf',
            'postfix/master.cf':'/etc/postfix/master.cf',
            'opendkim/opendkim.conf':'/etc/opendkim.conf',
            'opendkim/linesight2026.private':'/etc/opendkim/keys/99ai.pronhubcn.com/linesight2026.private',
            'opendkim/linesight2026.txt':'/etc/opendkim/keys/99ai.pronhubcn.com/linesight2026.txt',
            'mail/stage.json':'/etc/linesight-postfix-stage.json',
            'mail/linesight-mailpit.service':'/etc/systemd/system/linesight-mailpit.service',
        })
    if Path('/etc/linesight-smtp-relay.json').is_file():
        sources.update({
            'postfix/sasl_passwd':'/etc/postfix/sasl_passwd',
            'postfix/sasl_passwd.db':'/etc/postfix/sasl_passwd.db',
            'postfix/linesight_transport':'/etc/postfix/linesight_transport',
            'postfix/linesight_transport.db':'/etc/postfix/linesight_transport.db',
            'mail/relay.json':'/etc/linesight-smtp-relay.json',
        })
    return sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backup-only', action='store_true')
    parser.add_argument('--verify-api', type=Path)
    args = parser.parse_args()
    if args.verify_api:
        result = verify_restored_api(args.verify_api.resolve())
        print(json.dumps(result))
        return
    if os.name != 'posix' or os.geteuid() != 0:
        raise RuntimeError('Run this host-side command as root')
    os.umask(0o077)
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = Path('/var/backups/linesight/complete') / stamp
    backup.mkdir(parents=True, mode=0o700)
    live = Path('/var/lib/linesight')
    with closing(sqlite3.connect(f'file:{live / "linesight.sqlite3"}?mode=ro', uri=True)) as source:
        source.execute('BEGIN')
        expected = sqlite_manifest(source)
        with closing(sqlite3.connect(backup / 'linesight.sqlite3')) as target:
            source.backup(target)
        source.rollback()
    media = backup / 'media'; media.mkdir()
    with closing(sqlite3.connect(backup / 'linesight.sqlite3')) as db:
        files = set(value for row in db.execute('SELECT image,edge_preview FROM collaboration_evidence') for value in row if value)
        for name in files:
            original = media_path(live / 'media', name)
            target = media_path(media, name); target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
            assert sha(original) == sha(target)
        for image, digest in db.execute('SELECT image,content_hash FROM collaboration_evidence'):
            if digest:
                assert sha(media_path(media, image)) == digest, 'Evidence content fingerprint mismatch'
    shutil.copytree('/opt/linesight/backend', backup / 'backend', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2('/etc/linesight/linesight.env', backup / 'linesight.env')
    for name in ['identity.env', 'compose.yaml']:
        shutil.copy2(Path('/opt/linesight-identity') / name, backup / name)
    identity_files = {}
    for name in ['realm', 'providers']:
        source = Path('/opt/linesight-identity') / name
        if source.exists():
            shutil.copytree(source, backup / name)
            for file in (backup / name).rglob('*'):
                if file.is_file():
                    identity_files[file.relative_to(backup).as_posix()] = sha(file)
    shutil.copy2(Path(__file__).resolve(), backup / 'rehearse_cloud_restore.py')
    identity_rehearsal = Path(__file__).with_name('rehearse_restored_identity.py')
    if identity_rehearsal.exists():
        shutil.copy2(identity_rehearsal, backup / identity_rehearsal.name)
    provider = Provider()
    identity_manifest = provider.backup(backup / 'identity.dump')
    deployment_files = copy_deployment_config(backup, deployment_config_sources())
    manifest = {'sqlite':expected, 'provider':identity_manifest, 'media':{name:sha(media_path(media,name)) for name in sorted(files)}, 'identity_runtime_files':identity_files, 'deployment_files':deployment_files}
    (backup / 'private-manifest.json').write_text(json.dumps(manifest, indent=2))
    report = {'at':stamp, 'backup':str(backup), 'mode':'backup' if args.backup_only else 'restore_rehearsal', 'sqlite_tables':len(expected), 'provider_tables':len(identity_manifest), 'media_files':len(files), 'identity_runtime_files':identity_files, 'backup_permissions':'0700 directory / 0600 private files', 'production_replaced':False, 'artifacts_sha256':{name:sha(backup/name) for name in ['linesight.sqlite3','identity.dump','private-manifest.json']}}
    if not args.backup_only:
        restored = backup / 'restored'; restored.mkdir()
        shutil.copy2(backup / 'linesight.sqlite3', restored / 'linesight.sqlite3')
        shutil.copytree(media, restored / 'media')
        with closing(sqlite3.connect(restored / 'linesight.sqlite3')) as db:
            assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
            assert not db.execute('PRAGMA foreign_key_check').fetchall()
            assert sqlite_manifest(db) == expected
        for name, digest in manifest['media'].items():
            assert sha(media_path(restored / 'media', name)) == digest
        database = 'linesight_restore_' + stamp.lower()
        assert provider.restore(backup / 'identity.dump', database) == identity_manifest
        output = subprocess.check_output([sys.executable, str(Path(__file__).resolve()), '--verify-api', str(restored)], text=True)
        report['api'] = json.loads(output.strip().splitlines()[-1])
        report.update(sqlite_rows_identical=True, foreign_keys_valid=True, restored_media_identical=True, provider_rows_identical=True, provider_credentials_clients_keys_identical=True, temporary_provider_database_removed=True)
    for path in backup.rglob('*'):
        path.chmod(0o700 if path.is_dir() else 0o600)
    (backup / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()

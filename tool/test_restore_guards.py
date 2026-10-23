"""Safety boundaries for the live-data restore rehearsal helpers."""
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from rehearse_cloud_restore import Provider, media_path
from rehearse_restored_identity import backup_path, request, LoopbackRedirect
from export_cloud_backup import archive_members, decrypted_bytes, MAGIC
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag


class RestoreGuards(unittest.TestCase):
    def test_encrypted_archive_rejects_wrong_key_and_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            archive=Path(directory)/'snapshot.lsbk'
            key_file=Path(directory)/'key.bin'
            key=os.urandom(32); nonce=os.urandom(12)
            key_file.write_bytes(key)
            data=MAGIC+nonce+AESGCM(key).encrypt(nonce,b'backup fixture',MAGIC)
            archive.write_bytes(data)
            self.assertEqual(decrypted_bytes(archive,key_file),b'backup fixture')
            key_file.write_bytes(os.urandom(32))
            with self.assertRaises(InvalidTag): decrypted_bytes(archive,key_file)
            key_file.write_bytes(key)
            archive.write_bytes(data[:-1]+bytes([data[-1]^1]))
            with self.assertRaises(InvalidTag): decrypted_bytes(archive,key_file)

    def test_archive_rejects_paths_links_and_duplicates(self):
        for name in ['../secret','/etc/passwd','C:/secret','backend\\secret']:
            with self.subTest(name=name), tarfile.open(fileobj=io.BytesIO(),mode='w') as archive:
                archive.addfile(tarfile.TarInfo(name))
                with self.assertRaises(ValueError): archive_members(archive)
        with tarfile.open(fileobj=io.BytesIO(),mode='w') as archive:
            item=tarfile.TarInfo('link');item.type=tarfile.SYMTYPE;item.linkname='/etc/passwd'
            archive.addfile(item)
            with self.assertRaises(ValueError): archive_members(archive)
        with tarfile.open(fileobj=io.BytesIO(),mode='w') as archive:
            archive.addfile(tarfile.TarInfo('same'));archive.addfile(tarfile.TarInfo('same'))
            with self.assertRaises(ValueError): archive_members(archive)

    def test_restore_never_targets_live_or_arbitrary_database(self):
        provider = object.__new__(Provider)
        provider.database = 'keycloak'
        provider.sql = lambda *args: self.fail('Unsafe database reached SQL')
        for name in ['keycloak', 'postgres', 'linesight_restore_x;DROP DATABASE keycloak']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                provider.restore(Path('unused.dump'), name)

    def test_callback_failure_still_drops_only_its_clone(self):
        provider = object.__new__(Provider)
        provider.database = 'keycloak'
        provider.user = 'keycloak'
        commands = []
        provider.sql = lambda database, sql: commands.append((database, sql))
        provider.manifest = lambda database: {'table': {'count': 1}}
        with tempfile.TemporaryDirectory() as directory:
            dump = Path(directory) / 'snapshot.dump'
            dump.write_bytes(b'fixture')
            def fail(database):
                self.assertEqual(database, 'linesight_restore_probe')
                raise RuntimeError('Expected callback failure')
            with patch('rehearse_cloud_restore.subprocess.run'), self.assertRaises(RuntimeError):
                provider.restore(dump, 'linesight_restore_probe', fail)
        self.assertEqual(commands, [('keycloak','CREATE DATABASE "linesight_restore_probe";'),
                                    ('keycloak','DROP DATABASE "linesight_restore_probe";')])

    def test_backup_path_rejects_production_and_traversal(self):
        for name in ['/var/lib/linesight', '/var/backups/linesight/complete/../../linesight',
                     '/var/backups/linesight/complete/latest']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                backup_path(name)

    def test_identity_request_and_redirect_cannot_reach_live_provider(self):
        with self.assertRaises(ValueError):
            request('https://47.111.81.94/sso/realms/linesight/protocol/openid-connect/token')
        with self.assertRaises(ValueError):
            LoopbackRedirect().redirect_request(None, io.BytesIO(), 302, '', {},
                'https://47.111.81.94/sso/realms/linesight')

    def test_media_manifest_cannot_escape_backup_root(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                media_path(Path(directory), '../private.env')


if __name__ == '__main__':
    unittest.main()

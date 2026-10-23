"""Low-resource regression for snapshot integrity and restore target guards."""
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock
from rehearse_cloud_restore import media_path, sqlite_manifest, Provider, verify_restored_api


class RestoreSafetyTests(unittest.TestCase):
    def test_media_paths_remain_inside_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(media_path(root, 'workspace-5/image.png'), root.resolve() / 'workspace-5/image.png')
            for name in ['', '..', '../private.env', str(root.parent / 'private.env')]:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    media_path(root, name)

    def test_online_snapshot_is_equal_and_detects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with closing(sqlite3.connect(root / 'source.sqlite')) as source:
                source.execute('CREATE TABLE records (id INTEGER PRIMARY KEY, data BLOB)')
                source.execute('INSERT INTO records VALUES (?,?)', (1, b'original'))
                source.commit()
                source.execute('BEGIN')
                expected = sqlite_manifest(source)
                with closing(sqlite3.connect(root / 'clone.sqlite')) as clone:
                    source.backup(clone)
                source.rollback()
            with closing(sqlite3.connect(root / 'clone.sqlite')) as clone:
                self.assertEqual(sqlite_manifest(clone), expected)
                clone.execute('UPDATE records SET data=?', (b'corrupted',))
                self.assertNotEqual(sqlite_manifest(clone), expected)

    def test_provider_restore_cannot_target_live_or_arbitrary_database(self):
        provider = Provider.__new__(Provider)
        provider.database = 'keycloak'
        provider.sql = Mock()
        for target in ['keycloak', 'postgres', 'linesight_restore_;DROP DATABASE keycloak', 'linesight_restore_']:
            with self.subTest(target=target), self.assertRaises(ValueError):
                provider.restore(Path('unused.dump'), target)
        provider.sql.assert_not_called()

    def test_api_probe_cannot_bind_live_data_or_original_backup(self):
        for target in ['/var/lib/linesight', '/tmp/restored', '/var/backups/linesight/complete/20261023T134133033402Z']:
            with self.subTest(target=target), self.assertRaises(ValueError):
                verify_restored_api(Path(target))


if __name__ == '__main__':
    unittest.main()

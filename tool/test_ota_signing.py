"""Release signing preflight never rotates an existing app trust anchor."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import ota_release


class SigningPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'lib').mkdir()
        self.key = Ed25519PrivateKey.generate()
        public = base64.b64encode(self.key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        self.anchor = self.root / 'lib/ota_key.dart'
        self.anchor.write_text("const otaPublicKey = '" + public + "';")
        self.private = self.root / 'private.pem'
        root_patch = patch.object(ota_release, 'ROOT', self.root)
        key_patch = patch.object(ota_release, 'PRIVATE', self.private)
        root_patch.start(); key_patch.start()
        self.addCleanup(root_patch.stop); self.addCleanup(key_patch.stop)

    def save(self, key):
        self.private.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

    def test_missing_key_does_not_create_or_rotate_anything(self):
        before = self.anchor.read_bytes()
        with self.assertRaisesRegex(SystemExit, 'Restore its protected backup'):
            ota_release.signed({'sequence': 1})
        self.assertFalse(self.private.exists())
        self.assertEqual(self.anchor.read_bytes(), before)

    def test_wrong_or_invalid_key_cannot_sign(self):
        self.save(Ed25519PrivateKey.generate())
        with self.assertRaisesRegex(SystemExit, 'does not match'):
            ota_release.signed({'sequence': 1})
        self.private.write_bytes(b'not-a-private-key')
        with self.assertRaisesRegex(SystemExit, 'unreadable'):
            ota_release.signed({'sequence': 1})

    def test_matching_key_signs_canonical_payload(self):
        self.save(self.key)
        value = {'sequence': 1, 'action': 'rollback'}
        envelope = ota_release.signed(value)
        payload = base64.b64decode(envelope['payload'])
        self.key.public_key().verify(base64.b64decode(envelope['signature']), payload)
        self.assertEqual(json.loads(payload), value)
        self.assertEqual(payload, b'{"action":"rollback","sequence":1}')

    def test_pack_rejects_before_writing_manifest_or_payload(self):
        import sys
        with patch.object(sys, 'argv', ['ota_release.py', 'pack', '--base', '8102', '--track', 'production', '--sequence', '1']), self.assertRaisesRegex(SystemExit, 'missing'):
            ota_release.main()
        self.assertEqual(list(self.root.rglob('manifest.json')), [])
        self.assertEqual(list(self.root.rglob('*.so')), [])


if __name__ == '__main__':
    unittest.main()

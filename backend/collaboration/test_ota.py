import os
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from django.test import SimpleTestCase


class OtaDistributionTests(SimpleTestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, LINESIGHT_OTA_DIR=self.temp.name)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.folder = Path(self.temp.name) / 'preview/8078/x86_64'
        self.folder.mkdir(parents=True)
        self.url = '/api/v1/ota/preview/8078/x86_64/'

    def test_no_update_is_normal_and_not_cached(self):
        response = self.client.get(self.url + 'manifest.json')
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response['Cache-Control'], 'no-store')

    def test_public_read_only_distribution_has_no_registration_or_upload(self):
        (self.folder / 'manifest.json').write_text('{"payload":"test"}')
        response = self.client.get(self.url + 'manifest.json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'{"payload":"test"}')
        self.assertEqual(self.client.post(self.url + 'manifest.json', {}).status_code, 405)
        self.assertEqual(self.client.get(self.url + 'signing.pem').status_code, 404)
        self.assertEqual(self.client.get(self.url.replace('preview', 'arbitrary') + 'manifest.json').status_code, 404)

    def test_payload_immutable_and_missing_payload_not_success(self):
        name = 'a' * 64 + '.so'
        self.assertEqual(self.client.get(self.url + name).status_code, 404)
        (self.folder / name).write_bytes(b'code')
        response = self.client.get(self.url + name)
        self.assertEqual(b''.join(response.streaming_content), b'code')
        self.assertIn('immutable', response['Cache-Control'])

    def test_manifest_size_bounded(self):
        (self.folder / 'manifest.json').write_bytes(b'x' * 16385)
        self.assertEqual(self.client.get(self.url + 'manifest.json').status_code, 503)

    def test_runtime_configuration_is_bounded_read_only_and_not_cached(self):
        target = Path(self.temp.name) / 'app-config.json'
        with patch.dict(os.environ, LINESIGHT_RUNTIME_CONFIG=str(target)):
            url = '/api/v1/app-config/'
            self.assertEqual(self.client.get(url).status_code, 204)
            self.assertEqual(self.client.post(url, {}).status_code, 405)
            target.write_bytes(b'{"payload":"signed"}')
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response['Cache-Control'], 'no-store')
            self.assertEqual(b''.join(response.streaming_content), target.read_bytes())
            target.write_bytes(b'x' * (256 * 1024 + 1))
            self.assertEqual(self.client.get(url).status_code, 503)

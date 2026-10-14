"""Run with: python -m unittest discover -s test_support -p '*_test.py'."""
import base64
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(ROOT / 'tool/read_recovery_archive.py'), run_name='lsr_reader')
verify = MODULE['verify']


def archive(rows):
    payload = b'LINESIGHT-RECOVERY/1\n' + b''.join(
        json.dumps(row).encode() + b'\n' for row in rows)
    footer = {'type': 'checksum', 'algorithm': 'SHA-256',
              'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
    return payload + json.dumps(footer).encode() + b'\n'


class RecoveryReaderTests(unittest.TestCase):
    def setUp(self):
        # Only the exact temporary directory issued here is cleaned up.
        self.directory = tempfile.TemporaryDirectory(prefix='linesight-reader-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / 'original.lsr'
        self.value = b'\x00\xff\xc3(\xf0\x9f\x98\x80'
        self.rows = [
            {'type': 'manifest', 'snapshot': {'id': 'example', 'bytes': len(self.value)}},
            {'type': 'cell', 'table': 'state', 'key': '../../outside', 'bytes': len(self.value)},
            {'type': 'segment', 'index': 0, 'base64': base64.b64encode(self.value).decode()},
            {'type': 'endCell', 'segments': 1},
        ]
        self.source.write_bytes(archive(self.rows))

    def test_exact_invalid_bytes_and_safe_generated_names(self):
        output = self.root / 'raw'
        output.mkdir()
        result = verify(self.source, output)
        self.assertEqual(result['raw_bytes'], len(self.value))
        self.assertEqual((output / 'cell-000000.bin').read_bytes(), self.value)
        self.assertEqual(result['cells'][0]['key'], '../../outside')
        self.assertEqual(result['cells'][0]['sha256'], hashlib.sha256(self.value).hexdigest())
        self.assertEqual(list(output.iterdir()), [output / 'cell-000000.bin'])

    def test_checksum_truncation_and_extra_bytes_rejected(self):
        good = self.source.read_bytes()
        for bad in [good[:-10], good + b'{}\n', good.replace(b'example', b'altered')]:
            self.source.write_bytes(bad)
            with self.assertRaises(ValueError):
                verify(self.source)

    def test_rehashed_segment_and_count_errors_rejected(self):
        for row_index, field, value in [(2, 'index', 1), (1, 'bytes', 1), (3, 'segments', True)]:
            changed = json.loads(json.dumps(self.rows))
            changed[row_index][field] = value
            self.source.write_bytes(archive(changed))
            with self.assertRaises(ValueError):
                verify(self.source)

    def test_cli_refuses_existing_output_and_leaves_no_final_output_on_failure(self):
        output = self.root / 'extracted'
        command = [sys.executable, str(ROOT / 'tool/read_recovery_archive.py'),
                   str(self.source), '--extract', str(output)]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertTrue((output / 'index.json').is_file())
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual((output / 'cell-000000.bin').read_bytes(), self.value)
        self.source.write_bytes(b'broken')
        broken_output = self.root / 'failed'
        command[-1] = str(broken_output)
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertFalse(broken_output.exists())


if __name__ == '__main__':
    unittest.main()

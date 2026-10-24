"""Regression for Android's successful-exit null-root dump leaving stale XML."""
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


class FreshHierarchyTest(unittest.TestCase):
    def test_null_root_never_reads_the_previous_hierarchy(self):
        calls = []

        def command(parts, **kwargs):
            calls.append(parts)
            if parts[-2:] == ['getprop', 'ro.kernel.qemu']:
                return b'1\n'
            if 'uiautomator' in parts:
                return b'ERROR: null root node returned by UiTestAutomationBridge.\n'
            if 'cat' in parts:
                raise subprocess.CalledProcessError(1, parts, b'No such file')
            if 'rm' in parts:
                return b''
            raise AssertionError(parts)

        script = Path(__file__).with_name('release_android_ui.py')
        with patch.object(sys, 'argv', [str(script), 'inspect']), patch(
            'subprocess.check_output', side_effect=command
        ), self.assertRaises(subprocess.CalledProcessError):
            runpy.run_path(str(script), run_name='__main__')
        dumped = next(parts[-1] for parts in calls if 'uiautomator' in parts)
        read = next(parts[-1] for parts in calls if 'cat' in parts)
        self.assertEqual(dumped, read)
        self.assertRegex(read, r'^/sdcard/linesight-release-ui-[0-9a-f]{32}\.xml$')
        self.assertNotEqual(read, '/sdcard/linesight-release-ui.xml')
        self.assertEqual(calls[-1][-3:], ['rm', '-f', dumped])


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Checker behavior with synthetic binaries, separate from native core validation."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProfileCheckerTests(unittest.TestCase):
    def check(self, version, mode, expected, fail_profile=None):
        with tempfile.TemporaryDirectory(prefix='profile-check-test-') as directory:
            work = Path(directory)
            binary = work / 'core'
            # This executable only emits a version/check status, never starts a proxy.
            binary.write_text('#!' + sys.executable + '\n' +
                              'import sys\n' +
                              'if sys.argv[1] == "version": print(' + repr('sing-box version ' + version) + ')\n' +
                              'else: sys.exit(1 if ' + repr(fail_profile) +
                              ' and sys.argv[-1].endswith(str(' + repr(fail_profile) + ') + ".example.json") else 0)\n')
            binary.chmod(0o700)
            output = work / 'results'
            result = subprocess.run([sys.executable, '-B', str(ROOT / 'tests/check_client_profiles.py'),
                                     '--binary', str(binary), '--mode', mode, '--output', str(output)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, expected, result.stderr)
            if (output / 'summary.json').exists():
                summary = json.loads((output / 'summary.json').read_text())
                self.assertEqual(summary['tested_core'], version)
                self.assertEqual(summary['reviewed_core'], '1.14.2')
                self.assertEqual(summary['mode'], mode)
                self.assertEqual(len(summary['commands']), 4)
                self.assertEqual(summary['result'], 'FAIL' if fail_profile else 'PASS')
                self.assertEqual(summary['tun_start'], 'NOT RUN')
            else:
                self.assertNotEqual(expected, 0)

    def test_reviewed_exact(self):
        self.check('1.14.2', 'reviewed', 0)

    def test_reviewed_refuses_different_version(self):
        for version in ('1.14.0', '1.14.3'):
            self.check(version, 'reviewed', 1)

    def test_compatibility_newer_stable(self):
        self.check('1.14.3', 'compatibility', 0)

    def test_compatibility_same_stable(self):
        self.check('1.14.2', 'compatibility', 0)

    def test_compatibility_refuses_older_or_prerelease(self):
        for version in ('1.14.0', '1.15.0-beta.1', 'invalid'):
            self.check(version, 'compatibility', 1)

    def test_real_check_failures_still_fail_both_modes(self):
        for mode in ('reviewed', 'compatibility'):
            self.check('1.14.2', mode, 1, fail_profile='android')


if __name__ == '__main__':
    unittest.main()

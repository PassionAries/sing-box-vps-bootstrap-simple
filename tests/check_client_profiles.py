#!/usr/bin/env python3
"""Record native CLI construction checks of public examples; never start a TUN."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True)
    parser.add_argument('--mode', choices=('reviewed', 'compatibility'), default='reviewed')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = Path(args.binary).resolve(strict=True)
    output = args.output or ROOT / 'artifacts/client-profiles' / args.mode
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.run([str(binary), 'version'], capture_output=True, text=True, timeout=30)
    first_line = version.stdout.splitlines()[0] if version.stdout else ''
    expected = json.loads((ROOT / 'examples/1.14.2/client-versions.json').read_text())['core']['version']
    match = re.fullmatch(r'sing-box version (\d+\.\d+\.\d+)', first_line)
    assert version.returncode == 0 and match, 'Expected a stable core version'
    actual = match.group(1)
    if args.mode == 'reviewed':
        assert actual == expected, 'Wrong core version for reviewed templates'
    else:
        # CI obtains the current stable build from Homebrew; only the version gate is
        # relaxed here. All four real configuration checks remain mandatory.
        assert tuple(map(int, actual.split('.'))) >= tuple(map(int, expected.split('.'))), 'Core is older than the reviewed baseline'
    records = []
    files = ['examples/1.14.2/client-versions.json', 'tests/check_client_profiles.py', 'tests/client_profiles_test.py']
    with tempfile.TemporaryDirectory(prefix='client-profile-check-') as directory:
        for name in ('server', 'macos', 'android', 'ios'):
            relative = 'examples/1.14.2/' + name + '.example.json'
            files.append(relative)
            work = Path(directory) / name
            work.mkdir()
            command = [str(binary), 'check', '-D', str(work), '-c', str(ROOT / relative)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            records.append({'profile': name, 'command': command, 'exit_code': result.returncode})
            # Only the explicit public fixture allowlist is passed to the binary.
            (output / (name + '.log')).write_text(result.stdout + result.stderr)
    summary = {'mode': args.mode, 'reviewed_core': expected, 'tested_core': actual,
               'result': 'PASS' if all(r['exit_code'] == 0 for r in records) else 'FAIL',
               'environment': {'system': platform.system(), 'release': platform.release(),
                               'machine': platform.machine(), 'python': platform.python_version()},
               'version_output': version.stdout, 'commands': records,
               'source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files},
               'android_app': 'NOT RUN', 'ios_app': 'NOT RUN', 'tun_start': 'NOT RUN',
               'cold_rule_download': 'NOT RUN', 'real_vps': 'NOT RUN'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for record in records:
        print(record['profile'] + ': native configuration check exit ' + str(record['exit_code']))
    assert summary['result'] == 'PASS', 'Native configuration check failed; see public fixture logs'


if __name__ == '__main__':
    main()

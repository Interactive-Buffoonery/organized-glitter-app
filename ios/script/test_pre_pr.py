"""Exercise pre-PR orchestration without booting devices or building apps."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('pre-pr.sh')


class PrePRTests(unittest.TestCase):
    def run_job(self, failed=''):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'script').mkdir()
            for name in ('pre-pr.sh', 'pre-pr-device.sh'):
                shutil.copy(SCRIPT.with_name(name), root / 'script' / name)
            tools = root / 'bin'
            tools.mkdir()
            programs = {
                'git': 'exit 0',
                'xcodegen': 'exit 0',
                'xcodebuild': 'echo "test:$HEAVY_GATE_DEVICE" >> "$TRACE"; [ "$FAIL_DEVICE" != "$HEAVY_GATE_DEVICE" ]',
                'heavy-gate': '''id=$2
shift 3
echo "boot:$id" >> "$TRACE"
HEAVY_GATE_LEASE_TOKEN=test HEAVY_GATE_DEVICE=$id "$@"
status=$?
echo "shutdown:$id" >> "$TRACE"
exit "$status"''',
                'xcrun': '''if [ "$1" = simctl ]; then cat "$DEVICES"; else
printf '{"passedTests":1,"failedTests":0,"skippedTests":0}'
fi''',
            }
            for name, body in programs.items():
                path = tools / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            devices = root / 'devices.json'
            devices.write_text(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
                {'udid': family, 'name': family, 'state': 'Shutdown', 'isAvailable': True,
                 'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.' + family}
                for family in ('iPhone', 'iPad')]}}))
            env = {k: v for k, v in os.environ.items() if not k.startswith('HEAVY_GATE_')}
            env.update(PATH=str(tools) + ':' + env['PATH'], TRACE=str(root / 'trace'),
                       DEVICES=str(devices), FAIL_DEVICE=failed)
            result = subprocess.run(['sh', str(root / 'script/pre-pr.sh')], env=env,
                                    capture_output=True, text=True)
            return result, (root / 'trace').read_text().splitlines()

    def test_sessions_finish_in_order(self):
        result, trace = self.run_job()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ['boot:iPhone', 'test:iPhone', 'test:iPhone',
                                 'shutdown:iPhone', 'boot:iPad', 'test:iPad', 'shutdown:iPad'])

    def test_failed_tests_still_release_device(self):
        result, trace = self.run_job('iPhone')
        self.assertEqual(result.returncode, 1)
        self.assertLess(trace.index('shutdown:iPhone'), trace.index('boot:iPad'))
        self.assertEqual(trace[-1], 'shutdown:iPad')


if __name__ == '__main__':
    unittest.main()

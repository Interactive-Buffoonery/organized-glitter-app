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
    def run_job(self, failed='', gate_status='', diff_failure=''):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'script').mkdir()
            for name in ('pre-pr.sh', 'pre-pr-device.sh'):
                shutil.copy(SCRIPT.with_name(name), root / 'script' / name)
            tools = root / 'bin'
            tools.mkdir()
            programs = {
                'git': '[ -z "$HEAVY_GATE_LEASE_TOKEN" ] || [ -z "$DIFF_FAILURE" ]',
                'xcodegen': 'echo generate >> "$TRACE"',
                'xcodebuild': 'echo "test:$HEAVY_GATE_DEVICE" >> "$TRACE"; [ "$FAIL_DEVICE" != "$HEAVY_GATE_DEVICE" ]',
                'process-gate': '''[ "$#" -eq 8 ] && [ "$1" = --simulator-session ] && [ "$3" = -- ] && [ "$4" = sh ] || exit 64
[ "$5" = "$EXPECTED_WORKER" ] && [ "$2" = "$8" ] || exit 64
case "$7:$8" in iphone:iPhone|ipad:iPad) ;; *) exit 64 ;; esac
if [ -n "$GATE_STATUS" ]; then echo refused >> "$TRACE"; exit "$GATE_STATUS"; fi
id=$2
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
                       DEVICES=str(devices), FAIL_DEVICE=failed, GATE_STATUS=gate_status, DIFF_FAILURE=diff_failure,
                       EXPECTED_WORKER=str(root / "script/pre-pr-device.sh"))
            (root / 'trace').write_text('')
            result = subprocess.run(['sh', str(root / 'script/pre-pr.sh')], env=env,
                                    capture_output=True, text=True)
            return result, (root / 'trace').read_text().splitlines()

    def test_sessions_finish_in_order(self):
        result, trace = self.run_job()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ['boot:iPhone', 'generate', 'test:iPhone', 'test:iPhone',
                                 'shutdown:iPhone', 'boot:iPad', 'test:iPad', 'shutdown:iPad'])
        report = result.stdout.split('Logs and Xcode result bundles')[0]
        summaries = [line for line in report.splitlines() if ': PASS (' in line][-3:]
        self.assertEqual([line.split(':')[0] for line in summaries], ['unit-tests', 'iphone-ui', 'ipad-ui'])

    def test_failed_tests_still_release_device(self):
        result, trace = self.run_job('iPhone')
        self.assertEqual(result.returncode, 1)
        self.assertLess(trace.index('shutdown:iPhone'), trace.index('boot:iPad'))
        self.assertEqual(trace[-1], 'shutdown:iPad')

    def test_gate_refusal_stops_before_tests(self):
        result, trace = self.run_job(gate_status='75')
        self.assertEqual(result.returncode, 75)
        self.assertEqual(trace, ['refused'])
        self.assertIn('process-gate --status and --help', result.stderr)

    def test_whitespace_failure_is_not_gate_refusal(self):
        result, trace = self.run_job(diff_failure='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Workspace has whitespace errors', result.stderr)
        self.assertNotIn('process-gate --status and --help', result.stderr)
        self.assertFalse(any(event.startswith('test:') for event in trace))
        self.assertEqual(trace[-1], 'shutdown:iPad')


if __name__ == '__main__':
    unittest.main()

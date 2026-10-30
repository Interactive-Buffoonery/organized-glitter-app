"""Exercise pre-PR orchestration without booting devices or building apps."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('pre-pr.sh')


class PrePRTests(unittest.TestCase):
    def run_job(self, failed='', fail_status='1', diff_failure='', devices=True, device_set=''):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'script').mkdir()
            for name in ('pre-pr.sh', 'pre-pr-device.sh'):
                shutil.copy(SCRIPT.with_name(name), root / 'script' / name)
            tools = root / 'bin'
            tools.mkdir()
            programs = {
                'git': '[ -z "$DIFF_FAILURE" ]',
                'xcodegen': 'echo generate >> "$TRACE"',
                'xcodebuild': '''set_flag=none
for arg; do case $arg in
  *,id=*) id=${arg##*id=} ;;
  -DVTSimulatorSetLocation=*) set_flag=${arg#*=} ;;
esac; done
echo "test:$id:$set_flag" >> "$TRACE"; [ "$FAIL_DEVICE" != "$id" ] || exit "$FAIL_STATUS"''',
                'xcrun': 'printf \'{"passedTests":1,"failedTests":0,"skippedTests":0}\'',
            }
            for name, body in programs.items():
                path = tools / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith('SIMLOCK_') and not k.endswith('_SIMULATOR_ID')}
            env.update(PATH=str(tools) + ':' + env['PATH'], TRACE=str(root / 'trace'),
                       FAIL_DEVICE=failed, FAIL_STATUS=fail_status,
                       DIFF_FAILURE=diff_failure)
            if devices:
                env.update(IPHONE_SIMULATOR_ID='iPhone', IPAD_SIMULATOR_ID='iPad')
            if device_set:
                env['SIMLOCK_IOS_DEVICE_SET'] = device_set
            (root / 'trace').write_text('')
            result = subprocess.run(['sh', str(root / 'script/pre-pr.sh')], env=env,
                                    capture_output=True, text=True)
            return result, (root / 'trace').read_text().splitlines()

    def test_sessions_finish_in_order(self):
        result, trace = self.run_job()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ['generate', 'test:iPhone:none', 'test:iPhone:none', 'test:iPad:none'])
        report = result.stdout.split('Logs and Xcode result bundles')[0]
        summaries = [line for line in report.splitlines() if ': PASS (' in line][-3:]
        self.assertEqual([line.split(':')[0] for line in summaries], ['unit-tests', 'iphone-ui', 'ipad-ui'])

    def test_device_set_reaches_every_build(self):
        result, trace = self.run_job(device_set='/devices')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([event for event in trace if event.startswith('test:')], ['test:iPhone:/devices', 'test:iPhone:/devices', 'test:iPad:/devices'])

    def test_failed_tests_still_run_the_ipad(self):
        result, trace = self.run_job('iPhone')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace[-1], 'test:iPad:none')

    def test_interrupted_tests_stop_the_run(self):
        result, trace = self.run_job('iPhone', fail_status='143')
        self.assertEqual((result.returncode, trace), (143, ['generate', 'test:iPhone:none']))

    def test_missing_devices_stop_before_tests(self):
        result, trace = self.run_job(devices=False)
        self.assertEqual((result.returncode, trace), (1, []))
        self.assertIn('IPHONE_SIMULATOR_ID and IPAD_SIMULATOR_ID', result.stderr)

    def test_whitespace_failure_skips_tests(self):
        result, trace = self.run_job(diff_failure='1')
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(event.startswith('test:') for event in trace))

if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Exercise failure budgets and concurrency independently of temporal results."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import oracle_replay as replay

ROOT = Path(__file__).resolve().parents[1]


class ReplayTests(unittest.TestCase):
    def setUp(self):
        work = ROOT / '.roc-time-tmp' / 'oracles'
        work.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(prefix='harness-controls-', dir=work)
        self.addCleanup(self.directory.cleanup)
        self.session = Path(self.directory.name)
        self.case = {'id': '0', 'operation': 'forward', 'input': ['1970', '1', '1'],
                     'expected': ['ok', '0'], 'evidence': 'control'}

    def fixture(self, body):
        script = self.session / 'fake-fixture'
        script.write_text(f'#!{sys.executable}\n' + body)
        script.chmod(0o755)
        return script

    def test_negative_protocol_controls(self):
        replay.self_check(self.session)

    def test_trace_markers_are_preserved_without_accepting_other_stderr(self):
        trailer = 'ROC_METRICS protocol=1 allocations=3 requested_bytes=24 deallocations=1 work=1\n'
        result = replay.parse_metrics('ROC_TRACE protocol=1 mark=17 allocations=2\n' + trailer)
        self.assertEqual(result['traces'], [{'mark': 17, 'allocations': 2}])
        with self.assertRaises(ValueError):
            replay.parse_metrics('unexpected warning\n' + trailer)

    def test_timeout_kills_fixture_and_preserves_case(self):
        binary = self.fixture('import time\ntime.sleep(30)\n')
        with patch.object(replay, 'CASE_TIMEOUT', 0.2):
            with self.assertRaisesRegex(ValueError, 'time budget'):
                replay.run_case(binary, self.case, self.session)
        self.assertIn('1970', (self.session / 'failure-0.json').read_text())

    def test_excessive_output_fails_even_after_process_exit(self):
        binary = self.fixture('import sys\nsys.stdout.write("x" * 65536)\n')
        with self.assertRaisesRegex(ValueError, 'output budget'):
            replay.run_case(binary, self.case, self.session)
        self.assertLess((self.session / 'failure-0.json').stat().st_size, 20000)

    def test_parallel_execution_preserves_order_and_worker_bound(self):
        lock = threading.Lock()
        active = peak = 0
        def observe(_binary, case, _session):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            time.sleep(0.015 if int(case['id']) % 2 == 0 else 0.001)
            with lock:
                active -= 1
            return {'id': case['id']}
        cases = [{**self.case, 'id': str(i)} for i in range(12)]
        with patch.object(replay, 'run_case', observe):
            results = replay.replay_cases(Path('unused'), cases, self.session, 3)
        self.assertEqual([r['id'] for r in results], [str(i) for i in range(12)])
        self.assertGreater(peak, 1)
        self.assertLessEqual(peak, 3)

    def test_invalid_transport(self):
        for inputs in (['9223372036854775808', '1', '1'], ['1970', '256', '1'], ['+1', '1', '1']):
            with self.assertRaises(ValueError):
                replay.validate_calendar_cases([{**self.case, 'input': inputs}])
        # These malformed calendar fields are intentionally valid transport:
        # the package under test must return the structured temporal error.
        replay.validate_calendar_cases([{**self.case, 'input': ['1970', '0', '0'], 'expected': ['error', 'InvalidMonth']}])


if __name__ == '__main__':
    unittest.main()

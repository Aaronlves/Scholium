#!/usr/bin/env python3
"""Exercise the real Swift test runners with bounded, synthetic process logs."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFY = (ROOT / "Tools/Scripts/verify.sh").read_text(encoding="utf-8")
FUNCTION_NAMES = (
    "swift_test_success_summary",
    "report_swift_test_success",
    "report_swift_test_failure",
    "run_swift_test_once",
    "run_swift_test_product",
)
FUNCTIONS = "\n".join(
    re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}", VERIFY).group()
    for name in FUNCTION_NAMES
)
SUCCESS = "✔ Test run with 3 tests in 1 suite passed after 0.125 seconds.\n"
START = "◇ Test run started.\n"


class SwiftTestResultTests(unittest.TestCase):
    def run_both(self, log, expected_status, process_status=0):
        scratch_root = ROOT / ".build/verify-swift-results-tests"
        scratch_root.mkdir(parents=True, exist_ok=True)
        for runner in (
            'run_swift_test_once "Fixture" "fixture"',
            'run_swift_test_product "ScholiumContractsTests"',
        ):
            with self.subTest(runner=runner), tempfile.TemporaryDirectory(dir=scratch_root) as directory:
                directory = Path(directory)
                sample = directory / "process.log"
                sample.write_text(log, encoding="utf-8")
                script = "set -euo pipefail\n" + FUNCTIONS + "\n" + """
swift() {
  cat "${MOCK_LOG}"
  return "${MOCK_STATUS}"
}
""" + runner
                result = subprocess.run(
                    ["zsh", "-c", script],
                    env={
                        **os.environ,
                        "ROOT": str(ROOT),
                        "SCRATCH": str(directory / "scratch"),
                        "PROFILE": "full",
                        "MOCK_LOG": str(sample),
                        "MOCK_STATUS": str(process_status),
                    },
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
                if expected_status == 0:
                    self.assertIn(": Test run with ", result.stdout)
                else:
                    self.assertNotIn(": Test run with ", result.stdout)
                    self.assertIn("Complete log:", result.stderr)
                self.assertNotRegex(result.stdout, r": passed(?:\n|$)")

    def test_complete_positive_run(self):
        self.run_both(START + SUCCESS, 0)

    def test_singular_and_suiteless_success(self):
        self.run_both(START + "✔ Test run with 1 test passed after 0.001 seconds.\n", 0)

    def test_absent_summary(self):
        self.run_both("Build complete!\n", 65)

    def test_truncated_run_after_individual_passes(self):
        self.run_both(START + '✔ Test "One" passed after 0.100 seconds.\n◇ Test "Two" started.\n', 65)

    def test_old_success_does_not_complete_later_run(self):
        self.run_both(START + SUCCESS + START + '◇ Test "Next" started.\n', 65)

    def test_zero_tests(self):
        self.run_both(START + "✔ Test run with 0 tests passed after 0.001 seconds.\n", 65)

    def test_no_matching_cases(self):
        self.run_both("warning: No matching test cases were run\n" + START + SUCCESS, 65)

    def test_failed_run_despite_zero_exit(self):
        self.run_both(START + "✘ Test run with 3 tests in 1 suite failed after 0.125 seconds with 1 issue.\n", 65)

    def test_reported_failure_is_not_hidden_by_later_summary(self):
        self.run_both(START + '✘ Test "One" recorded an issue.\n' + SUCCESS, 65)

    def test_nonzero_exit_is_preserved_despite_success_summary(self):
        self.run_both(START + SUCCESS, 7, process_status=7)


if __name__ == "__main__":
    unittest.main()

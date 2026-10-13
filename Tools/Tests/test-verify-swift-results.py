#!/usr/bin/env python3
"""Exercise the real Swift test runners with bounded, synthetic process logs."""

import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFY = (ROOT / "Tools/Scripts/verify.sh").read_text(encoding="utf-8")
FUNCTION_NAMES = (
    "swift_test_success_summary",
    "report_swift_test_success",
    "report_swift_test_failure",
    "run_swift_test_once",
    "run_swift_test_product",
    "prepare_swift_tests",
    "run_measurement_test",
)
FUNCTIONS = "\n".join(
    re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}", VERIFY).group()
    for name in FUNCTION_NAMES
)
SUCCESS = "✔ Test run with 3 tests in 1 suite passed after 0.125 seconds.\n"
START = "◇ Test run started.\n"


def run_shell_fixture(script, environment, cancellation):
    if cancellation is None:
        return subprocess.run(["zsh", "-c", script], env=environment, capture_output=True, text=True, timeout=10)
    directory = Path(environment["RUN_ROOT"]).parent
    mock = directory / "mock-swift"
    mock.write_text("#!/bin/zsh\nprint 'Test run started.'\nprint $$ > \"${CHILD_PID}\"\ntouch \"${READY}\"\nwhile true; do /bin/sleep 1; done\n")
    mock.chmod(0o755)
    environment = {**environment, "MOCK_SWIFT": str(mock), "CHILD_PID": str(directory / "child-pid"),
                   "READY": str(directory / "ready")}
    target, sig = cancellation
    process = subprocess.Popen(["zsh", "-c", script], env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        deadline = time.monotonic() + 5
        while not (directory / "ready").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        if not (directory / "ready").exists():
            raise AssertionError("Signal fixture never became ready")
        child = int((directory / "child-pid").read_text())
        if target == "group":
            os.killpg(process.pid, sig)
        elif target == "root":
            os.kill(process.pid, sig)
            # Cancellation owners stop children too. zsh can defer a foreground
            # command's handler until that command returns.
            time.sleep(0.1)
            if not Path(environment["TEST_TEMP"]).exists():
                raise AssertionError("State removed before foreground child stopped")
            os.kill(child, signal.SIGTERM)
        else:
            os.kill(child, sig)
        stdout, stderr = process.communicate(timeout=5)
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
    finally:
        # This session contains only our disposable mock processes.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if process.poll() is None:
            process.communicate(timeout=5)


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
                        "LOG_ROOT": str(directory),
                        "DEPENDENCIES": str(directory / "dependencies"),
                        "PROFILE": "full",
                        "RUN_ROOT": str(directory),
                        "GITHUB_OUTPUT": str(directory / "action-output"),
                        "GITHUB_STEP_SUMMARY": str(directory / "action-summary"),
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


class BuildCacheFallbackTests(unittest.TestCase):
    def run_build(self, profile, reused, statuses, expected_status, expected_calls):
        scratch_root = ROOT / ".build/verify-swift-results-tests"
        scratch_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch_root) as directory:
            directory = Path(directory)
            scratch = directory / "build"
            dependencies = directory / "dependencies"
            if reused:
                scratch.mkdir()
                dependencies.mkdir()
                (scratch / "cached-marker").touch()
                (dependencies / "cached-marker").touch()
            counter = directory / "calls"
            script = "set -euo pipefail\n" + FUNCTIONS + "\n" + """
swift() {
  local calls=0
  [[ ! -f "${COUNTER}" ]] || calls=$(cat "${COUNTER}")
  calls=$((calls + 1))
  print "$calls" > "${COUNTER}"
  [[ "$*" == *"--build-tests"* && "$*" == *"--force-resolved-versions"* ]] || return 99
  if (( calls == 1 )); then
    print "Build complete!"
    return "${FIRST_STATUS}"
  fi
  print "Build complete!"
  return "${SECOND_STATUS}"
}
prepare_swift_tests
"""
            result = subprocess.run(["zsh", "-c", script], env={
                **os.environ, "ROOT": str(ROOT), "SCRATCH": str(scratch),
                "DEPENDENCIES": str(dependencies), "LOG_ROOT": str(directory),
                "PROFILE": profile, "COUNTER": str(counter),
                "RUN_ROOT": str(directory), "GITHUB_OUTPUT": str(directory / "action-output"),
                "GITHUB_STEP_SUMMARY": str(directory / "action-summary"),
                "FIRST_STATUS": str(statuses[0]), "SECOND_STATUS": str(statuses[1]),
            }, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
            self.assertEqual(int(counter.read_text()), expected_calls)
            output = directory / "action-output"
            self.assertEqual(output.read_text() if output.exists() else "",
                             "build-ready=true\n" if expected_status == 0 else "")
            if reused:
                self.assertEqual((scratch / "cached-marker").exists(), expected_calls == 1)
                self.assertEqual((dependencies / "cached-marker").exists(), expected_calls == 1)
            self.assertTrue((directory / "debug-test-build.log").exists())
            self.assertEqual((directory / "debug-test-build-clean-fallback.log").exists(), expected_calls == 2)

    def test_warm_build_executes_current_source_without_cleaning(self):
        self.run_build("daily", True, (0, 0), 0, 1)

    def test_bad_restored_build_falls_back_once(self):
        self.run_build("daily", True, (1, 0), 0, 2)

    def test_real_compile_failure_remains_visible_after_fallback(self):
        self.run_build("daily", True, (1, 7), 7, 2)

    def test_cold_build_failure_has_no_retry(self):
        self.run_build("daily", False, (7, 0), 7, 1)

    def test_full_build_failure_has_no_cache_fallback(self):
        self.run_build("full", True, (7, 0), 7, 1)


class VerificationExitTests(unittest.TestCase):
    def run_exit(self, phase, process_status, complete=True, cancellation=None):
        # Execute the real call sites, including nested runner failures. An
        # explicit `exit 7` alone misses zsh's default function-trap behavior.
        header = VERIFY.split("\nROOT=", 1)[0]
        reporting = "\n".join(re.search(rf"(?ms)^{name}\(\) \{{\n.*?^\}}", VERIFY).group()
                              for name in ("phase_begin", "phase_end", "finish_verification"))
        build_start = VERIFY.index('\nphase_begin "Current-source Debug test build"')
        loop_start = VERIFY.index("\nfor test_product in ", build_start)
        loop_end = VERIFY.index('\nphase_begin "Compiled localization catalogs"', loop_start)
        body = VERIFY[build_start:loop_start] if phase == "build" else VERIFY[loop_start:loop_end]
        traps = VERIFY[VERIFY.index("\ntrap finish_verification EXIT"):VERIFY.index('\nphase_begin "Documentation and structural guards"')]
        scratch_root = ROOT / ".build/verify-swift-results-tests"
        scratch_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch_root) as directory:
            directory = Path(directory)
            run = directory / "run"
            for name in ("logs", "tmp", "pycache", "build", "release-build", "dependencies", "release-dependencies"):
                (run / name).mkdir(parents=True, exist_ok=True)
            unrelated = directory / "unrelated-build"
            unrelated.mkdir()
            marker = unrelated / "preserve"
            marker.touch()
            sample = directory / "process.log"
            sample.write_text(START + SUCCESS if complete else "Build complete!\n")
            script = header + "\n" + FUNCTIONS + "\n" + reporting + "\n" + """
typeset -F started_at=${EPOCHREALTIME} phase_started=0
phase_label=""
touch "${RUN_ROOT}/timings.tsv"
""" + traps + ('\nswift() { "${MOCK_SWIFT}" "$@"; }\n' if cancellation else
                     '\nswift() { cat "${MOCK_LOG}"; return "${MOCK_STATUS}"; }\n') + body
            result = run_shell_fixture(script, {
                **os.environ, "ROOT": str(ROOT), "RUN_ROOT": str(run), "LOG_ROOT": str(run / "logs"),
                "TEST_TEMP": str(run / "tmp"), "SCRATCH": str(unrelated),
                "DEPENDENCIES": str(run / "dependencies"), "RELEASE_SCRATCH": str(unrelated),
                "MOCK_LOG": str(sample), "MOCK_STATUS": str(process_status),
                "SCHOLIUM_SKIP_MEASUREMENT_EVIDENCE": "1", "SCHOLIUM_SKIP_DISPLAY_EVIDENCE": "1",
                "GITHUB_OUTPUT": str(directory / "action-output"),
                "GITHUB_STEP_SUMMARY": str(directory / "action-summary"),
            }, cancellation)
            expected = 128 + cancellation[1] if cancellation else (process_status if process_status else (0 if complete else 65))
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count("Verification evidence:"), 1)
            summary = (run / "summary.md").read_text()
            self.assertIn(f"exit status: {expected}", summary)
            self.assertEqual(summary, (directory / "action-summary").read_text())
            self.assertEqual((run / "timings.tsv").read_text().splitlines()[-1].split("\t")[-1], str(expected))
            for name in ("tmp", "pycache", "build", "release-build", "dependencies", "release-dependencies"):
                self.assertEqual((run / name).exists(), cancellation is not None, name)
            if cancellation:
                self.assertIn("disposable state retained", summary)
                self.assertIn("interrupted=true", (directory / "action-output").read_text())
            self.assertTrue(marker.exists())
            self.assertTrue(list((run / "logs").glob("*.log")))

    def test_successful_run_reports_and_cleans(self):
        self.run_exit("tests", 0)

    def test_nested_test_failure_reports_and_preserves_status(self):
        self.run_exit("tests", 7)

    def test_incomplete_zero_exit_test_run_is_reported_failed(self):
        self.run_exit("tests", 0, complete=False)

    def test_nested_build_failure_reports_and_preserves_status(self):
        self.run_exit("build", 7)

    def test_child_sigint_reports_and_retains_possible_helper_state(self):
        self.run_exit("tests", 0, cancellation=("child", signal.SIGINT))

    def test_child_sigterm_reports_and_retains_possible_helper_state(self):
        self.run_exit("tests", 0, cancellation=("child", signal.SIGTERM))

    def test_root_sigint_reports_after_child_drain_preserving_int_status(self):
        self.run_exit("tests", 0, cancellation=("root", signal.SIGINT))

    def test_root_sigterm_reports_after_child_drain_preserving_term_status(self):
        self.run_exit("tests", 0, cancellation=("root", signal.SIGTERM))

    def test_group_sigint_reports_once_and_preserves_int_status(self):
        self.run_exit("tests", 0, cancellation=("group", signal.SIGINT))

    def test_group_sigterm_reports_once_and_preserves_term_status(self):
        self.run_exit("tests", 0, cancellation=("group", signal.SIGTERM))



if __name__ == "__main__":
    unittest.main()

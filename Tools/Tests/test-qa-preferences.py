#!/usr/bin/env python3
"""Bounded preservation tests use in-memory preferences, never user domains."""
import copy
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("preservation", ROOT / "Tools/Scripts/preserve-qa-preferences.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakePreferences:
    def __init__(self, values):
        self.values = values
        self.active = False
        self.writes = []
        self.reject_write = False

    def read(self, domain):
        return copy.deepcopy(self.values)

    def write(self, domain, values, snapshot):
        self.writes.append(copy.deepcopy(values))
        if values is not None:
            assert module.same_values(values, plistlib.loads(snapshot.read_bytes()))
        if not self.reject_write:
            self.values = copy.deepcopy(values)

    def require_stopped(self, domain):
        if self.active:
            raise RuntimeError("QA app active")


class PreservationTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".build/qa-preferences-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(directory.cleanup)
        self.state = Path(directory.name) / "snapshot"
        self.preferences = FakePreferences({"native frame": "original", "enabled": True, "data": b"\x00\xff", "nested": [1, 2.5, {"x": False}]})
        self.original = copy.deepcopy(self.preferences.values)

    def capture(self):
        module.capture(self.state, module.DOMAIN, os.getpid(), self.preferences)

    def restore(self):
        module.restore(self.state, module.DOMAIN, os.getpid(), self.preferences)

    def test_captures_complete_types_without_reset_and_restores_task_changes(self):
        self.capture()
        self.assertEqual(self.preferences.writes, [])
        self.assertTrue(module.same_values(self.original, plistlib.loads((self.state / "original.plist").read_bytes())))
        self.preferences.values["native frame"] = "task frame"
        self.preferences.values["added by test"] = 42
        del self.preferences.values["data"]
        self.restore()
        self.assertTrue(module.same_values(self.original, self.preferences.values))
        self.assertFalse(self.state.exists())

    def test_absent_and_empty_domains_have_distinct_restoration(self):
        for original in [None, {}]:
            self.preferences.values = original
            self.capture()
            self.preferences.values = {"new test value": 1}
            self.restore()
            self.assertIs(type(self.preferences.values), type(original))
            self.assertEqual(self.preferences.values, original)

    def test_native_delete_may_leave_an_empty_domain_with_no_stored_keys(self):
        self.preferences.values = None
        self.capture()
        self.preferences.values = {}
        self.restore()
        self.assertEqual(self.preferences.writes, [])
        self.assertFalse(self.state.exists())

    def test_unchanged_domain_has_no_write(self):
        self.capture()
        self.restore()
        self.assertEqual(self.preferences.writes, [])

    def test_bool_integer_and_real_types_are_not_interchangeable(self):
        self.capture()
        self.preferences.values["enabled"] = 1
        self.restore()
        self.assertIs(self.preferences.values["enabled"], True)
        self.assertFalse(module.same_values({"x": 1}, {"x": 1.0}))

    def test_rejects_production_domain_and_unresolved_prior_snapshot(self):
        with self.assertRaises(RuntimeError):
            module.capture(self.state, "com.scholium.app", os.getpid(), self.preferences)
        self.assertFalse(self.state.exists())
        self.capture()
        before = (self.state / "original.plist").read_bytes()
        with self.assertRaises(FileExistsError):
            self.capture()
        self.assertEqual((self.state / "original.plist").read_bytes(), before)

    def test_wrong_owner_or_corrupted_prior_copy_never_writes(self):
        self.capture()
        with self.assertRaises(RuntimeError):
            module.restore(self.state, module.DOMAIN, os.getpid() + 1, self.preferences)
        (self.state / "original.plist").write_bytes(b"not a plist")
        with self.assertRaises(Exception):
            self.restore()
        self.assertEqual(self.preferences.writes, [])

    def test_active_app_or_failed_readback_retains_verified_snapshot(self):
        self.capture()
        self.preferences.values = {"task": "changed"}
        self.preferences.active = True
        with patch.object(module.time, "sleep"), self.assertRaises(RuntimeError):
            self.restore()
        self.assertTrue((self.state / "original.plist").exists())
        self.assertEqual(self.preferences.writes, [])
        self.preferences.active = False
        self.preferences.reject_write = True
        with self.assertRaises(RuntimeError):
            self.restore()
        self.assertTrue((self.state / "original.plist").exists())

    def test_native_read_distinguishes_absence_before_export(self):
        result = subprocess.CompletedProcess([], 1, b"", f"Error: Domain '{module.DOMAIN}' not found.".encode())
        with patch.object(module.subprocess, "run", return_value=result) as run:
            self.assertIsNone(module.Preferences().read(module.DOMAIN))
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][1], "read")

    def test_reused_owner_pid_cannot_authorize_restore(self):
        self.capture()
        self.preferences.values = {"task": "changed"}
        with patch.object(module, "owner_started", return_value="different process start"), self.assertRaises(RuntimeError):
            self.restore()
        self.assertEqual(self.preferences.writes, [])
        self.assertTrue((self.state / "original.plist").exists())

    def test_running_app_blocks_capture_before_creating_snapshot(self):
        self.preferences.active = True
        with self.assertRaises(RuntimeError):
            self.capture()
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()

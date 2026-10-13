#!/usr/bin/env python3
"""A cache may restore only within an identical build environment/locked graph."""

import importlib.util
import os
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cache", ROOT / "Tools/Scripts/verification-cache-key.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class CacheKeyTests(unittest.TestCase):
    def test_every_partition_input_and_stability(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"DEVELOPER_DIR": "/selected/Xcode"}):
            root = Path(directory)
            for name in ("Package.swift", "Package.resolved"):
                (root / name).write_text(name)
            values = {}
            def run(args, **kwargs):
                return values.get(tuple(args), "original").encode()
            original = cache.fingerprint(root, run)
            self.assertEqual(original, cache.fingerprint(root, run))
            for command in (("xcodebuild", "-version"), ("xcrun", "swift", "--version"),
                            ("xcrun", "--sdk", "macosx", "--show-sdk-path"),
                            ("xcrun", "--sdk", "macosx", "--show-sdk-version"),
                            ("xcrun", "--sdk", "macosx", "--show-sdk-build-version"),
                            ("uname", "-m"), ("sw_vers", "-buildVersion")):
                values[command] = "changed"
                self.assertNotEqual(original, cache.fingerprint(root, run), command)
                values.clear()
            with patch.dict(os.environ, {"DEVELOPER_DIR": "/other/Xcode"}):
                self.assertNotEqual(original, cache.fingerprint(root, run))
            for name in ("Package.swift", "Package.resolved"):
                (root / name).write_text("changed")
                self.assertNotEqual(original, cache.fingerprint(root, run))
                (root / name).write_text(name)
            other = root / "other-checkout"
            other.mkdir()
            for name in ("Package.swift", "Package.resolved"):
                (other / name).write_text(name)
            self.assertNotEqual(original, cache.fingerprint(other, run))
            (root / "Package.resolved").unlink()
            with self.assertRaises(FileNotFoundError):
                cache.fingerprint(root, run)


if __name__ == "__main__":
    unittest.main()

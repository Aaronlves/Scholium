#!/usr/bin/env python3
"""Check code/prose distinctions without weakening the Contracts boundary."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "Tools/Scripts/validate-contracts-purity.sh"
FORBIDDEN = [
    "FileManager", "URLSession", "SQLite", "FSEvent", "AppKit", "SwiftUI",
    "Combine", "UserDefaults", "NSWorkspace", "NSOpenPanel",
]


class ContractsPurityTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".build/contracts-purity/tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def validate(self, files):
        for name, source in files.items():
            (self.root / name).write_text(source, encoding="utf-8")
        return subprocess.run(
            [str(VALIDATOR), str(self.root)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )

    def test_prose_comments_raw_strings_and_regex_are_not_dependencies(self):
        result = self.validate({"Allowed.swift": r'''
import Foundation
// Combine FileManager AppKit
/* SwiftUI /* UserDefaults */ URLSession */
let message = "Combine complete conditions instead."
let quoted = "An escaped quote: \"FileManager\"; a literal \\(AppKit)"
let multiline = """
Combine complete property and direct-link conditions.
NSWorkspace and NSOpenPanel are prose here.
"""
let raw = ##"FileManager \(SwiftUI) \#(URLSession)"##
let pattern = /FileManager|Combine/
let longerName = "" // Identifiers containing a forbidden word remain allowed.
struct FileManagerDescription {}
'''})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("1 Swift files passed", result.stdout)

    def test_every_existing_forbidden_identifier_is_still_rejected(self):
        files = {f"{name}.swift": f"import {name}\n" for name in FORBIDDEN}
        result = self.validate(files)
        self.assertEqual(result.returncode, 1, result.stdout)
        for name in FORBIDDEN:
            self.assertIn(f"{name}.swift:1:8: error: Contracts cannot reference {name}", result.stdout)

    def test_qualified_calls_escaped_identifiers_and_attributed_imports(self):
        result = self.validate({"Code.swift": '''
@preconcurrency import Combine
let manager = Foundation.FileManager.default
let value = `UserDefaults`.standard
#if os(macOS)
import struct AppKit.NSSize
#endif
'''})
        self.assertEqual(result.returncode, 1, result.stdout)
        for name in ["Combine", "FileManager", "UserDefaults", "AppKit"]:
            self.assertIn(f"Contracts cannot reference {name}", result.stdout)

    def test_string_interpolation_remains_executable_code(self):
        result = self.validate({"Interpolation.swift": r'''
let normal = "Current: \(FileManager.default)"
let raw = ##"Current: \##(UserDefaults.standard)"##
let nested = "\("Inner: \(URLSession.shared)")"
'''})
        self.assertEqual(result.returncode, 1, result.stdout)
        for name in ["FileManager", "UserDefaults", "URLSession"]:
            self.assertIn(f"Contracts cannot reference {name}", result.stdout)

    def test_unparseable_source_fails_closed(self):
        result = self.validate({"Broken.swift": 'let text = "unterminated\n'})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("could not parse Swift source", result.stdout)

    def test_missing_or_empty_source_cannot_pass(self):
        result = self.validate({})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("no Swift sources", result.stdout)
        result = subprocess.run(
            [str(VALIDATOR), str(self.root / "missing")], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("source directory is unavailable", result.stdout)


if __name__ == "__main__":
    unittest.main()

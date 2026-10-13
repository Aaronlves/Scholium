#!/usr/bin/env python3
"""Exercise event ancestry and hostile path cases without touching the checkout."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("route", ROOT / "Tools/Scripts/classify-verification.py")
route = importlib.util.module_from_spec(spec)
spec.loader.exec_module(route)


class RoutingTests(unittest.TestCase):
    def test_hostile_and_unknown_paths(self):
        names = ("Docs/Status/03-open-work.md\nScholium/App.swift", "../README.md",
                 "Docs/Status/../Status/03-open-work.md", "Docs/Status/99-unknown.md",
                 "Docs/Status/03-open-work.MD", "Docs/Status/03-open-work.md/evil",
                 "Tools/Scripts/verify.sh", "Package.swift", "Package.resolved", ".github/workflows/verify.yml",
                 "AGENTS.md", ".agents/skills/foo/SKILL.md", "Scholium/App.swift", "README.md ")
        for name in names:
            with self.subTest(name=name):
                self.assertFalse(route.docs_diff(b":100644 100644 abc def M\0" + name.encode() + b"\0"))
        with self.assertRaises(UnicodeError):
            route.docs_diff(b":100644 100644 abc def M\0README.md\xff\0")

    def test_modes_status_and_malformed_diff(self):
        for header in (b":120000 120000 abc def M", b":100644 100755 abc def M",
                       b":000000 100644 0 def A", b":100644 000000 abc 0 D",
                       b":100644 100644 abc def R100", b":160000 160000 abc def M"):
            self.assertFalse(route.docs_diff(header + b"\0README.md\0"))
        for raw in (b"", b"x", b":100644 100644 abc def M\0", b":100644 100644 abc def M\0README.md"):
            self.assertFalse(route.docs_diff(raw))
        self.assertTrue(route.docs_diff(b":100644 100644 abc def M\0README.md\0"))

    def test_real_events(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], env=env, stderr=subprocess.DEVNULL).decode().strip()
            git("init", "-b", "main")
            git("config", "user.email", "fixture@example.invalid")
            git("config", "user.name", "Fixture")
            (root / "README.md").write_text("Initial\n")
            git("add", ".")
            git("commit", "-m", "Base")
            base = git("rev-parse", "HEAD")
            (root / "README.md").write_text("Document edit\n")
            git("commit", "-am", "Docs")
            head = git("rev-parse", "HEAD")
            push = {"before": base, "after": head}
            self.assertEqual(route.classify(root, "push", push, head)[0], "docs")
            self.assertEqual(route.classify(root, "push", push, base)[0], "daily")
            self.assertEqual(route.classify(root, "push", {**push, "forced": True}, head)[0], "daily")
            for bad in ("0" * 40, "-HEAD", "HEAD", "1" * 40, "", None):
                with self.subTest(base=bad), self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    route.classify(root, "push", {**push, "before": bad}, head)
            self.assertEqual(route.classify(root, "push", {"before": head, "after": head}, head)[0], "daily")
            git("checkout", "-b", "merge", base)
            (root / "other.swift").write_text("base change\n")
            git("add", ".")
            git("commit", "-m", "New base")
            pr_base = git("rev-parse", "HEAD")
            git("merge", "--no-ff", "main", "-m", "PR merge")
            merge = git("rev-parse", "HEAD")
            pr = {"pull_request": {"base": {"sha": pr_base}, "head": {"sha": head}}}
            self.assertEqual(route.classify(root, "pull_request", pr, merge)[0], "docs")
            pr["pull_request"]["base"]["sha"] = base
            self.assertEqual(route.classify(root, "pull_request", pr, merge)[0], "daily")

    def test_cli_falls_back_and_reports_fixed_output(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            event = directory / "event.json"
            output = directory / "output"
            for event_name, value, expected in (
                ("push", [], "daily"),
                ("pull_request", {}, "daily"),
                ("push", {"before": "HEAD", "after": "0" * 40}, "daily"),
                ("workflow_dispatch", {"inputs": []}, "daily"),
                ("workflow_dispatch", {"inputs": {"profile": "docs"}}, "daily"),
                ("workflow_dispatch", {"inputs": {"profile": "full"}}, "full"),
                ("workflow_dispatch", {"inputs": {"profile": "daily"}}, "daily"),
            ):
                with self.subTest(event_name=event_name, value=value):
                    event.write_text(json.dumps(value))
                    output.write_text("")
                    result = subprocess.run(["python3", str(ROOT / "Tools/Scripts/classify-verification.py")],
                        env={**os.environ, "GITHUB_EVENT_PATH": str(event), "GITHUB_OUTPUT": str(output),
                             "GITHUB_EVENT_NAME": event_name, "GITHUB_SHA": "0" * 40},
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), f"profile={expected}\n")
            event.write_text("not JSON")
            output.write_text("")
            result = subprocess.run(["python3", str(ROOT / "Tools/Scripts/classify-verification.py")],
                env={**os.environ, "GITHUB_EVENT_PATH": str(event), "GITHUB_OUTPUT": str(output)},
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), "profile=daily\n")

    def test_manual_and_unknown_events(self):
        for profile in ("full", "daily"):
            self.assertEqual(route.classify(ROOT, "workflow_dispatch", {"inputs": {"profile": profile}}, None)[0], profile)
        self.assertEqual(route.classify(ROOT, "workflow_dispatch", {}, None)[0], "full")
        with self.assertRaises(ValueError):
            route.classify(ROOT, "workflow_dispatch", {"inputs": {"profile": "docs"}}, None)
        self.assertEqual(route.classify(ROOT, "pull_request_target", {}, None)[0], "daily")


if __name__ == "__main__":
    unittest.main()

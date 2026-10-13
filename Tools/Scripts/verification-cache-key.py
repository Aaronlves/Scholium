#!/usr/bin/env python3
"""Fingerprint the actual toolchain, SDK, host, checkout path and locked graph."""

import hashlib
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def fingerprint(root, run=subprocess.check_output):
    def command(*args):
        return run(list(args), stderr=subprocess.STDOUT).decode().strip()

    identity = {
        "schema": 1,
        "root": str(root.resolve()),
        "developer_dir": os.environ["DEVELOPER_DIR"],
        "xcode": command("xcodebuild", "-version"),
        "swift": command("xcrun", "swift", "--version"),
        "sdk": command("xcrun", "--sdk", "macosx", "--show-sdk-path"),
        "sdk_version": command("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "sdk_build": command("xcrun", "--sdk", "macosx", "--show-sdk-build-version"),
        "arch": command("uname", "-m"),
        "os": command("sw_vers", "-buildVersion"),
        "manifest": (root / "Package.swift").read_text(),
        "lock": (root / "Package.resolved").read_text(),
    }
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


def main():
    key = fingerprint(ROOT)
    print(key)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"partition={key}\n")
            stream.write(f"build-path=.build/ci-verification/daily/{key}/build\n")
            stream.write(f"dependency-path=.build/ci-verification/daily/{key}/dependencies\n")


if __name__ == "__main__":
    main()

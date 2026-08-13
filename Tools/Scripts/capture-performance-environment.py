#!/usr/bin/env python3
"""Capture privacy-safe machine and artifact metadata for Scholium G7."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path


def command(*arguments: str) -> str | None:
    try:
        value = subprocess.run(
            arguments,
            check=True,
            capture_output=True,
            text=True,
            timeout=20,
        ).stdout.strip()
        return value or None
    except (OSError, subprocess.SubprocessError):
        return None


def sysctl(name: str) -> str | None:
    return command("/usr/sbin/sysctl", "-n", name)


def default_bool(domain: str, key: str) -> bool:
    value = command("/usr/bin/defaults", "read", domain, key)
    if value in {"1", "true", "TRUE", "YES"}:
        return True
    if value in {"0", "false", "FALSE", "NO"}:
        return False
    # These accessibility preferences are opt-in system settings. In their
    # defaults domains, an absent key represents the unset/off state.
    return False


def process_is_running(name: str) -> bool:
    result = subprocess.run(
        ["/usr/bin/pgrep", "-x", name],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise RuntimeError(f"Could not inspect process state for {name}")


def full_keyboard_access_enabled() -> bool:
    if default_bool("com.apple.Accessibility", "FullKeyboardAccessEnabled"):
        return True
    raw_mode = command("/usr/bin/defaults", "read", "-g", "AppleKeyboardUIMode")
    try:
        mode = int(raw_mode) if raw_mode is not None else 0
    except ValueError:
        mode = 0
    return mode & 0b10 != 0


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def display_record() -> object:
    raw = command("/usr/sbin/system_profiler", "SPDisplaysDataType", "-json")
    if raw is None:
        return {"status": "unavailable"}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {"status": "unavailable"}
    displays: list[dict[str, object]] = []
    for controller in payload.get("SPDisplaysDataType", []):
        for display in controller.get("spdisplays_ndrvs", []):
            displays.append(
                {
                    "name": display.get("_name"),
                    "resolution": display.get("_spdisplays_resolution"),
                    "main": display.get("spdisplays_main"),
                }
            )
    return displays


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--artifact-kind", required=True, choices=("debug_qa", "packaged_release"))
    parser.add_argument("--fixture-manifest", required=True, type=Path)
    arguments = parser.parse_args()

    manifest = json.loads(arguments.fixture_manifest.read_text(encoding="utf-8"))
    binary = arguments.app / "Contents" / "MacOS" / "Scholium"
    frontmost = command(
        "/usr/bin/osascript",
        "-e",
        'tell application "System Events" to get name of first application process whose frontmost is true',
    )
    report = {
        "schema": "scholium-performance-environment-v1",
        "machine": {
            "model": sysctl("hw.model"),
            "cpu": sysctl("machdep.cpu.brand_string"),
            "physical_memory_bytes": sysctl("hw.memsize"),
            "logical_cpu_count": sysctl("hw.logicalcpu"),
        },
        "operating_system": {
            "version": platform.mac_ver()[0],
            "kernel": platform.release(),
        },
        "power_source": command("/usr/bin/pmset", "-g", "batt"),
        "displays": display_record(),
        "foreground_application": frontmost or "unavailable",
        "window": {"width_points": 1380, "layout_mode": "wide"},
        "accessibility": {
            "increase_contrast": default_bool(
                "com.apple.universalaccess", "increaseContrast"
            ),
            "reduce_transparency": default_bool(
                "com.apple.universalaccess", "reduceTransparency"
            ),
            "reduce_motion": default_bool(
                "com.apple.universalaccess", "reduceMotion"
            ),
            "differentiate_without_color": default_bool(
                "com.apple.universalaccess", "differentiateWithoutColor"
            ),
            "voice_over": process_is_running("VoiceOver"),
            "full_keyboard_access": full_keyboard_access_enabled(),
        },
        "logging": "default release logging; performance records contain timing and counts only",
        "artifact": {
            "kind": arguments.artifact_kind,
            "bundle_identifier": arguments.bundle_id,
            "executable_sha256": file_sha256(binary),
        },
        "fixture": {
            "fixture": manifest.get("fixture"),
            "version": manifest.get("version"),
            "tree_hash": manifest.get("triptych", {}).get("tree_sha256"),
            "manifest_sha256": file_sha256(arguments.fixture_manifest),
        },
    }
    arguments.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

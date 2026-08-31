#!/usr/bin/env python3
"""Validate required Scholium privileges while tolerating signing metadata."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


APP_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.network.client": True,
    "com.apple.security.network.server": True,
    "com.apple.security.temporary-exception.files.home-relative-path.read-write": [
        "/Library/Application Support/Scholium/"
    ],
}

# Xcode and distribution signing may add executable identity metadata to the
# final signature. These values identify the signer or app; they do not grant
# a new device, data, network, or sandbox capability.
SIGNING_METADATA_ENTITLEMENTS = {
    "com.apple.application-identifier",
    "com.apple.developer.team-identifier",
}


def expected_entitlements(component: str) -> dict[str, object]:
    if component == "app":
        return APP_ENTITLEMENTS
    if component == "cli":
        return {}
    raise ValueError(f"unknown component {component!r}")


def decode_entitlements(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if not data.strip():
        return {}
    value = plistlib.loads(data)
    if not isinstance(value, dict):
        raise ValueError("the entitlement payload is not a dictionary")
    return value


def validate(component: str, actual: dict[str, object]) -> None:
    expected = expected_entitlements(component)
    missing = sorted(set(expected) - set(actual))
    extra = sorted(
        set(actual) - set(expected) - SIGNING_METADATA_ENTITLEMENTS
    )
    changed = sorted(
        key for key in set(actual) & set(expected) if actual[key] != expected[key]
    )
    invalid_metadata = sorted(
        key for key in set(actual) & SIGNING_METADATA_ENTITLEMENTS
        if not isinstance(actual[key], str) or not actual[key].strip()
    )
    details = []
    if missing:
        details.append(f"missing={','.join(missing)}")
    if extra:
        details.append(f"extra={','.join(extra)}")
    if changed:
        details.append(f"changed={','.join(changed)}")
    if invalid_metadata:
        details.append(f"invalid-signing-metadata={','.join(invalid_metadata)}")
    if not details:
        return
    raise ValueError(
        f"{component} entitlement privilege mismatch: {'; '.join(details)}"
    )


def self_test() -> None:
    validate("app", dict(APP_ENTITLEMENTS))
    validate("cli", {})
    validate("app", {
        **APP_ENTITLEMENTS,
        "com.apple.application-identifier": "TEAMID.com.scholium.app",
        "com.apple.developer.team-identifier": "TEAMID",
    })
    validate("cli", {
        "com.apple.application-identifier": "TEAMID.com.scholium.cli",
        "com.apple.developer.team-identifier": "TEAMID",
    })
    for component, invalid in [
        ("app", {**APP_ENTITLEMENTS, "com.apple.security.device.camera": True}),
        ("app", {key: value for key, value in APP_ENTITLEMENTS.items()
                 if key != "com.apple.security.app-sandbox"}),
        ("cli", {"com.apple.security.app-sandbox": True}),
        ("app", {**APP_ENTITLEMENTS, "com.apple.security.get-task-allow": True}),
        ("app", {**APP_ENTITLEMENTS, "com.apple.developer.team-identifier": ""}),
    ]:
        try:
            validate(component, invalid)
        except ValueError:
            continue
        raise AssertionError(f"invalid {component} entitlement set was accepted")
    print("Entitlement privilege-boundary self-test passed")


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        self_test()
        return 0
    if len(argv) != 2:
        print(
            "usage: validate-entitlements.py <app|cli> <entitlements.plist>",
            file=sys.stderr,
        )
        return 64
    component, path = argv
    try:
        validate(component, decode_entitlements(Path(path)))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Entitlement validation failed: {error}", file=sys.stderr)
        return 65
    print(f"{component} entitlement privilege boundary passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

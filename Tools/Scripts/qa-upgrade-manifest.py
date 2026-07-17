#!/usr/bin/env python3
"""Seed and compare exact-byte Triptych fixtures for Scholium QA upgrades."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
from typing import Any


SCHEMA = "scholium-qa-upgrade-manifest-v1"
AUTHORITATIVE_ROOTS = {"01-analyses", "02-topics", "03-works"}
PORTABLE_ROOT = ".scholium"
FIXED_MTIME_NS = 1_700_000_000_000_000_000

FIXTURES: dict[str, bytes] = {
    "01-analyses/Upgrade Safety/01-bom-crlf.md": (
        b"\xef\xbb\xbf---\r\n"
        b"title: BOM and CRLF\r\n"
        b"# preserved comment\r\n"
        b"unknown_key:\r\n  nested: true\r\n"
        b"summary: |\r\n  first line\r\n  second line\r\n"
        b"---\r\n# BOM and CRLF\r\n\r\nExact bytes must survive.\r\n"
    ),
    "01-analyses/Upgrade Safety/02-lf.md": (
        b"---\ntitle: LF fixture\n---\n# LF fixture\n\nA final newline follows.\n"
    ),
    "02-topics/Upgrade Safety/03-no-final-newline.md": (
        b"---\ntitle: No final newline\n---\n# No final newline\n\nThe final byte is not LF."
    ),
    "02-topics/Upgrade Safety/04-unicode-cjk.md": (
        "---\ntitle: Unicode and CJK\naliases:\n  - 情感与理由\n---\n"
        "# 情感与理由 — café — λόγος\n\n研究笔记必须保持原始字节。\n"
    ).encode("utf-8"),
    "03-works/Upgrade Safety/05-empty.md": b"",
    "03-works/Upgrade Safety/06-folded-yaml.md": (
        b"---\n"
        b"title: Folded YAML\n"
        b"custom_commentary: >-\n"
        b"  Unknown frontmatter remains\n"
        b"  outside Scholium ownership.\n"
        b"---\n"
        b"# Folded YAML\n"
    ),
    "01-analyses/Upgrade Safety/Launch Probe.md": (
        b"---\ntitle: Upgrade Safety Launch Probe\n---\n"
        b"# Upgrade Safety Launch Probe\n\nThis note is opened read-only by the QA gate.\n"
    ),
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def category_for(relative_path: str) -> str:
    first = relative_path.split("/", 1)[0]
    if first in AUTHORITATIVE_ROOTS:
        return "authoritative"
    if first == PORTABLE_ROOT:
        return "portable"
    return "unexpected"


def seed(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for relative_path, expected in FIXTURES.items():
        destination = root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and destination.read_bytes() != expected:
            raise ValueError(f"Refusing to replace a different fixture: {relative_path}")
        destination.write_bytes(expected)
        destination.chmod(0o644)
        os.utime(destination, ns=(FIXED_MTIME_NS, FIXED_MTIME_NS))


def manifest_entry(path: Path, root: Path) -> dict[str, Any]:
    relative_path = path.relative_to(root).as_posix()
    metadata = path.lstat()
    mode = stat.S_IMODE(metadata.st_mode)
    if stat.S_ISLNK(metadata.st_mode):
        target = os.readlink(path).encode("utf-8", errors="surrogateescape")
        kind = "symlink"
        size = len(target)
        digest = sha256_bytes(target)
    elif stat.S_ISREG(metadata.st_mode):
        kind = "file"
        size = metadata.st_size
        digest = sha256_bytes(path.read_bytes())
    else:
        kind = "other"
        size = metadata.st_size
        digest = None
    return {
        "path": relative_path,
        "category": category_for(relative_path),
        "kind": kind,
        "size": size,
        "sha256": digest,
        "mode": f"{mode:04o}",
        "mtime_ns": metadata.st_mtime_ns,
    }


def capture(root: Path) -> dict[str, Any]:
    if not root.is_dir():
        raise ValueError(f"Manifest root is not a directory: {root}")
    entries = [
        manifest_entry(path, root)
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix())
        if path.is_symlink() or not path.is_dir()
    ]
    summary = {"authoritative": 0, "portable": 0, "unexpected": 0}
    for entry in entries:
        summary[entry["category"]] += 1
    return {"schema": SCHEMA, "summary": summary, "entries": entries}


def write_manifest(root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(capture(root), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != SCHEMA or not isinstance(payload.get("entries"), list):
        raise ValueError(f"Unsupported manifest: {path}")
    return payload


def read_allowlist(path: Path | None) -> list[str]:
    if path is None:
        return []
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            if not stripped.startswith(f"{PORTABLE_ROOT}/"):
                raise ValueError(
                    f"Portable allowlist entry must begin with {PORTABLE_ROOT}/: {stripped}"
                )
            patterns.append(stripped)
    return patterns


def is_allowed_portable(path: str, patterns: list[str]) -> bool:
    return category_for(path) == "portable" and any(
        fnmatch.fnmatchcase(path, pattern) for pattern in patterns
    )


def compare_payloads(
    before: dict[str, Any],
    after: dict[str, Any],
    patterns: list[str],
) -> tuple[list[str], list[str]]:
    before_by_path = {entry["path"]: entry for entry in before["entries"]}
    after_by_path = {entry["path"]: entry for entry in after["entries"]}
    failures: list[str] = []
    allowed: list[str] = []
    for relative_path in sorted(before_by_path.keys() | after_by_path.keys()):
        previous = before_by_path.get(relative_path)
        current = after_by_path.get(relative_path)
        if previous == current:
            continue
        if is_allowed_portable(relative_path, patterns):
            allowed.append(relative_path)
            continue
        if previous is None:
            reason = "created"
        elif current is None:
            reason = "deleted"
        else:
            changed_fields = [
                field
                for field in ("kind", "size", "sha256", "mode", "mtime_ns")
                if previous.get(field) != current.get(field)
            ]
            reason = "changed " + ", ".join(changed_fields)
        failures.append(f"{relative_path}: {reason}")
    return failures, allowed


def compare_files(before_path: Path, after_path: Path, allowlist: Path | None) -> int:
    failures, allowed = compare_payloads(
        load_manifest(before_path),
        load_manifest(after_path),
        read_allowlist(allowlist),
    )
    if allowed:
        print("Allowed portable changes:")
        for relative_path in allowed:
            print(f"  {relative_path}")
    if failures:
        print("Upgrade-safety comparison failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("Upgrade-safety comparison passed: all protected paths are unchanged.")
    return 0


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="scholium-upgrade-manifest-") as temporary:
        root = Path(temporary) / "Triptych"
        seed(root)
        baseline = capture(root)
        failures, allowed = compare_payloads(baseline, capture(root), [])
        assert not failures and not allowed

        authoritative = root / "01-analyses/Upgrade Safety/02-lf.md"
        authoritative.write_bytes(authoritative.read_bytes() + b"mutation")
        failures, _ = compare_payloads(baseline, capture(root), [])
        assert any("02-lf.md" in failure for failure in failures)

        authoritative.write_bytes(FIXTURES["01-analyses/Upgrade Safety/02-lf.md"])
        authoritative.chmod(0o644)
        os.utime(authoritative, ns=(FIXED_MTIME_NS, FIXED_MTIME_NS))

        authoritative.chmod(0o600)
        failures, _ = compare_payloads(baseline, capture(root), [])
        assert any("changed mode" in failure for failure in failures)
        authoritative.chmod(0o644)

        os.utime(
            authoritative,
            ns=(FIXED_MTIME_NS + 1, FIXED_MTIME_NS + 1),
        )
        failures, _ = compare_payloads(baseline, capture(root), [])
        assert any("changed mtime_ns" in failure for failure in failures)
        os.utime(authoritative, ns=(FIXED_MTIME_NS, FIXED_MTIME_NS))

        portable = root / ".scholium/identities.json"
        portable.parent.mkdir(parents=True, exist_ok=True)
        portable.write_text("{}\n", encoding="utf-8")
        failures, allowed = compare_payloads(
            baseline,
            capture(root),
            [".scholium/identities.json"],
        )
        assert not failures and allowed == [".scholium/identities.json"]

        portable.chmod(0o600)
        failures, _ = compare_payloads(baseline, capture(root), [])
        assert any(".scholium/identities.json" in failure for failure in failures)
    print("qa-upgrade-manifest self-test passed")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    seed_parser = commands.add_parser("seed", help="Add deterministic hostile fixtures.")
    seed_parser.add_argument("--root", type=Path, required=True)

    capture_parser = commands.add_parser("capture", help="Capture a file manifest.")
    capture_parser.add_argument("--root", type=Path, required=True)
    capture_parser.add_argument("--output", type=Path, required=True)

    compare_parser = commands.add_parser("compare", help="Compare two manifests.")
    compare_parser.add_argument("--before", type=Path, required=True)
    compare_parser.add_argument("--after", type=Path, required=True)
    compare_parser.add_argument("--portable-allowlist", type=Path)

    commands.add_parser("self-test", help="Exercise comparison failure modes.")
    return root


def main() -> int:
    arguments = parser().parse_args()
    try:
        if arguments.command == "seed":
            seed(arguments.root)
        elif arguments.command == "capture":
            write_manifest(arguments.root, arguments.output)
        elif arguments.command == "compare":
            return compare_files(
                arguments.before,
                arguments.after,
                arguments.portable_allowlist,
            )
        elif arguments.command == "self-test":
            self_test()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"qa-upgrade-manifest: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

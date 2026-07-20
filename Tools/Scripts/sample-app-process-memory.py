#!/usr/bin/env python3
"""Measure one Scholium app plus only the WebKit services it owns.

The sampler deliberately fails closed.  WebKit workers are launchd children,
so PPID and process-name scans cannot establish ownership.  `launchctl print
pid/<app-pid>` exposes the service instances created for that originator; every
reported PID is then checked against the expected executable before RSS is
summed.  No research content, document identity, or filesystem path is emitted.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


SCHEMA = "scholium-process-memory-v1"
SERVICE_PATTERN = re.compile(
    r"^\s*(?P<pid>[1-9][0-9]*)\s+\S+\s+"
    r"com\.apple\.WebKit\.(?P<role>WebContent|GPU|Networking)\."
    r"[A-Za-z0-9-]+\s*$"
)
ORIGINATOR_PATTERN = re.compile(r"^\s*originator\s*=\s*(?P<path>.+?)\s*$")
ROLE_KEY = {
    "WebContent": "web_content",
    "GPU": "gpu",
    "Networking": "networking",
}
EXPECTED_WEBKIT_ROLES = frozenset(ROLE_KEY.values())


class SamplingError(RuntimeError):
    pass


@dataclass(frozen=True)
class OwnedServices:
    originator: Path
    role_by_pid: dict[int, str]


def normalized(path: Path | str) -> Path:
    return Path(os.path.realpath(os.fspath(path)))


def parse_launchctl_print(source: str) -> OwnedServices:
    originator: Path | None = None
    role_by_pid: dict[int, str] = {}
    in_services = False

    for line in source.splitlines():
        if originator is None:
            match = ORIGINATOR_PATTERN.match(line)
            if match:
                originator = normalized(match.group("path"))
        if line.strip() == "services = {":
            if in_services:
                raise SamplingError("launchctl output contains duplicate service blocks")
            in_services = True
            continue
        if in_services and line.strip() == "}":
            in_services = False
            continue
        if not in_services:
            continue
        match = SERVICE_PATTERN.match(line)
        if not match:
            continue
        pid = int(match.group("pid"))
        role = ROLE_KEY[match.group("role")]
        if pid in role_by_pid:
            raise SamplingError(f"launchctl output repeats service PID {pid}")
        role_by_pid[pid] = role

    if originator is None:
        raise SamplingError("launchctl output has no originator")
    observed_roles = set(role_by_pid.values())
    missing = EXPECTED_WEBKIT_ROLES - observed_roles
    if missing:
        raise SamplingError(
            "launchctl output lacks active WebKit roles: " + ", ".join(sorted(missing))
        )
    return OwnedServices(originator=originator, role_by_pid=role_by_pid)


def parse_ps_rows(source: str, expected_pids: set[int]) -> dict[int, tuple[int, Path]]:
    rows: dict[int, tuple[int, Path]] = {}
    for line in source.splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) != 3:
            continue
        try:
            pid = int(fields[0])
            rss_kib = int(fields[1])
        except ValueError as error:
            raise SamplingError("ps returned a nonnumeric PID or RSS value") from error
        if pid in rows:
            raise SamplingError(f"ps repeated PID {pid}")
        rows[pid] = (rss_kib, normalized(fields[2]))

    if set(rows) != expected_pids:
        missing = sorted(expected_pids - set(rows))
        extra = sorted(set(rows) - expected_pids)
        raise SamplingError(f"process set changed during sampling; missing={missing}, extra={extra}")
    if any(rss_kib <= 0 for rss_kib, _ in rows.values()):
        raise SamplingError("ps returned a nonpositive RSS value")
    return rows


def validate_process_paths(
    app: Path,
    app_pid: int,
    services: OwnedServices,
    rows: dict[int, tuple[int, Path]],
) -> None:
    expected_executable = normalized(app / "Contents/MacOS/Scholium")
    if rows[app_pid][1] != expected_executable:
        raise SamplingError("the supplied PID does not execute the supplied Scholium app")
    if services.originator != normalized(app):
        raise SamplingError("launchctl originator does not match the supplied Scholium app")

    expected_suffix = {
        "web_content": "com.apple.WebKit.WebContent",
        "gpu": "com.apple.WebKit.GPU",
        "networking": "com.apple.WebKit.Networking",
    }
    for pid, role in services.role_by_pid.items():
        executable = rows[pid][1]
        if "/WebKit.framework/" not in str(executable):
            raise SamplingError(f"service PID {pid} is not a WebKit framework executable")
        if executable.name != expected_suffix[role]:
            raise SamplingError(f"service PID {pid} executable does not match role {role}")


def find_unique_app_pid(app: Path) -> int:
    executable = normalized(app / "Contents/MacOS/Scholium")
    spellings = {str(executable)}
    if str(executable).startswith("/private/tmp/"):
        spellings.add(str(executable)[len("/private"):])
    pids: set[int] = set()
    for spelling in sorted(spellings):
        result = subprocess.run(
            ["/usr/bin/pgrep", "-f", f"^{re.escape(spelling)}( |$)"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode not in (0, 1):
            raise SamplingError("pgrep could not locate the supplied Scholium app")
        try:
            pids.update(int(value) for value in result.stdout.split())
        except ValueError as error:
            raise SamplingError("pgrep returned a nonnumeric app PID") from error
    if len(pids) != 1:
        raise SamplingError(
            f"expected one process for the exact Scholium executable, found {len(pids)}"
        )
    return next(iter(pids))


def sample(app: Path, requested_pid: int | None) -> dict[str, object]:
    app = normalized(app)
    if not (app / "Contents/MacOS/Scholium").is_file():
        raise SamplingError("the supplied app bundle has no Scholium executable")
    app_pid = requested_pid if requested_pid is not None else find_unique_app_pid(app)
    if app_pid <= 0:
        raise SamplingError("app PID must be positive")

    launchctl = subprocess.run(
        ["/bin/launchctl", "print", f"pid/{app_pid}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if launchctl.returncode != 0:
        raise SamplingError("launchctl could not inspect the supplied app PID")
    services = parse_launchctl_print(launchctl.stdout)

    expected_pids = {app_pid, *services.role_by_pid.keys()}
    ps = subprocess.run(
        ["/bin/ps", "-p", ",".join(str(pid) for pid in sorted(expected_pids)),
         "-o", "pid=,rss=,comm="],
        check=False,
        capture_output=True,
        text=True,
    )
    if ps.returncode != 0:
        raise SamplingError("ps could not inspect the attributed process set")
    rows = parse_ps_rows(ps.stdout, expected_pids)
    validate_process_paths(app, app_pid, services, rows)

    resident_by_role = {role: 0 for role in ["app", *sorted(EXPECTED_WEBKIT_ROLES)]}
    count_by_role = {role: 0 for role in resident_by_role}
    resident_by_role["app"] = rows[app_pid][0] * 1_024
    count_by_role["app"] = 1
    for pid, role in services.role_by_pid.items():
        resident_by_role[role] += rows[pid][0] * 1_024
        count_by_role[role] += 1

    return {
        "schema": SCHEMA,
        "sample_uptime_ns": time.monotonic_ns(),
        "scope": "app_plus_attributed_webkit_services",
        "process_count": sum(count_by_role.values()),
        "resident_bytes": sum(resident_by_role.values()),
        "role_process_counts": count_by_role,
        "role_resident_bytes": resident_by_role,
    }


def append_bytes(path: Path, payload: bytes) -> None:
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def read_progress(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    if path.is_symlink() or not path.is_file():
        raise SamplingError("memory progress path is not a regular file")
    records: list[dict[str, object]] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError as error:
            raise SamplingError(f"invalid progress record at line {line_number}") from error
        if not isinstance(record, dict) or set(record) != {"sample", "transition", "mode"}:
            raise SamplingError(f"invalid progress keys at line {line_number}")
        records.append(record)
    return records


def watch_progress(
    app: Path,
    progress_path: Path,
    acknowledgment_path: Path,
    output_path: Path,
    sample_count: int,
    timeout_seconds: float,
) -> None:
    if sample_count <= 0 or sample_count > 1_001:
        raise SamplingError("watch sample count is out of bounds")
    if timeout_seconds <= 0 or timeout_seconds > 3_600:
        raise SamplingError("watch timeout is out of bounds")
    paths = [progress_path, acknowledgment_path, output_path]
    parents = {normalized(path.parent) for path in paths}
    if len(parents) != 1 or not next(iter(parents)).is_dir():
        raise SamplingError("watch files must share one existing directory")
    for path in paths:
        if not path.is_absolute() or path.is_symlink():
            raise SamplingError("watch files must be absolute nonsymlink paths")
        if path.exists() and path.stat().st_size > 0:
            raise SamplingError("watch output files must begin empty")

    deadline = time.monotonic() + timeout_seconds
    next_sample = 0
    while next_sample < sample_count:
        if time.monotonic() >= deadline:
            raise SamplingError(f"timed out waiting for memory progress sample {next_sample}")
        progress = read_progress(progress_path)
        if len(progress) <= next_sample:
            time.sleep(0.05)
            continue
        if len(progress) > sample_count:
            raise SamplingError("memory progress contains too many samples")
        marker = progress[next_sample]
        if marker.get("sample") != next_sample or marker.get("transition") != next_sample:
            raise SamplingError("memory progress sequence is not contiguous")
        expected_mode = "live_preview" if next_sample % 2 == 0 else "source"
        if marker.get("mode") != expected_mode:
            raise SamplingError("memory progress mode sequence is invalid")

        last_error: SamplingError | None = None
        readiness_deadline = min(deadline, time.monotonic() + 10.0)
        while time.monotonic() < readiness_deadline:
            try:
                result = sample(app, None)
                break
            except SamplingError as error:
                last_error = error
                time.sleep(0.1)
        else:
            raise SamplingError(
                f"could not obtain attributed process set for sample {next_sample}: {last_error}"
            )
        result.update(marker)
        append_bytes(
            output_path,
            json.dumps(result, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n",
        )
        append_bytes(acknowledgment_path, f"{next_sample}\n".encode("ascii"))
        next_sample += 1

    print(f"Attributed Editor memory samples: {sample_count}")


def self_test() -> None:
    launchctl = """pid/42 = {
\toriginator = /tmp/Scholium-QA.app
\tservices = {
\t   101      - \tcom.apple.WebKit.GPU.11111111-1111-1111-1111-111111111111
\t       0      - \tcom.apple.WebKit.WebContent
\t   102      - \tcom.apple.WebKit.WebContent.22222222-2222-2222-2222-222222222222
\t   103      - \tcom.apple.WebKit.Networking.33333333-3333-3333-3333-333333333333
\t}
}
"""
    parsed = parse_launchctl_print(launchctl)
    assert parsed.originator == normalized("/tmp/Scholium-QA.app")
    assert parsed.role_by_pid == {101: "gpu", 102: "web_content", 103: "networking"}

    ps = """ 42 100 /tmp/Scholium-QA.app/Contents/MacOS/Scholium
101 10 /System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU
102 20 /System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent
103 30 /System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.Networking
"""
    rows = parse_ps_rows(ps, {42, 101, 102, 103})
    assert rows[102][0] == 20

    missing_role = launchctl.replace(
        "\t   103      - \tcom.apple.WebKit.Networking.33333333-3333-3333-3333-333333333333\n",
        "",
    )
    try:
        parse_launchctl_print(missing_role)
    except SamplingError:
        pass
    else:
        raise AssertionError("missing WebKit roles must fail closed")
    print("Process memory sampler self-test passed")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--watch-progress", type=Path)
    parser.add_argument("--acknowledgment", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--samples", type=int)
    parser.add_argument("--timeout-seconds", type=float, default=600.0)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    if arguments.self_test:
        self_test()
        return
    if arguments.app is None:
        raise SystemExit("--app is required unless --self-test is used")
    try:
        watch_arguments = (
            arguments.watch_progress,
            arguments.acknowledgment,
            arguments.output,
            arguments.samples,
        )
        if any(value is not None for value in watch_arguments):
            if any(value is None for value in watch_arguments):
                raise SamplingError(
                    "--watch-progress, --acknowledgment, --output, and --samples are required together"
                )
            watch_progress(
                arguments.app,
                arguments.watch_progress,
                arguments.acknowledgment,
                arguments.output,
                arguments.samples,
                arguments.timeout_seconds,
            )
            return
        result = sample(arguments.app, arguments.pid)
    except SamplingError as error:
        print(f"Process memory sampling failed closed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()

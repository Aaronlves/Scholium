#!/usr/bin/env python3
"""Measure one Scholium app and its explicitly attributed services.

The sampler deliberately fails closed.  WebKit workers are launchd children,
so PPID and process-name scans cannot establish ownership.  `launchctl print
pid/<app-pid>` exposes the service instances created for that originator; every
reported PID is then checked against the expected executable before RSS is
summed. Explicit options permit incomplete startup role sets, report their PIDs
and per-process RSS in bytes, collect physical footprint separately, and include
other allowlisted services from that same originator. No research content or
document identity is emitted; the last option reports only verified system
executable paths.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


SCHEMA = "scholium-process-memory-v1"
SERVICE_PATTERN = re.compile(
    r"^\s*(?P<pid>[1-9][0-9]*)\s+\S+\s+"
    r"com\.apple\.WebKit\.(?P<role>WebContent|GPU|Networking)\."
    r"[A-Za-z0-9-]+\s*$"
)
ACTIVE_SERVICE_PATTERN = re.compile(r"^\s*(?P<pid>[1-9][0-9]*)\s+\S+\s+(?P<label>\S+)\s*$")
ORIGINATOR_PATTERN = re.compile(r"^\s*originator\s*=\s*(?P<path>.+?)\s*$")
ROLE_KEY = {
    "WebContent": "web_content",
    "GPU": "gpu",
    "Networking": "networking",
}
EXPECTED_WEBKIT_ROLES = frozenset(ROLE_KEY.values())
# Exact label/executable pairs observed in this originator's service domain.
# New active service kinds require explicit validation rather than a guessed
# process-name match or silently incomplete whole-domain measurement.
OTHER_SERVICE_EXECUTABLES = {
    "com.apple.appkit.xpc.ThemeWidgetControlViewService":
        "/System/Library/Frameworks/AppKit.framework/Versions/C/XPCServices/"
        "ThemeWidgetControlViewService.xpc/Contents/MacOS/ThemeWidgetControlViewService",
    "com.apple.SafariPlatformSupport.Helper":
        "/System/Library/PrivateFrameworks/SafariPlatformSupport.framework/Versions/A/XPCServices/"
        "com.apple.SafariPlatformSupport.Helper.xpc/Contents/MacOS/com.apple.SafariPlatformSupport.Helper",
    "com.apple.audio.SandboxHelper":
        "/System/Library/Frameworks/AudioToolbox.framework/XPCServices/"
        "com.apple.audio.SandboxHelper.xpc/Contents/MacOS/com.apple.audio.SandboxHelper",
    "com.apple.SetStoreUpdateService":
        "/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/"
        "SetStoreUpdateService.xpc/Contents/MacOS/SetStoreUpdateService",
    "com.apple.appkit.xpc.openAndSavePanelService":
        "/System/Library/Frameworks/AppKit.framework/Versions/C/XPCServices/"
        "com.apple.appkit.xpc.openAndSavePanelService.xpc/Contents/MacOS/"
        "com.apple.appkit.xpc.openAndSavePanelService",
}


class SamplingError(RuntimeError):
    pass


class ProcessChanged(SamplingError):
    """An observed exit or identity change invalidates the whole sample."""


@dataclass(frozen=True)
class OwnedServices:
    originator: Path
    role_by_pid: dict[int, str]
    additional_labels_by_pid: dict[int, tuple[str, ...]] = field(default_factory=dict)


def normalized(path: Path | str) -> Path:
    return Path(os.path.realpath(os.fspath(path)))


def parse_launchctl_print(
    source: str, *, allow_partial_webkit: bool = False, include_other_owned_services: bool = False
) -> OwnedServices:
    originator: Path | None = None
    role_by_pid: dict[int, str] = {}
    additional_labels_by_pid: dict[int, set[str]] = {}
    in_services = False
    service_block_seen = False

    for line in source.splitlines():
        if originator is None:
            match = ORIGINATOR_PATTERN.match(line)
            if match:
                originator = normalized(match.group("path"))
        if line.strip() == "services = {":
            if in_services or (include_other_owned_services and service_block_seen):
                raise SamplingError("launchctl output contains duplicate service blocks")
            in_services = True
            service_block_seen = True
            continue
        if in_services and line.strip() == "}":
            in_services = False
            continue
        if not in_services:
            continue
        match = SERVICE_PATTERN.match(line)
        if not match:
            if include_other_owned_services:
                active = ACTIVE_SERVICE_PATTERN.match(line)
                if active:
                    pid = int(active.group("pid"))
                    label = active.group("label")
                    if label not in OTHER_SERVICE_EXECUTABLES:
                        raise SamplingError(f"unrecognized active originator service {label!r} (PID {pid})")
                    if pid in role_by_pid:
                        raise SamplingError(f"originator service PID {pid} has conflicting roles")
                    additional_labels_by_pid.setdefault(pid, set()).add(label)
                elif re.match(r"^\s*[1-9][0-9]*(?:\s|$)", line):
                    raise SamplingError("malformed active originator service row")
            continue
        pid = int(match.group("pid"))
        role = ROLE_KEY[match.group("role")]
        if pid in role_by_pid or pid in additional_labels_by_pid:
            raise SamplingError(f"launchctl output repeats service PID {pid}")
        role_by_pid[pid] = role

    if originator is None:
        raise SamplingError("launchctl output has no originator")
    if include_other_owned_services and (not service_block_seen or in_services):
        raise SamplingError("launchctl output has no complete originator service block")
    observed_roles = set(role_by_pid.values())
    missing = EXPECTED_WEBKIT_ROLES - observed_roles
    if missing and not allow_partial_webkit:
        raise SamplingError(
            "launchctl output lacks active WebKit roles: " + ", ".join(sorted(missing))
        )
    return OwnedServices(
        originator=originator, role_by_pid=role_by_pid,
        additional_labels_by_pid={pid: tuple(sorted(labels)) for pid, labels in additional_labels_by_pid.items()},
    )


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
    for pid, (rss_kib, _) in rows.items():
        if rss_kib <= 0:
            raise SamplingError(f"ps returned a nonpositive RSS value for PID {pid}")
    return rows


def validate_process_paths(
    app: Path,
    app_pid: int,
    services: OwnedServices,
    rows: dict[int, tuple[int, Path]],
) -> None:
    expected_executable = normalized(app / "Contents/MacOS/Scholium")
    if rows[app_pid][1] != expected_executable:
        raise SamplingError(
            f"PID {app_pid} role app has unexpected executable {str(rows[app_pid][1])!r}"
        )
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
            raise SamplingError(
                f"service PID {pid} role {role} is not a WebKit framework executable: {str(executable)!r}"
            )
        if executable.name != expected_suffix[role]:
            raise SamplingError(
                f"service PID {pid} executable {str(executable)!r} does not match role {role}"
            )
    for pid, labels in services.additional_labels_by_pid.items():
        expected = {normalized(OTHER_SERVICE_EXECUTABLES[label]) for label in labels}
        if len(expected) != 1 or rows[pid][1] not in expected:
            raise SamplingError(
                f"originator service PID {pid} role other_services executable {str(rows[pid][1])!r} "
                "does not match its allowlisted labels"
            )


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


class RUsageInfoV0(ctypes.Structure):
    # macOS SDK sys/resource.h, RUSAGE_INFO_V0. libproc writes the struct
    # directly to the buffer supplied to proc_pid_rusage.
    _fields_ = [("ri_uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "ri_user_time", "ri_system_time", "ri_pkg_idle_wkups", "ri_interrupt_wkups",
            "ri_pageins", "ri_wired_size", "ri_resident_size", "ri_phys_footprint",
            "ri_proc_start_abstime", "ri_proc_exit_abstime",
        )
    ]


@dataclass(frozen=True)
class ProcessReading:
    start_abstime: int
    executable_uuid: bytes
    executable: Path
    physical_footprint: int

    @property
    def identity(self) -> tuple[int, bytes, Path]:
        return self.start_abstime, self.executable_uuid, self.executable


class ProcessReader:
    def __init__(self) -> None:
        try:
            library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
            self.read_usage = library.proc_pid_rusage
            self.read_path = library.proc_pidpath
        except (OSError, AttributeError) as error:
            raise SamplingError("public libproc process inspection is unavailable") from error
        self.read_usage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        self.read_usage.restype = ctypes.c_int
        self.read_path.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        self.read_path.restype = ctypes.c_int

    @staticmethod
    def failed(operation: str, pid: int) -> SamplingError:
        error_number = ctypes.get_errno()
        if error_number == errno.ESRCH:
            return ProcessChanged(f"process set changed during sampling; PID {pid} no longer exists ({operation})")
        return SamplingError(f"{operation} failed for PID {pid}: {os.strerror(error_number)}")

    def usage(self, pid: int) -> RUsageInfoV0:
        usage = RUsageInfoV0()
        ctypes.set_errno(0)
        if self.read_usage(pid, 0, ctypes.byref(usage)) != 0:
            raise self.failed("proc_pid_rusage", pid)
        if usage.ri_proc_exit_abstime != 0:
            raise ProcessChanged(f"process set changed during sampling; PID {pid} exited")
        if usage.ri_proc_start_abstime == 0:
            raise SamplingError(f"proc_pid_rusage returned no process start identity for PID {pid}")
        return usage

    def read(self, pid: int) -> ProcessReading:
        usage = self.usage(pid)
        # Selected SDK sys/proc_info.h: PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN.
        buffer = ctypes.create_string_buffer(4_096)
        ctypes.set_errno(0)
        length = self.read_path(pid, buffer, len(buffer))
        if length <= 0:
            error = self.failed("proc_pidpath", pid)
            # Path lookup can race an exit after the usage read. Only a public
            # exit/identity observation, never an arbitrary path error, permits
            # the caller to discard this transaction as a lifecycle change.
            current = self.usage(pid)
            if (current.ri_proc_start_abstime, bytes(current.ri_uuid)) != (
                usage.ri_proc_start_abstime, bytes(usage.ri_uuid)
            ):
                raise ProcessChanged(f"process set changed during sampling; PID {pid} identity changed during path lookup")
            raise error
        if length >= len(buffer) or not buffer.value or not buffer.value.startswith(b"/"):
            raise SamplingError(f"proc_pidpath returned an invalid executable path for PID {pid}")
        return ProcessReading(
            int(usage.ri_proc_start_abstime), bytes(usage.ri_uuid), normalized(os.fsdecode(buffer.value)),
            int(usage.ri_phys_footprint),
        )


def sample(
    app: Path,
    requested_pid: int | None,
    *,
    allow_partial_webkit: bool = False,
    include_process_ids: bool = False,
    include_physical_footprint: bool = False,
    include_other_owned_services: bool = False,
) -> dict[str, object]:
    app = normalized(app)
    if not (app / "Contents/MacOS/Scholium").is_file():
        raise SamplingError("the supplied app bundle has no Scholium executable")
    app_pid = requested_pid if requested_pid is not None else find_unique_app_pid(app)
    if app_pid <= 0:
        raise SamplingError("app PID must be positive")

    reader = ProcessReader()
    before = {app_pid: reader.read(app_pid)}
    pending_error: SamplingError | None = None
    try:
        launchctl = subprocess.run(
            ["/bin/launchctl", "print", f"pid/{app_pid}"],
            check=False,
            capture_output=True,
            text=True,
        )
        if launchctl.returncode != 0:
            raise SamplingError("launchctl could not inspect the supplied app PID")
        services = parse_launchctl_print(
            launchctl.stdout, allow_partial_webkit=allow_partial_webkit,
            include_other_owned_services=include_other_owned_services,
        )
        expected_pids = {app_pid, *services.role_by_pid.keys(), *services.additional_labels_by_pid.keys()}
        for pid in sorted(expected_pids - {app_pid}):
            before[pid] = reader.read(pid)
        ps = subprocess.run(
            ["/bin/ps", "-p", ",".join(str(pid) for pid in sorted(expected_pids)),
             "-o", "pid=,rss=,comm="],
            check=False,
            capture_output=True,
            text=True,
        )
        if ps.returncode != 0:
            raise SamplingError("ps could not inspect the attributed process set")
        ps_rows = parse_ps_rows(ps.stdout, expected_pids)
        # ps remains the RSS authority. Its presentation of comm is not the
        # executable identity; obtain that path directly from the kernel.
        rows = {pid: (ps_rows[pid][0], before[pid].executable) for pid in expected_pids}
        validate_process_paths(app, app_pid, services, rows)
    except SamplingError as error:
        pending_error = error

    after: dict[int, ProcessReading] = {}
    endpoint_error: SamplingError | None = None
    changed: ProcessChanged | None = None
    # Complete the endpoint check even when ps/path validation failed. A proven
    # exit or PID/exec change invalidates all metrics, never just one process.
    for pid, initial in sorted(before.items()):
        try:
            current = reader.read(pid)
            after[pid] = current
            if current.identity != initial.identity:
                raise ProcessChanged(f"process set changed during sampling; PID {pid} identity changed")
        except ProcessChanged as error:
            changed = changed or error
        except SamplingError as error:
            endpoint_error = endpoint_error or error
    if changed is not None:
        raise changed
    if pending_error is not None:
        raise pending_error
    if endpoint_error is not None:
        raise endpoint_error

    role_by_pid = {app_pid: "app", **services.role_by_pid}
    roles = ["app", *sorted(EXPECTED_WEBKIT_ROLES)]
    if include_other_owned_services:
        roles.append("other_services")
        role_by_pid.update({pid: "other_services" for pid in services.additional_labels_by_pid})
    resident_by_role = dict.fromkeys(roles, 0)
    count_by_role = {role: 0 for role in resident_by_role}
    for pid, role in role_by_pid.items():
        resident_by_role[role] += rows[pid][0] * 1_024
        count_by_role[role] += 1

    result = {
        "schema": SCHEMA,
        "sample_uptime_ns": time.monotonic_ns(),
        "scope": "app_plus_attributed_originator_services" if include_other_owned_services
        else "app_plus_attributed_webkit_services",
        "process_count": sum(count_by_role.values()),
        "resident_bytes": sum(resident_by_role.values()),
        "role_process_counts": count_by_role,
        "role_resident_bytes": resident_by_role,
    }
    if allow_partial_webkit:
        result["missing_webkit_roles"] = sorted(EXPECTED_WEBKIT_ROLES - set(services.role_by_pid.values()))
    if include_process_ids:
        result["role_process_ids"] = {
            role: sorted(pid for pid, observed_role in role_by_pid.items() if observed_role == role)
            for role in resident_by_role
        }
        result["process_resident_bytes"] = {
            str(pid): rows[pid][0] * 1_024 for pid in sorted(role_by_pid)
        }
    footprint_by_pid: dict[int, int] = {}
    if include_physical_footprint:
        footprint_by_role = dict.fromkeys(resident_by_role, 0)
        for pid, role in sorted(role_by_pid.items()):
            footprint_by_pid[pid] = after[pid].physical_footprint
            if footprint_by_pid[pid] <= 0:
                raise SamplingError(f"proc_pid_rusage returned no live physical footprint for PID {pid}")
            footprint_by_role[role] += footprint_by_pid[pid]
        result["physical_footprint_bytes"] = sum(footprint_by_role.values())
        result["role_physical_footprint_bytes"] = footprint_by_role
        if include_process_ids:
            result["process_physical_footprint_bytes"] = {
                str(pid): footprint for pid, footprint in footprint_by_pid.items()
            }
    if include_other_owned_services:
        additional = []
        for pid, labels in sorted(services.additional_labels_by_pid.items()):
            service = {
                "pid": pid, "labels": list(labels), "executable": str(rows[pid][1]),
                "resident_bytes": rows[pid][0] * 1_024,
            }
            if include_physical_footprint:
                service["physical_footprint_bytes"] = footprint_by_pid[pid]
            additional.append(service)
        result["additional_owned_services"] = additional
    return result


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
    *,
    allow_partial_webkit: bool = False,
    include_process_ids: bool = False,
    include_physical_footprint: bool = False,
    include_other_owned_services: bool = False,
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
                result = sample(
                    app, None, allow_partial_webkit=allow_partial_webkit,
                    include_process_ids=include_process_ids,
                    include_physical_footprint=include_physical_footprint,
                    include_other_owned_services=include_other_owned_services,
                )
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
    from types import SimpleNamespace
    from unittest.mock import patch

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
    validate_process_paths(Path("/tmp/Scholium-QA.app"), 42, parsed, rows)

    def requires_error(operation) -> SamplingError:
        try:
            operation()
        except SamplingError as error:
            return error
        raise AssertionError("invalid attribution or unavailable measurement must fail closed")

    missing_role = launchctl.replace(
        "\t   103      - \tcom.apple.WebKit.Networking.33333333-3333-3333-3333-333333333333\n",
        "",
    )
    requires_error(lambda: parse_launchctl_print(missing_role))
    no_workers = """pid/42 = {
    originator = /tmp/Scholium-QA.app
    services = {
        0 - com.apple.WebKit.WebContent
    }
}
"""
    requires_error(lambda: parse_launchctl_print(no_workers))
    assert parse_launchctl_print(no_workers, allow_partial_webkit=True).role_by_pid == {}
    assert parse_launchctl_print(missing_role, allow_partial_webkit=True).role_by_pid == {
        101: "gpu", 102: "web_content",
    }
    requires_error(lambda: parse_launchctl_print("services = {\n}\n", allow_partial_webkit=True))

    # Freeze the SDK's V0 ABI and exercise ctypes output/error handling without
    # launching an app or querying unrelated processes during this self-test.
    assert ctypes.sizeof(RUsageInfoV0) == 96
    assert RUsageInfoV0.ri_phys_footprint.offset == 72
    assert RUsageInfoV0.ri_proc_start_abstime.offset == 80
    assert RUsageInfoV0.ri_proc_exit_abstime.offset == 88
    measured_pids: list[int] = []
    footprints = {42: 75_000, 101: 5_000, 102: 10_000, 103: 15_000}

    def read_usage(pid, flavor, buffer):
        assert flavor == 0
        measured_pids.append(pid)
        usage = ctypes.cast(buffer, ctypes.POINTER(RUsageInfoV0)).contents
        usage.ri_phys_footprint = footprints.get(pid, 1_000)
        usage.ri_proc_start_abstime = pid * 1_000
        usage.ri_uuid[:] = pid.to_bytes(16, "little")
        return 0

    def captured(
        source: str, process_rows: str, *, kernel_paths=None, usage_callback=None,
        path_callback=None, ps_callback=None, **options,
    ) -> dict[str, object]:
        measured_pids.clear()
        paths = {
            int(fields[0]): fields[2]
            for line in process_rows.splitlines()
            if len(fields := line.strip().split(maxsplit=2)) == 3
        } if kernel_paths is None else kernel_paths

        def read_path(pid, buffer, capacity):
            if path_callback is not None:
                return path_callback(pid, buffer, capacity)
            if pid not in paths:
                ctypes.set_errno(errno.ESRCH)
                return 0
            raw = os.fsencode(paths[pid])
            assert len(raw) < capacity
            buffer.value = raw
            return len(raw)

        results = [
            subprocess.CompletedProcess([], 0, stdout=source, stderr=""),
            subprocess.CompletedProcess([], 0, stdout=process_rows, stderr=""),
        ]

        def run(command, **kwargs):
            if command[0] == "/bin/ps" and ps_callback is not None:
                ps_callback()
            return results.pop(0)

        with patch.object(Path, "is_file", return_value=True), \
                patch.object(subprocess, "run", side_effect=run), \
                patch.object(ctypes, "CDLL", return_value=SimpleNamespace(
                    proc_pid_rusage=usage_callback or read_usage, proc_pidpath=read_path,
                )):
            return sample(Path("/tmp/Scholium-QA.app"), 42, **options)

    strict = captured(launchctl, ps)
    assert set(strict) == {
        "schema", "sample_uptime_ns", "scope", "process_count", "resident_bytes",
        "role_process_counts", "role_resident_bytes",
    }
    assert strict["resident_bytes"] == 160 * 1_024
    assert measured_pids == [42, 101, 102, 103] * 2  # Identity checks are mandatory.

    options = dict(allow_partial_webkit=True, include_process_ids=True, include_physical_footprint=True)
    startup = captured(no_workers, ps.splitlines()[0], **options)
    assert startup["process_count"] == 1 and startup["resident_bytes"] == 100 * 1_024
    assert startup["role_process_counts"] == {"app": 1, "gpu": 0, "networking": 0, "web_content": 0}
    assert startup["missing_webkit_roles"] == ["gpu", "networking", "web_content"]
    assert startup["role_process_ids"] == {"app": [42], "gpu": [], "networking": [], "web_content": []}
    assert startup["role_resident_bytes"] == {"app": 100 * 1_024, "gpu": 0, "networking": 0, "web_content": 0}
    assert startup["process_resident_bytes"] == {"42": 100 * 1_024}
    assert startup["role_physical_footprint_bytes"] == {"app": 75_000, "gpu": 0, "networking": 0, "web_content": 0}
    assert startup["process_physical_footprint_bytes"] == {"42": 75_000}
    assert startup["physical_footprint_bytes"] == 75_000 and measured_pids == [42, 42]
    measured_pids.clear()

    partial_rows = "\n".join(ps.splitlines()[:3])
    partial = captured(missing_role, partial_rows, **options)
    assert partial["missing_webkit_roles"] == ["networking"]
    assert partial["physical_footprint_bytes"] == 90_000
    assert partial["process_physical_footprint_bytes"] == {"42": 75_000, "101": 5_000, "102": 10_000}
    assert partial["role_process_ids"]["networking"] == []
    assert measured_pids == [42, 101, 102] * 2
    measured_pids.clear()
    complete = captured(launchctl, ps, **options)
    assert complete["missing_webkit_roles"] == []
    assert complete["physical_footprint_bytes"] == 105_000
    assert complete["process_physical_footprint_bytes"] == {str(pid): value for pid, value in footprints.items()}
    assert sum(complete["process_physical_footprint_bytes"].values()) == complete["physical_footprint_bytes"]
    assert complete["role_process_ids"]["web_content"] == [102]
    expected_resident = {"42": 100 * 1_024, "101": 10 * 1_024, "102": 20 * 1_024, "103": 30 * 1_024}
    assert complete["process_resident_bytes"] == expected_resident
    assert measured_pids == [42, 101, 102, 103] * 2
    measured_pids.clear()

    footprint_without_ids = captured(launchctl, ps, include_physical_footprint=True)
    assert "role_process_ids" not in footprint_without_ids
    assert "process_resident_bytes" not in footprint_without_ids
    assert "process_physical_footprint_bytes" not in footprint_without_ids
    assert footprint_without_ids["physical_footprint_bytes"] == complete["physical_footprint_bytes"]
    assert footprint_without_ids["role_physical_footprint_bytes"] == complete["role_physical_footprint_bytes"]
    assert measured_pids == [42, 101, 102, 103] * 2
    measured_pids.clear()
    ids_without_footprint = captured(launchctl, ps, include_process_ids=True)
    assert ids_without_footprint["role_process_ids"] == complete["role_process_ids"]
    assert ids_without_footprint["process_resident_bytes"] == expected_resident
    assert "process_physical_footprint_bytes" not in ids_without_footprint
    assert "physical_footprint_bytes" not in ids_without_footprint
    assert measured_pids == [42, 101, 102, 103] * 2

    # Two workers of the same role and deliberately shuffled ps rows distinguish
    # PID identity from row position, while freezing ps's KiB-to-byte conversion.
    multiple_workers = launchctl.replace(
        "\tservices = {", "\tservices = {\n    104 - com.apple.WebKit.WebContent.44444444-4444-4444-4444-444444444444", 1
    )
    shuffled_rows = "\n".join([
        ps.splitlines()[3],
        "104 67 /System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent",
        ps.splitlines()[1], ps.splitlines()[0], ps.splitlines()[2],
    ])
    multiple = captured(multiple_workers, shuffled_rows, include_process_ids=True)
    assert multiple["process_resident_bytes"] == {**expected_resident, "104": 67 * 1_024}
    assert multiple["role_process_ids"]["web_content"] == [102, 104]
    assert multiple["role_process_counts"]["web_content"] == 2
    assert multiple["role_resident_bytes"]["web_content"] == 87 * 1_024
    assert multiple["resident_bytes"] == 227 * 1_024
    assert set(multiple["process_resident_bytes"]) == {
        str(pid) for pids in multiple["role_process_ids"].values() for pid in pids
    }
    assert sum(multiple["process_resident_bytes"].values()) == multiple["resident_bytes"]
    for role, pids in multiple["role_process_ids"].items():
        assert sum(multiple["process_resident_bytes"][str(pid)] for pid in pids) == multiple["role_resident_bytes"][role]
    assert "physical_footprint_bytes" not in multiple
    assert measured_pids == [42, 101, 102, 103, 104] * 2

    requires_error(lambda: captured(no_workers.replace("Scholium-QA.app", "Foreign.app"), ps.splitlines()[0], **options))
    requires_error(lambda: captured(no_workers, ps.splitlines()[0].replace("/Scholium", "/Foreign"), **options))
    requires_error(lambda: captured(missing_role, partial_rows.replace("com.apple.WebKit.GPU", "com.apple.WebKit.Networking"), **options))
    requires_error(lambda: captured(missing_role, ps.splitlines()[0], **options))

    panel_label = "com.apple.appkit.xpc.openAndSavePanelService"
    panel_path = (
        "/System/Library/Frameworks/AppKit.framework/Versions/C/XPCServices/"
        "com.apple.appkit.xpc.openAndSavePanelService.xpc/Contents/MacOS/"
        "com.apple.appkit.xpc.openAndSavePanelService"
    )
    assert OTHER_SERVICE_EXECUTABLES[panel_label] == panel_path
    labels = list(OTHER_SERVICE_EXECUTABLES)
    other_service_lines = "\n".join(f"    {201 + index} - {label}" for index, label in enumerate(labels))
    # Repeated aliases for one PID must not count that process twice. Inactive
    # templates and out-of-block service stubs never become active processes.
    all_services = launchctl.replace(
        "services = {", "services = {\n" + other_service_lines
        + f"\n    201 - {labels[0]}\n    205 - {panel_label}", 1
    ) + "service stubs = {\n    999 - com.apple.UnknownInactiveTemplate\n}\n"
    other_rows = "\n".join(
        f"{201 + index} {index + 2} {OTHER_SERVICE_EXECUTABLES[label]}"
        for index, label in enumerate(labels)
    )
    all_rows = ps + other_rows + "\n"
    for index in range(len(labels)):
        footprints[201 + index] = (index + 2) * 1_000
    narrow = captured(all_services, ps)
    assert set(narrow) == set(strict) and narrow["role_process_counts"] == strict["role_process_counts"]
    assert narrow["scope"] == "app_plus_attributed_webkit_services"
    full_options = {**options, "include_other_owned_services": True}
    whole_domain = captured(all_services, all_rows, **full_options)
    assert whole_domain["scope"] == "app_plus_attributed_originator_services"
    assert whole_domain["role_process_counts"]["other_services"] == 5
    assert whole_domain["role_process_ids"]["other_services"] == [201, 202, 203, 204, 205]
    assert whole_domain["role_resident_bytes"]["other_services"] == 20 * 1_024
    assert whole_domain["role_physical_footprint_bytes"]["other_services"] == 20_000
    assert whole_domain["process_count"] == 9 and whole_domain["resident_bytes"] == 180 * 1_024
    assert whole_domain["physical_footprint_bytes"] == 125_000
    assert whole_domain["process_physical_footprint_bytes"] == {str(pid): value for pid, value in footprints.items()}
    assert whole_domain["process_resident_bytes"] == {
        **expected_resident, "201": 2 * 1_024, "202": 3 * 1_024, "203": 4 * 1_024, "204": 5 * 1_024,
        "205": 6 * 1_024,
    }
    assert sum(whole_domain["process_resident_bytes"].values()) == whole_domain["resident_bytes"]
    assert sum(whole_domain["process_physical_footprint_bytes"].values()) == whole_domain["physical_footprint_bytes"]
    for role, pids in whole_domain["role_process_ids"].items():
        assert sum(whole_domain["process_resident_bytes"][str(pid)] for pid in pids) == whole_domain["role_resident_bytes"][role]
        assert sum(whole_domain["process_physical_footprint_bytes"][str(pid)] for pid in pids) == whole_domain["role_physical_footprint_bytes"][role]
    assert measured_pids == [42, 101, 102, 103, 201, 202, 203, 204, 205] * 2
    assert len(whole_domain["additional_owned_services"]) == 5
    assert whole_domain["additional_owned_services"][0] == {
        "pid": 201, "labels": [labels[0]], "executable": str(normalized(OTHER_SERVICE_EXECUTABLES[labels[0]])),
        "resident_bytes": 2 * 1_024, "physical_footprint_bytes": 2_000,
    }
    assert whole_domain["additional_owned_services"][4] == {
        "pid": 205, "labels": [panel_label], "executable": str(normalized(panel_path)),
        "resident_bytes": 6 * 1_024, "physical_footprint_bytes": 6_000,
    }
    measured_pids.clear()
    startup_domain = captured(no_workers, ps.splitlines()[0], **full_options)
    assert startup_domain["additional_owned_services"] == []
    assert startup_domain["role_process_counts"]["other_services"] == 0
    assert startup_domain["role_resident_bytes"]["other_services"] == 0
    assert startup_domain["role_physical_footprint_bytes"]["other_services"] == 0
    measured_pids.clear()
    requires_error(lambda: captured(all_services.replace(labels[0], "com.apple.UnknownActiveService", 1), all_rows, **full_options))
    requires_error(lambda: captured(all_services, all_rows.replace(OTHER_SERVICE_EXECUTABLES[labels[0]], "/System/Library/Foreign"), **full_options))
    requires_error(lambda: captured(all_services.replace(panel_label, panel_label + ".unknown"), all_rows, **full_options))
    requires_error(lambda: captured(all_services, all_rows.replace(panel_path, OTHER_SERVICE_EXECUTABLES[labels[0]]), **full_options))
    requires_error(lambda: captured(all_services, ps, **full_options))
    requires_error(lambda: captured(all_services.replace("201 - ", "101 - ", 1), all_rows, **full_options))
    requires_error(lambda: captured(all_services.replace("201 - ", "202 - ", 1), all_rows, **full_options))
    requires_error(lambda: captured(all_services.replace("services = {", "services = {\n 999 -", 1), all_rows, **full_options))
    requires_error(lambda: parse_launchctl_print("originator = /tmp/Scholium-QA.app\n", **{
        "allow_partial_webkit": True, "include_other_owned_services": True,
    }))

    kernel_paths = {pid: str(path) for pid, (_, path) in rows.items()}
    lifecycle_prefix = "process set changed during sampling;"

    # Kernel identity must tolerate ps display truncation without relaxing the
    # executable allowlist. Stable unrecognized kernel paths remain fatal.
    truncated_comm = ps.replace(str(rows[101][1]), "/display/truncated")
    assert captured(launchctl, truncated_comm, kernel_paths=kernel_paths)["resident_bytes"] == strict["resident_bytes"]
    foreign_paths = {**kernel_paths, 101: "/System/Library/Foreign"}
    error = requires_error(lambda: captured(launchctl, ps, kernel_paths=foreign_paths))
    assert not str(error).startswith(lifecycle_prefix)
    assert "PID 101 role gpu" in str(error) and "/System/Library/Foreign" in str(error)

    zero_rss = ps.replace("101 10 ", "101 0 ")
    error = requires_error(lambda: captured(launchctl, zero_rss))
    assert "nonpositive RSS value for PID 101" in str(error)
    assert not str(error).startswith(lifecycle_prefix)

    def endpoint_usage(change):
        def read(pid, flavor, buffer):
            result = read_usage(pid, flavor, buffer)
            if pid == 101 and measured_pids.count(pid) == 2:
                change(buffer._obj)
            return result
        return read

    for mutate in (
        lambda usage: setattr(usage, "ri_proc_exit_abstime", 1),
        lambda usage: setattr(usage, "ri_proc_start_abstime", 999_999),
        lambda usage: usage.ri_uuid.__setitem__(0, 255),
    ):
        error = requires_error(lambda: captured(launchctl, zero_rss, usage_callback=endpoint_usage(mutate)))
        assert str(error).startswith(lifecycle_prefix)

    # An exec that changes only the executable path also invalidates the
    # transaction, including when its initial path was already unrecognized.
    changed_paths = dict(foreign_paths)
    def change_path():
        changed_paths[101] = kernel_paths[101]
    error = requires_error(lambda: captured(
        launchctl, ps, kernel_paths=changed_paths, ps_callback=change_path,
    ))
    assert str(error).startswith(lifecycle_prefix)

    def unavailable_usage(error_number, *, endpoint_only=False):
        def read(pid, flavor, buffer):
            if pid == 101 and (not endpoint_only or measured_pids.count(pid) == 1):
                ctypes.set_errno(error_number)
                return -1
            return read_usage(pid, flavor, buffer)
        return read

    for endpoint_only in (False, True):
        error = requires_error(lambda: captured(
            launchctl, zero_rss, usage_callback=unavailable_usage(errno.ESRCH, endpoint_only=endpoint_only),
        ))
        assert str(error).startswith(lifecycle_prefix)
    error = requires_error(lambda: captured(launchctl, ps, usage_callback=unavailable_usage(errno.EPERM)))
    assert not str(error).startswith(lifecycle_prefix) and "proc_pid_rusage failed for PID 101" in str(error)

    def unavailable_path(error_number):
        def read(pid, buffer, capacity):
            if pid == 101:
                ctypes.set_errno(error_number)
                return 0
            buffer.value = os.fsencode(kernel_paths[pid])
            return len(buffer.value)
        return read

    for error_number in (errno.ESRCH, errno.EPERM):
        error = requires_error(lambda: captured(launchctl, ps, path_callback=unavailable_path(error_number)))
        assert str(error).startswith(lifecycle_prefix) == (error_number == errno.ESRCH)

    # A failed path lookup may race a zombie transition between public calls.
    error = requires_error(lambda: captured(
        launchctl, ps, path_callback=unavailable_path(errno.ENOENT),
        usage_callback=endpoint_usage(lambda usage: setattr(usage, "ri_proc_exit_abstime", 1)),
    ))
    assert str(error).startswith(lifecycle_prefix)

    error = requires_error(lambda: captured(
        launchctl, ps, include_physical_footprint=True,
        usage_callback=endpoint_usage(lambda usage: setattr(usage, "ri_phys_footprint", 0)),
    ))
    assert str(error).startswith("proc_pid_rusage returned no live physical footprint for PID 101")
    print("Process memory sampler self-test passed")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--allow-partial-webkit", action="store_true",
                        help="Allow absent startup WebKit roles, reporting them explicitly with zero counts")
    parser.add_argument("--include-process-ids", action="store_true",
                        help="Include validated per-role PIDs and per-PID process_resident_bytes")
    parser.add_argument("--physical-footprint", action="store_true",
                        help="Also read proc_pid_rusage physical footprint; unavailable readings fail closed")
    parser.add_argument("--include-other-owned-services", action="store_true",
                        help="Include every active originator service, requiring exact known label/executable pairs")
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
                allow_partial_webkit=arguments.allow_partial_webkit,
                include_process_ids=arguments.include_process_ids,
                include_physical_footprint=arguments.physical_footprint,
                include_other_owned_services=arguments.include_other_owned_services,
            )
            return
        result = sample(
            arguments.app, arguments.pid, allow_partial_webkit=arguments.allow_partial_webkit,
            include_process_ids=arguments.include_process_ids,
            include_physical_footprint=arguments.physical_footprint,
            include_other_owned_services=arguments.include_other_owned_services,
        )
    except SamplingError as error:
        print(f"Process memory sampling failed closed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Parent-owned, QA-only ScreenCaptureKit request supervisor."""

import argparse
import ctypes
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


REPOSITORY = Path(__file__).resolve().parents[2]
BUILD = REPOSITORY / ".build"
REQUEST_SUFFIX = ".request.json"
STOPPING = False


def contained_path(value):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("absolute .build path required")
    parts = path.relative_to(BUILD).parts
    if not parts or BUILD.is_symlink() or not BUILD.is_dir():
        raise ValueError("repository .build directory required")
    current = BUILD
    for index, part in enumerate(parts):
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            if index != len(parts) - 1:
                raise ValueError("parent directory missing") from None
            continue
        if stat.S_ISLNK(mode):
            raise ValueError("symlinks are forbidden")
    return path


def regular_file(path):
    return stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink()


def request_id(path):
    identifier = path.name.removesuffix(REQUEST_SUFFIX)
    if str(uuid.UUID(identifier)) != identifier.lower():
        raise ValueError("canonical UUID required")
    return identifier


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def read_request(path, pid_path):
    if not regular_file(path):
        raise ValueError("regular request file required")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        raw = stream.read(4097)
    if len(raw) > 4096:
        raise ValueError("request too large")
    request = json.loads(raw, object_pairs_hook=unique_object,
                         parse_constant=lambda _: (_ for _ in ()).throw(ValueError("invalid number")))
    if (type(request) is not dict or set(request) != {"schema", "pid", "output"}
            or type(request["schema"]) is not int or request["schema"] != 1
            or type(request["pid"]) is not int or not 1 < request["pid"] <= 2**31 - 1
            or type(request["output"]) is not str):
        raise ValueError("invalid request schema")
    output = contained_path(request["output"])
    if os.path.lexists(output) or not output.parent.is_dir():
        raise ValueError("fresh output directory required")
    buffer = ctypes.create_string_buffer(4096)
    if pid_path(request["pid"], buffer, len(buffer)) <= 0:
        raise ValueError("QA process unavailable")
    executable = Path(os.fsdecode(buffer.value)).resolve()
    qa = BUILD / "qa-runtime"
    allowed = {
        qa / "Scholium-QA.app/Contents/MacOS/Scholium",
        qa / "registered/Scholium-Codex-QA-Do-Not-Use.app/Contents/MacOS/Scholium",
    }
    if executable not in allowed:
        raise ValueError("only this checkout's QA executable is allowed")
    return request["pid"], output


def finished(directory, identifier, exit_code):
    destination = directory / f"{identifier}.finished.json"
    descriptor, temporary = tempfile.mkstemp(prefix=f".{identifier}.", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump({"exit_code": int(exit_code)}, stream)
            stream.write("\n")
        # Publish complete JSON atomically, without replacing any existing leaf.
        os.link(temporary, destination, follow_symlinks=False)
    finally:
        os.unlink(temporary)


def stop(process):
    if process.poll() is None:
        try:
            process.send_signal(signal.SIGINT)
        except ProcessLookupError:
            pass
    try:
        return process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
        return process.wait()


def interrupted(_signal, _frame):
    global STOPPING
    STOPPING = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--requests", required=True)
    parser.add_argument("--recorder", required=True)
    parser.add_argument("--owner-pid", required=True, type=int)
    args = parser.parse_args()
    directory = contained_path(args.requests)
    recorder = contained_path(args.recorder)
    if not directory.is_dir() or any(directory.iterdir()):
        raise ValueError("fresh existing empty request directory required")
    if not regular_file(recorder) or not os.access(recorder, os.X_OK):
        raise ValueError("executable recorder required")
    if args.owner_pid <= 1 or args.owner_pid == os.getpid():
        raise ValueError("shell owner PID required")
    recorder_identity = recorder.stat()
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    pid_path = library.proc_pidpath
    pid_path.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    pid_path.restype = ctypes.c_int
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    processed = set()
    active = None
    try:
        while not STOPPING:
            try:
                os.kill(args.owner_pid, 0)
            except ProcessLookupError:
                break
            contained_path(str(directory))
            if active is not None:
                identifier, process, log = active
                stop_path = directory / f"{identifier}.stop"
                code = process.poll()
                if os.path.lexists(stop_path):
                    valid_stop = regular_file(stop_path)
                    code = stop(process)
                    if not valid_stop:
                        code = 65
                if code is not None:
                    log.close()
                    finished(directory, identifier, code)
                    active = None
            if active is None:
                for path in sorted(directory.glob(f"*{REQUEST_SUFFIX}")):
                    identifier = request_id(path)
                    if identifier in processed:
                        continue
                    processed.add(identifier)
                    log = None
                    try:
                        log_path = directory / f"{identifier}.log"
                        descriptor = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                        log = os.fdopen(descriptor, "wb")
                        pid, output = read_request(path, pid_path)
                        current = contained_path(str(recorder)).stat()
                        if (current.st_dev, current.st_ino) != (recorder_identity.st_dev, recorder_identity.st_ino):
                            raise ValueError("recorder changed")
                        process = subprocess.Popen(
                            [str(recorder), "--pid", str(pid), "--output", str(output)],
                            stdin=subprocess.DEVNULL, stdout=log, stderr=log)
                        active = (identifier, process, log)
                    except Exception:
                        if log is not None:
                            log.write(b"Capture request rejected or helper launch failed.\n")
                            log.close()
                        finished(directory, identifier, 65)
                    break
            time.sleep(0.05)
    finally:
        if active is not None:
            identifier, process, log = active
            stop(process)
            log.close()
            finished(directory, identifier, 130)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never echo request contents, process paths, or JSON source into logs.
        print(f"QA capture supervisor failed: {type(error).__name__}", file=sys.stderr)
        sys.exit(1)

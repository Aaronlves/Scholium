#!/usr/bin/env python3
"""Preserve the shared QA domain around one coordinated native test run.

CFFIXED_USER_HOME does not prove native preference isolation. Never reset the
domain before a run. A failed/interrupted restoration retains the private prior
copy for explicit inspection; a later run cannot silently adopt that snapshot.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import uuid

DOMAIN = "com.scholium.qa"
STATE_NAME = "qa-preferences-preservation"


def allowed_domain(domain):
    if domain == DOMAIN:
        return True
    prefix = DOMAIN + ".preservation-test."
    if not domain.startswith(prefix):
        return False
    suffix = domain[len(prefix):]
    try:
        return str(uuid.UUID(suffix)) == suffix
    except ValueError:
        return False


def same_values(left, right):
    # Python's ordinary equality treats True == 1. Preference types matter.
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(same_values(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(same_values(a, b) for a, b in zip(left, right))
    return left == right


class Preferences:
    def read(self, domain):
        # `defaults export` returns an empty dictionary even for an absent
        # domain on current macOS; use read to preserve absence explicitly.
        existence = subprocess.run(["/usr/bin/defaults", "read", domain], capture_output=True)
        if existence.returncode != 0:
            message = (existence.stdout + existence.stderr).decode(errors="replace")
            if f"Domain '{domain}' not found." in message or f"Domain {domain} does not exist" in message:
                return None
            raise RuntimeError("Cannot determine whether QA preferences exist; no settings changed")
        result = subprocess.run(["/usr/bin/defaults", "export", domain, "-"], capture_output=True)
        if result.returncode == 0:
            values = plistlib.loads(result.stdout)
            if not isinstance(values, dict):
                raise RuntimeError("QA preferences are not a dictionary")
            return values
        raise RuntimeError("Cannot read the QA preference domain; no settings changed")

    def write(self, domain, values, snapshot):
        args = ["/usr/bin/defaults", "import", domain, str(snapshot)] if values is not None else ["/usr/bin/defaults", "delete", domain]
        subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
        if values is not None:
            # On current macOS import merges keys. Remove only additions absent
            # from the verified prior copy, after the import has succeeded.
            current = self.read(domain)
            for key in (current or {}).keys() - values.keys():
                subprocess.run(["/usr/bin/defaults", "delete", domain, key],
                               check=True, stdout=subprocess.DEVNULL)

    def require_stopped(self, domain):
        result = subprocess.run(["/usr/bin/lsappinfo", "find", "bundleID=" + domain], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip():
            raise RuntimeError("A QA-domain app is active or its state is unavailable; preferences were not restored")


def owner_started(owner_pid):
    if owner_pid <= 1:
        raise RuntimeError("Invalid QA owner PID")
    result = subprocess.run(["/bin/ps", "-p", str(owner_pid), "-o", "lstart="],
                            capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError("QA preservation owner is no longer running")
    return result.stdout.strip()


def capture(state, domain, owner_pid, preferences):
    if not allowed_domain(domain):
        raise RuntimeError("Only QA and UUID test preference domains are allowed")
    started = owner_started(owner_pid)
    preferences.require_stopped(domain)
    # mkdir is also the lease for this checkout. Other coordinated runners
    # fail before launching. Never replace an unresolved prior snapshot.
    state.mkdir(mode=0o700)
    try:
        values = preferences.read(domain)
        if values is not None:
            snapshot = state / "original.plist"
            snapshot.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY, sort_keys=True))
            snapshot.chmod(0o600)
        metadata = {"schema": 1, "domain": domain, "ownerPID": owner_pid, "ownerStarted": started, "present": values is not None}
        (state / "owner.json").write_text(json.dumps(metadata))
        (state / "owner.json").chmod(0o600)
    except BaseException:
        # No launch is authorized without a complete owner record. Keep any
        # successfully captured prior bytes instead of guessing at cleanup.
        raise
    print("Captured QA preference values; no domain reset")


def restore(state, domain, owner_pid, preferences):
    metadata = json.loads((state / "owner.json").read_text())
    expected = {"schema": 1, "domain": domain, "ownerPID": owner_pid,
                "ownerStarted": owner_started(owner_pid), "present": metadata.get("present")}
    if not allowed_domain(domain) or metadata != expected or type(metadata["present"]) is not bool:
        raise RuntimeError("QA snapshot ownership is invalid; retained without changing preferences")
    # Allow asynchronous NSApplication termination to complete, never kill an
    # unrelated app or overwrite preferences while the domain is still in use.
    for attempt in range(51):
        try:
            preferences.require_stopped(domain)
            break
        except RuntimeError:
            if attempt == 50:
                raise
            time.sleep(0.1)
    snapshot = state / "original.plist"
    original = plistlib.loads(snapshot.read_bytes()) if metadata["present"] else None
    if original is not None and not isinstance(original, dict):
        raise RuntimeError("Invalid QA snapshot; preferences were not changed")
    current = preferences.read(domain)
    changed = sorted(k for k in (original or {}).keys() | (current or {}).keys()
                     if k not in (original or {}) or k not in (current or {}) or not same_values(original[k], current[k]))
    # Current macOS may keep an empty plist after `defaults delete`. For a
    # previously absent domain, verify no stored keys remain; do not manipulate
    # cfprefsd or delete preference files behind its back. Existing domains
    # still require exact type-aware values, including an empty dictionary.
    def restored(values):
        return (values is None or values == {}) if original is None else same_values(original, values)

    if not restored(current):
        preferences.write(domain, original, snapshot)
    if not restored(preferences.read(domain)):
        raise RuntimeError("QA preference verification failed; original snapshot retained")
    # Remove the verified snapshot only after a type-aware read through the
    # preferences service. Binary plist byte ordering need not be identical.
    snapshot.unlink(missing_ok=True)
    (state / "owner.json").unlink()
    state.rmdir()
    print(f"Verified QA preference restoration ({len(changed)} changed keys)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["capture", "restore"])
    parser.add_argument("--owner-pid", required=True, type=int)
    parser.add_argument("--domain", default=DOMAIN)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    state = root / ".build" / STATE_NAME
    try:
        globals()[args.action](state, args.domain, args.owner_pid, Preferences())
    except Exception as error:
        parser.exit(1, f"QA preference preservation failed: {error}. Evidence: {state}\n")


if __name__ == "__main__":
    main()

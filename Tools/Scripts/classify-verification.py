#!/usr/bin/env python3
"""Select the docs gate only from a verified event and a complete, safe Git diff."""

import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SHA = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
ROOT_DOCS = {"README.md", "Design.md", "Docs/SCHOLIUM_SPEC.md",
             "Docs/IMPLEMENTATION_ARCHITECTURE.md", "Docs/IMPLEMENTATION_STATUS.md"}
DOCS = ROOT_DOCS | {f"Docs/{directory}/{chapter}.md" for directory, chapters in {
    "Architecture": ("01-runtime-and-ownership", "02-agent-collaboration",
                     "05-source-storage-and-read-models", "06-documents-and-editor"),
    "Status": ("03-open-work", "04-verification"),
    "Specification": ("01-foundation-and-triptych", "02-notes-and-file-operations",
                      "03-agent-collaboration-and-workflows", "04-connect-search-and-recovery",
                      "05-integrations-onboarding-and-boundaries", "06-interface-shell-and-library",
                      "07-document-and-research-interface", "09-accessibility-and-adaptation",
                      "10-release-and-open-decisions", "12-agent-chat", "13-settings", "14-chat-interface"),
}.items() for chapter in chapters}


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def commit(value):
    if not isinstance(value, str) or not SHA.fullmatch(value) or set(value) == {"0"}:
        raise ValueError("missing or invalid commit")
    return value


def docs_diff(raw):
    """No quoting/line splitting: raw -z preserves hostile filenames exactly."""
    fields = raw.split(b"\0")
    if not raw or fields.pop() != b"" or len(fields) % 2:
        return False
    for header, name in zip(fields[::2], fields[1::2]):
        # Only edits to existing regular, non-executable documentation qualify.
        if not re.fullmatch(rb":100644 100644 [0-9a-f]+ [0-9a-f]+ M", header):
            return False
        path = name.decode("ascii", errors="strict")
        if path not in DOCS:
            return False
    return True


def classify(root, event_name, event, expected_sha):
    if not isinstance(event, dict):
        raise ValueError("invalid event object")
    if event_name == "workflow_dispatch":
        inputs = event.get("inputs", {})
        if not isinstance(inputs, dict):
            raise ValueError("invalid manual inputs")
        profile = inputs.get("profile", "full")
        if profile not in {"full", "daily"}:
            raise ValueError("unknown manual profile")
        return profile, "explicit manual scope"
    if event_name not in {"push", "pull_request"}:
        return "daily", "unknown event"
    head = commit(git(root, "rev-parse", "HEAD").decode().strip())
    if head != commit(expected_sha):
        return "daily", "checkout does not match event"
    if event_name == "push":
        base = commit(event.get("before"))
        if commit(event.get("after")) != head or event.get("deleted") or event.get("forced"):
            return "daily", "ambiguous push"
        git(root, "merge-base", "--is-ancestor", base, head)
    else:
        pr = event["pull_request"]
        base, source = commit(pr["base"]["sha"]), commit(pr["head"]["sha"])
        parents = git(root, "rev-list", "--parents", "-n", "1", head).decode().split()
        if parents != [head, base, source]:
            return "daily", "unverified PR merge parents"
    # Missing base/history, malformed events and any unfamiliar path fall back.
    raw = git(root, "diff", "--raw", "--no-abbrev", "--no-renames", "-z", base, head, "--")
    return ("docs", "only existing regular documentation changed") if docs_diff(raw) else (
        "daily", "diff requires daily coverage")


def main():
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        route, reason = classify(ROOT, os.environ.get("GITHUB_EVENT_NAME"), event,
                                 os.environ.get("GITHUB_SHA"))
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        route, reason = "daily", "missing or unverified event/diff"
    print(f"Verification route: {route} ({reason})")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"profile={route}\n")


if __name__ == "__main__":
    main()

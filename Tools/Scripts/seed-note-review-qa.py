#!/usr/bin/env python3
"""Seed the disposable ordinary-product QA with current Note Review fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import UUID, uuid5


RECORD_COUNT = 100
CHANGED_TOPIC_COUNT = 60
MULTI_NOTE_CHANGED_COUNT = 20
REVIEWED_TOPIC_COUNT = 57
REVIEWED_WORK_COUNT = 15
NAMESPACE = UUID("ba52bc73-1730-4a46-920b-fb11fa4ca41f")


def stable_uuid(value: str) -> str:
    return str(uuid5(NAMESPACE, value))


def fingerprint(value: str) -> dict[str, Any]:
    data = value.encode("utf-8")
    return {"sha256": hashlib.sha256(data).hexdigest(), "byteCount": len(data)}


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected one JSON object at {path}")
    return value


def require_disposable_fixture(root: Path) -> None:
    expected = (
        Path(__file__).resolve().parents[2]
        / ".build"
        / "qa-runtime"
        / "fixtures"
    ).resolve()
    if root.resolve() != expected:
        raise ValueError(
            "Refusing to seed outside the repository-owned "
            f"disposable QA fixture: {expected}"
        )
    for required in (
        root / "01-analyses" / "QA Autosave A.md",
        root / "02-topics" / "QA Topic.md",
        root / "03-works" / "QA Work.md",
        root / ".scholium" / "manifest.json",
        root / ".scholium" / "identities.json",
    ):
        if not required.is_file():
            raise ValueError(f"Disposable QA fixture is incomplete: {required}")


def current_identities(root: Path) -> tuple[str, dict[str, dict[str, Any]]]:
    manifest = read_json(root / ".scholium" / "manifest.json")
    triptych_id = str(UUID(str(manifest["id"])))
    current_vault_ids: set[str] = set()
    for value in manifest.get("vaultIDs", []):
        try:
            current_vault_ids.add(str(UUID(str(value))))
        except ValueError:
            continue

    identities = read_json(root / ".scholium" / "identities.json")
    by_path: dict[str, dict[str, Any]] = {}
    for item in identities.get("records", []):
        if str(item.get("vaultID", "")).lower() not in current_vault_ids:
            continue
        relative_path = item.get("relativePath")
        if relative_path in {"QA Autosave A.md", "QA Topic.md", "QA Work.md"}:
            if relative_path in by_path:
                raise ValueError(f"Duplicate current identity for {relative_path}")
            by_path[relative_path] = item
    expected = {"QA Autosave A.md", "QA Topic.md", "QA Work.md"}
    if set(by_path) != expected:
        raise ValueError(
            f"Expected current identities for {sorted(expected)}, found {sorted(by_path)}"
        )
    return triptych_id, by_path


def participant(
    identity: dict[str, Any],
    role: str,
    title: str,
    starting_revision: dict[str, Any],
) -> dict[str, Any]:
    return {
        "note_id": str(UUID(identity["id"])),
        "note": {
            "vaultID": str(UUID(identity["vaultID"])),
            "relativePath": identity["relativePath"],
        },
        "role": role,
        "title": title,
        "starting_revision": starting_revision,
        "ending_revision": identity["fingerprint"],
        "is_tombstone": False,
    }


def write_private_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.chmod(path, 0o600)


def make_record(
    ordinal: int,
    triptych_id: str,
    identities: dict[str, dict[str, Any]],
) -> tuple[str, dict[str, Any], set[str]]:
    record_id = stable_uuid(f"note-review-qa-record-{ordinal:03d}")
    topic = identities["QA Topic.md"]
    work = identities["QA Work.md"]
    analysis = identities["QA Autosave A.md"]
    changes_topic = ordinal <= CHANGED_TOPIC_COUNT
    changes_work = ordinal <= MULTI_NOTE_CHANGED_COUNT
    uses_analysis = ordinal % 10 == 0

    topic_start = (
        fingerprint(f"QA Topic before Agent activity {ordinal}")
        if changes_topic
        else topic["fingerprint"]
    )
    participants = [participant(topic, "topic", "QA Topic", topic_start)]
    changed_paths: set[str] = set()
    confirmed_changes: list[dict[str, Any]] = []
    if changes_topic:
        changed_paths.add("QA Topic.md")
        confirmed_changes.append(
            {
                "note_id": str(UUID(topic["id"])),
                "actor": "agent",
                "starting_revision": topic_start,
                "ending_revision": topic["fingerprint"],
            }
        )
    if changes_work:
        work_start = fingerprint(f"QA Work before Agent activity {ordinal}")
        participants.append(participant(work, "work", "QA Work", work_start))
        changed_paths.add("QA Work.md")
        confirmed_changes.append(
            {
                "note_id": str(UUID(work["id"])),
                "actor": "agent",
                "starting_revision": work_start,
                "ending_revision": work["fingerprint"],
            }
        )
    if uses_analysis:
        participants.append(
            participant(
                analysis,
                "analysis",
                "QA Autosave A",
                analysis["fingerprint"],
            )
        )

    started = datetime(2026, 8, 1, 8, 0, tzinfo=timezone.utc) + timedelta(
        minutes=ordinal * 7
    )
    finished = started + timedelta(minutes=4)
    length_variant = (
        "A concise disposable result."
        if ordinal % 3 == 1
        else "A medium disposable result records the bounded QA relationship."
        if ordinal % 3 == 2
        else (
            "A longer disposable result exists to exercise reading cadence in the "
            "ordinary Records detail without presenting invented research as genuine evidence."
        )
    )
    change_label = (
        "multi-Note Agent change"
        if changes_work
        else "Topic Agent change"
        if changes_topic
        else "no source change"
    )
    record: dict[str, Any] = {
        "schema_version": 15,
        "id": record_id,
        "triptych_id": triptych_id,
        "record_title": f"QA {ordinal:03d} · {change_label}",
        "kind": "action",
        "action": {
            "schema_version": 2,
            "action_id": "synthesize",
            "material_note_ids": (
                [str(UUID(analysis["id"]))] if uses_analysis else []
            ),
        },
        "method": {
            "registration_key": "10000000-0000-0000-0000-000000000003",
            "display_name": "Synthesize",
            "profile_revision": fingerprint("QA bounded Synthesize Profile"),
        },
        "primary_note_id": str(UUID(topic["id"])),
        "participating_notes": participants,
        "statements": [
            {
                "id": stable_uuid(f"note-review-qa-statement-{ordinal:03d}"),
                "author": "agent",
                "kind": "agent_feedback",
                "attribution": "Synthetic QA Agent",
                "text": length_variant,
                "created_at": finished.isoformat().replace("+00:00", "Z"),
            }
        ],
        "result_disposition": "completed",
        "academic_results": [],
        "fidelity_completion": "completed" if ordinal % 3 == 0 else "unverified",
        "confirmed_changes": confirmed_changes,
        "discrepancies": [],
        "literature_recommendations": [],
        "started_at": started.isoformat().replace("+00:00", "Z"),
        "finished_at": finished.isoformat().replace("+00:00", "Z"),
    }

    if ordinal % 4 == 0:
        evaluation_revision = stable_uuid(f"note-review-qa-evaluation-{ordinal:03d}")
        record["researcher_evaluation"] = {
            "revision": evaluation_revision,
            "author": "researcher",
            "observed_issues": [],
            "no_issues_observed": True,
            "valuable_discovery": ordinal % 8 == 0,
            "note": "Synthetic QA evaluation for the progressive Response reading plane.",
            "updated_at": (finished + timedelta(minutes=2))
            .isoformat()
            .replace("+00:00", "Z"),
        }
        if ordinal % 8 == 0:
            record["method_feedback_comment"] = {
                "revision": stable_uuid(
                    f"note-review-qa-method-feedback-{ordinal:03d}"
                ),
                "author": "researcher",
                "text": "Synthetic QA feedback asks the Method to expose its inferential bridge.",
                "source_evaluation_revision": evaluation_revision,
                "updated_at": (finished + timedelta(minutes=3))
                .isoformat()
                .replace("+00:00", "Z"),
            }
    return record_id, record, changed_paths


def seed(root: Path) -> dict[str, Any]:
    require_disposable_fixture(root)
    triptych_id, identities = current_identities(root)
    store_root = root / ".scholium" / "research-records" / "v1"
    records_root = store_root / "records"
    reviews_root = store_root / "note-reviews"
    records_root.mkdir(parents=True, exist_ok=True, mode=0o755)
    reviews_root.mkdir(parents=True, exist_ok=True, mode=0o755)
    existing = list(records_root.glob("*.json")) + list(reviews_root.glob("*.json"))
    if existing:
        raise ValueError(
            "Refusing to replace existing portable Record or Note Review files in QA"
        )

    topic_activities: list[dict[str, str]] = []
    work_activities: list[dict[str, str]] = []
    for ordinal in range(1, RECORD_COUNT + 1):
        record_id, record, changed_paths = make_record(
            ordinal, triptych_id, identities
        )
        write_private_json(records_root / f"{record_id}.json", record)
        if "QA Topic.md" in changed_paths:
            topic_activities.append(
                {
                    "record_id": record_id,
                    "note_id": str(UUID(identities["QA Topic.md"]["id"])),
                }
            )
        if "QA Work.md" in changed_paths:
            work_activities.append(
                {
                    "record_id": record_id,
                    "note_id": str(UUID(identities["QA Work.md"]["id"])),
                }
            )

    reviewed_at = "2026-08-09T09:00:00Z"
    for relative_path, activities in (
        ("QA Topic.md", topic_activities[:REVIEWED_TOPIC_COUNT]),
        ("QA Work.md", work_activities[:REVIEWED_WORK_COUNT]),
    ):
        identity = identities[relative_path]
        note_id = str(UUID(identity["id"]))
        write_private_json(
            reviews_root / f"{note_id}.json",
            {
                "schema_version": 1,
                "note_id": note_id,
                "observed_revision": identity["fingerprint"],
                "reviewed_at": reviewed_at,
                "covered_activities": activities,
            },
        )

    record_files = list(records_root.glob("*.json"))
    if len(record_files) != RECORD_COUNT:
        raise RuntimeError(f"Expected {RECORD_COUNT} Records, found {len(record_files)}")
    unique_ids = {read_json(path)["id"] for path in record_files}
    if len(unique_ids) != RECORD_COUNT:
        raise RuntimeError("Synthetic QA Record IDs are not unique")
    return {
        "schema": 8,
        "records": len(record_files),
        "topic_associations": RECORD_COUNT,
        "changed_topic": len(topic_activities),
        "pending_topic": len(topic_activities) - REVIEWED_TOPIC_COUNT,
        "changed_work": len(work_activities),
        "pending_work": len(work_activities) - REVIEWED_WORK_COUNT,
        "no_change": RECORD_COUNT - CHANGED_TOPIC_COUNT,
        "multi_note_changed": MULTI_NOTE_CHANGED_COUNT,
        "evaluations": RECORD_COUNT // 4,
        "method_feedback": RECORD_COUNT // 8,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture_root", type=Path)
    args = parser.parse_args()
    print(json.dumps(seed(args.fixture_root), sort_keys=True))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate or verify Scholium's deterministic RDF-1 performance Triptych."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path


FIXTURE_VERSION = "rdf-1-v3"
TOTAL_NOTES = 800
LONG_NOTE_WORDS = 5_000
CJK_STRESS_CHARACTERS = 100_000
ROLE_SPECS = (
    ("analyses", "01-analyses", "analysis", 267),
    ("topics", "02-topics", "topic", 266),
    ("works", "03-works", "work", 267),
)
LONG_NOTE_PATH = "Long/Canonical-5000-Word-Work.md"
CJK_STRESS_NOTE_PATH = "Long/Canonical-100000-CJK-Work.md"
TOKEN_PATTERN = re.compile(r"\b[\w'-]+\b", re.UNICODE)
CJK_CHARACTER_PATTERN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def markdown_section_bytes(path: Path, heading: str) -> bytes:
    source = path.read_text(encoding="utf-8")
    marker = f"### {heading}\n"
    start = source.find(marker)
    if start == -1:
        raise SystemExit(f"Missing canonical protocol section: {heading}")
    end = source.find("\n### ", start + len(marker))
    section = source[start:] if end == -1 else source[start:end]
    return section.encode("utf-8")


def body_word_count(value: str) -> int:
    return len(TOKEN_PATTERN.findall(value))


def cjk_character_count(value: str) -> int:
    return len(CJK_CHARACTER_PATTERN.findall(value))


def require_disposable_output(path: Path, allow_outside_tmp: bool) -> Path:
    resolved = path.expanduser().resolve()
    repository_build = Path(__file__).resolve().parents[2] / ".build"
    try:
        resolved.relative_to(repository_build)
        if resolved == repository_build:
            raise SystemExit("Refusing to replace the repository .build root itself.")
        return resolved
    except ValueError:
        pass
    if allow_outside_tmp:
        return resolved
    private_tmp = Path("/private/tmp").resolve()
    try:
        resolved.relative_to(private_tmp)
    except ValueError as error:
        raise SystemExit(
            "RDF-1 generation is destructive and defaults to the repository .build tree. "
            "Pass --allow-outside-tmp only for an intentionally reviewed external fixture location."
        ) from error
    if resolved == private_tmp:
        raise SystemExit("Refusing to replace /tmp itself.")
    return resolved


def valid_frontmatter(role: str, index: int, title: str) -> str:
    return f"""---
title: {json.dumps(title)}
record_type: rdf1_{role}
tags: [rdf1, performance, cluster-{index % 17:02d}]
status: active
created: 2026-07-14T00:00:00Z
updated: 2026-07-14T00:00:00Z
fixture: true
rdf1_id: {role}-{index:03d}
---"""


def malformed_frontmatter(role: str, index: int) -> str:
    return f"""---
title: [deliberately unterminated
record_type: rdf1_{role}
rdf1_id: {role}-{index:03d}
---"""


def regular_body(role: str, index: int, count: int) -> tuple[str, int, int]:
    title = f"RDF-1 {role.title()} Note {index:03d}"
    next_index = index % count + 1
    relation = "+" if index % 10 == 0 else ""
    sentinel = ""
    if role == "analysis" and index == 1:
        sentinel = " RDF1WarmAnalysis"
    elif role == "analysis" and index == 2:
        sentinel = " RDF1AlternateAnalysis"
    elif role == "topic" and index == 1:
        sentinel = " rdf1exacttopic"
    elif role == "topic" and index == 2:
        sentinel = " 哲学检索边界"
    body = f"""# {title}

This synthetic note measures deterministic Scholium performance without containing research material.{sentinel}

The fixture discusses deliberative control, normative reasons, objections, replies, source fidelity, and explicit uncertainty. Its prose is intentionally repetitive enough to exercise indexing while remaining clearly non-scholarly.

{relation}[[RDF-1 {role.title()} Note {next_index:03d}]]
"""
    return body, 1, 1 if relation else 0


def long_note_body() -> str:
    vocabulary = (
        "argument evidence inference objection reply source authority conclusion "
        "uncertainty distinction relation agency value reason response context"
    ).split()
    words = [vocabulary[index % len(vocabulary)] for index in range(LONG_NOTE_WORDS)]
    words[0:4] = ["[[RDF-1", "Work", "Note", "003]]"]
    paragraphs = [" ".join(words[start : start + 100]) for start in range(0, len(words), 100)]
    body = "\n\n".join(paragraphs) + "\n"
    assert body_word_count(body) == LONG_NOTE_WORDS
    return body


def cjk_stress_note_body() -> str:
    # Deterministic synthetic prose-shaped material. It is deliberately not a
    # philosophical source and exists only to exercise CJK editing boundaries.
    seed = "研究性能边界输入选择撤销渲染滚动保存恢复"
    characters = (seed * ((CJK_STRESS_CHARACTERS // len(seed)) + 1))[
        :CJK_STRESS_CHARACTERS
    ]
    paragraphs = [
        characters[start : start + 1_000]
        for start in range(0, len(characters), 1_000)
    ]
    body = "\n\n".join(paragraphs) + "\n"
    assert cjk_character_count(body) == CJK_STRESS_CHARACTERS
    return body


def write_note(path: Path, source: str) -> dict[str, object]:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = source.encode("utf-8")
    path.write_bytes(encoded)
    return {
        "bytes": len(encoded),
        "sha256": sha256_bytes(encoded),
    }


def project_file(name: str) -> Path:
    return Path(__file__).resolve().parents[2] / name


def generate(output: Path) -> dict[str, object]:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    entries: list[dict[str, object]] = []
    role_counts: dict[str, int] = {}
    valid_frontmatter_count = 0
    malformed_frontmatter_count = 0
    markdown_links = 0
    typed_relations = 0

    for role_key, vault_name, role, count in ROLE_SPECS:
        vault_root = output / vault_name
        role_counts[role_key] = count
        for index in range(1, count + 1):
            is_long_note = role == "work" and index == 1
            is_cjk_stress_note = role == "work" and index == 2
            is_malformed = index == count
            title = (
                "Canonical 5000 Word Work"
                if is_long_note
                else "Canonical 100000 CJK Work"
                if is_cjk_stress_note
                else f"RDF-1 {role.title()} Note {index:03d}"
            )
            if is_long_note:
                relative_path = LONG_NOTE_PATH
                body = long_note_body()
                link_count = 1
                typed_count = 0
            elif is_cjk_stress_note:
                relative_path = CJK_STRESS_NOTE_PATH
                body = cjk_stress_note_body()
                link_count = 0
                typed_count = 0
            else:
                relative_path = f"Cluster-{(index - 1) % 17:02d}/{role}-note-{index:03d}.md"
                body, link_count, typed_count = regular_body(role, index, count)

            frontmatter = (
                malformed_frontmatter(role, index)
                if is_malformed
                else valid_frontmatter(role, index, title)
            )
            if is_malformed:
                malformed_frontmatter_count += 1
            else:
                valid_frontmatter_count += 1
            source = f"{frontmatter}\n{body}"
            metadata = write_note(vault_root / relative_path, source)
            markdown_links += link_count
            typed_relations += typed_count
            entries.append(
                {
                    "vault": role_key,
                    "vault_directory": vault_name,
                    "relative_path": relative_path,
                    "frontmatter": "malformed" if is_malformed else "valid",
                    "body_words": body_word_count(body),
                    "markdown_links": link_count,
                    "typed_relations": typed_count,
                    **metadata,
                }
            )

    assert len(entries) == TOTAL_NOTES
    tree_material = "\n".join(
        f"{entry['vault']}:{entry['relative_path']}:{entry['sha256']}" for entry in entries
    ).encode("utf-8")
    script_path = Path(__file__).resolve()
    protocol_path = project_file("Docs/Specification/10-release-and-open-decisions.md")
    protocol_section = "21.4 Packaged performance gate"
    manifest: dict[str, object] = {
        "fixture": "Scholium Reference Data Fixture 1",
        "version": FIXTURE_VERSION,
        "determinism": {"random_seed": None, "mode": "deterministic-no-rng"},
        "generator": {
            "path": "Tools/Scripts/generate-rdf1.py",
            "sha256": sha256_file(script_path),
        },
        "protocol": {
            "path": "Docs/Specification/10-release-and-open-decisions.md",
            "section": "21.4",
            "sha256": (
                sha256_bytes(markdown_section_bytes(protocol_path, protocol_section))
                if protocol_path.exists()
                else None
            ),
        },
        "triptych": {
            "note_count": len(entries),
            "role_counts": role_counts,
            "total_bytes": sum(int(entry["bytes"]) for entry in entries),
            "valid_frontmatter": valid_frontmatter_count,
            "malformed_frontmatter": malformed_frontmatter_count,
            "markdown_links": markdown_links,
            "typed_relations": typed_relations,
            "maximum_folder_depth": max(
                len(Path(str(entry["relative_path"])).parts) - 1 for entry in entries
            ),
            "tree_sha256": sha256_bytes(tree_material),
        },
        "canonical_documents": {
            "warm_note": {
                "vault": "analyses",
                "relative_path": "Cluster-00/analysis-note-001.md",
            },
            "alternate_note": {
                "vault": "analyses",
                "relative_path": "Cluster-01/analysis-note-002.md",
            },
            "cold_long_note": {
                "vault": "works",
                "relative_path": LONG_NOTE_PATH,
                "body_word_count": LONG_NOTE_WORDS,
                "word_count_rule": "Unicode word tokens in the Markdown body after frontmatter",
            },
            "cjk_stress_note": {
                "vault": "works",
                "relative_path": CJK_STRESS_NOTE_PATH,
                "cjk_character_count": CJK_STRESS_CHARACTERS,
                "character_count_rule": "CJK Unified Ideographs in the Markdown body after frontmatter",
            },
        },
        "search_queries": [
            {
                "query": "RDF1WarmAnalysis",
                "expected": [{"vault": "analyses", "relative_path": "Cluster-00/analysis-note-001.md"}],
                "ordering": "exact-single-result",
            },
            {
                "query": "rdf1exacttopic",
                "expected": [{"vault": "topics", "relative_path": "Cluster-00/topic-note-001.md"}],
                "ordering": "exact-single-result",
            },
            {
                "query": "哲学检索边界",
                "expected": [{"vault": "topics", "relative_path": "Cluster-01/topic-note-002.md"}],
                "ordering": "exact-single-result",
            },
        ],
        "notes": entries,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def verify(output: Path) -> dict[str, object]:
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"Missing RDF-1 manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("version") != FIXTURE_VERSION:
        raise SystemExit(f"Unexpected RDF-1 version: {manifest.get('version')!r}")
    entries = manifest.get("notes")
    if not isinstance(entries, list) or len(entries) != TOTAL_NOTES:
        raise SystemExit(f"RDF-1 must contain exactly {TOTAL_NOTES} manifest entries.")

    listed_paths: set[Path] = set()
    tree_rows: list[str] = []
    for entry in entries:
        relative = Path(str(entry["vault_directory"])) / str(entry["relative_path"])
        note_path = output / relative
        if relative in listed_paths:
            raise SystemExit(f"Duplicate RDF-1 manifest path: {relative}")
        listed_paths.add(relative)
        if not note_path.is_file():
            raise SystemExit(f"Missing RDF-1 note: {note_path}")
        data = note_path.read_bytes()
        if len(data) != entry["bytes"] or sha256_bytes(data) != entry["sha256"]:
            raise SystemExit(f"RDF-1 note does not match its manifest: {note_path}")
        tree_rows.append(f"{entry['vault']}:{entry['relative_path']}:{entry['sha256']}")

    actual_paths = {
        path.relative_to(output)
        for _, vault_directory, _, _ in ROLE_SPECS
        for path in (output / vault_directory).rglob("*.md")
        if path.is_file()
    }
    if actual_paths != listed_paths:
        missing = sorted(str(path) for path in listed_paths - actual_paths)
        unlisted = sorted(str(path) for path in actual_paths - listed_paths)
        raise SystemExit(f"RDF-1 path mismatch; missing={missing}, unlisted={unlisted}")

    tree_sha = sha256_bytes("\n".join(tree_rows).encode("utf-8"))
    if tree_sha != manifest["triptych"]["tree_sha256"]:
        raise SystemExit("RDF-1 tree hash does not match its manifest.")

    long_note = output / "03-works" / LONG_NOTE_PATH
    source = long_note.read_text(encoding="utf-8")
    parts = source.split("---\n", 2)
    if len(parts) != 3 or body_word_count(parts[2]) != LONG_NOTE_WORDS:
        raise SystemExit(f"RDF-1 long note must contain exactly {LONG_NOTE_WORDS} body words.")

    cjk_stress_note = output / "03-works" / CJK_STRESS_NOTE_PATH
    source = cjk_stress_note.read_text(encoding="utf-8")
    parts = source.split("---\n", 2)
    if len(parts) != 3 or cjk_character_count(parts[2]) != CJK_STRESS_CHARACTERS:
        raise SystemExit(
            f"RDF-1 CJK stress note must contain exactly {CJK_STRESS_CHARACTERS} CJK characters."
        )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[2] / ".build/scholium-rdf1",
        help="Disposable output root (default: repository .build/scholium-rdf1)",
    )
    parser.add_argument("--verify", action="store_true", help="Verify an existing fixture without rewriting it")
    parser.add_argument("--allow-outside-tmp", action="store_true")
    arguments = parser.parse_args()
    output = require_disposable_output(arguments.output, arguments.allow_outside_tmp)
    manifest = verify(output) if arguments.verify else generate(output)
    if not arguments.verify:
        manifest = verify(output)
    print(
        f"RDF-1 {manifest['version']} verified: "
        f"{manifest['triptych']['note_count']} notes, "
        f"tree {manifest['triptych']['tree_sha256']}"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Validate Scholium's closed documentation authority sets and local links."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import sys
import unicodedata
from urllib.parse import unquote


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPOSITORY_ROOT / "Docs"
MAX_AUTHORITY_LINE_LENGTH = 300
MAX_CHAPTER_WORDS = 6_500

MANIFESTS = (
    (DOCS_ROOT / "SCHOLIUM_SPEC.md", DOCS_ROOT / "Specification"),
    (DOCS_ROOT / "IMPLEMENTATION_ARCHITECTURE.md", DOCS_ROOT / "Architecture"),
    (DOCS_ROOT / "IMPLEMENTATION_STATUS.md", DOCS_ROOT / "Status"),
)

MARKDOWN_LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
SECTION_ID = re.compile(
    r"^#{2,3}\s+(Appendix [A-Z]|\d+(?:\.\d+)*)(?:\.|\s)"
)


def failure(message: str) -> None:
    print(f"Documentation authority validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def markdown_target(raw_target: str) -> str:
    target = raw_target.strip()
    if " \"" in target:
        target = target.split(" \"", 1)[0]
    return unquote(target)


def github_heading_anchors(path: Path) -> set[str]:
    anchors: set[str] = set()
    occurrences: Counter[str] = Counter()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^#{1,6}\s+(.+?)\s*#*$", line)
        if not match:
            continue
        heading = re.sub(r"`([^`]*)`", r"\1", match.group(1)).strip().lower()
        normalized = unicodedata.normalize("NFKC", heading)
        slug = "".join(
            character
            for character in normalized
            if character.isalnum() or character in {" ", "-", "_"}
        )
        slug = re.sub(r"\s+", "-", slug)
        suffix = occurrences[slug]
        occurrences[slug] += 1
        anchors.add(slug if suffix == 0 else f"{slug}-{suffix}")
    return anchors


def validate_manifest(manifest: Path, chapter_directory: Path) -> list[Path]:
    if not manifest.is_file():
        failure(f"missing manifest {manifest.relative_to(REPOSITORY_ROOT)}")
    if not chapter_directory.is_dir():
        failure(f"missing chapter directory {chapter_directory.relative_to(REPOSITORY_ROOT)}")

    source = manifest.read_text(encoding="utf-8")
    declared: list[Path] = []
    for raw_target in MARKDOWN_LINK.findall(source):
        target = markdown_target(raw_target).split("#", 1)[0]
        if not target:
            continue
        candidate = (manifest.parent / target).resolve()
        if candidate.parent == chapter_directory.resolve() and candidate.suffix == ".md":
            declared.append(candidate)

    duplicate_declarations = [
        path for path, count in Counter(declared).items() if count > 1
    ]
    if duplicate_declarations:
        failure(
            f"duplicate chapter declarations in {manifest.name}: "
            + ", ".join(path.name for path in duplicate_declarations)
        )

    actual = sorted(path.resolve() for path in chapter_directory.glob("*.md"))
    if set(declared) != set(actual):
        missing = sorted(set(actual) - set(declared))
        stale = sorted(set(declared) - set(actual))
        details = []
        if missing:
            details.append("undeclared=" + ",".join(path.name for path in missing))
        if stale:
            details.append("missing=" + ",".join(path.name for path in stale))
        failure(f"{manifest.name} chapter set mismatch ({'; '.join(details)})")

    for chapter in declared:
        source = chapter.read_text(encoding="utf-8")
        expected_root_link = f"[{manifest.name}](../{manifest.name})"
        if expected_root_link not in source:
            failure(
                f"{chapter.relative_to(REPOSITORY_ROOT)} does not point to {manifest.name}"
            )
        if not source.startswith("# "):
            failure(f"{chapter.relative_to(REPOSITORY_ROOT)} has no chapter title")
        word_count = len(source.split())
        if word_count > MAX_CHAPTER_WORDS:
            failure(
                f"{chapter.relative_to(REPOSITORY_ROOT)} has {word_count} words "
                f"(maximum {MAX_CHAPTER_WORDS})"
            )
    return declared


def validate_local_links(paths: list[Path]) -> int:
    anchors_by_path: dict[Path, set[str]] = {}
    checked = 0
    for source_path in paths:
        source = source_path.read_text(encoding="utf-8")
        for raw_target in MARKDOWN_LINK.findall(source):
            target = markdown_target(raw_target)
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            path_text, separator, anchor = target.partition("#")
            destination = (
                source_path if not path_text else (source_path.parent / path_text).resolve()
            )
            if not destination.exists():
                failure(
                    f"broken link in {source_path.relative_to(REPOSITORY_ROOT)}: {target}"
                )
            if separator and anchor:
                if not destination.is_file():
                    failure(
                        f"anchor target is not a file in "
                        f"{source_path.relative_to(REPOSITORY_ROOT)}: {target}"
                    )
                available = anchors_by_path.setdefault(
                    destination,
                    github_heading_anchors(destination),
                )
                if anchor not in available:
                    failure(
                        f"missing anchor in {source_path.relative_to(REPOSITORY_ROOT)}: "
                        f"{target}"
                    )
            checked += 1
    return checked


def validate_line_lengths(paths: list[Path]) -> None:
    for path in paths:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if len(line) > MAX_AUTHORITY_LINE_LENGTH:
                failure(
                    f"{path.relative_to(REPOSITORY_ROOT)}:{number} has {len(line)} "
                    f"characters (maximum {MAX_AUTHORITY_LINE_LENGTH})"
                )


def validate_specification_sections(paths: list[Path]) -> None:
    seen: dict[str, Path] = {}
    top_level: list[str] = []
    expected_top_level = [*(str(number) for number in range(1, 23)), "Appendix A", "Appendix B"]
    for path in paths:
        for line in path.read_text(encoding="utf-8").splitlines():
            match = SECTION_ID.match(line)
            if not match:
                continue
            section_id = match.group(1)
            if section_id in seen:
                failure(
                    f"section {section_id} is owned by both "
                    f"{seen[section_id].relative_to(REPOSITORY_ROOT)} and "
                    f"{path.relative_to(REPOSITORY_ROOT)}"
                )
            seen[section_id] = path
            if section_id in expected_top_level:
                top_level.append(section_id)
    if top_level != expected_top_level:
        failure(
            "specification top-level order mismatch: "
            + ", ".join(top_level)
        )


def main() -> None:
    declared_sets: list[list[Path]] = []
    for manifest, chapter_directory in MANIFESTS:
        declared_sets.append(validate_manifest(manifest, chapter_directory))

    authority_paths = [manifest for manifest, _ in MANIFESTS]
    authority_paths.extend(path for declared in declared_sets for path in declared)
    validate_line_lengths(authority_paths)
    validate_specification_sections(declared_sets[0])

    link_sources = authority_paths + [
        REPOSITORY_ROOT / "README.md",
        REPOSITORY_ROOT / "README.zh-Hans.md",
    ]
    checked_links = validate_local_links(link_sources)
    chapter_count = sum(len(declared) for declared in declared_sets)
    largest_chapter = max(len(path.read_text(encoding="utf-8").split()) for path in authority_paths)
    print(
        "Documentation authority: "
        f"{len(MANIFESTS)} manifests, {chapter_count} chapters, "
        f"{checked_links} local links; largest chapter {largest_chapter} words."
    )


if __name__ == "__main__":
    main()

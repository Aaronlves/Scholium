#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SKILLS_ROOT = ROOT / ".agents" / "skills"
CATALOG_PATH = SKILLS_ROOT / "catalog.json"
IDENTIFIER = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
KINDS = {"auditor", "base", "interface", "language", "overlay", "specialist"}


def fail(message: str) -> None:
    print(f"catalog validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def frontmatter_name(skill_file: Path) -> str:
    lines = skill_file.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        fail(f"{skill_file} has no YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        fail(f"{skill_file} has unterminated YAML frontmatter")
    names = [line.split(":", 1)[1].strip() for line in lines[1:end] if line.startswith("name:")]
    if len(names) != 1:
        fail(f"{skill_file} must declare exactly one frontmatter name")
    return names[0].strip('"\'')


def main() -> None:
    try:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {CATALOG_PATH}: {error}")

    if catalog.get("schema_version") != 1:
        fail("schema_version must be 1")
    entries = catalog.get("capabilities")
    if not isinstance(entries, list) or not entries:
        fail("capabilities must be a non-empty array")

    capabilities: set[str] = set()
    mapped_skills: set[str] = set()
    required_fields = {"capability", "skill", "kind", "description"}
    optional_fields = {"modes"}

    for index, entry in enumerate(entries):
        if (
            not isinstance(entry, dict)
            or not required_fields.issubset(entry)
            or not set(entry).issubset(required_fields | optional_fields)
        ):
            fail(
                f"entry {index} must contain {sorted(required_fields)} and only optional {sorted(optional_fields)}"
            )
        capability = entry["capability"]
        skill = entry["skill"]
        kind = entry["kind"]
        description = entry["description"]
        if not isinstance(capability, str) or not IDENTIFIER.fullmatch(capability):
            fail(f"entry {index} has invalid capability identifier")
        if capability in capabilities:
            fail(f"duplicate capability {capability}")
        capabilities.add(capability)
        if not isinstance(skill, str) or not IDENTIFIER.fullmatch(skill):
            fail(f"entry {index} has invalid skill identifier")
        if skill in mapped_skills:
            fail(f"skill {skill} is mapped more than once")
        mapped_skills.add(skill)
        if kind not in KINDS:
            fail(f"entry {index} has invalid kind {kind!r}")
        if not isinstance(description, str) or not description.strip():
            fail(f"entry {index} has an empty description")
        modes = entry.get("modes", [])
        if not isinstance(modes, list) or not modes:
            if "modes" in entry:
                fail(f"entry {index} modes must be a non-empty array")
        elif any(not isinstance(mode, str) or not IDENTIFIER.fullmatch(mode) for mode in modes):
            fail(f"entry {index} has an invalid mode identifier")
        elif len(modes) != len(set(modes)):
            fail(f"entry {index} contains duplicate modes")

        skill_file = SKILLS_ROOT / skill / "SKILL.md"
        if not skill_file.is_file():
            fail(f"mapped skill {skill} has no SKILL.md")
        declared_name = frontmatter_name(skill_file)
        if declared_name != skill:
            fail(f"{skill_file} declares {declared_name!r}, expected {skill!r}")

    discovered_skills = {
        path.parent.name for path in SKILLS_ROOT.glob("*/SKILL.md") if path.is_file()
    }
    missing = sorted(discovered_skills - mapped_skills)
    stale = sorted(mapped_skills - discovered_skills)
    if missing or stale:
        fail(f"catalog mismatch; missing={missing}, stale={stale}")

    print(f"Validated {len(entries)} Scholium developer-skill capability mappings.")


if __name__ == "__main__":
    main()

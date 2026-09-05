#!/usr/bin/env python3
"""Validate the complete local Scholium developer-skill package surface."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml


SKILLS_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = SKILLS_ROOT / "catalog.json"
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---(?:\n|\Z)", re.DOTALL)
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FORBIDDEN_AUXILIARY = {"README.md", "CHANGELOG.md", "INSTALLATION_GUIDE.md", "QUICK_REFERENCE.md"}


def fail(message: str) -> None:
    print(f"toolkit validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read JSON {path.relative_to(SKILLS_ROOT)}: {error}")


def load_yaml(path: Path) -> object:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        fail(f"cannot read YAML {path.relative_to(SKILLS_ROOT)}: {error}")


def validate_entry(skill_dir: Path) -> tuple[str, int, int]:
    skill_path = skill_dir / "SKILL.md"
    source = skill_path.read_text(encoding="utf-8")
    match = FRONTMATTER.match(source)
    if match is None:
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} has invalid frontmatter")
    try:
        frontmatter = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} has invalid frontmatter: {error}")
    if not isinstance(frontmatter, dict):
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} frontmatter is not a mapping")
    if set(frontmatter) != {"name", "description"}:
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} must declare only name and description")
    name = frontmatter.get("name")
    description = frontmatter.get("description")
    if name != skill_dir.name or not isinstance(description, str) or not description.strip():
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} name or description is invalid")
    if "researcher-codex-development-contract.md" not in source:
        fail(f"{skill_path.relative_to(SKILLS_ROOT)} does not route the shared development contract")

    metadata_path = skill_dir / "agents" / "openai.yaml"
    metadata = load_yaml(metadata_path)
    if not isinstance(metadata, dict) or not isinstance(metadata.get("interface"), dict):
        fail(f"{metadata_path.relative_to(SKILLS_ROOT)} has no interface mapping")
    interface = metadata["interface"]
    for key in ("display_name", "short_description", "default_prompt"):
        if not isinstance(interface.get(key), str) or not interface[key].strip():
            fail(f"{metadata_path.relative_to(SKILLS_ROOT)} has invalid {key}")
    short_description = interface["short_description"]
    if not 25 <= len(short_description) <= 64:
        fail(f"{metadata_path.relative_to(SKILLS_ROOT)} short_description must be 25-64 characters")
    if f"${name}" not in interface["default_prompt"]:
        fail(f"{metadata_path.relative_to(SKILLS_ROOT)} default_prompt must mention ${name}")

    eval_path = skill_dir / "evals" / "evals.json"
    if not eval_path.exists():
        fail(f"{skill_dir.name} has no evals/evals.json")
    evaluation = load_json(eval_path)
    if not isinstance(evaluation, dict) or evaluation.get("skill_name") != name:
        fail(f"{eval_path.relative_to(SKILLS_ROOT)} skill_name does not match {name}")
    cases = evaluation.get("evals")
    if not isinstance(cases, list) or len(cases) < 2:
        fail(f"{eval_path.relative_to(SKILLS_ROOT)} must contain at least two evaluations")
    identifiers: set[int] = set()
    for case in cases:
        if not isinstance(case, dict) or not isinstance(case.get("id"), int):
            fail(f"{eval_path.relative_to(SKILLS_ROOT)} contains an invalid case")
        if case["id"] in identifiers:
            fail(f"{eval_path.relative_to(SKILLS_ROOT)} contains duplicate id {case['id']}")
        identifiers.add(case["id"])
        if not all(isinstance(case.get(key), str) and case[key].strip() for key in ("prompt", "expected_output")):
            fail(f"{eval_path.relative_to(SKILLS_ROOT)} case {case['id']} lacks prompt or output")
        if not isinstance(case.get("files"), list):
            fail(f"{eval_path.relative_to(SKILLS_ROOT)} case {case['id']} has invalid files")
        assertions = case.get("assertions")
        if not isinstance(assertions, list) or not assertions or not all(isinstance(item, str) and item.strip() for item in assertions):
            fail(f"{eval_path.relative_to(SKILLS_ROOT)} case {case['id']} has invalid assertions")
    eval_count = len(cases)

    link_count = validate_links(skill_dir)
    return name, eval_count, link_count


def validate_links(skill_dir: Path) -> int:
    checked = 0
    for source_path in sorted(skill_dir.rglob("*.md")):
        source = source_path.read_text(encoding="utf-8")
        for raw_target in MARKDOWN_LINK.findall(source):
            target = raw_target.strip().strip("<>")
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            checked += 1
            resolved = (source_path.parent / target).resolve()
            try:
                resolved.relative_to(SKILLS_ROOT)
            except ValueError:
                fail(f"{source_path.relative_to(SKILLS_ROOT)} link escapes the skill tree: {target}")
            if not resolved.exists():
                fail(f"{source_path.relative_to(SKILLS_ROOT)} has broken link: {target}")
    return checked


def validate_python() -> int:
    checked = 0
    for path in sorted(SKILLS_ROOT.rglob("*.py")):
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except (OSError, SyntaxError) as error:
            fail(f"cannot compile {path.relative_to(SKILLS_ROOT)}: {error}")
        checked += 1
    return checked


def main() -> None:
    catalog = load_json(CATALOG_PATH)
    if not isinstance(catalog, dict) or not isinstance(catalog.get("capabilities"), list):
        fail("catalog.json has no capabilities array")
    catalog_skills = [entry.get("skill") for entry in catalog["capabilities"] if isinstance(entry, dict)]
    if len(catalog_skills) != len(set(catalog_skills)):
        fail("catalog.json contains duplicate skill mappings")

    skill_dirs = sorted(path.parent for path in SKILLS_ROOT.glob("*/SKILL.md"))
    discovered = [path.name for path in skill_dirs]
    if sorted(catalog_skills) != discovered:
        fail(f"catalog mismatch: catalog={sorted(catalog_skills)}, discovered={discovered}")

    auxiliary = sorted(
        path.relative_to(SKILLS_ROOT)
        for path in SKILLS_ROOT.rglob("*")
        if path.is_file() and path.name in FORBIDDEN_AUXILIARY
    )
    if auxiliary:
        fail(f"unnecessary auxiliary files: {auxiliary}")

    evals = 0
    links = 0
    for skill_dir in skill_dirs:
        _, package_evals, package_links = validate_entry(skill_dir)
        evals += package_evals
        links += package_links
    python_files = validate_python()
    print(
        f"Validated {len(skill_dirs)} skills, {len(catalog_skills)} catalog mappings, "
        f"{evals} evaluations, {links} local links, and {python_files} Python files."
    )


if __name__ == "__main__":
    main()

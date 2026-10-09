#!/usr/bin/env python3
"""Prepare raw skill-evaluation inputs; check the bounded title-edit artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
import yaml

from validate_toolkit import SKILLS_ROOT, fixture_paths


ROOT = SKILLS_ROOT.parents[1]
BUILD = ROOT / ".build"
TITLE_SKILL = "scholium-markdown-yaml-fidelity"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_path(value: str) -> Path:
    path = Path(value).resolve()
    if path == BUILD.resolve() or not path.is_relative_to(BUILD.resolve()):
        raise ValueError("evaluation working directory must be below repository .build")
    return path


def prepare(args: argparse.Namespace) -> None:
    skill_dir = SKILLS_ROOT / args.skill
    if skill_dir.parent != SKILLS_ROOT or not (skill_dir / "SKILL.md").is_file():
        raise ValueError("select an existing canonical skill")
    data = json.loads((skill_dir / "evals/evals.json").read_text())
    case = next(item for item in data["evals"] if item["id"] == args.case)
    files = fixture_paths(skill_dir, case)
    if not files or len({path.name for path in files}) != len(files):
        raise ValueError("select an artifact case with distinct input filenames")
    instructions_root = Path(args.instructions_root).resolve()
    entry = instructions_root / args.skill / "SKILL.md"
    if not entry.is_file():
        raise ValueError("selected instruction snapshot has no matching SKILL.md")
    run = run_path(args.run_dir)
    run.mkdir(parents=True, exist_ok=False)
    inputs = run / "input"
    inputs.mkdir()
    for path in files:
        shutil.copyfile(path, inputs / path.name)
    prompt = (
        f"Use the skill at {entry}. Read only that entry and references relevant to this task "
        "from the selected instruction tree. Do not inspect evaluation definitions, helper "
        "implementations, expected answers or other evaluation runs.\n\n"
        f"Working directory: {run}\nRaw input files: "
        + ", ".join(str(inputs / path.name) for path in files)
        + f"\n\n{case['prompt']}\n"
    )
    (run / "performer.md").write_text(prompt)
    (run / "manifest.json").write_text(json.dumps({
        "skill": args.skill, "case": args.case, "instructions_root": str(instructions_root),
        "entry_sha256": digest(entry),
        "case_sha256": hashlib.sha256(json.dumps(case, sort_keys=True).encode()).hexdigest(),
        "inputs": {path.name: digest(path) for path in files},
    }, indent=2) + "\n")
    print(f"Prepared raw inputs and performer prompt: {run / 'performer.md'}")


def check_title(args: argparse.Namespace) -> None:
    run = run_path(args.run_dir)
    (run / "verification.json").unlink(missing_ok=True)
    manifest = json.loads((run / "manifest.json").read_text())
    if (manifest["skill"], manifest["case"]) != (TITLE_SKILL, 0):
        raise ValueError("the byte oracle applies only to the title-edit case")
    source_path = SKILLS_ROOT / TITLE_SKILL / "evals/fixtures/title-edit/source.md"
    source = source_path.read_bytes()
    candidate = (run / "result.md").read_bytes()
    source_hash = manifest["inputs"]["source.md"]
    if digest(source_path) != source_hash or digest(run / "input/source.md") != source_hash:
        raise ValueError("fixture or performer input changed since preparation")
    marker = b"title: 'Old title' # retain this note\r\n"
    if source.count(marker) != 1:
        raise ValueError("title fixture does not have a unique top-level scalar locator")
    start = source.index(marker) + len(b"title: ")
    end = start + len(b"'Old title'")
    prefix, suffix = source[:start], source[end:]
    if len(candidate) < len(prefix) + len(suffix) or not (
        candidate.startswith(prefix) and candidate.endswith(suffix)
    ):
        raise ValueError("bytes outside the authorized title scalar changed")
    scalar = candidate[len(prefix):len(candidate) - len(suffix)]
    if yaml.safe_load(scalar.decode("utf-8")) != "Researcher's revised title":
        raise ValueError("replacement is not the intended title scalar")

    def mapping(raw: bytes) -> dict:
        text = raw.decode("utf-8-sig")
        value = yaml.safe_load(text.split("---\r\n", 2)[1])
        if not isinstance(value, dict):
            raise ValueError("frontmatter is not a complete mapping")
        return value

    expected = mapping(source)
    expected["title"] = "Researcher's revised title"
    if mapping(candidate) != expected:
        raise ValueError("complete candidate mapping does not have the intended semantics")
    (run / "verification.json").write_text(json.dumps({
        "result": "pass", "claim": "bounded title artifact only",
        "unchanged_bytes": True, "complete_mapping_semantics": True,
        "source_sha256": source_hash, "candidate_sha256": digest(run / "result.md"),
    }, indent=2) + "\n")
    print("PASS: exact unchanged bytes and intended complete YAML mapping; application behavior untested.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare_parser = sub.add_parser("prepare")
    prepare_parser.add_argument("skill")
    prepare_parser.add_argument("case", type=int)
    prepare_parser.add_argument("run_dir")
    prepare_parser.add_argument("--instructions-root", default=str(SKILLS_ROOT))
    prepare_parser.set_defaults(action=prepare)
    check_parser = sub.add_parser("check-title")
    check_parser.add_argument("run_dir")
    check_parser.set_defaults(action=check_title)
    args = parser.parse_args()
    try:
        args.action(args)
    except (OSError, ValueError, KeyError, IndexError, StopIteration, yaml.YAMLError) as error:
        parser.exit(1, f"fixture evaluation failed: {error}\n")


if __name__ == "__main__":
    main()

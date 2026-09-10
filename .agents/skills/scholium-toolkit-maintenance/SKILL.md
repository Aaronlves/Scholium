---
name: scholium-toolkit-maintenance
description: "Audit, maintain, or evaluate Scholium's canonical developer-skill toolkit. Use for `.agents/skills`, the catalog, metadata, routing, references, validation, overlap, staleness, or duplicate discovery; exclude product code and shipped skills."
---

# Scholium Toolkit Maintenance

Maintain only the canonical `.agents/skills/` tree and capability catalog.
Keep release-shipped skills, personal plugins, and installed caches outside
this task; never create or publish a developer-toolkit mirror.

Apply the shared [development contract](references/researcher-codex-development-contract.md)
and [authoring contract](references/developer-skill-authoring-contract.md).

## Modes

- **Audit:** inspect and report without editing.
- **Maintain:** make the requested correction, simplification, merge, rename,
  or deletion.
- **Evaluate:** exercise routing and boundaries without changing product behavior.

## Method

1. Inspect the affected packages, catalog entries, references, metadata,
   scripts, evaluations, callers, and routing neighbors. Inventory the whole
   toolkit only for whole-toolkit work or an otherwise unresolved collision.
2. Compare trigger, responsibility, permission, side effects, output, and proof.
   Remove duplicate or stale instructions; merge only materially coinciding
   responsibilities. Preserve consequential invariants and retained source lineage.
3. Change canonical source and update catalog mappings or modes when affected.
   Check for broken links and duplicate discovery; do not modify app code or
   product authority incidentally.
4. Run `scripts/validate_toolkit.py`, the package validator for each changed
   skill, and `Tools/Scripts/validate-scholium-toolkit-catalog.py` from the repository.

For changed routing or permission behavior, read the
[evaluation guide](references/evaluation-cases.md) and forward-test representative
positive and neighboring cases with fresh agents and raw prompts. Keep expected
answers out of performer context. Structural validity is not behavioral proof.

Report meaningful removals, preserved boundaries, actual validation, and
untested behavior. Existing tasks may retain startup discovery metadata; a new
task is needed to verify fresh discovery, not to finish this maintenance work.

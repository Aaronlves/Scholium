---
name: scholium-markdown-yaml-fidelity
description: "Implement, diagnose, or test Scholium's lossless Markdown/YAML pipeline. Use for exact parsing, targeted edits, schema projection, validation, source versions, BOM, Unicode, newlines, or save behavior that could alter authored bytes."
---

# Scholium Markdown and YAML Fidelity

Keep exact Markdown bytes authoritative. Parsed YAML, rendered Markdown, and
typed projections are views of source, never replacement authorities.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Method

1. Reopen the current specification, architecture, construction, writer,
   parser, projection, call sites, and focused tests.
2. Separate vault role, schema profile, and exact source. Resolve current
   fields, validation, and rejection rules from live authority rather than this
   skill.
3. Classify the operation from its submitted payload: read, body edit,
   property edit, full-source edit, or no-op.
4. Patch only the uniquely owned range, validate the complete proposed result,
   and pass it through the sole transactional writer.
5. Prove both intended semantic change and byte preservation outside the
   changed range.

For nontrivial parsing or mutation work, load the
[fidelity fixture matrix](references/fidelity-fixture-matrix.md). For a new
backend or library decision, first apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md).

## Invariants

- Preserve byte order marks, newline form, comments, ordering, quoting,
  multiline structure, unknown data, and final-newline state outside the edit.
- Recognize frontmatter only at the valid document boundary. Fail closed on an
  ambiguous target or invalid proposed mapping; do not silently repair nearby
  source.
- A property edit changes only the submitted property. A full-source payload
  remains a full-source operation even when its apparent difference is small.
- Display formatting never authorizes source normalization or value respelling.
- No-op writes must not synthesize source or metadata changes.
- Schema projection does not define workflow, permission, or philosophical
  meaning.

## Evidence

Use disposable fixtures and two independent oracles: exact unchanged bytes and
valid intended semantics. Exercise the affected read and mutation classes,
including malformed and unsupported inputs. Run focused owning tests and report
any unsupported construct or deliberate normalization explicitly.

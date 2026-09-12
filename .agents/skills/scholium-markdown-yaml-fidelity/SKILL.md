---
name: scholium-markdown-yaml-fidelity
description: "Implement, diagnose, or test exact Markdown/YAML parsing, projection, and targeted source edits in Scholium."
---

# Scholium Markdown and YAML Fidelity

Keep exact Markdown bytes authoritative. Parsed YAML, rendered Markdown, and
typed projections are views of source, never replacement authorities.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Locate the representation that loses fidelity

Classify the submitted operation as no-op, body-range, property-range, or
full-source replacement. The visible size of a diff does not change the
operation's authority. Locate the first conversion between exact bytes,
lexical ranges, parsed values, schema projection, and candidate bytes.

Use two independent checks: exact bytes outside authorized ranges, and the
intended semantics after reparsing the complete candidate. Parsed equality
cannot prove source preservation; byte equality alone cannot prove that a
property acquired the intended type. Canonically equivalent Unicode strings
may still have different bytes.

For a range error, name the coordinate system at each boundary: UTF-8 bytes,
UTF-16 code units, graphemes, normalized editor positions, or source positions.
Derive ranges against the same immutable source revision. Repeated text requires
an exact locator and expected bytes; a first-substring search is not identity.
For a batch, preserve the contract's original-versus-sequential range semantics
and reject ambiguity before applying any effect.

Use the [fidelity fixtures](references/fidelity-fixture-matrix.md) to select the
smallest input exposing the conversion, plus a neighboring valid case. Patch
only a provably owned lexical range, reparse, and use the existing transactional
writer. If the representation cannot preserve untouched syntax, reject that
mutation rather than serialize the parsed document. Consult architecture for
ownership changes and [backend research](../scholium-engineering/references/backend-decision-research.md)
only for a new parser or library decision.

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

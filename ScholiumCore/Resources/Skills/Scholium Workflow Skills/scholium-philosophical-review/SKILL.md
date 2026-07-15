---
name: scholium-philosophical-review
description: Conduct independent, genre-sensitive philosophical review in Scholium of papers, chapters, proposals, notes, source-analysis reports, and other philosophical writing. Evaluate significance, background, concepts, arguments, interpretation, source fidelity, dialectic, contribution, and exposition against an exact version. Use for full-panel, rapid, single-lens, referee-simulation, or regression review. Do not use for source-level Debate Importance rating, received-feedback processing, specialist citation formatting, prose rewriting, or publication-workflow authorization.
---

# Scholium Philosophical Review

Apply `scholium-core-protocol`. Review the work, not the author. Treat the recommendation as an evaluation of the exact version, not as truth, approval, or submission status.

Use this package for broad philosophical evaluation. If the task is only to check source fidelity, conceptual accuracy, reconstruction, or evidential role in already produced content, use `scholium-content-audit` instead.

## Select a submode

Read [references/submodes.md](references/submodes.md) and select one:

- `full-panel`;
- `rapid-panel`;
- `single-lens`;
- `referee-simulation`;
- `regression-review`.

Add heuristic scoring only when the researcher requests it.

## Establish the review packet

```text
Mode: review
Submode:
Exact target and version:
Genre, method, audience, and stage:
Review question:
Material and sources available:
Read set:
Write set:
Permission: read-only unless separately authorized
Output:
Stop condition:
Durability:
```

Do not issue a whole-work recommendation if the complete relevant work or a stable version is unavailable.

## Load the method

Read [references/method.md](references/method.md) completely.

Read [references/report-template.md](references/report-template.md) only for a structured full review or referee simulation. Do not force it onto a rapid or single-lens review.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. The compatible Practice is `reviewer`. Record any methodological difference between that optional overlay and the official review method.

## Execute

1. Calibrate standards to the work's genre, task, audience, and stage.
2. Build the strongest charitable philosophical map before criticizing.
3. Apply the selected independent lenses without letting one diagnosis seed all others.
4. Verify only source-dependent claims that materially affect a finding.
5. Adjudicate findings by reasons and evidence, not reviewer frequency or scores.
6. Bind every major finding to a determinate target and locator.
7. Separate defects, plausible concerns, optional improvements, and missing verification.
8. Return an ordered revision burden without silently rewriting the work.

## Return

```text
Review scope and exact version:
Genre, task, and assumed standards:
Strongest charitable reconstruction:
Strongest contribution:
Version-bound recommendation:
Decisive reasons:
Prioritized findings:
Lens disagreements:
Ordered revision burden:
Sources checked and missing:
Residual risks:
Researcher decisions needed:
```

A review finding is not automatically accepted feedback or an authorized revision. Route received human comments to `scholium-feedback-processing`; route accepted revisions to a new development or writing packet.

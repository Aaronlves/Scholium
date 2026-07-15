---
name: scholium-source-analysis
description: Analyze philosophical and philosophically relevant sources in Scholium through distinct Orientation, Analytical, and Review passes, treating them as arguments, conceptual interventions, interpretations, dialectical moves, cases, formal results, normative reasoning, empirical contributions, or topic maps. Use for papers, books, chapters, primary texts, commentaries, handbooks, surveys, and interdisciplinary sources when their philosophical role matters. Keep source claims, reconstruction, evaluation, and project-use candidates distinct; do not use for bibliography-formatting tasks, independent peer review, or note integration.
---

# Scholium Source Analysis

Apply `scholium-core-protocol`. This package contains the complete official Scholium source-analysis method and does not require an external personal method.

## Select a submode

Read [references/submodes.md](references/submodes.md) and choose exactly one:

- `analysis-only`;
- `analysis-plus-handoff-candidates`;
- `analysis-plus-authorized-updates`;
- `topic-map`;
- `hybrid`.

If no project context exists, use `analysis-only`. If project context exists but no exact write permission is present, use `analysis-plus-handoff-candidates`.

`analysis-plus-authorized-updates` is a request-level composite, not permission for the analysis phase to edit notes. Read the Core Mixed-mode reference and sequence a read-only Source Analysis phase, a fresh `source-to-note` Research Integration phase for only the exact authorized targets, and one Content Audit of each final changed fingerprint.

## Establish the source packet

```text
Mode: analyze | analyze phase of Mixed
Submode:
Source object:
Session analysis unit:
Existing source-level Analysis: none | exact target
Declared Research Unit before task: absent | exact scope and limitations
Proposed Research Unit after task: unchanged | exact scope and limitations
Research question:
Requested depth:
Available material and access status:
Pass state: not-started | orientation-complete | analytical-complete | review-complete
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
```

## Load the method

Read [references/method.md](references/method.md) completely.

Load conditional references only when triggered:

- read [references/bibliography-and-handoff.md](references/bibliography-and-handoff.md) when screening cited literature or producing project-use candidates;
- read [references/source-clusters.md](references/source-clusters.md) for an edited volume, multi-author collection, chapter sequence, or bounded multi-source cluster.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. Compatible Practices are `historical-interpreter`, `conceptual-analyst`, and `argument-reconstructionist`.

## Select the durable report contract

Do not force a report template when the requested output is ephemeral. When a durable Analysis report is required:

- Read [references/report-templates.md](references/report-templates.md) for Scholium's project-neutral thorough, concise, and provisional report structures.
- Reuse the existing source-level Analysis by default, including for a long book. Do not create one Analysis per chapter merely because the current session unit is a chapter.
- Declare or revise the minimal Research Unit through `scholium-research-integration`; never treat the current session unit as whole-source coverage unless the resulting file actually supports that claim.
- Treat an existing target's declared schema and preserved custom fields as authoritative for that target. Do not invent project-specific fields, migrate a corpus, or reinterpret custom metadata without a separate researcher instruction.

The template controls report structure, not evidential status. Every populated field still requires support from the checked source, verified metadata, or an explicitly labeled agent reconstruction.

## Execute

Verify source identity, version, access, locator reliability, the exact session analysis unit, and any existing durable Research Unit. Then complete the three passes in order. Do not merge, skip, or retrospectively relabel one traversal as several passes.

1. **Orientation pass** — traverse the complete session analysis unit once to map its question, thesis or purpose, structure, genre, method, the author's debate framing, turning points, and candidate load-bearing passages. Keep the map provisional.
2. **Analytical pass** — traverse the complete session analysis unit a second time to reconstruct its concepts, arguments or interpretive moves, objections, replies, concessions, scope, support, and unresolved alternatives. Draft the analysis with explicit evidential layers and reliable locators.
3. **Review pass** — traverse the complete session analysis unit a third time while checking the analytical draft against the source. Search for omissions, counterevidence, qualifications, terminology drift, mistaken dialectical roles, weak reconstructions, and locator or quotation errors; revise the draft and mark unresolved uncertainty.

Only after the Review pass may the agent finalize the analysis, apply the selected durable report contract, update a cumulative source-level Analysis, or issue a handoff. Expand the durable Research Unit only to source material actually represented after review, and retain material limitations. The Review pass is internal source-analysis verification; it does not replace independent philosophical review or the exact-version `scholium-content-audit` required after a durable substantive change.

## Return

Lead with access status, analytical scope, source function, central question or thesis, principal contribution, and strongest unresolved problem. For durable reports, include enough locators and layer labels for independent checking.

If the researcher asks to persist the analysis or use it to change another note, hand the result and exact Research Unit change to `scholium-research-integration` with a fresh write and permission check. Mark any substantively changed fingerprint `audit-needed`; do not describe it as audited until `scholium-content-audit` checks that exact version.

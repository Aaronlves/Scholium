---
name: scholium-derived-index-integrity
description: "Implement, diagnose, or test Scholium retrieval, links, and derived-index correctness, including tokenizer or backend evaluation."
---

# Scholium Derived Index Integrity

Keep every index disposable, deterministic, vault-scoped, access-checked, and
traceable to exact source revisions. Retrieval is a lead, not evidence or write
authority.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
For a tokenizer, engine, dependency, or backend-lifecycle decision, load
[engine evaluation](references/engine-evaluation.md). Ordinary active-index
corrections use the method below without an engine comparison or shadow runtime.

## Separate retrieval stages

For a missing or incorrect hit, trace eligibility, source projection,
tokenization, query interpretation, matching, ranking, limiting, and presentation
in that order until the first divergence. A missing hit is not necessarily a
ranking defect, and a correct result set does not establish correct locators.

Compare the affected query over identical authorized bytes through the active
index and a clean rebuild. If only incremental state differs, inspect generation
and invalidation; if both are wrong, inspect shared semantics. Keep an independent
small expected result, since rebuild and incremental paths can share a bug.

For links, distinguish syntax recognition, target identity, locator, and derived
relationship. Duplicate basenames need an ambiguity result, not a tie-break that
silently chooses a target. For federation, inspect access before merging and
limits before and after merge; retain each hit's provenance.

Select relevant cases from the [fixture matrix](references/search-link-fixture-matrix.md).
Correct the first responsible stage and verify ordered identities, eligibility,
locators, and affected mutation/rebuild equivalence. Use
[backend research](../scholium-engineering/references/backend-decision-research.md)
only when the correction requires a new mechanism or dependency.

## Invariants

- Publish only complete, identified generations; reject stale or cancelled
  publication and rebuild incompatible or corrupt state deterministically.
- Apply one versioned search contract to tokenization, normalization, query,
  ranking, filtering, ties, snippets, and source locations. Resolve its current
  values live rather than copying them here.
- Authorize scope before query or federation. Local index presence grants no
  access, and adapters must preserve identity, provenance, revision, and limits.
- Persist saved-search definitions, not result bytes; re-evaluate them against
  current access and generations without broadening scope.
- Derive links, relationships, diagnostics, and source spans through one exact
  semantic projection. Return ambiguity deterministically rather than guessing.
- Neutral or transitive connectivity never becomes philosophical support.
- Derived tokens, snippets, and caches never reconstruct writable Markdown or
  expose research content through logs.

## Evidence

Use generated multilingual and adversarial fixtures appropriate to the changed
semantics. Test mutation/rebuild equivalence, authorization, cancellation,
corruption recovery, saved-query round trips, and interface parity where
applicable. Establish semantic correctness before measuring speed. Run focused
owner checks. Report the exact scope, generation, eligibility context,
exercised mutations, and remaining frontend differences.

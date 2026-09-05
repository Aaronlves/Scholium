---
name: scholium-derived-index-integrity
description: "Implement, diagnose, or test Scholium's derived search, link, relationship, diagnostic, and index state. Use for lexical or federated retrieval, saved queries, ranking, scopes, CJK or Unicode, semantic projections, link resolution, incremental generations, recovery, or GUI and CLI parity."
---

# Scholium Derived Index Integrity

Keep every index disposable, deterministic, vault-scoped, access-checked, and
traceable to exact source revisions. Retrieval is a lead, not evidence or write
authority.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Use this skill for correctness of the active derived backend. Use the Swift
index-engine specialist only when comparing or changing tokenizer, storage
engine, dependency, or backend lifecycle.

## Method

1. Reopen the current query/result contract, construction, authorization and
   federation boundary, semantic projection, persistence, adapters, and tests.
2. Identify authoritative inputs, versioned semantics, generation identity,
   eligibility rules, publication point, and recovery path.
3. Load the [search and link fixture matrix](references/search-link-fixture-matrix.md)
   for the affected retrieval, saved-query, graph, or mutation behavior.
4. Change one owning boundary. Do not create a second tokenizer, ranker,
   resolver, eligibility rule, or generated-state authority in an adapter.
5. Compare incremental/event-driven results with a clean rebuild over the same
   authorized bytes.

For a new mechanism or dependency, apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md).

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

---
name: scholium-swift-index-engine
description: "Decide, prototype, benchmark, implement, or review Scholium's Swift-owned lexical index engine and tokenizer boundary. Use for Apple Natural Language, SQLite FTS5 tokenizer strategy, CJK or mixed-script segmentation, Swift-callable native tokenizers, backend cutover, or measured search scale; exclude bounded current-index bugs, authoritative writes, and unmeasured rewrites."
---

# Scholium Swift Index Engine

Evolve the lexical engine through a deterministic Swift-owned boundary over
disposable derived state. Exact documents, access decisions, conflicts, and
writes remain outside it.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Use derived-index integrity for ordinary bugs in the active backend. Use this
specialist only to compare or change tokenizer, engine, dependency, native
boundary, or backend lifecycle.

## Modes

- **`decision`:** compare mechanisms against one named correctness, scale,
  portability, or recovery need without changing production behavior.
- **`fixture-prototype`:** build the smallest isolated candidate over generated
  fixtures and compare it with the live baseline.
- **`integrated-shadow`:** run the candidate behind the single index boundary
  and compare authorized results, recovery, packaging, and measured cost while
  the baseline remains the production result.
- **`cutover`:** add repository engineering in Architecture Cutover mode, then
  replace the production backend only after contract, equivalence, recovery,
  packaging, and portability evidence is complete; delete the superseded route
  in the same bounded change.

## Method

1. Reopen the live search contract, construction, adapters, persistence,
   packaging, tests, and benchmark authority.
2. Name one observable correctness, scale, portability, or recovery problem.
   Do not replace an engine because another technology has a longer feature list.
3. Research the established mechanisms that can solve that problem. Load
   [search and tokenization guidance](references/swift-search-and-tokenization.md)
   and the shared
   [backend decision research](../scholium-engineering/references/backend-decision-research.md).
4. Progress only through evidence actually earned: `decision`,
   `fixture-prototype`, `integrated-shadow`, then `cutover`. Use the
   [evaluation template](templates/tokenizer-evaluation.md) when a durable
   decision record is requested.
5. Integrate behind the single versioned index boundary and retire a replaced
   production path rather than retaining dual authorities.

Before prototype or integration, load the
[index boundary contract](references/scholium-index-contract.md).

## Invariants

- The engine receives immutable, already-authorized values and cannot reopen a
  vault or decide eligibility.
- Document and query processing share one versioned policy. Raw identifiers,
  researcher terminology, source ranges, and original fields remain distinct
  from normalized terms.
- Derived tokens never reconstruct writable source.
- Publish only complete generations; reject stale or cancelled work and rebuild
  incompatible state from authoritative snapshots.
- Keep one writer and one explicit federation policy. Do not compare scores
  across corpora as though they automatically share a ranking population.
- A candidate engine must prove lexical-semantic parity or an authorized
  improvement, deterministic rebuild, failure isolation, packaging, and
  portability against the live baseline.

## Evidence

Use generated multilingual fixtures that expose the named semantic boundary,
then compare clean and incremental behavior, cancellation, recovery, access,
and measured cost where relevant. Report the stage reached, baseline and
candidate semantics, packaging evidence, tests run, decision, and uncertainty.
Never present prototype evidence as integrated or release-ready behavior.

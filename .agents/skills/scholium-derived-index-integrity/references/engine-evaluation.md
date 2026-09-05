# Tokenizer and index-engine evaluation

Load this only for a tokenizer, engine, dependency, native-boundary, or backend
lifecycle decision. A bounded bug in the active implementation uses the main
skill's correctness method without an engine-selection exercise.

Reopen the live retrieval contract, current owner, dependencies, packaging,
tests, and any relevant benchmark authority. Name the correctness, scale,
portability, or recovery gap; feature count alone is not a reason to replace it.
Use [tokenization guidance](swift-search-and-tokenization.md) and
[backend decision research](../../scholium-engineering/references/backend-decision-research.md)
when a mechanism choice remains. Before prototype or integration, read the
[index boundary checklist](scholium-index-contract.md).

## Choose the evidence needed

- A decision-only request compares mechanisms without production edits.
- A fixture prototype compares the candidate and baseline on the same generated,
  authorized inputs. It does not grant the candidate production authority.
- Integrated shadowing is optional: use it when explicitly requested or when
  runtime interleavings, workload, or integration risk cannot be resolved by
  isolated evidence. Name that need first; do not build a dual runtime just to
  satisfy a stage list. The baseline remains the production result while shadowing.
- For an authorized production cutover, verify required semantics, clean and
  incremental rebuild, cancellation, recovery, access boundaries, packaging,
  and applicable portability. Reuse evidence already earned; shadow execution
  is not a mandatory prerequisite. Add cross-layer engineering only when actual
  ownership or integration scope requires it, then remove the replaced route.

The engine consumes immutable, already-authorized inputs. It cannot reopen a
vault, decide eligibility, or write research documents. Document and query
processing share a versioned policy; raw identifiers and source positions remain
separate from normalized tokens. Preserve one writer, complete generations, and
explicit federation semantics across replacement.

Report semantic differences before performance, plus the decision, evidence
obtained, and unresolved limits. Use the [evaluation template](../templates/tokenizer-evaluation.md)
only when a durable comparison is requested, omitting irrelevant fields. Prototype
or shadow results do not establish release acceptance.

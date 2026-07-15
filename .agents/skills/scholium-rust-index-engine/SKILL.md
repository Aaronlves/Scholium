---
name: scholium-rust-index-engine
description: Decide, prototype, implement, benchmark, or review a Rust-backed derived index engine for Scholium. Use for persistent full-text search, Tantivy or SQLite FTS5 evaluation, tokenizer and CJK behavior, incremental indexing, generation commits, Swift–Rust query protocols, federated cross-vault search over vault-scoped lexical indexes, corruption recovery, search parity, or determining whether measured scale justifies Rust. Do not use for authoritative vault writes, unmeasured rewrites, semantic claims about philosophical evidence, or ordinary Swift search fixes that already meet acceptance targets.
---

# Scholium Rust Index Engine

Build a disposable, deterministic derived engine. Swift remains the authority for vault access, exact documents, privacy policy, conflicts, proposals, and every authoritative research-file or vault write. Rust may write only its disposable derived-generation tree outside every vault.

The live baseline is already a Swift-owned, per-vault `SQLiteSearchIndex` using SQLite FTS5, incremental generation commits, and `FederatedSearchEngine` across eligible registered vaults. The GUI and CLI consume this shared contract. Treat Rust as an adoption-gated alternative to that measured baseline, not as the missing persistence layer and not as the default next implementation.

Pair this skill with `rust-language`, `scholium-development`, `scholium-derived-index-integrity`, and `scholium-performance-audit`. Add `scholium-trust-boundary-audit` when persisted content, privacy, FFI, or path handling changes.

Run this skill only after `scholium-development` has bound one unique workspace/package checkout pair. Resolve all repository paths from that package root; never infer the checkout from an installed skill cache.

## Pass the adoption gate

Do not add Rust to Scholium's product or package integration until one condition is verified. A disposable fixture-only prototype may gather evidence for this gate, but does not itself authorize integration:

- an active canonical performance gate misses a declared search/index target for a measured engine reason; the 800-note protocol counts only when `scholium-performance-audit` marks that gate active;
- expected scale, mutation rate, tokenizer need, portability requirement, or recovery behavior materially exceeds the measured active Swift SQLite FTS5 design;
- a Windows/Linux agent CLI or shared portable engine is an approved product requirement;
- advanced tokenization or query functionality has a justified, tested Rust implementation advantage.

If Swift meets the target, improve `SQLiteSearchIndex`, its app adapter, or `FederatedSearchEngine` instead. Persisted lexical search, incremental mutation, and vault-scoped federation already exist and therefore do not justify a second toolchain. A Rust prototype must identify a measured unmet requirement that cannot be addressed safely and proportionally in the active Swift/SQLite design.

Read [references/backend-and-tokenization.md](references/backend-and-tokenization.md) before selecting an engine. Read [references/scholium-index-contract.md](references/scholium-index-contract.md) before writing a prototype or boundary.

## Implement the active search contract

Load the active versioned user-visible search contract owned by `scholium-derived-index-integrity` and record its exact version. Do not independently revise search semantics in this backend skill. Confirm that the active contract covers:

- indexed roles and privacy exclusions;
- title, aliases, tags, authors, filterable metadata, headings, and body fields;
- normalization, case/diacritic policy, punctuation, identifiers, prefixes, phrases, AND/OR behavior, and query escaping;
- CJK and mixed-script tokenization;
- field weights, stable tie-breaking, filters, limits, and snippets;
- the exact GUI/CLI parity requirement.

A result is a retrieval lead, not evidence. Never infer support, criticism, source role, or philosophical agreement from ranking or connectivity.

## Keep the boundary narrow

Swift supplies an immutable `IndexBuildRequest` for one complete vault snapshot after applying the live Swift-owned privacy policy. It contains only authorized documents, fields, and complete field text. Rust must not reopen arbitrary vault paths or decide which research content is eligible.

Rust returns owned `IndexBuildResponse` and `SearchResponse` envelopes carrying protocol, request, source-snapshot, published-generation, search-contract, and privacy-policy identity. Search hits contain note identity, source fingerprint, score, matched field, and matched terms. Swift computes the displayed snippet and source line from the current exact note after verifying the fingerprint. If a prototype returns snippet fragments instead, use owned `plain`/`match` strings rather than offsets with an unspecified Unicode unit. Follow [references/scholium-index-contract.md](references/scholium-index-contract.md) as the sole Swift–Rust wire-schema authority.

Start with a persistent `scholium-index` subprocess and a versioned local protocol. It provides crash isolation and independent verification. Consider an in-process UniFFI library only after the protocol, Swift 6 compatibility, packaging, and measured call overhead are understood.

## Publish complete generations

- Store every index under `Application Support/Scholium/Vaults/<vault-id>/`, never in a vault.
- Key documents by vault UUID plus normalized relative path; store the source fingerprint in derived metadata.
- Use one writer and immutable reader snapshots. Commit a complete generation before making it visible.
- Keep one writer owner across the app and CLI. If both later need mutation, use one local index service rather than competing writers.
- Include engine version, schema version, tokenizer version, active search-contract version, privacy-policy version, source-snapshot ID, and corpus fingerprint manifest.
- Treat edit as delete-plus-add when required by the backend. Model rename as removal of the old identity plus insertion of the new identity.
- Reject stale build completion when a newer snapshot exists. Support cancellation without publishing partial state.
- On missing files, corruption, incompatible schema, or manifest mismatch, discard and rebuild from the authoritative Swift snapshot.
- Do not merge raw BM25 scores from independently built vault-scoped indexes as though they shared one corpus; federate cross-vault search by an explicit grouping or normalization policy.

## Develop in shadows

1. Establish the current `SQLiteSearchIndex` and `FederatedSearchEngine` correctness, privacy, packaging, mutation, and performance baseline from live code and focused tests.
2. Build the Rust engine only against generated fixtures.
3. Run both engines on the same immutable snapshot and compare conformance to the active search contract.
4. Exercise add, edit, rename, delete, malformed metadata, cancellation, corruption, and rebuild.
5. Enable the Rust engine behind a development flag; keep the active Swift/SQLite engine as fallback.
6. Cut over only after both engines conform to the active contract, privacy tests, crash recovery, packaging, and release benchmarks pass. Version and approve any intentional user-visible semantic change under `scholium-derived-index-integrity` before cutover.

Do not give Rust vault-write permission as part of cutover.

## Verify and report proportionally

Test Unicode normalization, CJK, emoji, prefixes, phrases, query syntax injection, stable ties, snippets, filters, identical relative paths in different vaults, Swift privacy-policy exclusions, and research-text-free logs. Never persist research queries, indexed fields, snippets, or note text in logs or failure artifacts. For integrated mutation tests, compare incremental state with a clean rebuild after every change.

Apply only the stage reached by the task:

1. **Decision or review:** inspect the live Swift baseline, active search contract, backend evidence, adoption gate, packaging risk, and benchmark evidence. Do not claim executable verification that was not run.
2. **Fixture-only prototype:** use generated fixtures; run Rust format, lint, and focused tests plus the relevant index fixture matrix. Do not require app packaging or release benchmarks.
3. **Integrated shadow:** also run Scholium's focused Swift suite, dual-engine mutation equivalence, privacy and crash-recovery tests, and package-boundary checks affected by the integration.
4. **Cutover or release:** run Rust release gates, `./Tools/Scripts/verify.sh`, the active canonical performance gate under `scholium-performance-audit`, and packaged macOS smoke tests. If the 800-note gate remains inactive, run only a labeled scenario and report performance acceptance as unresolved rather than claiming a cutover pass.

Report the stage, backend/version, tokenizer, protocol, index location, tests actually run, build/query p50 and p95 when measured, memory/index size when measured, contract-conformance differences, crash behavior, and remaining uncertainty.

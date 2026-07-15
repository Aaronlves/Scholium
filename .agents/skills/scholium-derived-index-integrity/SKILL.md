---
name: scholium-derived-index-integrity
description: Implement, review, diagnose, or test Scholium's active derived search, link, relationship, diagnostic, and index state. Use for SQLiteSearchIndex, FederatedSearchEngine, SearchEngine, SavedSearchStore, per-vault FTS5 generations, query parsing or ranking, snippets, scopes, role or privacy eligibility, CJK or Unicode behavior, MarkdownSemanticDocument, LinkGraphBuilder, wikilink resolution, backlinks, incremental refresh, corruption recovery, or GUI and CLI parity.
---

# Scholium Derived Index Integrity

Make every index disposable, deterministic, vault-scoped, access-checked, and traceable to exact source fingerprints. Correctness and privacy precede incremental speed.

## Locate the checkout

Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. Do not infer the checkout from an installed plugin cache. If no unique root is in scope, stop and request it. Resolve paths below from the repository root.

Pair this skill with `scholium-development` for implementation and final verification, `scholium-markdown-yaml-fidelity` for parsed metadata, `scholium-vault-file-coordination` for watcher generations, `scholium-trust-boundary-audit` for role/privacy eligibility and generated-state placement, and `scholium-performance-audit` only after semantics pass. Add `scholium-rust-index-engine` and `rust-language` only when a measured Rust-backed alternative is actually being evaluated.

This skill owns Scholium's versioned user-visible search, link, relationship, and derived-index semantics. Backend code must implement this contract without redefining it. File coordination owns filesystem event acknowledgement; workflow code owns the meaning of roles and privacy labels, while this skill enforces their declared search eligibility.

## Confirm the active architecture

Inspect these live surfaces before changing behavior:

- `ScholiumCore/SearchIndex.swift`: `SQLiteSearchIndex`, FTS5 query parsing, per-vault generations, and `FederatedSearchEngine`;
- `Scholium/Services/SearchEngine.swift`: the thin current-vault GUI adapter;
- `Scholium/App/ScholiumApp.swift` and `Scholium/Views/SearchWorkspaceView.swift`: workspace scopes, result opening, and saved searches;
- `ScholiumCLI/main.swift`: synchronized per-vault indexes and agent federation;
- `ScholiumCore/WorkbenchModels.swift`: `SavedSearchStore` outside every vault;
- `MarkdownSemanticDocument.swift`, `LinkGraph.swift`, and the compatibility `LinkEngine.swift` adapter.

SQLite FTS5 is the active lexical backend, not a future option. GUI and CLI consume the same `ScholiumCore` query and result contract; do not introduce a second tokenizer, ranking model, link resolver, or eligibility rule in an app adapter.

## Maintain per-vault generations

- Store one database per stable vault UUID under `Application Support/Scholium/Vaults/<vault-id>/indexes/search-v1.sqlite`; never key identity only by path and never write generated state into a vault.
- Publish an `IndexGeneration` containing vault ID, sequence, contract version, and the complete per-path fingerprint map.
- Apply rebuilds and mutations transactionally. Make an incremental add, edit, rename, or delete produce the same documents, hits, graph state, and diagnostics as a clean rebuild over the same bytes.
- Advance a generation only after its rows and fingerprint manifest commit. Do not expose a partly rebuilt database or combine hits whose reported generation cannot be identified.
- Treat missing, corrupt, wrong-schema, or contract-incompatible databases as rebuildable derived state. Preserve the deterministic rebuild path and test recovery.
- Keep file-event sequence, catalog snapshot, graph generation, and SQLite generation distinct; record their correspondence rather than pretending one counter represents all layers.

## Preserve one search contract

- Version tokenization, canonical normalization, `unicode61` diacritic behavior, explicit CJK character/bigram expansion, phrases, explicit prefixes, exclusions, multi-term logic, field weights, filters, limits, stable tie-breaking, snippets, and source-line calculation.
- Escape all FTS syntax through the query parser. Do not interpolate a raw user query into SQL.
- Keep snippets and highlights UTF-16-safe while retaining one-based full-file source lines. Never mix Swift character counts with `NSRange` or JavaScript offsets.
- Treat every `SearchHit` as a `retrieval_lead`, not proof, evidence, philosophical support, settlement, or prose authorization.
- Keep research text out of logs, signposts, error artifacts, and benchmark labels.

## Federate only eligible vaults

- Select indexes only from registered vaults with current persisted access and the explicitly requested current-note, current-vault, workspace, or role scope.
- Apply actor, role, privacy, and explicit-inclusion rules before querying or merging. Being present in a local index does not make a note authorized for every caller.
- Preserve the current agent rule: dissertation-control results are excluded from ordinary workspace federation unless control access is explicitly included. Test both denial and explicit inclusion.
- Do not infer access from a filename, folder name, metadata keyword, or evidential layer. If the privacy contract becomes more granular, define the rule first and add denial tests before indexing or returning that material.
- Use `FederatedSearchEngine` as the core merge and authorization boundary. Keep GUI and CLI result ordering, limits, provenance, and eligibility conformant even when an app surface opens the per-vault indexes itself.
- Return vault UUID, vault name, registered role, relative path, fingerprint, index generation, source line, and evidential layer with every federated hit.

## Keep saved searches declarative

- Persist only the researcher-created name and query/scope/role state through `SavedSearchStore` outside all vaults.
- Never persist result bytes or treat saved results as current. Re-evaluate a saved definition against current access, current generations, and the active search-contract version.
- Reject or visibly migrate definitions whose fields or role scopes are no longer valid; never broaden their scope silently.

## Derive links and searchable semantics once

- Parse each exact `NoteDocument` into `MarkdownSemanticDocument` and reuse its headings, callouts, footnotes, links, literal exclusions, diagnostics, and source spans for indexing and graph construction.
- Build authoritative outgoing, incoming, relationship, and diagnostic state through `LinkGraphBuilder`. Treat the app `LinkEngine` as a compatibility adapter, not a second semantic contract.
- Resolve exact paths before relative paths, stems, titles, or aliases. Return all ambiguous candidates deterministically and never select Set iteration order.
- Support declared wikilinks, aliases, embeds, headings, blocks, same-note fragments, and Markdown internal links; exclude escaped constructs, code, comments, frontmatter, and other literal regions.
- Preserve source line, UTF-8/UTF-16 span, target fragment, resolution, and every explicit occurrence. Feed broken-link state into search only from the corresponding graph snapshot.
- Keep Vector-Link v1 direction and symmetry exact. Untyped links are neutral, legacy relationships remain distinguishable, reified endpoints do not invent evidence, and multi-hop paths never inherit philosophical support.

Read [references/search-link-fixture-matrix.md](references/search-link-fixture-matrix.md) before changing search, saved-search persistence, federation, link resolution, or generated indexes.

## Audit and verify

For an integrity request, report malformed metadata, unauthorized scope expansion, broken or ambiguous links, duplicate or case-folded paths, stale entries, generation mismatches, orphaned derived records, saved-search drift, and clean-rebuild differences before proposing repairs. Never delete or rewrite a research file automatically.

Add pure, parameterized tests in an importable target. Exercise rebuild and add/edit/rename/delete mutations, concurrent queries, cancellation, corruption recovery, federated denial/inclusion, saved-search round trips, GUI/CLI parity, and graph/search regeneration. Compare event-driven state with a clean rebuild after every mutation.

Run focused `SearchIndexTests`, `LinkGraphTests`, `MarkdownSemanticDocumentTests`, and saved-search tests, then `./Tools/Scripts/verify.sh`. Use the performance skill only after all semantic and access tests pass. Report query semantics, fixture size, per-vault generations, eligibility context, and every deliberate GUI/CLI difference.

## Standards and lineage

Use [CommonMark](https://spec.commonmark.org/), [Obsidian internal links](https://obsidian.md/help/links), [Obsidian aliases](https://obsidian.md/help/aliases), and [SQLite FTS5](https://www.sqlite.org/fts5.html). The report-before-repair discipline selectively adapts the MIT-licensed [llm-wiki-skills wiki-lint workflow](https://github.com/vanillaflava/llm-wiki-skills/tree/master/wiki-lint) without adopting its bespoke schema.

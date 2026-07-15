# Index backend and tokenization decisions

## Decision table

| Option | Choose when | Main cautions |
|---|---|---|
| Active Swift SQLite FTS5 | Default Scholium backend while it meets the versioned contract and measured targets | Query grammar escaping, tokenizer/version differences, generation/rebuild discipline, concurrency ownership, and CJK policy |
| Rust with Tantivy | A portable engine needs BM25, configurable tokenizers, facets/fast fields, incremental segments, or larger-scale throughput | More dependencies, FFI/process packaging, strict schema, tokenizer plugins, and segment lifecycle |
| Custom Rust inverted index | Only when Scholium's required semantics cannot be represented safely elsewhere | Large correctness surface: persistence, ranking, merging, tokenization, queries, and recovery |

Do not select a backend from a microbenchmark alone. Compare correctness, build latency, warm/cold query p95, memory, index size, mutation cost, crash recovery, binary size, dependency risk, and packaging.

Backend selection does not authorize a user-visible search-semantic change. `scholium-derived-index-integrity` owns and versions the active contract; evaluate every option against its golden fixtures. Propose and approve any intentional tokenization, ranking, filtering, snippet, or parity change there before treating it as a backend requirement.

## SQLite FTS5

Scholium's active `ScholiumCore/SearchIndex.swift` baseline uses per-vault FTS5 databases under Application Support, a `unicode61` tokenizer, transactional rebuild and incremental mutation, generation/fingerprint records, deterministic ranking, and Swift-owned federation. `SearchIndexTests.swift` is the focused parity and privacy fixture surface. Inspect the live code before asserting any missing capability.

FTS5 offers full-text query syntax, prefix indexes, column filters, phrases, NEAR, BM25-related ranking functions, and built-in tokenizers. Relevant tokenizer behavior:

- `unicode61` groups contiguous Unicode letters/numbers, case-folds according to Unicode 6.1, and removes many Latin diacritics by default.
- explicit prefix indexes accelerate selected prefix lengths.
- `trigram` supports substring matching, including general non-whitespace text, but full-text terms shorter than three Unicode characters do not match.
- external-content/contentless designs have synchronization pitfalls; a disposable index should retain an unambiguous rebuild path.

Primary reference: [SQLite FTS5](https://www.sqlite.org/fts5.html).

## Tantivy

Tantivy is a Rust search library rather than a server. It provides strict schemas, BM25 search, phrase queries, configurable tokenizers, fast fields/facets, immutable segments, incremental and multithreaded indexing, and commit/reload visibility.

Important operational facts:

- a document edit is delete plus reindex;
- changes become searchable after the writer commits and readers reload;
- tokenizer choice is attached to indexed fields and must be stable across a generation;
- the default tokenizer splits on whitespace/punctuation, lowercases, and removes tokens over its limit;
- Chinese, Japanese, and Korean normally require an audited third-party tokenizer or a deliberately specified n-gram approach.
- ICU4X `WordSegmenter` is a candidate foundation for a custom tokenizer because it implements Unicode word segmentation and offers dictionary/model strategies; verify the current crate/version and benchmark it on the actual multilingual fixture before adoption.

Primary references:

- [Tantivy repository and feature overview](https://github.com/quickwit-oss/tantivy)
- [Tantivy architecture](https://docs.rs/tantivy/latest/tantivy/)
- [Tantivy schema](https://docs.rs/tantivy/latest/tantivy/schema/)
- [Tantivy tokenizers](https://docs.rs/tantivy/latest/tantivy/tokenizer/)
- [ICU4X WordSegmenter](https://docs.rs/icu_segmenter/latest/icu_segmenter/struct.WordSegmenter.html)

## Backend conformance checklist for tokenization

Verify that the active contract owned by `scholium-derived-index-integrity` defines and tests these independently of the backend. This checklist does not choose their values:

1. Normalize source and query text with one declared Unicode normalization form.
2. Specify locale-independent case folding and whether Latin diacritics are significant.
3. Preserve raw identifiers, citation keys, paths, and tags in exact/raw fields alongside human-language text fields.
4. State hyphen, apostrophe, underscore, colon, Markdown syntax, and heading-boundary behavior.
5. Support one-character queries intentionally; do not let a trigram implementation silently drop them.
6. Test Chinese characters and phrases, Japanese kana/kanji, mixed CJK/Latin, emoji, composed/decomposed accents, and supplementary scalars.
7. Keep query parsing structured. Escape user text rather than exposing backend grammar accidentally.
8. Avoid silent stemming of names, citation keys, quotations, Greek terminology, and philosophical technical terms. Separate exact/raw fields from normalized language fields.

Unicode word boundaries are defaults, not a complete language-specific segmentation solution. Primary reference: [Unicode Standard Annex #29](https://www.unicode.org/reports/tr29/).

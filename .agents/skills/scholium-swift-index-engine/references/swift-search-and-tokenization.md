# Swift search and tokenization decisions

Use this to select a mechanism, not to preserve a candidate list or current
implementation snapshot. Reopen the selected SDK, SQLite build, dependency
source, license, dictionaries, packaging, and current primary documentation.

## Decision order

Prefer, in order:

1. a correction to the active Swift and SQLite boundary;
2. bounded preprocessing through a verified platform service;
3. a tokenizer extension that preserves the active query and source-location contract;
4. a maintained Swift-callable analyzer for a measured unsupported need; and
5. a custom index only when preceding mechanisms cannot satisfy the contract.

Choose from the complete retrieval contract and operational cost, not feature
count or tokenizer speed alone. A candidate must improve the named correctness
or scale problem while preserving packaging, privacy, recovery, and ownership.

## Candidate questions

- Can document and query processing use the same versioned policy?
- Are normalized terms kept separate from raw identifiers and source ranges?
- Are positions and snippets traceable across the repository's string and
  bridge boundaries?
- Are short terms, researcher terminology, mixed scripts, phrases, prefixes,
  punctuation, and identifiers handled intentionally rather than accidentally?
- Can incremental mutation equal a clean rebuild, and can incompatible state be
  detected and rebuilt?
- Are cancellation, concurrency, resource ownership, corruption, and repeated
  open/close behavior explicit?
- Are maintenance, source, tests, releases, licenses, dictionaries, transitive
  dependencies, architectures, binary cost, signing, failure isolation, and
  rebuild behavior acceptable?

Platform tokenization is a service, not automatically a stable persisted
format. Native tokenizer callbacks and foreign analyzers require explicit
buffer, offset, lifetime, error, and threading ownership. Never rewrite the
only stored text merely to make tokenization easier.

## Conformance evidence

Define the adopted Unicode, case, width, diacritic, punctuation, compound,
phrase, prefix, and query-escaping policy in the live versioned contract. Test
documents and queries together over generated multilingual fixtures and
preserve exact raw fields. Report semantic differences before performance.

Primary starting points: [Apple Natural Language](https://developer.apple.com/documentation/naturallanguage),
[SQLite FTS5](https://www.sqlite.org/fts5.html),
[Unicode text segmentation](https://www.unicode.org/reports/tr29/), and current
[Swift C++ interoperability](https://www.swift.org/documentation/cxx-interop/)
when a native boundary is actually selected.

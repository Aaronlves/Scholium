# Tokenizer or index-engine evaluation

## Evidence stage

- Stage: decision / fixture-prototype / integrated-shadow / cutover
- Date and source revision:
- Selected SDK, Swift toolchain, packaged SQLite, and target architectures:

## Problem and success condition

- Researcher-visible retrieval problem:
- Active search-contract version:
- Required semantic result:
- Required performance or resource result:
- Explicit non-goals:

## Baseline and candidate

| Item | Active baseline | Candidate |
| --- | --- | --- |
| Engine and version | | |
| Tokenizer, dictionary or model | | |
| Normalization and raw fields | | |
| Storage and generation owner | | |
| Dependency and license | | |
| Packaging and failure recovery | | |

## Fixture and oracle

- Generated fixture identity and size:
- Simplified and Traditional Chinese:
- Japanese:
- Korean:
- Mixed scripts, emoji, normalization, identifiers, and one-character terms:
- Add/edit/rename/delete and clean-rebuild histories:
- Privacy, corruption, cancellation, and stale-generation injections:

## Contract comparison

| Behavior | Expected | Baseline | Candidate | Disposition |
| --- | --- | --- | --- | --- |
| Terms and exact/raw matching | | | | |
| Prefixes and phrases | | | | |
| Filters and ranking | | | | |
| Snippets, highlights, and source lines | | | | |
| Stable ties and GUI/CLI parity | | | | |
| Recovery and rebuild | | | | |

## Measurements

Record release-build sample count, warm-up policy, p50, p95, maximum, build
latency, mutation latency, peak memory, index size, and binary-size change. Mark
unmeasured values explicitly; do not substitute an engine microbenchmark for a
complete product boundary.

## Decision

- Result: retain baseline / revise prototype / integrate in shadow / cut over
- Evidence supporting the result:
- Intentional semantic changes requiring authority updates:
- Remaining uncertainty and human review:

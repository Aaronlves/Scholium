# Scholium Beta performance benchmark

**Protocol authority:** This is the sole canonical Scholium benchmark protocol.
The performance-audit skill routes here; its adjacent reference is
routing-only and must not define a competing fixture, sample count, threshold,
or gate.

**Current status:** RDF-1, complete-boundary instrumentation, the external
XCUITest driver, strict report validator, and fail-closed runner are
implemented. One four-metric Debug scenario run has validated the plumbing.
No packaged Release product-gate run or threshold approval exists, so G7 is
not passed.

## Scope and evidence classes

Scholium keeps three kinds of performance evidence separate:

1. **Regression microbenchmarks** run inside Swift tests and detect obvious
   slowdowns in internal SQLite search and semantic Markdown projection.
2. **Scenario-only measurements** exercise an incomplete fixture, fewer than
   30 retained samples, or something other than the exact packaged Release app.
3. **Product-gate measurements** exercise the exact packaged Release app,
   frozen RDF-1, complete user-visible boundaries, and 30 retained samples.

Only the third class can satisfy PRD gate G7. A passing unit test, Debug build,
human stopwatch run, or internal engine timer must never be reported as the
product gate.

## Proposed Beta thresholds

These thresholds require release-owner approval before the Beta decision.
Each limit is strict and uses nearest-rank p95 over exactly 30 valid measured
samples after five excluded warm-ups. Thirty retained samples are the Beta
tradeoff between tail-latency evidence and sustained thermal load on Reference
Machine R1; the report also exposes the maximum and every raw duration.

| Interaction | Proposed p95 limit |
| --- | ---: |
| Warm library launch to a usable note list | `< 1,000 ms` |
| Indexed Search query to complete visible results | `< 100 ms` |
| Warm Read-note activation to interactive rendering | `< 300 ms` |
| Application-cold 5,000-word Read-note activation to interactive rendering | `< 1,000 ms` |

The report must retain every raw duration and include p50, p95, maximum, mean,
sample count, invalidated trials with reasons, correctness results, and the
machine and artifact record.

## Canonical RDF-1 fixture

`Tools/Scripts/generate-rdf1.py` is the canonical deterministic no-RNG RDF-1
generator. It writes only to `/tmp` unless an intentionally reviewed run passes
`--allow-outside-tmp`.

```bash
python3 Tools/Scripts/generate-rdf1.py \
  --output /tmp/scholium-rdf1
python3 Tools/Scripts/generate-rdf1.py \
  --output /tmp/scholium-rdf1 \
  --verify
```

RDF-1 contains exactly 800 synthetic Markdown notes across Analyses, Topics,
and Works. Its generated `manifest.json` records:

- generator and protocol hashes plus deterministic no-RNG mode;
- paths, byte sizes, SHA-256 values, role counts, and a complete tree hash;
- valid and deliberately malformed frontmatter counts;
- link, typed-relation, and folder-depth coverage;
- one canonical 5,000-word Work and the exact body-word rule;
- fixed warm, alternate, and cold document paths; and
- fixed English and CJK Search queries with expected result identities.

The fixture is invented test material and must never be cited, imported into a
research vault, or used as philosophical evidence.

## Instrumented interaction contracts

The app enables performance recording only when an explicit supported metric,
safe run id, sample index, and existing `/tmp` JSONL parent are supplied. Each
record contains timing and correctness-count metadata only. It never contains
a query, note path, note title, or research text.

- Warm library launch starts immediately before the XCUITest launch request
  and ends after the 267-note Analyses list is published and AppKit has laid it
  out.
- Indexed Search uses the fixed `RDF1WarmAnalysis` query in `This Vault`. It
  starts only on the final query mutation and ends after exactly one result is
  published and laid out.
- Warm Read starts inside `openNote` for the canonical warm document. Search is
  used only to prepare and invoke the deterministic navigation action; its
  preparation time precedes the timer. Read readiness requires WebKit
  navigation completion plus two animation frames.
- Cold Read starts immediately before launching the app on the canonical
  5,000-word Work and uses the same WebKit readiness boundary.

The external driver uses one isolated, metric-specific `SCHOLIUM_HOME`. Warm
Search and warm Read samples run sequentially in one app process after setup;
warm library launch and application-cold Read still launch a fresh process for
each sample because process startup is part of those contracts. The driver
inserts bounded cooling intervals between cold relaunches and gate metrics.
The five gate warm-ups converge derived state before the 30 retained samples.

## Product-gate environment

The product-gate runner must use:

- the exact app produced by `Tools/Scripts/package-app.sh` from the reviewed
  commit, not `swift run`, a Debug binary, or the QA app;
- one unchanged machine record covering macOS, model, CPU, memory, power mode,
  display, foreground applications, window size, accessibility settings, and
  logging level;
- a disposable RDF-1 copy plus isolated Application Support, preferences,
  bookmarks, and derived state; and
- instrumentation that reaches the complete visible and accessible boundary,
  including SwiftUI publication and WKWebView interactive readiness.

Warm launch begins at the launch request and ends when the note list is
visible, selectable, and unblocked. Indexed Search begins at the final query
mutation and ends when the complete expected result set is visibly published.
Warm and cold Read activation end only when the expected note is rendered and
interactive; semantic HTML projection alone is insufficient.

`package-app.sh` embeds `ScholiumBuildProvenance.plist`. Gate mode refuses to
run unless the checkout is clean and exactly tagged, the packaged app reports
the same commit and tag, and its provenance records a clean source tree. It
also refuses to run without explicit release-owner threshold approval.

Scenario-only smoke run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  ./Tools/Scripts/run-performance-benchmarks.sh \
  --app /tmp/Scholium-QA.app \
  --fixture /tmp/scholium-rdf1 \
  --output /tmp/scholium-performance-scenario \
  --scenario
```

Product gate after the reviewed commit is clean, exactly tagged, packaged, and
the proposed thresholds are approved:

```bash
SCHOLIUM_RELEASE_OWNER_APPROVED_THRESHOLDS=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  ./Tools/Scripts/run-performance-benchmarks.sh \
  --app "/path/to/Scholium.app" \
  --fixture /tmp/scholium-rdf1 \
  --output "/path/outside/the/repository/g7" \
  --gate
```

## Verified scenario-only evidence

On 2026-07-14, the four-metric runner completed with a Debug QA app, zero
warm-ups, and one retained sample per metric. It produced four privacy-safe
JSONL files, an environment record, and a report classified as
`scenario_only` with `gate_status: not_applicable`. The recorded durations
were 7,668.7 ms library launch, 327.1 ms indexed Search, 267.2 ms warm Read,
and 8,606.0 ms cold Read. These values validate the harness only; they are not
p95 measurements and do not support a Beta performance claim. RDF-1 verified
before and after the run with the same complete tree hash.

On 2026-07-15, the thermally bounded driver completed a second four-metric
Debug QA smoke with zero warm-ups and one retained sample. Warm Search and
warm Read each used one app process; Library and Cold Read retained their
process-boundary launches. The report at
`/tmp/scholium-performance-batched-smoke-v3/report.json` recorded 7,225.0 ms
Library, 430.0 ms Search, 265.2 ms Warm Read, and 8,614.5 ms Cold Read with all
correctness checks passing. It is `scenario_only` / `not_applicable` and proves
the revised harness contract only. An earlier 1+3 diagnostic exposed duplicate
Search begin events and Command-F resetting scope to This Note; the driver now
re-arms only after leaving the target query and explicitly selects This Vault
before warm-Read navigation.

## Remaining activation work

RDF-1 closes the deterministic corpus, manifest, fixed document, fixed query,
and correctness-fixture requirements. G7 remains inactive until all of the
following are complete:

1. obtain release-owner approval for the proposed thresholds;
2. freeze and exactly tag a clean reviewed commit, then package that exact
   source with provenance;
3. run the packaged artifact and frozen RDF-1 on Reference Machine R1 with
   five warm-ups and 30 retained samples for every metric; and
4. retain and review the raw results, environment metadata, correctness
   assertions, and strict nearest-rank p95 verdict outside every vault.

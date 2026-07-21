# Scholium Beta performance benchmark

**Protocol authority:** Sole canonical Scholium benchmark protocol. Routing
references must not define competing fixtures, samples, thresholds, or gates.

**Current status:** RDF-1, complete-boundary instrumentation, the external
XCUITest driver, strict validator, and fail-closed runner are implemented;
Debug scenarios validated the harness. G7 remains open because thresholds are
unapproved and no packaged Release product-gate run exists.

## Scope and evidence classes

Keep three evidence classes separate:

1. **Regression microbenchmarks** run inside Swift tests and detect obvious
   slowdowns in internal SQLite search and semantic Markdown projection.
2. **Scenario-only measurements** exercise an incomplete fixture, fewer than
   30 retained samples, or something other than the exact packaged Release app.
3. **Product-gate measurements** exercise the exact packaged Release app,
   frozen RDF-1, complete user-visible boundaries, and 30 retained samples.

Only product-gate measurements satisfy G7. Unit tests, Debug builds, human
stopwatches, and internal timers never do.

## Proposed Beta thresholds

These strict thresholds require release-owner approval. Use nearest-rank p95
over exactly 30 valid samples after five excluded warm-ups; this balances tail
evidence against sustained thermal load on R1. Retain every raw duration and
the maximum.

| Interaction | Proposed p95 limit |
| --- | ---: |
| Warm library launch to a usable note list | `< 1,000 ms` |
| Indexed Search query to complete visible results | `< 100 ms` |
| Warm Read-note activation to interactive rendering | `< 300 ms` |
| Application-cold 5,000-word Read-note activation to interactive rendering | `< 1,000 ms` |

The Editor special topic additionally proposes these **Usable Core** limits.
They are not G7 product-gate thresholds until the release owner approves them
and the external driver implements the complete visible boundary:

| Editor interaction | Proposed p95 limit |
| --- | ---: |
| Key down to the first painted frame containing the edit | `< 100 ms` |
| Visible Live Preview/Source mode transition | `< 100 ms` |
| Cached internal-link, Vector-Link, or footnote preview presentation | `< 100 ms` |
| Warm Live Preview activation to interactive rendering | `< 300 ms` |
| Application-cold 5,000-word Live Preview activation | `< 1,000 ms` |
| Live projection work for one visible-range update | `< 5 ms` |

Continuous scrolling must not add one uninterrupted Editor task longer than
one display refresh interval, and neither the app nor Web UI thread may add an
uninterrupted task longer than 100 ms. A 100,000-CJK-character stress fixture
must remain editable at its beginning, middle, and end with working undo, mode
switching, and byte-exact save. After 50 note/mode switches, retained
`EditorState`/`WKWebView` counts and total process memory must converge rather
than grow monotonically. These are correctness and stability conditions, not
single-duration percentile metrics.

Report raw durations, p50, p95, maximum, mean, sample count, invalid trials and
reasons, correctness, machine, and artifact.

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

RDF-1 contains exactly 800 synthetic Markdown notes across all three vaults.
Its `manifest.json` records:

- generator and protocol hashes plus deterministic no-RNG mode;
- paths, byte sizes, SHA-256 values, role counts, and a complete tree hash;
- valid and deliberately malformed frontmatter counts;
- link, typed-relation, and folder-depth coverage;
- one canonical 5,000-word Work and the exact body-word rule;
- one canonical 100,000-CJK-character Work and the exact CJK-scalar rule;
- fixed warm, alternate, and cold document paths; and
- fixed English and CJK Search queries with expected result identities.

Never cite RDF-1, import it into a research vault, or use it as philosophical
evidence.

## Instrumented interaction contracts

Recording requires a supported metric, safe run ID, sample index, and existing
`/tmp` JSONL parent. Records contain timing and correctness counts only—never a
query, note path/title, or research text.

- Warm library launch starts immediately before the XCUITest launch request
  and ends after the 267-note Analyses list is published and AppKit has laid it
  out.
- Indexed Search uses the fixed `RDF1WarmAnalysis` query in `This Vault`. It
  starts only on the final query mutation and ends after exactly one result is
  published and laid out.
- Warm Read starts inside `openNote` for the canonical warm document. Search is
  not used for navigation because lexical results correctly open their matching
  source location in Source mode. The driver expands the two fixed RDF-1
  Library folders before sampling and invokes the deterministic target and
  alternate note rows directly. Read readiness requires WebKit navigation
  completion plus two animation frames.
- Cold Read starts immediately before launching the app on the canonical
  5,000-word Work and uses the same WebKit readiness boundary.

The driver uses one isolated, metric-specific `SCHOLIUM_HOME`. Warm Search and
Read share one post-setup process; warm launch and cold Read relaunch per
sample because startup belongs to those contracts. Bounded cooling separates
cold relaunches and metrics; five warm-ups converge derived state before the
30 retained samples.

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

The interaction boundaries above are normative: visible, selectable, and
unblocked for launch; complete visible results for Search; rendered and
interactive for Read. Semantic HTML projection alone is insufficient.

Editor bridge v4 retains a fixed 256-sample circular diagnostic buffer
containing only metric names, durations, document length,
visible-range/decorations counts, and byte counts. It records startup, document
load, visible-range projection, key-to-state, key-to-paint, mode-transition
work/paint, cached-preview work/paint, aggregated scroll sessions, bridge
requests, and a best-effort JavaScript heap sample. Scroll-session records
contain frame count, longest observed frame, and dropped-frame count rather
than one allocation per frame; corresponding User Timing measures are cleared
after capture. Paint records use CodeMirror's `requestMeasure` followed by the
next animation frame. The bridge query proves instrumentation transport only;
its internal work durations are regression evidence, not a substitute for the
external visible-boundary driver. WebKit process memory must be measured from
the process set because `performance.memory` is not a portable WKWebView API.

The retained-memory journey is an app-owned 51-sample handshake: one sample
after the initial editor bridge becomes ready, followed by one sample after
each of 50 alternating Live Preview/Source bridge acknowledgments. The app
writes progress into the run-specific sandbox directory, the external sampler
attributes the exact app/WebKit process set and acknowledges the sample, and
the UI driver advances only after that acknowledgment. QA requests may bypass
SwiftUI menu presentation overhead, but they must still update the current
retained document session and wait for the production WebView/CodeMirror mode
transition; directly emitting readiness or sampling before the bridge ACK is
invalid.

`package-app.sh` embeds `ScholiumBuildProvenance.plist`. Gate mode refuses to
run unless the checkout is clean and exactly tagged, the packaged app reports
the same commit and tag, and its provenance records a clean source tree. It
also refuses to run without explicit release-owner threshold approval.

Scenario-only smoke run:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" \
  ./Tools/Scripts/run-performance-benchmarks.sh \
  --app .build/qa-runtime/Scholium-QA.app \
  --fixture /tmp/scholium-rdf1 \
  --output /tmp/scholium-performance-scenario \
  --scenario
```

Product gate after the reviewed commit is clean, exactly tagged, packaged, and
the proposed thresholds are approved:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
SCHOLIUM_RELEASE_OWNER_APPROVED_THRESHOLDS=1 \
DEVELOPER_DIR="$developer_dir" \
  ./Tools/Scripts/run-performance-benchmarks.sh \
  --app "/path/to/Scholium.app" \
  --fixture /tmp/scholium-rdf1 \
  --output "/path/outside/the/repository/g7" \
  --gate
```

## Evidence pointer

Only [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) records current
evidence. Temporary Debug smoke results validate only the harness.

## Remaining activation work

G7 remains inactive until all of the following are complete:

1. obtain release-owner approval for the proposed thresholds;
2. freeze and exactly tag a clean reviewed commit, then package that exact
   source with provenance;
3. run the packaged artifact and frozen RDF-1 on Reference Machine R1 with
   five warm-ups and 30 retained samples for every metric; and
4. retain and review the raw results, environment metadata, correctness
   assertions, and strict nearest-rank p95 verdict outside every vault.

Editor activation remains separate work: RDF-1 v2 contains the reviewed
100,000-CJK-character stress document. A real WKWebView integration test edits
that scale of CJK source exactly and another keeps one dirty buffer exact
through 50 typed Source/Live bridge transitions. A prior disposable XCU journey
was reported to exercise beginning, middle, and end edits, but the current
macOS 27 rerun cannot make CodeMirror's document-height virtualized
accessibility text node a reliable input target; that journey therefore is not
current acceptance evidence. These are correctness observations, not visible
percentile or memory evidence. The
current fail-closed memory sampler uses `launchctl print pid/<app-pid>` to
obtain only the WebKit service instances owned by that exact app originator,
then requires every PID to resolve through `ps` to the expected app or WebKit
framework executable before summing RSS. PPID and process-name scans remain
invalid, and a missing service role, changed process set, originator mismatch,
or executable mismatch invalidates the sample. Parser/rejection self-tests and
one live isolated-QA probe pass. The 50-transition external journey and its
51-sample acknowledgment handshake are wired into the fail-closed runner, but
the retained artifacts contain only incomplete prefixes of at most five
samples and therefore do not prove convergence. UI-driven runners share
one unlocked-console preflight and keep every result bundle under the
repository-local `.build/` scratch tree; a locked host is an infrastructure
failure, never a performance result. The remaining work is to complete and
retain the convergence series on an unlocked host, add external visible Editor
latency actions, approve the proposed Usable Core limits, and then run the same
five-warm-up/30-sample protocol against the exact packaged Release app.

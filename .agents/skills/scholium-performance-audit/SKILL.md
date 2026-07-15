---
name: scholium-performance-audit
description: Diagnose, measure, and improve Scholium runtime performance without weakening source fidelity or vault safety. Use for slow launch, indexing, federated search, note switching, scrolling, active CodeMirror or WKWebView rendering, high CPU or memory, hangs, excessive SwiftUI updates, synthetic regression microbenchmarks, or the RDF-1 product acceptance gate. Do not use for speculative refactoring without a performance symptom or measurement goal.
---

# Scholium Performance Audit

Separate code suspicion from measured evidence. Preserve exact-document semantics, revision checks, and human approval while optimizing.

## Locate the checkout

Do not infer the checkout from this installed skill. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If no unique root is in scope, stop and request the checkout. Resolve paths and run commands from the repository root.

Pair this skill with `scholium-development` for implementation and final verification, `scholium-swiftui-implementation` for measured SwiftUI remediation, `scholium-markdown-editor-integration` for any measured reader/editor or TextKit/WebKit change, and `scholium-ui-automation` for repeatable packaged-app interactions and isolated launch state. Add `scholium-trust-boundary-audit` when a proposed optimization affects writes, caches, private diagnostics, or filesystem authorization.

## Establish a baseline

1. Read `AGENTS.md`, `README.md`, and the relevant code path.
2. Record the macOS version, hardware, build configuration, vault size, note-size distribution, and exact interaction.
3. For the product gate, generate the disposable RDF-1 corpus with
   `Tools/Scripts/generate-rdf1.py` from the repository root, then benchmark it
   with isolated application state. Other fixtures are scenario-only and must be
   named as such. Never use a private research vault or research-derived content.
4. Use a release build for acceptance measurements. Use Debug only for diagnosis and label it accordingly.
5. Classify the run before changing code: internal regression microbenchmark, diagnostic GUI scenario, or product acceptance gate. Define elapsed time, p50/p95 latency, CPU, memory peak, dropped frames, or unexpected view updates without allowing one class to impersonate another.

Read [Docs/PERFORMANCE_BENCHMARK.md](../../../Docs/PERFORMANCE_BENCHMARK.md) for
the product targets, RDF-1 generator, current gate status, sample protocol,
and reproducibility rules. The adjacent reference only routes to that document.
A scenario-only measurement is not a gate result.

## Triage by subsystem

- **Launch and refresh:** `VaultService`, file enumeration, parsing, index generation, FSEvents coalescing.
- **Search and navigation:** `SQLiteSearchIndex`, `FederatedSearchEngine`, query parsing, filtering, sorting, selection, note loading, and link computation.
- **Read rendering:** detached `SafeMarkdownRenderer` projection followed by `SafeMarkdownReadWebView` HTML loading, WebKit navigation completion, source-line focus, CSS application, and interactive readiness.
- **Editing:** `MarkdownEditorWebView`, bundled CodeMirror startup, ready handshake, `setDocument`, mode and CSS changes, UTF-16 delta bridge traffic, Swift buffer updates, save-buffer reconciliation when present, autosave, selection, and focus. Measure `NativeMarkdownReadView` only when its fallback is explicitly activated; do not describe `NativeMarkdownEditorView` as active unless a reviewed change actually reactivates it.
- **SwiftUI:** observation fan-out, unstable identity, work in `body`, broad environment reads, layout churn.
- **Zotero:** bounded exact-item localhost API calls for the current or directly linked Analyses, and work accidentally performed on the main actor. Attachment enumeration and export are Product Guide non-goals.

Read [references/swiftui-performance-checks.md](references/swiftui-performance-checks.md) for code-review checks.

Route every measured editor remediation through `scholium-markdown-editor-integration`; performance evidence does not override source, range, selection, undo, focus, or accessibility invariants.

For logging, signposts, privacy, and diagnostic capture, read
[references/observability.md](references/observability.md). Instrument only the
boundaries needed to answer the current question; do not log research content.

## Escalate evidence deliberately

1. Start with code-path tracing and lightweight signposts or timers.
2. Use Instruments when code review cannot establish the cause:
   - Time Profiler for CPU and main-thread work;
   - SwiftUI instrument for update causes and long view-body work;
   - Hangs for unresponsive interactions;
   - Allocations or Leaks for memory growth.
3. Capture the same interaction before and after the change.
4. Treat a screenshot or trace as evidence only for the recorded build, machine, vault, and interaction.

## Remediate narrowly

- Reduce repeated work before changing architecture.
- Narrow observed inputs and pass derived leaf values when broad state causes invalidation.
- Preserve stable note identity across sorting, filtering, and refresh.
- Move parsing, filtering, graph construction, and formatting out of SwiftUI `body`.
- Coalesce file-system refreshes without dropping real changes.
- Keep AppKit and any active WebKit calls on their required actors; move only safe CPU work away from the main actor.
- Do not cache authoritative Markdown in a way that can bypass fingerprint, conflict, or refresh checks.
- Do not trade exact-source preservation for faster YAML reserialization.

## Verify and report

Run the same scenario and report:

- baseline and result with units;
- p50/p95 and sample count when measuring latency;
- code-backed suspicions separately from trace-backed findings;
- regression tests or benchmark harness used;
- remaining uncertainty and the next measurement that would reduce it.

Treat `Tests/ScholiumCoreTests/PerformanceAcceptanceTests.swift` as an
internal regression microbenchmark despite its suite and test names. Its
generated search test samples an internal SQLite engine, and its long-note test
stops after semantic HTML projection; neither exercises the packaged Release
app or a complete user-visible CodeMirror/WKWebView boundary. A passing test is
early-warning evidence, not a product-gate result.

Do not claim the RDF-1 acceptance gate passed unless
`Docs/PERFORMANCE_BENCHMARK.md` marks it active and the current task used its
canonical fixture version, release artifact, state definitions, five warm-ups,
30 retained samples, quantile method, correctness checks, and approved
thresholds. Otherwise label the result **scenario-only** or **regression
microbenchmark**, whichever is accurate.

## Source lineage

The audit structure adapts the MIT-licensed performance-review ideas in [Dimillian/Skills](https://github.com/Dimillian/Skills/tree/main/swiftui-performance-audit) and the MIT-licensed SwiftUI performance checks in [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill), constrained to Scholium's macOS architecture and trust boundary.

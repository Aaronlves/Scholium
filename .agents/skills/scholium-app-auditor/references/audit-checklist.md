# Scholium App Audit Checklist

`Docs/PRODUCT_GUIDE.md` owns target behavior. Retired Proposal, Revision, Agent Review, Research Session, authored Canvas, and export workflows are not target requirements. Audit only their absence from reachable target surfaces and the non-destructive treatment of legacy files.

Use this as coverage accounting, not as a demand to perform every expensive test on every audit. Mark each section **checked**, **not applicable**, **not checked**, or **blocked**, and record the evidence used.

## Contents

- [1. Build and repository baseline](#1-build-and-repository-baseline)
- [2. Correctness and domain contracts](#2-correctness-and-domain-contracts)
- [3. Vault safety and exact-source fidelity](#3-vault-safety-and-exact-source-fidelity)
- [4. Input, output, security, and privacy](#4-input-output-security-and-privacy)
- [5. Swift safety and error handling](#5-swift-safety-and-error-handling)
- [6. Concurrency and lifecycle](#6-concurrency-and-lifecycle)
- [7. Memory and resource ownership](#7-memory-and-resource-ownership)
- [8. Search, links, indexes, and persistence](#8-search-links-indexes-and-persistence)
- [9. Interface and accessibility](#9-interface-and-accessibility)
- [10. Performance and responsiveness](#10-performance-and-responsiveness)
- [11. Tests and diagnostics](#11-tests-and-diagnostics)
- [12. Packaging and release](#12-packaging-and-release)

## 1. Build and repository baseline

- Confirm the selected Xcode, Swift compiler, Swift language mode, SDK, deployment target, and build configuration independently.
- Inspect all package targets, products, pinned dependencies, generated bundles, scripts, CI entry points, warnings, and uncommitted work.
- Check that generated artifacts are reproducible from locked sources and are verified against source.
- Check generated and install-only trees for suspicious numbered duplicates, stale side-by-side copies, or manually patched dependencies. Recreate them from the lockfile and compare the committed bundle; do not report ignored generated clutter as source corruption without proving impact.
- Check documentation claims against reachable implementation and tests.
- Treat `Docs/IMPLEMENTATION_STATUS.md` as dated status evidence. Recheck its role/schema/lint/session/bridge claims against the upstream workflow report, live types, callers, and focused tests.
- Check that verification does not accidentally package, sign, mutate real vaults, or depend on undeclared machine state.

## 2. Correctness and domain contracts

- Trace empty, missing, malformed, duplicate, stale, renamed, deleted, maximum-size, cancellation, and partial-failure cases.
- Check that failures leave memory, disk, indexes, UI selection, and review state consistent.
- Check stable identity across sorting, filtering, refresh, windows, and same-named notes or vaults.
- Check date, locale, Unicode, UTF-8/UTF-16, line/column, path, and fingerprint assumptions at boundaries.
- Check that declared workflow roles and relation directions are preserved rather than inferred from names or connectivity.
- Check that implementation and handbook behavior do not contradict each other.

## 3. Vault safety and exact-source fidelity

- Keep every authoritative write behind canonical containment, existing-regular-file checks, stable vault identity, starting fingerprint, pre-write snapshot, validation, and atomic replacement.
- Reject traversal, symlink escape, cross-vault identity mismatch, stale revisions, malformed frontmatter, and nonexistent targets.
- Preserve BOM, newline style, final newline, comments, unknown YAML fields, ordering, quoting, multiline values, and untouched source bytes.
- Keep generated indexes, reviews, comments, Dialogue replies, checkpoints, Canvas state, window sessions, caches, and logs outside vaults. Keep only the portable state explicitly allowed by the Product Guide in `.scholium/`.
- Check snapshot failure, disk-full, permission loss, external replacement, rename, delete/recreate, and recovery paths.
- Ensure existing-note CLI mutations require the current fingerprint, remain contained in the selected vault, and fail on stale revisions. Direct agent edits are researcher-authorized work; do not reintroduce Proposal as an app authorization layer.

## 4. Input, output, security, and privacy

- Treat Markdown, YAML, paths, query text, imported metadata, Zotero data, WebKit messages, rendered HTML, CSS, Dialogue records, Critiques, and checkpoint manifests as untrusted.
- Check structured APIs replace shell, SQL, HTML, path, and URL string interpolation where injection is possible.
- Check HTML sanitization, script/navigation blocking, CSS containment, file URL access, and external-link handling.
- Check authorization at the operation boundary, not only in presentation state.
- Check secrets, tokens, bookmarks, private paths, note titles, queries, and research content are absent from source, telemetry, crash output, fixtures, and routine logs.
- Keep Zotero access read-only and database snapshots outside research sources.
- Bound file size, recursion, query work, allocations, retries, timeouts, and concurrent fan-out.
- Check dependency provenance, lock state, licenses, known advisories, and release inclusion.

## 5. Swift safety and error handling

- Inspect reachable `!`, `try!`, implicitly unwrapped optionals, unsafe pointers, unchecked casts, `fatalError`, `precondition`, and indexing assumptions.
- Ensure `try?`, empty `catch`, broad catch, fallback values, and optional returns do not erase errors callers must distinguish.
- Ensure cleanup occurs on success, throw, early return, cancellation, and deinitialization.
- Check value versus reference semantics, identity versus equality, hashing stability, and mutation through shared references.
- Check `Codable` keys, optionality, dates, unknown fields, schema evolution, and backward compatibility against fixtures.
- Check API call sites communicate side effects, ownership, errors, isolation, and non-obvious complexity.
- Verify availability against compiler and deployment target separately; do not infer it from package tools version.

Useful candidate searches, all requiring contextual inspection:

```text
try!  as!  fatalError  precondition  assertionFailure
@unchecked Sendable  nonisolated(unsafe)  Unsafe  withCheckedContinuation
Task.detached  Task {  DispatchQueue  NSLock  os_unfair_lock  sleep  usleep
catch {  try?  print(  NSLog  TODO  FIXME
```

## 6. Concurrency and lifecycle

- Identify the owner and isolation domain for every shared mutable resource.
- Keep UI state on `MainActor` and blocking or CPU-heavy work off it.
- Validate every `Sendable` claim and every value crossing an isolation boundary.
- Treat `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, continuations, and manual locks as proof obligations.
- Give every unstructured task an owner, lifetime, cancellation path, and intended actor context.
- Propagate cancellation through loops, streams, bridges, file work, indexing, and UI teardown.
- Resume continuations exactly once; terminate streams and observers; remove notifications and FSEvent streams.
- Never hold a lock across `await`, perform slow work under a lock, or assume async work resumes on the same thread.
- Check save, watcher, index, selection, Dialogue/checkpoint creation, window, and deallocation interleavings.
- Distinguish shared app services from per-window `AppState`. Check cross-window commit delivery, dirty-buffer conflicts, duplicate repository/watcher/index ownership, and reconciliation between identity/bookmark and workspace-role registries.

## 7. Memory and resource ownership

- Inspect escaping and stored closures, delegates, timers, observers, tasks, streams, WebViews, coordinators, and services for retain cycles.
- Choose `weak` only when disappearance is valid and `unowned` only when lifetime dominance is proved.
- Check file descriptors, SQLite statements/connections, security-scoped resources, temporary files, processes, and signposts close on every path.
- Distinguish bounded caches from leaks and apply explicit eviction where needed.
- Measure suspected growth with appropriate tooling before reporting a performance defect.

## 8. Search, links, indexes, and persistence

- Compare full rebuild with incremental add, edit, rename, delete, and delete/recreate results.
- Check tokenization, normalization, CJK, Unicode, prefix behavior, ranking, snippets, filters, aliases, headings, ambiguity, and broken links.
- Preserve vault scope and stable identity in federated results and persisted state.
- Ensure stale or corrupt derived state can be detected and rebuilt without touching vault content.
- Keep neutral links and transitive connections from becoming philosophical evidence.
- Check persistence versions, migrations, interrupted commits, corruption recovery, and deterministic ordering.

## 9. Interface and accessibility

- Read the complete `Docs/DESIGN_HANDBOOK.md` before judging user-facing behavior.
- Check normal, empty, loading, error, conflict, cancellation, and recovery states.
- Check menu, keyboard, pointer, focus, VoiceOver, Full Keyboard Access, minimum width, text scaling, light/dark, Increase Contrast, Reduce Transparency, and Reduce Motion paths as relevant.
- Do not make hover, drag, color, motion, gesture, or secondary click the only route to a core action.
- Check destructive and consequential actions for clear labels, preview, confirmation, progress, cancellation, and recovery.
- Check SwiftUI/AppKit/WebKit focus, selection, undo, accessibility identifiers, and represented state agree.
- Distinguish Human Review, qualification, Dialogue, attributed Critique, derived Attention, and research evidence visually and semantically.

## 10. Performance and responsiveness

- Define the scenario, metric, build, fixture, hardware, and acceptance threshold before calling behavior slow.
- Check launch, scans, note switching, search, indexing, editor projection, scrolling, Canvas, checkpoint, and Zotero paths for repeated or main-thread work.
- Check SwiftUI observation fan-out, unstable identity, work in `body`, full-corpus recomputation, unbounded tasks, and cache invalidation.
- Use release builds and report p50/p95 with sample count for acceptance claims.
- Never trade exact-source fidelity, revision checks, authorization, correctness, or accessibility for speed.

## 11. Tests and diagnostics

- Cover success, boundary, malformed input, failure, cancellation, deallocation, race, and recovery paths.
- Require regression tests for confirmed defects where practical.
- Prefer deterministic events or clocks to sleeps, live networks, execution-order assumptions, and shared state.
- Keep tests isolated from real Application Support, credentials, bookmarks, Zotero libraries, and research vaults.
- For GUI evidence, inspect and when authorized run `Tools/Scripts/build-qa-app.sh` plus `Tools/Scripts/run-ui-tests.sh` against the disposable fixture copy. Record the current `UITests/ScholiumUITests.swift` coverage and result artifact; do not infer coverage from an old QA note or a test target that merely builds.
- Check test assertions prove externally meaningful behavior and unchanged surrounding bytes where fidelity matters.
- Resolve compiler warnings and static findings or document a concrete justification.
- Keep diagnostics actionable and privacy-preserving; never treat absence of sanitizer reports as proof of safety.

## 12. Packaging and release

- Verify versioning, app and CLI identity, entitlements, sandbox/bookmark behavior, resources, fonts, notices, and generated editor assets.
- Keep the isolated `com.kbmanager.qa` Debug bundle separate from the release artifact. A QA launch cannot establish release configuration, hardened signing, notarization, migration, clean-account access, or distribution behavior.
- Test the packaged artifacts rather than substituting a development run for release evidence.
- Verify signing deeply and strictly; notarize when distribution requires it; do not re-sign a tested distribution artifact after mutation.
- Check clean-account launch, first run, upgrades, legacy migration, permission denial/revocation, offline behavior, and rollback or recovery.
- Check Debug-only behavior, test hooks, private fixtures, absolute paths, and development credentials are absent from release output.
- Report architecture, signing, notarization, accessibility, performance, and clean-account readiness separately; one does not imply another.

# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Current verification snapshot

**2026-09-16 — Note editing reliability:** Scoped checks cover the final Review
save boundary, exact newline Undo/Redo and reconstruction, half-open block
selection, CRLF logical lines, rename autosave admission, inactive-tab external
publication, and replacement-size rejection. Conflict Reload also preserves newer
revisions and byte-distinct input received during its awaited work. The Editor
suite passes 289 tests across 44 files; Core 405 plus three performance tests,
Contracts 92, and Application 165 plus one architecture measurement pass.
The 946-test App run had one invalid synthetic-pointer/animation-timing test;
after replacing it with the existing native click route and waiting for natural
animation completion, that test passed separately with its original caret and
pixel requirements. Static checks, resource reproduction, public-symbol boundary,
Release compilation and bundled-helper checks pass. This is staged verification,
not an uninterrupted green gate. Two disposable 500-Note UI journeys pass: dirty
Review handoff and continued autosave after external rename. QA app/state were
removed; installed-release, IME and human accessibility acceptance remain separate.
Evidence: `.build/note-editing-fix/` and
`.build/editor-history-review/heading-animation-settle.log`.

**2026-09-15 — Beta preparation repository gate:** With Xcode 27.0
(27A5218g), Swift 6.4 and the macOS 27.0 SDK, the complete `verify.sh` run
finished successfully on the versioned pre-tag tree. Documentation authority,
localization, lint, Contracts purity, entitlement and performance self-tests,
Editor typecheck and 43-file/273-test Editor suite, deterministic RDF-1
fixture, 405 Core tests plus three Core performance tests, 92 Contracts tests,
165 Application tests plus one architecture measurement, 929 App tests, the
symbol graph boundary, Release build and bundled-helper checks all passed.
This is repository evidence for the Beta candidate; exact-tag packaging,
artifact checks, clean-account smoke, and human accessibility/interaction
acceptance remain separate evidence classes.

**2026-09-15 — `v0.2.1-beta.1` packaged artifact:** The clean tagged commit
`c251d2122a890e8ec477a074b96821d4dd7bbf24` produced the arm64 DMG
`Scholium-v0.2.1-beta.1-macos-arm64.dmg` with marketing version `0.2.1`, build
`2`, minimum macOS `26.0`, and the version-matched bundled helper and Core
Protocol resources. App/helper signatures, entitlements, architecture,
provenance, package contents, read-only DMG mount/copy, and SHA-256 checksum
passed. The exact packaged first-launch Bootstrap smoke passed with production
machine state unchanged. This Beta is ad-hoc signed and not Developer ID
signed or notarized; human accessibility and interaction acceptance remain
separate open boundaries.

**2026-09-15 — In-app Chat presentation and runtime controls:** Focused slices
report 19 final-panel checks, 29 composer-entry checks, 32 context/message
checks, and 31 Agent-roster checks, with overlapping coverage rather than an
additive total. Xcode 27 Debug builds plus scoped formatting, localization and
documentation validation pass. Disposable 500-Note QA covered English/Light and
Chinese/Dark states, composer focus and draft retention, candidate lists, pending
questions, queued input, Stop, Context, Changes, Agent monitoring and recovery
routes. Some Context inspection attempts closed `SkyComputerUseService`; the
native-disclosure correction was verified, but this remains a tooling boundary,
not a claim that the service is repaired internally. Full Keyboard Access,
VoiceOver, Switch Control, installed IME, complete adaptation and real-provider
acceptance remain open. Evidence is under `.build/chat-sidebar-audit/` and
`.build/agent-roster/`.

**2026-09-15 — Search and staged gate evidence:** Contracts purity, current
Search rendering and system-Trash wording checks pass. A staged gate recorded
405 Core, 3 performance, 92 Contracts, 165 Application and one
architecture-measurement test pass. The 895-test App phase had one retired Trash
wording assertion; after its test-only correction, the 77 Frontend Architecture
tests passed, but the six-minute App phase was not rerun. Release compilation,
symbol-boundary checks and helper protocol isolation passed. This is staged
evidence, not one uninterrupted green `verify.sh` run.

Search contract 20 uses schema 18 and ranking policy 4. The unchanged 2,056-Note
benchmark reports warm-query p95 of 97 ms, first-five-page p95 of 466 ms, and
incremental-publication p95 of 27 ms against the unchanged 100/500/250 ms
budgets. Current Saved Searches use the ordinary parser only; unsupported stored
definitions remain protected and nonexecuting. Paragraph predicates, term-group
insertion, exact ranges, Unicode source preservation, hydration recovery and
App/MCP provenance have scoped evidence. A separate Search integration attempt
hit a Preview Styles `LineLength` failure; the line is fixed and scoped lint
passes, but the complete gate has not been rerun. Evidence includes
`.build/check-blocker-final-integration-gate.log`,
`.build/search-performance-final-correctness.log`,
`.build/search-clean-cutover-tests.log` and
`.build/verification-release/release-build.log`.

**2026-09-15 — Workspace shell and Search presentation:** Focus Layout and the
unified Search entry have bounded scoped checks (18 Focus Layout tests, plus 19
Search-controller and three field/menu-wiring tests, with overlap). Disposable
500-Note QA confirms ordinary/full-screen entry and exit, pane restoration,
retained Document state and the existing advanced Search window. The earlier
layout-dependent Search route is not part of the current surface. Hover-specific
behavior, VoiceOver, IME, conflict/recovery and the complete adaptation matrix
remain open. Evidence includes `.build/fullscreen-focus-final-tests.log`,
`.build/advanced-search-shortcut-tests.log` and
`.build/sidebar-search-simplification-tests.log`.

**2026-09-15 — Library batches and file sheets:** Thirty-eight scoped App and
28 Core tests pass, together with presentation checks for compact, narrow,
partial, unavailable and recovery states. Twenty-two native renders cover
normal/narrow widths, Light/high-contrast Dark and mixed-script paths. Disposable
500-Note QA verified selection, menu/accessibility Move, cancellation,
collision handling, remaining-only retry preparation, retained documents and
window resizing. The native Computer Use connection was then lost, so final
full-app sheet polish, Trash and physical-input routes remain open. Evidence is
under `.build/library-file-operation-final-tests.log`,
`.build/file-operation-final-layout-tests.log` and
`.build/file-operation-review/`.

**2026-09-14 — Note reorganization and editor boundaries:** Scoped Core, App and
Contracts checks cover paragraph anchors, footnote dependencies, exact YAML
choices, reference-scope isolation, resource relocation, dirty conflicts,
source readback and detached WebView save receipts. Disposable-fixture QA
verified paragraph insertion, destination Undo/Redo, preview cancellation,
Merge, incoming-reference following and system-Trash routing. Complete
background-tab insertion, full visual/assistive-technology acceptance and
post-Trash cleanup remain open. Editor candidate/deletion, native document
previews, research sheets and preview-renderer reuse also have bounded focused
evidence; their physical input, IME, VoiceOver and complete adaptation claims
remain open. Evidence includes `.build/knowledge-reuse-fixes-tests.log`,
`.build/preview-perf-tests.log`, `.build/slash-candidates-journey.log`,
`.build/native-research-sheet-tests.log`.

**2026-09-13 — Source safety and App-only delivery:** Late-writer
reproductions preserve exact external bytes and return Recovery Required; 111
selected Core, Application and App-MCP-router tests cover interruption, failed
retention, deferred cleanup, revision-checked restoration and move/Agent Undo.
The App-only cutover also passed its bounded owning tests, helper smoke,
public-symbol checks and a Release build. These are source/fixture and delivery
proof only; installed-release, live sync-provider, packaged external-host and
human Recovery acceptance remain open. Evidence is under
`.build/note-safety-fix/`, `.build/cli-removal-*/` and
`.build/source-cutover/`.

**2026-09-08 — Bounded signed-in Chat loop:** Disposable 500-Note QA with the
official Codex runtime completed one bounded multi-turn read, native approval,
exact Note update, comparison, eligible Undo, restart restoration and Stop; the
Note returned to its starting bytes. This closes CHAT-LIVE-01 and CHAT-LIVE-02
only for that route. Provider breadth, concurrency, packaging and human
accessibility remain separate acceptance boundaries. Evidence:
`.build/agent-chat-evolution/real-loop-retest-*.json`.

**2026-09-07 — Editor syntax continuity:** Editor tests, TypeScript and
resource-reproduction checks, Debug compilation and focused Swift/WebKit checks
pass. Disposable fixture QA covered Callouts, Chinese paste/Undo, disclosure,
Light/Dark and mode switching with byte-identical Undo. Minimum width, system
adaptation, IME, conflict/recovery and human perceptual acceptance remain open.
Evidence: `.build/editor-presentation-*.log`.

## Evidence boundary

These entries retain one representative result for each active proof boundary,
not a per-change transcript. Test counts from separate runs are not additive.
Focused tests, offscreen renders, Debug QA and deterministic fixtures prove only
their named scope; they do not establish packaged behavior, G7/G9,
VoiceOver, Full Keyboard Access, installed Simplified Chinese IME, physical
input or full visual adaptation unless explicitly stated.

Current capabilities belong to [Reachable Capabilities](01-capabilities.md),
user-facing reachability to [Reachable Interface](02-interface.md), and open
implementation or acceptance work to [Open Work](03-open-work.md). Target rules
remain in the Specification set. Superseded task narratives belong to Git
history; `.build` logs are local reproduction pointers, not release artifacts.

# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Current verification snapshot

**2026-09-17 — Derived refresh performance:** The identical expanded standard
500-Note Triptych (6,973,820 bytes; exact source bytes and query provenance
checked) reduces Debug cold configuration from 35.91 s to 13.05 s, reopened
usable state from 10.94–11.03 s to 2.99–3.10 s, completion after the
presentation signal from 17.33–17.45 s to 4.87–4.93 s, and unchanged refresh
from 2.26–2.30 s to 0.750–0.756 s. Reopening restores all 500 Search projections
with no projection recomputation; source authorization and semantic parsing
remain fresh. Source preparation is 2.32–2.38 s. Independent three-sample
index opening falls from 4.74–4.83 s to 2.39–2.50 s while retaining complete
SOM1 validation and corruption recovery. ASCII normalization reduces isolated
projection work by 43.7%; all 501 complete projections match the baseline
with unordered Set encoding canonicalized. Scoped Contracts, Application,
cache, codec and paragraph-recovery checks pass. The current-checkout full
`verify.sh` gate passes 355 Web, 423 Core, three Core performance, 96 Contracts,
171 Application, one architecture measurement and 1,002 App tests, public-symbol
guards, Release compilation and bundled-helper isolation. These schema-19 diagnostics
exclude presentation wait and do not establish packaged performance or native
click-to-paint acceptance. Evidence: `.build/refresh-optimization/`,
`.build/projection-cost/`, and `.build/search-opening-diagnostics/`.

**2026-09-17 — `v0.2.2-beta` packaged artifact:** The clean exact-tagged
commit `ea4918ec1958293879786a889108d0b186d33744` produced the arm64 DMG
`Scholium-v0.2.2-beta-macos-arm64.dmg` with marketing version `0.2.2`, build
`3`, minimum macOS `26.0`, and the version-matched bundled helper and Core
Protocol resources. The exact-tag `verify.sh` run passed 355 Web tests, 410
Core, three Core performance tests, 92 Contracts, 165 Application, one
architecture measurement, and 1,002 App tests, plus resource reproduction,
public-symbol guards, Release compilation and helper isolation. App/helper
signatures, entitlements, architecture, provenance, package contents,
read-only DMG mount/copy and SHA-256 checksum passed. Packaged first-launch
Bootstrap passed with production machine state unchanged. This Beta is ad-hoc
signed and not Developer ID signed or notarized; human accessibility and
interaction acceptance remain separate open boundaries.

**2026-09-16 — Editor state authority:** Xcode 27.0 (27A5218g), Swift 6.4
and macOS 27.0 SDK verification covers detached exact-source persistence,
background Review revision adoption (including NFC/NFD byte differences),
conflict source fidelity, suspension/resume ordering, lost commit-reply replay,
composition request expiry and exact UTF-8 capacity admission. `verify.sh`
passes 355 Web tests, 410 Core, 92 Contracts, 165 Application and 1,002 App
tests, plus four performance/architecture measurements, resource reproduction,
public-symbol guards, Release compilation and bundled-helper checks. Two
isolated 500-Note QA journeys pass: retained native tabs preserve background
saves and external revisions through further editing; dirty external edits
retain exact conflict/recovery behavior. Final copy-only localization changes
pass resource rebuild/typecheck and localization validation. QA app/state are
removed. Installed-release, physical IME and human accessibility acceptance
remain separate. Evidence: `.build/editor-boundary-evidence/`.

**2026-09-16 — Bootstrap simplification:** Xcode 27 Debug compilation and 102
scoped architecture/window-lifecycle tests pass. Two isolated QA journeys pass
for connecting/restoring a 500-Note Triptych and creating a new one after a
non-replacing destination conflict. They cover picker cancellation, retained
Back-navigation input, exact parent authorization, 480-point width, immediate
workspace handoff, relaunch and registration editing. English/Light screenshots
and Chinese/Light Computer Use were inspected; scoped lint, localization and
documentation checks pass. Dark, system adaptations and human assistive-technology
acceptance remain outside this evidence. QA app/state cleanup is recorded with
commands and results in `.build/bootstrap-verification/RESULTS.md`.

**2026-09-16 — Note switching:** Window-local editor-page reuse passes five
native regressions for exact source, Undo/selection isolation, direct replacement,
pool invalidation and unfinished dispatch. Two isolated 500-Note QA journeys pass
for mode/Library handoff and dirty-buffer process recovery. In a Debug synthetic
60-paragraph Edit scenario (2 warmups + 5 samples per path), median attached-editor
preparation falls from 197.438 to 50.358 ms. The boundary includes state capture,
pool clearing, bridge readiness and DOM layout; WebKit throttled frame delivery
in the test host, so no paint latency or Release gate is claimed. Cold startup
and human IME/accessibility acceptance remain outside this evidence.
Details: `.build/note-switch/RESULTS.md`.

**2026-09-16 — Settings performance:** Xcode 27 Debug build and 31 scoped
Settings tests pass. In the same disposable 500-Note, Time Profiler + Hangs
scenario, six warm Appearance selections reduce median hosting-layout CPU sample
weight from 72 to 40 ms; total action-window main-thread weight falls from 225.5
to 200.5 ms. Workspace totals overlap the baseline range. No >250 ms hang is
detected after the change, versus the baseline's 267.9 ms first-Appearance event.
These are sampled Debug measurements, not click-to-paint or Release acceptance.
Computer Use verifies drafts, hidden default-action isolation, active Return
save, Revert, search recovery, sidebar keyboard focus, child selectors, loaded
font menus and English/Chinese Light presentation. The subsequent scoped UI
audit below supplies deterministic interaction evidence. Native containment
tests cover resize and field-editor ownership. Dark and human adaptation
acceptance remain open. Evidence: `.build/settings-performance-fix/`.

**2026-09-16 — Settings UI automation:** After restarting the idle test service,
three scoped XCTest journeys pass separately on the same isolated Debug build.
Navigation covers five categories, drafts, rename/cancel, empty search/recovery,
hidden default actions, sidebar arrows, native 780-point resizing and Chinese
presentation. Notifications covers draft retention, reload cancellation and
confirmed discard, explicit save and relaunch persistence. Selection Actions
covers editor validation/cancel, nested and root hidden-action isolation,
positive search/restore, explicit save, window reopening and relaunch persistence.
Two new journeys are registered in the UI test project. Initial test-only
failures corrected native Outline/title queries and restored a saved QA
preference baseline before repetition. Scoped lint, project syntax and
documentation checks pass. This is staged scoped evidence, not the complete UI
suite or human acceptance. Dark/system adaptations, shortcut conflict recording
and live integration operations remain outside this run. Evidence:
`.build/settings-ui-audit/`.

**2026-09-16 — Settings redesign:** Xcode 27.0 (27A5218g), Swift 6.4
and macOS 27 SDK Debug compilation pass. The 26 scoped Settings tests and one
representative disposable 500-Note UI journey pass. The journey covers category
geometry, retained Appearance and Workspace drafts, rename/cancel, search empty
state and recovery, inactive-page accessibility, disabled Save state, consecutive
sidebar keyboard selection, native resizing to 780 points, and Chinese/Light
alongside English/Dark rendering. It caught and corrected inherited hosting
accessibility context, sidebar focus, and the Settings scene overwriting the
native resizable flag. Scoped lint, localization and documentation checks pass.
Window resizing animation and page reconstruction were removed; no frame-level
speedup or human smoothness acceptance is claimed. VoiceOver, Full Keyboard
Access, IME and system contrast/transparency/motion acceptance remain separate.
QA bundles and temporary state were removed. Evidence: `.build/settings-redesign/`.

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

**2026-09-16 — Chat delivery, preparation and object identity:** Stop and failed
delivery revoke automatic queue advancement; matching completion and delivery
acknowledgement reconcile once regardless of order. Local pre-send saving retains
live edits and uses the same ordered history writer. All material/selection entry
points share conversation-scoped preparation, and failed candidates retain their
query. Rich-object Copy/Expand use renderer-owned descriptors rather than a second
Markdown parse and positional matching. Owning runs pass 30 renderer and 101 Chat
tests; a subsequent 24-test native run overlaps that coverage. WebEditor passes
340 tests and bundle reproducibility. Disposable 500-Note Debug QA verifies failed
selection/query retention, successful Note preparation, independent table/code/
HTML/Mermaid actions, preview dismissal, and Stop with a normal-completion race
retaining its queue. Evidence and final integration results are recorded in
`.build/chat-fixes/verification.md`; installed IME and human accessibility remain
separate acceptance boundaries.

**2026-09-16 — Chat input-area responsibility cleanup:** The input-area owner
now measures queue/dock geometry and anchors candidates to their actual size;
the shell no longer compensates with negative queue padding or estimated popup
height. Submission and composition use the explicitly attached conversation
editor, and request disclosure disables that native editor. Xcode 27 Debug build,
25 focused composer/catalog/dock tests, scoped Swift formatting and documentation
validation pass. Disposable 500-Note QA at a 300-point sidebar covered candidate
resizing and selection, expanded queued input, question completion, Stop and
cross-conversation draft retention. Native tests additionally cover light/dark
request presentation, selection/identity preservation and marked-text callbacks.
Installed IME and full assistive-technology/adaptation acceptance remain open.
The shell's conversation-state lifetime and implicit reader-mode selection
remain separate structural work. Evidence:
`.build/chat-layering/verification.md`.

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

That measured build used Search contract 20, schema 18, and ranking policy 4. Its 2,056-Note
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

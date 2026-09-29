# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Release artifacts and gate provenance

**2026-09-27 — `v0.3.1-beta` packaged baseline:** Exact source commit
`7d77c68ce01231b86619b75487172d13f2053e94` produced
`Scholium-v0.3.1-beta-macos-arm64.dmg` (version `0.3.1`, build `12`, macOS
`26.0`, SDK `27.0`, arm64, ad-hoc). Its SHA-256 is
`a6296c8309b99bd7aea1b1b73f6eb9b8fa8a4207d1ce498225d4dc7fa3fb67ca`. The
[public release record](https://github.com/Aaronlves/Scholium/releases/tag/v0.3.1-beta)
reports the complete performance gate, 13/13 affected UI journeys, and mounted/
copied clean-account save/readback smoke; VoiceOver, input, adaptation, icon,
and Finder-restoration human acceptance remain open.

**2026-09-28 — `v0.3.2-beta` packaged candidate:** Exact clean tag at
`e225a72e5320f195adf154815f9c468e43e6d93a` produced
`Scholium-v0.3.2-beta-macos-arm64.dmg` (version `0.3.2`, build `13`, minimum
macOS `26.0`, SDK `27.0`, arm64, ad-hoc). `verify.sh` passed WebEditor (491),
Core (581), Core performance (3), Contracts (105), Application (236),
architecture measurement (1), and App (1,197); Release build and helper
isolation passed. Package checks passed for provenance, resources, licenses,
icon, private paths, entitlements, signatures, architecture, read-only DMG
mount/copy and SHA-256 `590023c506635c6dc2f539281a744d40d4fded11857307b2bb12ba3be28b48d8`.
Per researcher direction, XCUITest journeys and the mounted/copied clean-account
smoke were not run; affected UI journeys, human icon inspection, and G6/G9
evidence remain incomplete.
Logs: `.build/verification/` and `.build/verification-release/`; local candidate:
`~/Applications/Scholium Builds/v0.3.2-beta/`.

## Current source and native development proof

The following are scoped source/fixture results, not fresh verification of the
documentation simplification. Xcode 27.0 (27A5218g), Swift 6.4 and macOS 27.0 SDK
are recorded for the 2026-09-16 editor/Settings development runs. QA used
disposable standard 500-Note Triptych copies and isolated state; recorded QA
processes, bundles and temporary state were removed.

**2026-09-28 — Changes:** Original `verify.sh` passed all modules (1,195 App
tests/155 suites), localization, lint, RDF determinism, symbol, Release and
bundled-helper checks. Disposable standard 500-Note Triptych English/light Debug QA
covered cumulative English/Chinese source edits, difference navigation, close
without review, explicit review/history, newer pending after history delete/clear,
and This Mac Settings scope, 90-day default, counts and confirmation. Clearing
history left the Note hash unchanged; the test App, fixture copies and isolated
state were removed. Supplementary dark/narrow QA covered comparison, Settings
and keyboard routes. Human VoiceOver, physical input, full adaptation, packaging
and release acceptance remain open. Evidence:
`.build/changes-complete-gate-green-candidate.log`,
`.build/changes-qa-before-clear.sha256`, `.build/changes-qa-after-clear.sha256`.

**2026-09-17 — Inline writing assistance:** Owning mocked-runtime checks cover
independent model/low effort, isolated ephemeral execution, cancellation, cleanup
and bounded literal output. Editor typechecking and 364 tests cover AI-first
preview, unavailable/empty/timeout fallback, late-result rejection, IME suppression
and exact Undo. Eight native/context checks cover unfocused suppression,
source-neutral configuration and revision-bound background. A disposable 500-Note
QA journey verifies Settings search, default off/Luna, retained offline choice and
disable.
No provider generation or private vault was used. SwiftPM's inactive
WebKit host cannot establish native AI acceptance/Undo; real-runtime quality,
quota, IME, VoiceOver and full adaptations remain open.
Evidence: `.build/continuation/`.

**2026-09-17 — Writing References identity/navigation:** Seventeen owning tests
cover BOM/CRLF, exact revision-bound source opening, changed/unreadable/dirty
sources, duplicate titles and all three roles. Seventy-three adjacent navigation/
composition tests pass on recheck; the initial multiwindow external-deletion
timeout also passed isolated recheck. Debug QA verifies normal Source arrival,
visible mismatch feedback/dismissal, same-title directory distinction in
960-pixel Light/Dark windows and role/path AX identity. An earlier scoped journey
also covered Inspector switching, loading/results/empty states, Insert-menu/
Shift-Command-J entry, selection updates, group disclosure, pane/document departure,
Review command availability and unsent Chat staging; 13 state tests cover
late-response cancellation, provenance and complete-result insertion admission.
No private vault or Chat service was used. This does not establish VoiceOver,
physical input, full adaptations or native usable-card latency.
Evidence: `.build/reference-interface-fix-acceptance.md`,
`.build/reference-interface-fix-tests.log`,
`.build/reference-interface-fix-navigation-integration-recheck.log`,
`.build/retrieval-ui-acceptance.md`, `.build/retrieval-ui-state-tests.log`.

**2026-09-16 — Editor authority/recovery:** Deterministic coverage retains detached
exact-source persistence, background Review revision adoption including NFC/NFD,
conflict fidelity, suspension/resume ordering, lost commit-reply replay, composition
expiry and UTF-8 capacity admission. Two native 500-Note QA journeys retain
background saves/external revisions through further editing and dirty external
conflict/Recovery. Earlier scoped checks retain newline Undo/Redo/reconstruction,
half-open/CRLF selection, rename autosave, inactive-tab publication, replacement-size
rejection and newer-input preservation during Conflict Reload; native journeys
covered dirty Review handoff and continued autosave after external rename.
Evidence: `.build/editor-boundary-evidence/`, `.build/note-editing-fix/`.
Syntax-continuity fixture QA (2026-09-07) covers Callouts, Chinese paste/Undo,
disclosure, Light/Dark and mode switching with byte-identical Undo; it does not
establish installed IME, minimum width, full adaptation or human perception.
Evidence: `.build/editor-presentation-*.log`.

**2026-09-16 — Bootstrap:** Bootstrap's 102 scoped lifecycle tests
and two QA journeys cover connect/restore/create, non-replacing destination
conflict, picker cancellation, retained Back input, parent authorization,
480-point width, immediate handoff, relaunch and registration editing.
Evidence: `.build/bootstrap-verification/RESULTS.md`.

**2026-09-17 — Settings:** 61 scoped checks in 14 suites cover bilingual static
search routing, scoped drafts, native fixed-sidebar/toolbar association,
resizing/field-editor ownership, preferences and tool revision/authentication
boundaries, including tool-specific feedback targets. Native normalization QA
covers one system form background, protocol owner navigation and restoration of
the resize mask. Four distinct QA journeys cover seven task categories, retained
drafts, rename/cancel, hidden default actions and accessibility, sidebar arrows,
empty-search recovery, repeated Agent-result and explicit Zotero routing,
automatic H6 reveal, native 780-point resizing, inspected English/Dark and
Chinese/Light titlebar regions, Notifications reload/discard/save/relaunch,
inline Selection Actions validation/cancel/save/reopen/relaunch and disconnected
continuation/model retention. Transactions use the App menu; a separate Computer
Use observation opens Settings with Command-Comma from the focused QA editor.
The beta XCTest literal-comma attempts remain failures, not keyboard proof.
Evidence: `.build/settings-normalization-evidence/RESULTS.md`;
unchanged transaction journeys: `.build/settings-redesign-evidence/RESULTS.md`.
Recovery extensions have 121 owning checks and five distinct native journeys:
corrupt portable settings, scoped appearance repair, reminder draft lifecycle,
category navigation and default-value field repair. Exact backups, unknown-field
retention and unchanged Note bytes are checked. Independent review added a
rollback-writer preservation regression. Evidence:
`.build/settings-recovery-evidence/RESULTS.md`.

**2026-09-22 — Chat response/reading:** Tests cover history batching, stream
publication, WebKit selection, draft measurement and floating-composer geometry.
Synthetic 4,000-message hydration: 10.7s→22–42ms; 200 unchanged-draft sizing probes:
1.027s→13ms. These are microbenchmarks, not provider latency. Narrow Light/Dark
native QA verified input growth/shrink and latest-reply clearance; draft/Find/back
UI verification passed. Ten dark-reader mounts completed.
Evidence: `.build/chat-viewport-final.log`, `.build/chat-reader-dark-scheme-check.log`,
`.build/chat-experience-ui-final.log`.
Earlier delivery/queue/material and native-input proof remains in
`.build/chat-fixes/verification.md`, `.build/chat-layering/verification.md`.
Neither establishes installed-IME, VoiceOver, real inference or researcher visual
acceptance.

**Retained Chat component boundaries:** Deterministic fixtures and inspected
Light/Dark offscreen native renders cover Note/file/image/PDF materials and
selected-page-only delivery, retained draft failure, native clipboard/drop
callbacks, text Undo, questions/secret exclusion, exact Note-update previews,
runtime approvals, branching/retry, concurrent conversation states, Find and
archive actions, plans/context/quota, ancestry-verified Agent history/Stop and
generic notification routing. These inherited component results do not establish
live picker/paste/drop, actual system notifications, provider interpretation,
browser authentication, provider forks/questions/approvals, physical IME or
assistive technology. Installed official-runtime Skill discovery/disable/enable
has isolated local evidence, not inference acceptance.
The 2026-09-15 presentation QA covers English/Light and Chinese/Dark composer,
candidates, questions, queue, Stop, Context, Changes and Agent monitoring;
some Context inspections closed `SkyComputerUseService`. Native disclosure was
corrected, not the automation service's internals.
Evidence: `.build/chat-sidebar-audit/`, `.build/agent-roster/`.

**2026-09-08 — Bounded signed-in Chat loop:** Official-runtime QA completed one
multi-turn read, native approval, exact Note update, comparison, eligible Undo,
restart restoration and Stop; source returned to its starting bytes.
CHAT-LIVE-01/02 close only for this route. Managed Zotero breadth, write-path
acceptance, packaging, prolonged offline/material recovery and human accessibility remain open.
Evidence: `.build/agent-chat-evolution/real-loop-retest-*.json`.

**2026-09-13–15 — Files, reorganization and source safety:** Late-writer
reproductions retain exact external bytes and Recovery Required; 111 selected
tests cover interruption, retention/cleanup failure, revision-checked restoration,
move and Agent Undo. App-only delivery has bounded helper/symbol/Release evidence.
Reorganization fixtures cover anchors, footnotes, YAML choices, reference scope,
resource relocation, dirty conflicts/readback and detached saves; native QA covers
paragraph insertion, Undo/Redo, cancellation, merge, incoming references and
system-Trash routing. Library batch checks (38 App/28 Core) plus 22 native renders
cover narrow/partial/unavailable/recovery states and mixed-script paths; QA covers
selection, Move, cancellation/collision, remaining-only retry, retained documents
and resize. Automation connection loss limits final sheet/Trash/physical-input proof.
Background-tab insertion, post-Trash cleanup, live sync/File Provider/Finder and
human Recovery remain open.
Evidence: `.build/note-safety-fix/`, `.build/source-cutover/`,
`.build/knowledge-reuse-fixes-tests.log`,
`.build/library-file-operation-final-tests.log`,
`.build/file-operation-final-layout-tests.log`, `.build/file-operation-review/`.

**2026-09-30 — Window/Document lifecycle and toolbar tabs:** Earlier 67 lifecycle
tests and four native journeys establish retained pages/shared panes,
background save/external refresh, transfer/return, Find, formatting/Undo, Advanced
Search, exact-source save, close and Focus/full-screen restoration. Shared-base
layout passed 119 toolbar/window/architecture tests. Current 11 toolbar checks
cover continuous compression, unchanged-projection reuse, pointer-menu scope and
listener teardown. One native journey passes on macOS 27.2: right/Control-click
menus without switching selection, targeted background close, native Close,
available-interval centering, English/Chinese titles, Light/Dark, narrow overflow,
horizontal wheel input, core commands, reorder/drag-out, source-window tabs and
Focus. Frame timing, installed IME, human AX, conflict/recovery, full adaptation
and macOS 26 runtime remain unverified by this journey.
Evidence: `.build/tab-editor-port-final-tests.log`,
`.build/toolbar-tabs-native-fixed.log`, `.build/toolbar-tabs-visual-final.log`,
`.build/tab-available-space-tests.log`, `.build/tab-local-monitor-restored-tests.log`,
`.build/tab-native-optimized-acceptance.log`, `.build/tab-native-optimized-preview/`.

## Retrieval quality and useful measurement comparisons

**2026-09-23 — Retrieval:** Related-Content 14/ranking 12: source-line focus,
silent bounded Note preparation; focused eligibility/ranking preserved.
Unit/native checks cover exact capture, cold/prepared/rebuilt equivalence, invalidation,
corruption, cancellation and narrow-source reads.
Synthetic graph ablations preserve stronger unconnected material and improve
tied/selective ranking, without researcher acceptance.
Scorer results remain bit-identical over 8,000 paragraphs with 3/32 terms.
In three paired 500-Note Debug restarts, preparation
reduces foreground median 1.361→0.873 s, with 0.807–0.821 s background work;
paired and 21 prior source/locator results remain identical.
Evidence: `.build/two-layer-retrieval/`, `.build/retrieval-architecture/`,
`.build/retrieval-optimization/`, `.build/recommendation-graph-evaluation/`,
`.build/writing-references-performance/`.
Measurements below exclude editor capture/debounce, link-action preparation and
native publication; they are not G7 or click-to-paint acceptance.

- **2026-09-17 2,000-Note Release harness:** generated multilingual Notes, 16
  paragraphs each, plus Works seed. Configure 37.274 s; first query 2.883 s;
  repeats 2.003–2.012 s versus 3.222–3.256 s immediately before normalization/
  scan protection; varied focus 1.818–2.377 s; selected draft paragraph 2.327 s;
  reopen 5.716 s plus first query 2.786 s. Retention estimate remains 64 MiB;
  all candidates are checked/scored.
- **2026-09-23 500-Note Debug harness:** generated three-role corpus, 16 paragraphs
  per Note; Xcode 27/Swift 6.4. Identical-input warm medians after reopen:
  0.714 → 0.649 s; selected long focus: 1.604 → 1.129 s. Two repeats per
  workload, not p95; all 21 ordered result digests agree. Prepared-scorer medians
  across five samples: 3 terms 101 → 40 ms; 32 terms 593 → 153 ms.
- **Task-authorized 433-Note private-copy evaluation, all roles:** byte-verified
  copy with tests on a second disposable copy. Configure 24.963 s; 20 backend
  queries median/sample p95 1.840/1.975 s versus 2.546/2.731 s immediately before
  native optimization. All 16 private cases preserve ordered results; source
  bytes unchanged. This recorded exception is not standing private-vault authority.
- **Expanded standard 500-Note Debug refresh, schema 19:** 6,973,820 bytes.
  Cold configure 35.91 → 13.05 s; reopened usable state 10.94–11.03 → 2.99–3.10 s;
  completion after presentation signal 17.33–17.45 → 4.87–4.93 s; unchanged refresh
  2.26–2.30 → 0.750–0.756 s. All 500 projections restore without recomputation;
  authorization/parsing remain fresh.
- **2026-09-15 Search benchmark, 2,056 Notes:** schema 18 / ranking policy 4.
  Warm query p95 97 ms, first five pages p95 466 ms, incremental publication
  p95 27 ms against unchanged 100/500/250 ms budgets. A dated measured-build
  result, not current packaged performance.
- **2026-09-16 editor reuse:** synthetic 60-paragraph Debug Edit, two warmups and
  five samples/path. Median attached-editor preparation 197.438 → 50.358 ms,
  including capture, pool clearing, bridge readiness and DOM layout. Throttled
  WebKit frame delivery excludes paint/Release claims.
- **2026-09-16 Settings:** Debug Time Profiler + Hangs, six warm Appearance
  selections. Median hosting-layout CPU sample weight 72 → 40 ms; action-window
  main-thread weight 225.5 → 200.5 ms; no detected >250 ms hang versus baseline
  first-Appearance 267.9 ms. Workspace totals overlap; not click-to-paint.

Synthetic quality cases split 18 development/18 heldout: distinct-material nDCG@6
0.601/0.641 → 0.635/0.717; material recall 0.625 → 0.688/0.750. Agent-authored cases are
not blind validation or researcher acceptance; raw Note recall falls when duplicate
material is represented once. Earlier private aggregate known-useful recall@6 was 0.375;
one earlier ranking change replaces a judged sixth result with unjudged material.
Incomplete pools cannot establish improved/worsened philosophical usefulness.
Agent review of 12 passages in two changed cases finds no coordinate defect and
additional relevant material, not overall precision or researcher acceptance.

The ignored Python/ONNX multilingual prototype yields known-useful recall 0.479,
or 0.500 with fixed lexical/semantic RRF, but 72/96 hybrid results are unjudged and
Chinese-query recall is 0.200. Different paragraph preparation, absent App wiring
and unverified distribution mean this is neither a shipping backend nor full
precision evidence. Private content/paths, judgments, vectors and model assets
remain outside tracked fixtures.

Evidence: `.build/recommendation-evaluation/`,
`.build/recommendation-private-evaluation/`,
`.build/recommendation-native-comparison.json`,
`.build/recommendation-private-native-optimized.log`,
`.build/recommendation-scan-protection-2000.log`,
`.build/recommendation-final-owning-tests.log`,
`.build/recommendation-native-release-build.log`,
`.build/semantic-multilingual-prototype/`,
`.build/writing-references-release-harness/.build/writing-references-performance/`,
`.build/refresh-optimization/`, `.build/search-opening-diagnostics/`,
`.build/search-performance-final-correctness.log`,
`.build/note-switch/RESULTS.md`, `.build/settings-performance-fix/`.

## Evidence boundary

Compilation, deterministic tests, offscreen renders, exploratory Debug QA,
measurements, packaged smoke and human acceptance establish different claims.
Test counts are not additive. No development entry closes VoiceOver, physical Full
Keyboard Access, installed Simplified Chinese IME, complete visual adaptation,
G7/G9 or packaged external-host acceptance unless explicitly stated.
[Open Work](03-open-work.md) owns remaining limitations; the
[status entry](../IMPLEMENTATION_STATUS.md) summarizes reachability. Superseded
task narratives belong to Git; local `.build` pointers are not release artifacts.

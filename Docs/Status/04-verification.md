# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Release artifacts and gate provenance

**2026-09-17 — `v0.2.4-beta` packaged artifact:** Exact clean tag at
`f3d10cf6b4da3411418502d4a48c711c6ef92ed1` produced
`Scholium-v0.2.4-beta-macos-arm64.dmg`: marketing version `0.2.4`, build `5`,
minimum macOS `26.0`, SDK `27.0`, arm64 ad-hoc-signed App and version-matched
helper. Repository gate passed WebEditor (364), Core (499), Core
performance (3), Contracts (96), Application (201), architecture measurement
(1), and App (1,043 across 128 suites), plus public-symbol guards, Release
compilation and helper isolation. Resource, license, private-path, provenance,
nested-signature, entitlements, architecture, read-only DMG layout and SHA-256
checks passed; checksum:
`57948b121745fc28801237cbed3726ba78870c146d944ff8f5f917f2eb5ffa0c`.
Packaged clean-account Bootstrap smoke was attempted three times; XCTest
failed before launch on the first two with `Timed out while enabling automation
mode` (65.761 and 65.222 seconds), then passed on the third attempt in 7.621
seconds with production state unchanged. G9 passed; the first two remain
environment evidence, not product failures. Evidence:
`.build/package-v0.2.4-beta.log`,
`.build/package-v0.2.4-first-launch.log`,
`.build/package-v0.2.4-first-launch-retry.log`,
`.build/package-v0.2.4-first-launch-retry-2.log`,
`.build/release-0.2.4-preflight.log`, `.build/verification/` and
`.build/verification-release/release-build.log`.

**2026-09-17 — Earlier clean-account baseline, `v0.2.2-beta`:** Exact clean tag
at `ea4918ec1958293879786a889108d0b186d33744` produced
`Scholium-v0.2.2-beta-macos-arm64.dmg`: marketing version `0.2.2`, build `3`,
minimum macOS `26.0`, arm64 App and matched helper/Core Protocol resources.
Exact-tag `verify.sh` passed 355 Web, 410 Core, three Core performance, 92
Contracts, 165 Application, one architecture measurement and 1,002 App tests,
resource reproduction, public-symbol guards, Release compilation and helper
isolation. Signatures, entitlements, architecture, provenance, package contents,
read-only mount/copy and checksum checks passed. Packaged first-launch Bootstrap
passed with production machine state unchanged. This earlier pass is retained
as a baseline, not substituted for `v0.2.4-beta` G9. Both artifacts are ad-hoc
Beta packages, not Developer ID/notarized releases or human acceptance.

## Current source and native development proof

The following are scoped source/fixture results, not fresh verification of the
documentation simplification. Xcode 27.0 (27A5218g), Swift 6.4 and macOS 27.0 SDK
are recorded for the 2026-09-16 editor/Settings development runs. QA used
disposable standard 500-Note Triptych copies and isolated state; recorded QA
processes, bundles and temporary state were removed.

**2026-09-17 — Inline writing assistance:** Owning mocked-runtime checks cover
independent model/low effort, isolated ephemeral execution, cancellation, cleanup
and bounded literal output. Editor typechecking and 364 tests cover AI-first
preview, unavailable/empty/timeout fallback, late-result rejection, IME suppression
and exact Undo. Eight native/context checks cover unfocused suppression,
source-neutral configuration and revision-bound background. A disposable 500-Note
QA journey verifies Settings search, default off/Luna, retained offline choice and
disable. Gate components completed: 481 Core plus three performance, 96 Contracts,
183 Application plus one architecture measurement, 1,022 App tests, public-symbol
guards, Release compilation and helper isolation. An unrelated Zotero fixture
timeout passed isolated recheck and full Core rerun before gate continuation.
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
The complete source gate passed 364 Web, 494 Core plus three performance,
96 Contracts, 191 Application plus one architecture measurement and 1,038 App
tests, public-symbol guards, Release compilation and helper isolation.
These are scoped development results, not the complete UI suite or human
VoiceOver/Full Keyboard Access/installed-IME/system-adaptation acceptance.

**2026-09-16 — Chat delivery/composer:** Owning renderer/Chat checks cover Stop/
failed-delivery queue revocation, completion/acknowledgement ordering, ordered
pre-send saving, conversation-scoped material preparation and renderer-owned rich
object actions. Native 300-point-sidebar QA covers candidate resizing/selection,
expanded queue, question completion, Stop and independent drafts; additional
fixtures cover Light/Dark requests, marked-text callbacks and object actions.
Evidence: `.build/chat-fixes/verification.md`,
`.build/chat-layering/verification.md`.
That input-area proof did not establish shell conversation-state lifetime or
implicit reader-mode selection correctness; no new debt conclusion is inferred.
The 2026-09-08 input correction's 106 owning checks and simulated-runtime journey
retain whitespace geometry, wrapping, Return/Shift-Return, marked-text dispatch,
blank clicks, caret, Undo, drafts, disconnected Return and multiline sending.
This is not installed-IME or real inference acceptance.

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
CHAT-LIVE-01/02 close only for this route. Provider breadth, concurrency,
packaging, prolonged offline/material recovery and human accessibility remain open.
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

**2026-09-15 — Shell/Search:** Focus Layout/Search owning checks and native QA
cover ordinary/full-screen entry/exit, pane restoration, retained Document state
and the existing advanced Search window. Hover, physical input, IME, human AX,
conflict/recovery and full adaptation are not established.
Evidence: `.build/fullscreen-focus-final-tests.log`,
`.build/advanced-search-shortcut-tests.log`,
`.build/sidebar-search-simplification-tests.log`.

## Retrieval quality and useful measurement comparisons

**2026-09-17 — Graph retrieval:** Related-Content contract 12/ranking 10 passes
20 generated graph, ranking, runtime and English/Chinese explanation checks.
Evidence: `.build/graph-retrieval/graph-final-focused.log`. Two-step paths refine
matching paragraphs; no real-vault, native interaction or researcher usefulness
acceptance is established.
Complete repository gate and Release compilation pass:
`.build/graph-retrieval/repository-gate.log`.

**2026-09-17 — Lexical baseline:** Search schema 21 and Related-Content
contract 11/ranking policy 9 have 62 scoped retrieval checks and unchanged outcomes
for all 36 frozen synthetic cases after native-only normalization/projection reuse.
The Release App compiles without model/inference-runtime dependencies; this is
not packaging or native interaction acceptance. Measurements below are backend
harness/Debug samples unless stated, excluding editor capture/debounce, link-action
preparation and native publication; they are not G7 or click-to-paint acceptance.

- **Current 2,000-Note Release harness:** generated multilingual Notes, 16
  paragraphs each, plus Works seed. Configure 37.274 s; first query 2.883 s;
  repeats 2.003–2.012 s versus 3.222–3.256 s immediately before normalization/
  scan protection; varied focus 1.818–2.377 s; selected draft paragraph 2.327 s;
  reopen 5.716 s plus first query 2.786 s. Retention estimate remains 64 MiB;
  all candidates are checked/scored.
- **Earlier three-role baseline, same fixture:** schema 20 / Related ranking 8.
  Configure 33.162 s; first query 3.179 s; repeats 2.794–2.808 s; reopen 4.379 s
  plus first query 3.188 s; varied focus 2.306–2.924 s; selected 50-paragraph draft
  focus 3.336 s. Scenario samples, not p95; the Release harness excludes App
  tests using Debug-only helpers.
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
0.582/0.598 → 0.601/0.641; material recall stays 0.625. Agent-authored cases are
not blind validation or researcher acceptance; raw Note recall falls when duplicate
material is represented once. Private aggregate known-useful recall@6 stays 0.375;
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

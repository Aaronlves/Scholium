# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Dated proof and its limits.

## Current verification snapshot

**2026-09-08 — native sidebar layout cleanup:** Sidebar-owned container/content
insets replace the old Library aliases into the peripheral editorial grid. The
header label owns a wider full hit region and native typography; plain Buttons
and Menus use one system secondary-label role with inherited tint reset. The
custom header pointer/press painter and active-state parameter are removed.
A disposable identical-symbol comparison exposed the borderless menu rendering
difference before choosing the native plain path; all probe code was removed.
The workspace navigator uses AppKit `fillEqually`, replacing manual per-segment
widths that added to native chrome and overflowed the visual container edge.

The final 98 owning presentation/architecture checks pass. QA at a 300-point
sidebar covers light/dark Chat list/detail, aligned text/container tracks,
full-row whitespace activation, the enlarged archive-menu hit region, native
menu open/Escape, selected-mode disabled controls and cancellation. The corrected
navigator and Search edges were visually checked in dark mode. Existing QA
conversations remain available; the QA is retained for feedback. An attempted
wider-sidebar drag did not change the divider, so it is not wider-layout proof.
The compose symbol subsequently received a body-scaled half-point drawing
correction left/up within the unchanged header hit area. Symbol and screenshot
bounds informed this correction; dark QA checked its pairing with archive and
ellipsis. The 98 owning checks pass in `sidebar-optical-tests.log`.
Full VoiceOver, increased contrast/transparency/motion adaptation and whole-app
acceptance remain open. Evidence: `.build/chat-refinement/native-sidebar-tests.log`,
`native-sidebar-build.log`, `native-sidebar-qa.log` and Computer Use observations.

This is a record of reported execution on the named dates, not proof that a
later worktree passes. Test counts overlap and must not be summed. Logs are
local reproduction pointers, not release artifacts. Current capabilities belong
to the reachable chapters and outstanding acceptance to Open Work.

### Chat and current whole-app boundary — 2026-09-07–08

- **2026-09-08:** 136 owning checks passed for connection discovery, archive/
  restore, archived send exclusion, receipt retention and shared header actions.
  Disposable QA covered connection/Settings state, calendar-day groups, archive
  selection, read-only archive detail, restore and conversation-scoped Agent
  Changes. Logs: `.build/chat-refinement/chat-lifecycle-tests.log` and
  `lifecycle-final-qa.log`; exploratory Computer Use supplied UI observations.
- **2026-09-07:** 116 activity/file-feedback checks covered typed reads, no-op
  updates, edits, exact receipts, stop/reconnect and mutation admission. Live
  fixture MCP calls preserved two no-op Notes and rejected a stale update.
  Navigation refinement also reported 116 checks, then 97 presentation checks
  and 12 composer checks; these are overlapping runs. QA covered list/detail,
  continued work after Back, Stop, permission, file popover, exact comparison,
  long replies and Light/Dark at 1000/1100pt. Logs:
  `.build/chat-refinement/composer-final-tests.log`, `composer-qa.log`,
  `composer-localization.log`, and `qa-source-proof.json`.
- **Initial client integration, 2026-09-07:** 103 native-conversation and 35
  adjacent checks passed, plus the final menu-route check. Unsaved-selection
  handoff preserved Unicode, BOM, CRLF, editor generation and Undo. Installed
  Codex 0.153.4 passed isolated handshake, account/model queries and thread
  creation without inference. A deterministic runtime exercised streaming,
  steering, cancellation and reconnect. Disposable 500-Note QA exercised real
  App MCP create/update, Ask approval, comparison and byte-identical Undo;
  selection attachment, right Inspector Outline, persistence, bilingual text,
  long replies and 1000–1380pt windows were inspected.
- **Whole-app attempt, 2026-09-07:** static/resource checks, 348 Core tests,
  62 Contracts tests, 126 Application tests and architecture measurement passed.
  Search timing initially exceeded two thresholds; all three performance checks
  passed an isolated repeat at unchanged thresholds. The 637-test App run
  reported 21 issues. Focused import, file-selection and translation repairs
  passed; document scroll, editor projection/bridge and WebKit localization
  failures remained. This is not a passing full gate.
- Release App/CLI compilation and public-symbol validation passed separately;
  Release CLI seven-tool discovery, absent-App refusal and malformed token
  rejection passed. UI-test callers compiled with Xcode 27 beta; compilation
  is not an executed UI journey. Integration logs: `.build/codex-integration/`
  and `.build/verification/`.

Chat QA used deterministic runtimes and nonprivate disposable Triptychs, not
signed-in model inference. Real provider execution, human VoiceOver/IME and
complete adaptation remain unaccepted. Retention of a QA app for researcher
feedback was a dated session arrangement, not a claim about a currently running
process.

### Editor and source interaction

**2026-09-07 syntax continuity —** 228 editor tests, TypeScript/resource reproduction,
Debug App/test compilation, and 16 Swift/WebKit checks passed on Xcode 27 beta
(27A5218g). Fixture QA covered Callout placement, Chinese paste/Undo, disclosure,
Light/Dark, doubled text and mode switching; Undo restored identical bytes. Evidence:
`.build/editor-presentation-*.log`.

**2026-09-06 opening/title readiness —** Four regression checks passed. A 25-second QA
recording (1,427 decoded frames) had no YAML OCR hits during switching;
upward-scroll/reopen checks passed. A four-opening probe reported roughly 60ms
additional warm latency. This is neither a timing gate nor proof against every
compositor race. Evidence: Original opening-readiness QA and task observations; no
independent log path was recorded in the prior status..

**2026-09-05 syntax activation —** 219 Web/resource tests and 100 distinct focused
native checks passed, including construct boundaries, composition deferral, Callouts,
footnotes and 200% text. Keyboard QA preserved exact Markdown through autosave.
Evidence: `.build/syntax-presentation/`.

**2026-09-05 heading input —** 218 Web/resource tests and three WebKit checks passed;
keyboard QA (22.433s) covered entering/leaving headings, marker deletion and Undo.
Evidence: `.build/heading-editing/`.

**2026-09-05 completion —** 99 focused checks and a 32.531s QA journey passed for
retained native host, autosave, pointer/keyboard acceptance, Undo/Redo, Escape and
bounded geometry. Evidence: `.build/completion-refinement/`; earlier
`.build/floating-choices/`.

**2026-09-05 floating surfaces —** 142 focused native checks, 217 Web/resource tests and
five UI journeys passed for Find, completion, notification placement, Search and
footnotes. An old DOM assertion stopped that full-gate attempt; its correction was not a
rerun of the gate. Evidence: `.build/liquid-glass/`.

**2026-09-05 formatting routes —** 42 Swift/WebKit checks and 214 Web tests in 38 files
passed for unobscured selection, native formatting dispatch and mode transitions.
Evidence: `.build/editor-formatting-removal/`.


The 2026-09-07 geometry probes settled animations before measuring; they do not
establish motion timing. Its minimum-width, system adaptations, conflict/
recovery, installed-IME and human perceptual acceptance remain open. Older
passes cover only their named source and interaction, not later editor changes.

### Native shell, Search, Metadata and Settings

**2026-09-06 toolbar/Search —** 87 tests in eight suites; UI journeys for no-document
availability (21.322s) and quick/advanced query handoff (41.820s). Evidence:
`.build/native-toolbar-search-owners.log`, `native-toolbar-search-ui.log`,
`native-toolbar-search-final-build.log`.

**2026-09-06 Library/Search —** 77 tests in six suites; 33.690s Search journey for
composition, query retention, opening and close. Evidence:
`.build/sidebar-owning-tests.log`, `.build/sidebar-ui-test.log`.

**2026-09-06 continuous Metadata —** 11 tests in four suites; disposable 500-Note QA at
980pt covered Light/Dark, native Tab order, Escape, field departure, invalid drafts,
conflict/reload and persistence. Earlier 29 link-navigation checks overlap. Evidence:
`.build/continuous-metadata-tests.log`, `continuous-metadata-build.log`,
`continuous-metadata-localization.log`, `inspector-final-tests.log`,
`inspector-reader-tests.log`.

**2026-09-06 notification tracking —** Six focused checks; native clipping probe and QA
scrolling. Evidence: Original task Computer Use and native probe; no separate log path
recorded..

**2026-09-06 notification delivery —** 48 checks for authorization, denial, coalescing,
cancellation, exact routing and nonreplayed cold handoff. Fixture QA included
Light/Dark, 500pt width, local errors and focus. Real OS permission/click delivery and
human adaptation were not established. Evidence: Original notification task checks and
Computer Use observations..

**2026-09-06 Appearance/Settings —** Configuration reload, invalid/stale edits,
YAML/Undo and managed About checks passed. A reported complete repository run included
609 App tests, public symbols and Release compilation; later changes and failures
supersede it as a current gate claim. Evidence: Original Appearance task verification;
no independent log path recorded..

**2026-09-06 Settings follow-up —** 44 owning tests and 24 overlapping spacing checks;
seven-pane QA, and researcher acceptance of top-left pane animation. No full-gate
repeat. Evidence: Original Settings task and Computer Use observations..

**2026-09-05 Library file actions —** 115 tests and 27.819s organization journey covered
filters, native row size, contextual Move and cancellation with identical source.
Evidence: `.build/sidebar-refinement-logs/`.

**2026-09-05 native command adapters —** 100 checks and four QA journeys covered Find,
menus, information, default/disabled/destructive and cancellation. These establish that
dated adapter behavior, not conformance to the later native-design decision. Evidence:
`.build/button-consolidation/`.


Metadata's earlier QA included interfaces later removed; it does not establish
the current complete Inspector. Earlier Sidebar Outline and vertical-workspace
navigator journeys are superseded as shell-layout proof by the Chat/right-Outline
and segmented-workspace changes. Their historical task logs remain in Git's
prior document revisions. Human accessibility remains separate from all runs.

### Research-record removal and preceding integration boundaries

**2026-09-07:** 106 focused checks passed for Search, window/router, localization,
MCP and scene ownership. Later interface-repair runs reported 105 checks plus
four follow-ups (108 distinct overall), and residue removal reported 83 initial
and 136 final checks with overlap. Disposable QA checked ordinary Works Note
search, native Metadata input and Links, annotation navigation, frontmatter Undo
and opening readiness. Logs: `.build/records-removal/`, `.build/interface-repair/`
and `.build/residue-cleanup/`.

That complete verifier stopped after 347/348 Core tests: a generated-state
corruption fixture reported `couldNotExecuteSQL` concurrently and passed alone;
the cause was unconfirmed. The later Chat whole-app attempt above is the current
broader evidence boundary, not a retroactive pass for this source.

**2026-09-05:** a prior integration passed Web/resource and static guards,
351 Core plus three performance checks, 65 Contracts and 128 Application tests.
It stopped on four obsolete App assertions; the corrected App run passed
591 tests in 44 suites, with public-symbol and Release checks separately.
It was not one clean gate invocation. Logs: `.build/interface-repair-logs/`.

None of these records establishes packaged distribution, G7, physical Full
Keyboard Access, installed Simplified Chinese IME, VoiceOver or full visual
adaptation acceptance. Profile-specific open work remains in its owning chapter.

# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Latest dated proof boundary.

## Current verification snapshot

**Environment:** 2026-09-03 final fixed-index Research Records redesign and
originating-window attachment-routing snapshot, Xcode 27 beta toolchain
(`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`).

The complete repository gate was rerun after the Design-authoritative Research
Record redesign and exact originating-window routing fix. It established
automated evidence for strict portable storage, reference/currentness
validation, provider-separated Search, the ten-tool MCP surface, bounded Record
read/write/correction routes, the fixed-index/centered-reading composition,
single-line horizontal Note attachments, exact source-workspace routing, and
the retained Agent Change exact-source behavior.

Completed automated checks in this worktree:

- Web editor TypeScript checking and 208 tests in 38 files passed. Reader, editor,
  mathematics, and Mermaid bundles were rebuilt through the repository
  toolchain, and bundle reproducibility passed.
- Swift package tests passed: Core 344 tests in 36 suites, Core performance 3
  tests in 1 suite, Contracts 65 tests in 12 suites, Application 125 tests in
  17 suites, and the Application architecture measurement 1 test in 1 suite.
- The complete App suite passed after final localization cleanup: 548 tests in
  43 suites. Research Record coverage proves strict JSON round trips, append
  and correction history, damaged-file isolation, stale Note/Record rejection,
  restart persistence, independent provider results/generations, all ten MCP
  schemas and routes, no Agent Change for Record writes, bounded Markdown
  projection, native Search, semantic collection selection, minimal horizontal
  attachment controls, fixed originating-workspace route identity, exact
  attachment routing with no fallback Workspace creation, and a Record surface
  with no toolbar, content editor, or detached evidence rail. Retained coverage
  also proved that exact Agent Change evidence
  survives store reopening, that sequential updates remain independent rather
  than cumulative, that a body update exposes the removed blank line and
  inserted text, that direct Undo restores each byte-identical Before source,
  and that a superseded or undone ending is an Earlier Revision.
- The public-symbol graph boundary, documentation authority and local-link
  validator, interface localization validator, bundled-Skill validator,
  resource and retired-surface residue guards, and `git diff --check` passed.
- The Release product build passed in 131.40 seconds.
- Exploratory Computer Use opened the rebuilt isolated QA App with 18 live
  Notes, 14 Records containing 56 attributed steps and four corrections, plus
  32 retained Agent Changes. It visually confirmed the compact 980 × 720 window,
  hidden title-bar plane with no toolbar band, fixed 288-point index, 4-point
  grid rhythm, selection without a leading stripe, pinned question, and
  step-local single-line Note buttons with horizontal overflow. Activating an
  attachment opened the bound current Note, closed Records, and returned to the
  same exact `scholium-main` window identifier observed before opening Records;
  no second Workspace window was created. Escape dismissal also passed. This is
  direct exploratory evidence, not a deterministic XCTest or human acceptance
  result.
- The first complete-gate attempt encountered one transient
  `couldNotExecuteSQL` in the typed generated Search-state corruption recovery
  test. The exact test then passed alone, and the fresh complete gate passed the
  same test within all 344 Core tests. No production Search code changed in this
  work.
- On 2026-09-03 the two exact-comparison presentation tests and the focused
  palette snapshot/contrast and semantic-role architecture tests passed.
  `build-qa-app.sh` syntax validation and `git diff --check` passed. A fresh
  disposable fixture opened one coherent workspace instead of the former
  settings-only Bootstrap failure.
- On 2026-09-03 the locked Web editor toolchain typechecked, passed 211 tests in
  38 files, and rebuilt the Editor and Reader bundles. Focused WKWebView tests
  proved both Command-before-pointer and pointer-before-Command Edit previews,
  a previewable link inside an inactive Callout, visible armed-link feedback,
  Review/Edit annotation hover, keyboard focus, click retention and Escape,
  zero-line-height superscript geometry, unchanged document height, and no
  inline annotation panel. Focused renderer, localization, and presentation-
  ownership tests also passed. The complete gate attempt passed 347 Core tests,
  then stopped when the first-five-page Search microbenchmark measured 513.14
  ms against its 500 ms threshold; the same isolated three-test performance
  suite passed immediately afterward at 488.99 ms without a Search change.
  Contracts passed 64 tests, Application passed 127 tests plus its isolated
  architecture measurement, the public-symbol graph boundary passed, and the
  Release build passed in 195.61 seconds. The 564-test App run passed the new
  link and annotation coverage but ended on the existing long bridge matrix's
  narrow 200% projection timeout; that exact bridge test passed alone. This is
  not recorded as a clean complete-gate pass.
- On 2026-09-03 the footnote authoring and presentation slice advanced the
  editor bridge to version 20. The locked editor toolchain typechecked, passed
  213 tests in 38 files, and reproduced the Editor, Reader, mathematics, and
  Mermaid resources. Focused native tests passed for the typed commands,
  configurable shortcuts, named/inline rendering, presentation ownership, and
  Review preview/navigation/return. Focused Edit WKWebView journeys proved that
  named and inline locators preview rendered current-buffer definitions by
  pointer or focus without line reflow or source mutation, that named locator
  activation still reaches its exact definition, and that Inline Footnote wraps
  one selection in one generation with the expected selection and Undo label.
  The complete gate passed its authority/resource checks, editor tests, RDF-1
  fixtures, and all 347 nonperformance Core tests, then stopped when the
  pre-existing Search first-five-pages microbenchmark measured 561.40 ms
  against its 500 ms threshold. One isolated rerun measured 522.69 ms and also
  failed; no Search code changed in this slice. The standalone localization
  validator recognized every new footnote string but still reports seven
  pre-existing missing Research Record interface entries. This is not a clean
  complete-gate pass.
- On 2026-09-03 the focused Edit/Review layout correction retained CodeMirror's
  exact `break-spaces` behavior while replacing terminal-style arbitrary prose
  breaks with strict language-aware wrapping. The locked frontend passed all
  213 tests in 38 files and reproduced its four generated resources; all 102
  editor and Review WKWebView tests, 23 safe-renderer tests, and 86 frontend-
  architecture tests passed. The WebKit journeys proved document-start mode
  changes retain the filename title, inactive ATX markers have zero width while
  the active line exposes exact source, one inserted space has immediate
  measured effect, and a generated footnote locator cannot separate from its
  following punctuation. A follow-up journey proved that transferring focus
  from each H1–H6 body heading to the filename title hides its retained marker
  without changing source or dirty state. Documentation authority validation and
  `git diff --check` passed. Exploratory isolated QA confirmed the visible
  title, heading alignment, active-source transition, and paired footnote
  locator/punctuation; this is not human acceptance.
- On 2026-09-04 the caret-local repeated-space correction started from committed
  baseline `dc0a25c`. The locked frontend typechecked, passed 213 tests in 38
  files, and reproduced all four generated resources; all 102 editor WKWebView
  tests and 86 frontend-architecture tests passed. The focused WebKit journey
  proved that Edit uses natural start alignment and that adding a second
  internal prose space retains nonzero authored measure without introducing a
  visible whitespace marker, moves the neighboring word at the tested soft-wrap
  boundary, and preserves exact source. Selecting and deleting that extra space
  restores the word's exact pre-edit coordinates, alignment, and source without
  residue.
- On 2026-09-04 the Review-referenced Edit rhythm slice passed 190 focused
  mode-contract, frontend-architecture, and editor/Review WKWebView tests. The
  fixed catalog found no must-match local geometry differences; focused journeys
  preserved heading and quotation prose coordinates while exact active prefixes
  remained editable outside the measure, and retained one stable line box
  through blank-line entry, input, deletion, and exit. The locked frontend again
  typechecked, passed 213 tests, and reproduced all four generated resources.
  The complete gate passed documentation, resource, RDF-1, Core 347 plus 3
  performance tests, Contracts 64, and Application 127 plus its architecture
  measurement, then stopped because the unchanged WebKit localization test
  expects 100 entries while both current and committed catalogs contain 99.
  A focused QA mode-switch journey also stopped during fixture preparation
  because its disposable Triptych lacked `.scholium/identities.json`; it did not
  reach or judge the interface, and cleanup removed the QA process and bundle.
- On 2026-09-04 the philosophy-manuscript rhythm correction passed the locked
  213-test Web editor suite with reproducible generated resources and all 190
  focused mode-contract, frontend-architecture, and editor/Review WKWebView
  tests after the final blank-row correction. The fixed catalog reports no
  must-match difference: semantic block order,
  local line geometry, wrapping, visible starts, typography, and colors match,
  while cumulative vertical position is bounded by one prose row per authored
  blank line. The dedicated transition test measured a stable 29.47-pixel
  blank row through entry, first input, deletion, and exit and verified that
  its bottom never crosses the following row's top. All H1–H6 active source
  markers retain their heading's computed size. The body mix retains 10.86:1
  Light and 10.09:1 Dark contrast against Paper. The one complete
  repository-gate attempt passed documentation/resource/RDF checks,
  Core 347 plus 3 performance tests, Contracts 64, and Application 127 plus its
  architecture measurement, then stopped in the 574-test App run solely at the
  pre-existing localization assertion that expects 100 entries from unchanged
  99-entry English and Simplified Chinese catalogs; no Release build followed.
  A rebuilt isolated QA App opened the disposable `QA Autosave A` fixture in one
  workspace window without Bootstrap. This is automated and exploratory
  evidence; the researcher's visual acceptance remains pending.
- The affected macOS UI-test journey entered its test method and completed
  Settlement plus one MCP update. After synthetic Agent Changes activation,
  XCTest observed a disabled main window but neither rendered nor exposed the
  attached sheet, so the journey failed before comparison and Undo assertions.
  Exploratory Computer Use on the same isolated build rendered the red/green
  unified comparison and exposed change kind, exact line content, blank-line,
  line-number, and line-ending accessibility semantics. This observation is
  neither a deterministic UI pass nor human acceptance.
- On 2026-09-04 the Note-level document-attachment slice passed the locked
  214-test Web editor suite with reproducible Editor/Reader resources; 41
  focused protocol, localization, Quick Look, and Editor/Review WebKit tests;
  the Application source-neutral/stable-identity operation test; and the Core
  copy, availability, rollback, media-rejection, and symlink-containment tests.
  Editor projection retained exact source, generation, dirty state, title DOM,
  caret, and Undo; Review retained its page and scroll. Native Quick Look
  released its access lease and restored the retained focus target. An isolated
  nonprivate QA build showed the bounded middle-truncated capsule in Light and
  Dark appearances and the non-shifting Add control after returning to a
  retained Note; the title caret remained in place. This is automated and
  exploratory evidence, not human visual or assistive-technology acceptance.
  The complete repository gate was run once and reached the App suite, where
  it exposed stale ownership inventories, a title-less Review parity fixture,
  and a projection-settling pointer test. Each affected contract now passes
  its focused test, including the complete Edit/Review presentation matrix;
  the complete gate was not repeated under the repository's single-run rule.
- On 2026-09-04 the Sidebar command and activation-cursor slice passed 174
  focused App tests across Library projection, interface presentation,
  frontend/window ownership, and native toolbar suites. A newly seeded
  `Attachments` root remained absent from the Library while an exploratory
  isolated QA launch showed Search then the nonnumeric Accent-dot Notifications
  bell at the trailing side of the Scholium wordmark; the toolbar omitted Agent
  Changes with an empty local change store. The QA process was quit and the
  generated bundle/fixture state moved to Trash after inspection. The
  deterministic smoke journey did not enter
  its test method because XCTest timed out while enabling system automation
  mode; its result bundle records an initialization failure rather than an App
  assertion. Documentation authority and `git diff --check` passed. The
  standalone localization validator still reports the seven pre-existing
  Research Records entries already named above, so no clean complete-gate claim
  is made for this slice.

## Evidence boundary

No clean-account Codex or Claude Code ten-tool smoke, packaged-artifact bridge
smoke, deterministic Records/Agent Changes UI journey, VoiceOver, Full Keyboard
Access, Simplified Chinese IME, Finder, notarization, distribution, or human
acceptance has run for this redesign. Passing local automated and exploratory
checks does not establish those claims.

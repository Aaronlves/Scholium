# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Latest dated proof boundary.

## Current verification snapshot

**2026-09-07 — editor syntax continuity (focused, not release acceptance):**
228 editor tests, TypeScript checks, deterministic bundle reproduction, and
SwiftPM Debug App/test compilation pass with Xcode 27 beta (27A5218g).
16 scoped Swift/WebKit checks pass, including the complete syntax-catalog
Review/Edit geometry baseline, exact-source retention, Callout text placement
and continuation, heading/quotation reveal, and composition deferral. Geometry
probes explicitly settle local animations; they do not establish frame timing.
Disposable standard Triptych QA supplemented with a synthetic syntax Note
confirms direct Callout text placement, Chinese paste and Undo, disclosure,
Light/Dark presentation, doubled body font size, and menu/toolbar mode switching.
The edited fixture returns to identical bytes after Undo. The final role-label
presentation was inspected in Light appearance. This is exploratory Computer
Use evidence, not a perceptual animation, installed-IME, or accessibility pass.
Minimum-width, Increase Contrast,
Reduce Transparency, Reduce Motion, and conflict/recovery runtime acceptance
remain open for this change. Logs: `.build/editor-presentation-*.log`.

**2026-09-07 — question-centered Works cutover:** standalone research-record
presentation, storage, search federation, contracts, and Agent tools are removed.
Research content uses ordinary Works Notes; no migration, export, compatibility
adapter, or automatic recording path was added. Search contract is 16 and MCP
tool schema is 3, with seven tools.

- SwiftPM Debug App and CLI builds pass with the selected Xcode beta toolchain.
- 106 focused checks pass across Search contracts (22), window/toolbar/search/
  localization/App-router suites (80), stdio MCP (3), and scene ownership (1).
  The MCP test fixture was updated to the current schema before its final pass.
- Production-symbol removal scan, documentation authority, developer-toolkit and
  package validators, interface localization, and whitespace validation pass.
- Disposable 500-Note QA confirms About/Links as the only Inspector choices,
  no dedicated recording toolbar/menu command, scope-only search filtering,
  and direct opening of a Works Note from ordinary Search. App teardown removes
  the test bundle and disposable state; the repository fixture is preserved.
- Follow-up interface repair passes 105 frontend, ownership, Metadata, toolbar,
  Links, and Search checks: native palette/font use now shares existing owners;
  stale assertions match current native controls and editor readiness ownership.
  Disposable QA confirms Light/Dark Inspector presentation, native author-field
  focus frames and fixed surname/given-name Tab order, and Links disclosure.
  Links snippets now omit parser-owned annotations presented below the excerpt;
  literal code and malformed annotation text survive. Four follow-up checks pass
  for snippet formatting, exact-source frontmatter editing/Undo, and opening
  readiness across cached editor reconstruction. QA confirms annotation display
  and excerpt navigation retaining Edit mode (108 distinct checks overall).
  This UI evidence predates the residue cleanup below. Full accessibility/
  adaptation, packaged external-host and human acceptance remain outside it.
  Logs: `.build/records-removal/` and `.build/interface-repair/`.
- Residue cleanup removes unused view/state/parser owners, metrics, and copy;
  Search availability flows directly across layers under contract 16, and
  Settlement uses independent `.scholium/settlements/v2/` storage. No old-data
  migration or deletion occurs. 83 initial owning checks and 136 final checks
  pass (overlapping counts), including Search, Settlement, workspace execution,
  localization, and document/interface ownership. Native and CLI Debug compile.
- The complete verifier passes static guards, bilingual localization, generated
  editor-resource reproduction, and RDF-1 fixture checks. Core passes 347 of
  348 tests; the generated-state corruption fixture reports `couldNotExecuteSQL`
  under concurrent execution and passes in isolated reproduction. The cause is
  unconfirmed. The gate stops there; later whole-module checks and the Release
  build are not claimed. Final owning checks pass separately. Logs:
  `.build/residue-cleanup/` and `.build/verification/`.


**2026-09-06 Inspector and continuous Metadata editing:** 11 focused tests in
four suites passed after the continuous-edit cutover, covering native buffer
submission, marked-text command ownership, Metadata-before-document flush,
failure selection recovery, mode retention, and revision rejection. Xcode 27
beta Debug compiled. Computer Use on a disposable 500-Note Triptych confirmed
Light/Dark presentation at 980pt window width, scalar row alignment, author
surname/given-name traversal, Tab/Shift-Tab, focus-departure save, Escape rollback,
invalid-creator retention, navigation refusal and subsequent recovery. Conflict
probes retained the draft, explicitly reloaded the external revision, and saved
again. File reads confirmed persistence after Inspector projection changes,
opening the full Metadata sheet, and hiding the Inspector before Note navigation.
The inline Save/Cancel footer and competing layout candidates are removed.
Logs: `.build/continuous-metadata-tests.log`,
`.build/continuous-metadata-build.log`, and
`.build/continuous-metadata-localization.log`.

The preceding link-navigation slice passed 29 focused tests and visually
confirmed Review heading/incoming-occurrence positioning, Edit occurrence
positioning, and a retained Source editor locating line 83. These earlier probes
are recorded in `.build/inspector-final-tests.log` and
`.build/inspector-reader-tests.log`; their count overlaps the current checks.
All 500 original fixture Markdown files remained byte-identical. QA bundles and
state were cleaned up after inspection. The broader window suite previously
exposed four scroll-restoration assertions in unchanged controller/test code;
localization validation still reports two unrelated missing format strings
(`%arg · %arg`, `%arg/%arg`). Neither is counted as passing. Exact minimum-window
geometry, system accessibility adaptations, enlarged interface text, real IME,
and VoiceOver acceptance remain unverified. This is scoped implementation evidence.

**2026-09-06 Native toolbar and Search:** 87 owning tests in eight suites
passed, covering native toolbar validation and overflow commands, lifecycle
invalidation, window state, Library, Search response evidence, and presentation
contracts. Two isolated UI journeys passed: no-document disabled state across
Outline/Inspector and View menus, followed by restored availability after opening
a Note (21.322 seconds); and blank advanced Search, rapid query entry, quick-to-
advanced handoff, result navigation, query retention, and close (41.820 seconds).
The earlier custom unavailable hint/motion is removed. All toolbar controls use
native state rendering, including monochrome Settlement symbols and system title
color. Native glass grouping remains system-owned. Computer Use confirmed disabled
states, current document identity, transparent Sidebar Search results, and the
native advanced result list with concise metadata. An unqueried availability
default no longer appears as an index failure. Logs:
`.build/native-toolbar-search-owners.log`, `.build/native-toolbar-search-ui.log`,
and `.build/native-toolbar-search-final-build.log`. The final locally signed QA
Debug instance remains open with disposable fixture state for the researcher.
Full assistive/input and light/dark/system-adaptation acceptance remains pending;
these scoped checks do not establish a complete release gate.

**2026-09-06 Library and Search refinement:** 77 focused native tests in six
suites passed, covering workspace segments, toolbar placement, Search lifetime,
native field menus, and owning presentation contracts. The isolated Search
journey passed in 33.690 seconds: rapid query entry, Triptych alias result,
advanced-window handoff, absence of a recursive Advanced Search menu entry,
result navigation with retained query/window, and native close returning to the
Library. Active native field editors now resist stale render text assignments;
only explicit completion/saved-query replacements may replace their contents.
Computer Use confirmed the gray non-glass workspace segments, expanded/collapsed
native notification placement, and the final compact advanced layout with query
details in a small popover. Logs: `.build/sidebar-owning-tests.log` and
`.build/sidebar-ui-test.log`. One isolated ad-hoc-signed QA Debug instance is
left open with a disposable standard fixture copy at the researcher's request.
This is bounded presentation verification: broader App tests still have failures
outside this owning slice; no complete release gate is claimed. Full light/dark,
minimum-width, assistive-technology, genuine IME, and system-adaptation acceptance
remain pending human verification.

**Environment:** 2026-09-05 approved interface corrections, Xcode 27 beta
(`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`). This supersedes
older interface evidence; it is implementation verification, not release or
human acceptance.

- Outline is now a persistent native tree sharing the Sidebar with Triptych.
  The icon selector switches in place and repeating the active mode collapses
  the native split item; the collapsed state has no selected segment. AppKit's
  view-switch role and single-selection tracking provide neutral feedback on
  macOS 27, with native textured toolbar styling on macOS 26. Statistics remain
  centered in the Outline footer. Back/Forward precede the Muted Text document
  name in the Document toolbar; SwiftUI's duplicate visual title is removed.
  Editor protocol 25 adds explicit focus ownership to heading jumps; live source
  headings and current section are derived without writing or saving source.
  All 219 Web tests/resource reproducibility passed. Focused native runs cover
  47 protocol, toolbar, focus, and presentation checks, plus native tree/disclosure
  and shell-placement checks. Final-state reruns cover changed owners.
  Isolated Computer Use confirmed both icons and neutral selection, in-place
  sidebar switching, heading activation with editor focus, repeated-click collapse,
  restored Sidebar width, and retained document navigation while collapsed.
  Evidence: `.build/outline-sidebar/`; the QA Debug bundle is available for the
  researcher's testing. Complete keyboard, IME, accessibility/adaptation, and
  full XCUITest acceptance remain separate from this bounded evidence.
- Completion retains its original native glass and CodeMirror source, keyboard,
  and sole AX owner. Pointer and keyboard update one candidate; AppKit draws the
  selection. The persistent Outline no longer shares that transient interaction
  model. Earlier candidate verification remains under `.build/floating-choices/`.
- Syntax visibility uses one activation rule for construct rendering,
  navigation, and refresh signatures: an insertion point at either boundary
  keeps source visible, and nonempty selections require overlap. Parser-owned
  delimiters use Muted Text; unfinished inline punctuation stays ordinary text.
  All 219 Web tests/resource reproducibility and 100 distinct focused native
  tests passed across grouped runs. Coverage includes typed closing delimiters,
  interior/end/outside transitions, semantic typography, pointer activation,
  marked-text mode deferral, code/Mermaid, Callouts, footnotes, and 200% text.
  A stale footnote test was updated to inspect the existing native preview
  rather than a deleted DOM container. The isolated keyboard QA journey passed:
  closing-boundary retention, movement within the construct, hiding after a
  following space, and exact Markdown retained through real autosave.
  Evidence: `.build/syntax-presentation/`; full adaptation acceptance remains open.
- Heading editing now derives style and marker presentation from the live syntax
  catalog. The incomplete-prefix font fallback is removed, structural heading
  input invalidates the index, and empty ATX headings no longer use Setext
  underline geometry. All 218 Web tests and resource reproducibility passed.
  Three owning WebKit tests passed, including H1/H2/H6 incremental typing and
  marker deletion, exact mixed-script source, and existing heading-entry and
  filename-title focus behavior. The real keyboard QA journey passed in 22.433
  seconds: typing, leaving/re-entering, visible marker deletion, immediate prose
  styling, and Undo restoring the heading. Evidence: `.build/heading-editing/`.
  This is bounded editor verification, not full adaptation or release acceptance.
- Completion lifecycle and density corrections passed 99 focused tests across
  four suites. Autosave now invalidates transport requests without dismissing
  the active projection, and activation validates the accepted live buffer
  revision across disk-fingerprint rebasing. Selection reuses the same native
  host and frame; single-line/described rows use shared 28/40-point metrics and
  neutral interaction feedback. Tests cover retained view identity, narrow
  bounds, mixed-script sizing, exact source, and saved-snapshot reconciliation.
  The isolated completion QA journey passed in 32.531 seconds, including a real
  autosave before pointer acceptance, eight keyboard selection changes with
  stable geometry, Undo/Redo, subsequent keyboard acceptance, and Escape.
  Evidence: `.build/completion-refinement/`; human adaptation acceptance remains
  open.
- The button consolidation passed 100 focused interface/presentation tests and
  four isolated QA journeys: Find (47.732 seconds), Library/menu/sheet Cancel
  (30.661 seconds), Document Information menu/state (23.905 seconds), and
  default/disabled/destructive-cancel actions (48.559 seconds).
  Return moves only the disposable fixture with identical bytes;
  an empty destination stays disabled, and Escape cancels Trash without loss.
  Window and sheet/popover roots explicitly install the shared neutral style;
  the initial sheet screenshots exposed missing inherited styling, now fixed.
  Menu triggers use the corresponding native MenuStyle adapter; Clear is a
  neutral command button, while target-Document navigation retains link semantics.
  Native icon chrome has one owner, and ownership checks prohibit feature-owned
  native button/menu styles, prominent variants, and tint overrides. Narrow Light/High
  Contrast Dark component snapshots retain field identity. Documentation and
  localization validation pass. Evidence: `.build/button-consolidation/`.
  Full-app adaptation and human assistive/input acceptance remain open.
- The native floating-surface cutover passed 142 focused tests in six suites,
  plus subsequent container, completion, and Edit preview checks. All 217 Web
  tests and generated-resource reproducibility passed. Find, Search, previews,
  completion, progress, and notifications now share native Liquid Glass;
  persistent document integrity and recovery content retain opaque semantic
  surfaces. Notification copy, actions, material, and narrow-layout behavior
  have one component owner.
  Five isolated QA journeys passed: Find (41.244 seconds), completion
  (24.103 seconds), notification lifetime/placement (26.563 seconds), Search
  results/empty state (21.892 seconds), and mode-specific footnote preview
  (34.682 seconds). They verify unchanged prose geometry, replacement disclosure,
  exact-selection return, completion pointer/keyboard acceptance and Undo,
  native preview selection/copy/Escape, and reference/backlink navigation.
  Completion now fits actual labels/details; three native surface tests and
  the completion QA journey cover content sizing, narrow bounds, selection
  stability, pointer/keyboard acceptance, and Undo after Latin IME commitment.
  The complete gate passed Web/resources and stopped on one obsolete Core
  assertion requiring a removed DOM preview target. That assertion is corrected;
  the complete gate has not been rerun.
  Evidence: `.build/liquid-glass/`. Full-app adaptation, real IME candidate
  selection, and human assistive acceptance remain open.
- The editor formatting-bar removal passed 42 focused Swift protocol,
  architecture, and WKWebView tests, plus 214 Web tests in 38 files and
  generated-resource reproducibility. Mixed-script selection stays unobscured;
  native command dispatch retains exact Bold/Comment transforms, and pointer
  projection and mode-transition checks pass. Protocol 22 removes the unused
  toolbar image requests. Logs: `.build/editor-formatting-removal/`. This is
  isolated integration evidence, not a full-app UI or human acceptance run.
- The subsequent Library-only refinement passed 115 tests across the Library
  tree and frontend architecture suites. It covers one shared Note command list
  including Move, separated Content/Integrity filters, one Metadata group,
  direct sorting choices, and live native large/default row-size changes with
  retained selection and no navigation callback. The isolated QA organization
  journey passed in 27.819 seconds: filtered empty copy retains Clear and the
  current Document, clearing restores the Note row, and the exact row's contextual
  Move Note opens its sheet; Cancel preserves the original path and source bytes.
  The initial assertion incorrectly expected separate title text instead of the
  native combined accessible copy; the corrected test follows that structure
  and the Clear link role. Documentation/localization checks and `git diff
  --check` passed. Logs are in `.build/sidebar-refinement-logs/`; this bounded
  slice did not rerun the full repository gate or claim human adaptation
  acceptance.
- The complete gate passed frontend typechecking, all 214 Web tests in 38
  files, generated-resource and RDF-1 reproducibility, shipped-Skill and boundary
  guards, Core 351 tests plus 3 performance tests, Contracts 65, Application
  128, and its separate architecture measurement. It stopped at four App
  assertions that still required superseded specification prose. Those
  assertions were replaced or removed while retaining semantic and runtime
  coverage; the complete App suite then passed 591 tests in 44 suites. The
  remaining public-symbol boundary and Release build passed separately.
  This is not a clean single-invocation gate pass.
- Focused coverage proves pointer-mode native emphasis writeback is suppressed
  without changing selection, retained/native focus ownership, first Edit body
  entry after CRLF YAML, unrestricted Source-font persistence, and live WebKit
  typography changes without source or selection mutation.
- The focused native Triptych navigator XCUITest passed selection and Up/Down
  navigation. Its result bundle is retained under
  `.build/qa-ui-derived-data/Logs/Test/`; this does not replace physical keyboard
  or VoiceOver acceptance.
- Complete logs are retained under `.build/interface-repair-logs/`. Genuine
  VoiceOver, physical Full Keyboard Access, Simplified Chinese IME, enlarged
  text, minimum window size, and the complete Increase Contrast/Reduce Transparency/Reduce Motion
  adaptation matrix remain open.

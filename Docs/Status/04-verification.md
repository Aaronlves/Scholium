# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Latest dated proof boundary.

## Current verification snapshot

**Environment:** 2026-08-16, Xcode 27 beta, Swift 6.4, macOS 27.0 SDK.

The exact `v0.1.0-beta.8` commit `51a5f64ed7b1a825b718637e340b97030db10106`
passed one uninterrupted complete repository
gate: closed documentation manifests and shipped Skill resources; TypeScript
checking and 199 Web editor tests; reproducible editor, mathematics, and Mermaid
bundles; 434 Core tests plus 3 Search performance tests; 137 Contracts tests;
231 Application tests, 11 bridge tests, and 1 serialized architecture
measurement; 636 App tests; 7 executable Research Action CLI lifecycles; the
sandboxed App-to-standalone-CLI loopback probe; symbol and residue guards; and
an optimized Release build in 187.92 seconds.

The same clean tagged commit produced an architecture-labelled DMG and separate
standalone CLI ZIP with exact provenance and SHA-256 files. `hdiutil` verified
and read-only mounted the DMG; its visible root contained only Scholium and the
Applications alias, and the copied App passed strict signature, architecture,
sandbox-entitlement, and provenance checks. The CLI installed into an isolated
user prefix and launched by basename from an unrelated working directory.
GitHub published the tag and all four assets. Fresh exact-release downloads
matched both published checksums; the stable CLI `latest/download` route was
moved to this release and independently resolved to `v0.1.0-beta.8`.

This evidence is not Developer ID signing, notarization, a clean external-account
Agent journey, the current complete packaged G7 series, packaged-icon and human
visual acceptance, or a packaged first-launch UI journey. The release owner
directed publication with those gaps still open; they remain acceptance work
rather than passed evidence. The ad-hoc App is intentionally neither Developer
ID signed nor notarized and Gatekeeper rejects it until the documented user
override.

## Focused interface evidence

- On 2026-08-27, the external-Agent Skill deployment cutover passed the complete
  gate: documentation and 9 shipped-Skill guards; 206 Web, 465 Core plus 3
  performance, 150 Contract, 284 Application, 16 bridge, 1 architecture, and
  668 App tests; 16 signed executable CLI lifecycles; the sandbox loopback
  probe; symbol/residue guards; and a 184.40-second Release build. A disposable
  external Agent workspace obtained and registered 3 System plus 6 Action Skill
  sources through the real CLI, retained an unrelated non-Scholium Skill,
  received only minimum `required_skills` and the frozen Method revision in Run
  Context, executed all six Actions, and performed Analyze, Synthesize, and
  Write mutations only through `scholium agent write`. Continue returned its
  attached child Context without another pair/reload, and substituted external
  Skill entries failed closed. This proves local deterministic deployment and
  CLI behavior, not live Codex/Claude discovery refresh, a packaged external
  account, or human/researcher acceptance.

- On 2026-08-25, the window-workspace and Local Agent bridge ownership cutover
  passed the complete gate: documentation/Skill guards; 206 Web, 464 Core, 3
  performance, 150 Contract, 279 Application, 16 bridge, and 663 App tests;
  architecture measurement; 13 CLI lifecycles; App-to-standalone-CLI probe;
  residue guards; and the 188.64-second Release build.
  `WindowWorkspaceController` alone owns registration, assignment, capability
  activation, and recovery; `LocalAgentBridgeRequestRouter` alone translates
  the closed 17-operation wire set. A subsequent 197-test residue pass removed
  the generic recovery setter, single-field feedback wrapper, capability
  relay, and duplicate recovery finalizers; transaction notices now survive
  successful installation. No visible behavior changed, so no visual or
  researcher acceptance was required.

- On 2026-08-23, the explicit Record retrieval CLI facade passed the Debug CLI
  build, documentation-authority validator, and all 11 signed executable CLI
  lifecycles. The disposable fixture proves stable-Note `record list`, complete
  Record `record read`, complete-corpus manifest and exact persisted-byte
  fingerprints, multi-provider Search coexistence, and structured missing-Note
  and missing-Record errors. This is local automated evidence, not a packaged
  external-Agent journey or large-Record-corpus performance acceptance.

- On 2026-08-23, the Practice-to-reference cutover passed the complete gate:
  all guards; 199 Web, 455 Core, 3 performance,
  147 Contract, 269 Application, 16 bridge, and 645 App tests; 11 signed CLI
  lifecycles; sandbox probe; and the 188.62-second Release build. Every default
  Skill owns its lenses; no Practice catalog, resolver, Settings surface,
  snapshot, Record field, or improvement target remains. No XCUITest or human
  acceptance.

- On 2026-08-23, the Metadata lifecycle and recovery integration passed its
  focused Contracts, Core, Application, Settings, presentation, Search,
  localization, architecture, and 11 signed executable-CLI lifecycle owners.
  Disposable fixtures prove stable key/kind identity; editable labels and
  descriptions; append-only controlled choices; reversible archival that
  retains existing values; scope-aware property/choice completion; natural-JSON
  CLI CAS without source changes; exact single-record recovery; and a
  Metadata-only refresh with zero source and Metadata-catalog record reads. The
  task's single complete `verify.sh` run passed documentation and shipped-Skill
  guards, 199 Web-editor tests, reproducible bundles, RDF-1, 455 Core tests, 3
  performance tests, 147 Contract tests, 267 Application tests, 15 bridge
  tests, and the architecture measurement. All 645 App tests ran with one
  failure: the intended new recovery call was absent from the WindowModel Store
  allowlist. The allowlist was corrected, and its complete 58-test architecture
  owner passed. Per the one-complete-gate rule, later symbol, sandbox-bridge,
  and Release stages were not rerun. This is local automated evidence, not
  packaged, visual, assistive-technology, or researcher acceptance.

- On 2026-08-23, managed New Note creation removed the generic complete-source
  `create` port and duplicate Untitled-request construction. GUI, researcher
  CLI, and authenticated Agent creation retain one `createManagedNote` owner;
  exact-path Import alone exposes `importMarkdownSource`. The focused creation,
  Import, Agent-write, CLI-delegation, and window-architecture owners passed 130
  tests. The task's single complete `verify.sh` attempt then passed
  documentation and shipped-Skill guards, all 199 Web-editor tests,
  reproducible bundles, RDF-1, 454 Core tests, 3 Core performance tests, 147
  Contract tests, 265 Application tests, 15 bridge tests, the serialized
  architecture measurement, all 643 App tests, and the Debug/symbol stages. It
  stopped in the 10-test executable CLI lifecycle because a property-only
  Metadata change was absent from the incremental Search projection hash. The
  index now fingerprints both lexical and structured projections; a regression
  test proves Metadata-only incremental/clean-rebuild parity, and all 5 Search
  property plus 10 executable CLI lifecycle tests passed. Per the one-complete-
  gate rule, the sandbox bridge, Release stage, and complete gate were not
  rerun. This is local automated evidence, not packaged or human acceptance.

- On 2026-08-23, the resolved YAML/Metadata boundary passed its focused
  Contract, Core, Application, App, Search, Link, Agent, Zotero, Settings, and
  source-fidelity owners. The task's single complete `verify.sh` attempt passed
  documentation and shipped-Skill guards, all 199 Web-editor tests,
  reproducible bundles, RDF-1, 454 Core tests, 3 Core performance tests, 147
  Contract tests, 265 Application tests, 15 bridge tests, and the serialized
  Application architecture measurement. All 643 App tests then ran, with five
  issues in three tests: a new Zotero sheet used raw typography/cadence values,
  and one projection fixture still treated retired `tags` and `authors` YAML as
  scanned fields. The implementation and fixture were corrected without
  restoring generic YAML semantics; the complete 98-test Frontend architecture
  suite and the exact projection test passed. Per the one-complete-gate rule,
  later gate stages and the complete gate were not rerun. The focused Metadata
  XCUITest built for testing, but execution stopped before app launch because
  the configured disposable `Desktop/TestVaults` fixture was absent. This is
  local automated implementation evidence, not packaged, visual,
  assistive-technology, or researcher acceptance.

- On 2026-08-23, exact-key Zotero retrieval and bound-item refresh passed 21
  focused Contract, Application, and App architecture tests. They cover no
  item-collection fallback for a missing complete key, distinct exact
  user/group identities, bound preview plus commit reads limited to the exact
  item route, mapped fill/update planning, source-type retention, exact
  Markdown preservation, and the Inspector refresh owner. Documentation
  authority and Interface, Localizable, and WebKitInterface localization
  validation passed. The task's single complete `verify.sh` run passed
  documentation and shipped-Skill guards, 199 Web-editor tests, reproducible
  bundles, RDF-1, 450 Core tests, 3 Core performance tests, and all 146
  Contract tests. It then stopped after 262 of 264 Application tests: two
  unrelated bounded-write owner tests deterministically failed with an existing
  Metadata revision conflict and body-operation authorization rejection; each
  remained failing when isolated, so later targets did not run and the complete
  gate was not repeated. This is local automated evidence, not live-Zotero,
  visual, assistive-technology, packaged, or researcher acceptance.

- On 2026-08-23, Zotero Link and Fill passed 33 focused tests across exact
  local decoding/matching, same-key user/group selection, pure Metadata mapping,
  Application commit, server substitution, Metadata revision conflict, exact
  Markdown/YAML preservation, and interface ownership. Documentation authority
  and Interface, Localizable, and WebKitInterface localization validation also
  passed. The task's single complete `verify.sh` run passed documentation and
  shipped-Skill guards, all 199 Web-editor tests, reproducible bundles, RDF-1,
  450 Core tests, and 3 Core performance tests. It then completed 144 of 145
  Contract tests before one stale post-YAML-cutover Document Preview assertion
  expected retired YAML `title` instead of the current H1 title; later targets
  did not run. The assertion was corrected without restoring YAML semantics and
  its complete two-test owner suite passed. Per the one-complete-gate rule, the
  complete gate was not rerun. This is local automated evidence, not live-Zotero,
  packaged, assistive-technology, visual, or researcher acceptance.
  A subsequent residue-cleanup pass removed the superseded researcher-facing
  set-binding API, redundant library enumeration, unused transient result
  state and conformances, and generic Research error cases that belonged only
  to Link and Fill. Its 16 focused Zotero and portable-binding tests passed.
  Its single complete `verify.sh` run passed the documentation and shipped-Skill
  guards, 199 Web-editor tests, reproducible bundles, RDF-1, 450 Core tests,
  3 Core performance tests, and all 145 Contract tests, then found six stale
  Application assertions across four owners: five still treated retired YAML
  aliases/properties as managed Metadata, and one expected pre-structured
  Zotero creators. Those fixtures were corrected without restoring YAML
  semantics, and all 39 tests in their owning suites passed. The complete gate
  was not rerun.

- On 2026-08-23, the fixed-authored-YAML and optional-machine-field cutover
  passed 207 focused tests: authored-YAML and managed-Metadata contracts,
  Triptych settings and persistence, Workflow profiles, Agent-start wire,
  bounded creation and recovery, document operations, Settings architecture,
  Local Agent bridge, and executable CLI lifecycles. Documentation authority
  and Interface, Localizable, and WebKitInterface localization validation also
  passed. The task's single complete `verify.sh` run passed documentation and
  shipped-Skill guards, all 199 Web-editor tests, reproducible bundles, and
  RDF-1. It then completed the 450-test Core target with three issues from one
  stale Workflow-schema assertion that still expected authored `summary` in
  Settings `visibleFields`; later targets did not run. That owner test was
  updated without restoring Settings YAML authority, and its complete five-test
  suite passed. Per the one-full-gate rule, the complete gate was not rerun.
  This is local automated implementation evidence, not packaged or human
  acceptance.

- On 2026-08-23, the YAML/portable-Metadata cutover passed its focused owners:
  22 bounded-write, 8 Search-property projection/index, 40 Search/Record index,
  28 document-operation, 36 Triptych-control, 28 Settings-architecture, 10
  Property-contract, 10 presentation, 98 frontend-architecture, 10 Agent
  start/result, 15 bridge, and 10 executable-CLI lifecycle tests. A following
  complete `verify.sh` attempt passed documentation and shipped-resource
  guards, all 199 Web-editor tests, reproducible bundles, and RDF-1, then
  stopped at 451 Core tests with 12 issues caused by fixtures still assigning
  title, aliases, authors, and publication date to retired YAML semantics or
  expecting the preceding execution schema. Those owning fixtures were cut
  over without restoring YAML reads; all 75 affected Record, catalog, and link
  graph tests then passed. Per the one-complete-gate rule, later stages and the
  complete gate were not rerun. Documentation authority and Interface,
  Localizable, and WebKitInterface localization validation passed. The focused
  Metadata XCUITest built and launched a disposable repository-local fixture,
  but the QA app remained in
  two disabled bootstrap windows for 90 seconds and never reached a document
  surface, so it exercised no Metadata control. This is automated local
  implementation evidence; keyboard, first-record, conflict, accessibility,
  visual, and researcher acceptance remain open.

- On 2026-08-22, the direct Analysis-creation recovery integration passed 3
  Agent-start Contract tests, 37 Core persistence tests, 50 Application owner,
  Session, Result, and bridge tests, and 10 signed standalone-CLI lifecycles
  under Xcode 27 beta and Swift 6.4. Under the then-current, now-superseded
  creation contract, disposable fixtures covered Settings-required fields
  before start; they also covered root-only Agent creation and rejection of Agent-claimed
  subfolders;
  pre-commit reservation recovery without fabricated identity or mutable
  source type, existing metadata, or academic purpose; occupied
  path/identity and missing/trashed source; exact replay, replay conflict,
  frozen-source projection recovery, concurrent exact/changed starts, complete
  start-payload replay, and local/remote operation-specific unknown outcomes
  including non-retryable committed End response loss,
  Session replacement, and researcher-provided Record formation without a
  fabricated Source Reference; Analyze also completes without an automatic
  Fidelity child. Documentation authority and the
  external philosophy-workflow source-package validator passed. This is local
  automated evidence, not real-vault, packaged, or human acceptance. The
  standalone lifecycle executes the returned same-ID preflight recovery step
  after an injected `outcome_unknown` response.

- On 2026-08-22, the post-cutover cleanup passed 71 focused Core tests across
  vault mutation, coordinated system Trash, portable Record, and Local
  Execution owners; 14 Research Function contract tests; and 8 preparation
  tests. The fixtures preserve unsupported schema-11 Records and schema-1
  Discussions byte-for-byte, gate finished Record creation, reject duplicate
  recovery identities without trapping, preserve late Note and Folder
  replacements after the final path check, and resume an interrupted exact
  Note binding. The complete repository gate then passed 199 Web editor tests;
  446 Core tests plus 3 performance tests; 146 Contracts tests; 249 Application
  tests, 13 bridge tests, and 1 architecture measurement; all 646 App tests;
  documentation, shipped-resource, localization, purity, retired-name, JSON,
  duplicate-key, whitespace, and reproducibility guards; the public symbol
  graph; 10 signed executable CLI lifecycles; the sandboxed App-to-standalone-
  CLI bridge probe; and the optimized Release build. This is disposable local
  automated evidence, not Finder, multi-window, packaged, assistive-technology,
  or human acceptance.

- On 2026-08-22, the Local Execution envelope and system-Trash recovery cutover
  passed 38 Record/Local Execution store tests, 10 coordinated deletion tests,
  and the Application archive-and-retry test. The complete gate passed
  documentation, resources, 199 Web tests, 448 Core tests, 3 performance tests,
  and 146 Contracts tests before one old Application fixture read the envelope
  as the payload. After correcting only that fixture, all 255 Application tests,
  15 bridge tests, and the architecture measurement passed. The serial App run
  passed 645 of 646 tests before rejecting one new Chinese use of the retired
  Trash term; the corrected 8-test localization suite and catalog validator
  passed. Public-symbol, 10 signed CLI-lifecycle, sandboxed loopback-bridge, and
  optimized Release-build gates then passed; Release built in 183.24 seconds.
  The final post-cleanup Release rebuild passed in 190.37 seconds.
  The focused XCUITest could not start because the approved static
  `Desktop/TestVaults` fixture was absent, so alert clicking, focus, VoiceOver,
  and human visual acceptance remain unverified. No research vault was opened.
  A focused follow-up hardened valid-envelope payload failures: four Core tests
  proved outer and nested payload scoping, exact-byte archival, legacy recovery,
  and creation-record isolation; the owning Application archive-and-retry test
  and architecture-boundary test also passed. The UI helper parsed after its
  stale storage epoch was removed, but no XCUITest journey was run.
- On 2026-08-21, the untagged system-Trash cutover passed 7 coordinated
  deletion tests covering whole multi-Note Record cleanup, active Discussion
  discard, Work-plus-Critique receipts, plan-persistence and post-move crash
  recovery, unknown native outcomes, same-path recreation, and complete
  Folder-manifest drift. The earlier 22-test Vault repository suite exercised
  an exchange before its last identity check; it did not cover the interval
  after that check and before the path-based native Trash call. The associated
  37 Record-store, 25 document-operation, 4 CLI-delegation, 12
  workspace-projection, 58 window-architecture, 98 frontend-architecture, and
  8 localization tests passed on disposable fixtures. The latest aggregate
  `swift test` attempt passed the complete lower-layer batch and 645 of 646 App
  tests; its sole failure was an existing serialized Action-sheet test missing
  its asynchronous capture under the concurrent runner. That exact test passed
  alone in 0.014 seconds and its complete 20-test suite passed in 0.315 seconds;
  the WKWebView baseline that timed out in the preceding aggregate attempt also
  passed in this run. The Debug build, documentation authority (3 manifests, 22
  chapters, and 109 local links), interface localization, JSON, duplicate-key,
  whitespace, and retired-name checks passed. This is local automated evidence:
  no real research vault was used, and Finder restoration, the complete UI
  suite, VoiceOver speech, and researcher acceptance remain human QA work.
- On 2026-08-16, the recovery simplification cutover passed focused Core and
  Application owner tests for transaction-only save recovery, monotonic
  the then-current deletion owner, natural-key Agent evidence, direct Undo after conflict
  and rename, one unified workspace registration, Method/Practice replacement,
  and schema-14 terminal Local Execution compaction. The stabilized cross-layer
  integration passed the complete repository gate: documentation and shipped-
  resource validation; 199 Web editor tests and reproducible bundles; 434 Core
  plus 3 Search-performance tests; 137 Contracts tests; 231 Application tests,
  11 bridge tests, and 1 architecture measurement; 636 App tests; 7 executable
  CLI lifecycles; the sandboxed App-to-CLI loopback probe; symbol and residue
  guards; and an optimized Release build in 213.20 seconds. This is automated
  disposable-fixture evidence, not human interface or sustained-research
  acceptance.
- On 2026-08-15, the then-current recovery-loop hardening passed exact-owner
  tests for the since-removed separate access registries; old or damaged whole-bundle
  `.scholium` preflight, archive, rebuild, and same-Triptych reopen; unchanged
  Analyses, Topics, and Works bytes; active-runtime refusal; and explicit
  Saved Search and machine-local Method locator archive/reset.
  Valid concurrent replacements remain in place rather than being archived,
  and the portable recovery token covers the complete control directory tree.
  App tests also proved the Saved Search presentation owner and Simplified
  Chinese recovery controls. The stabilized cross-layer integration passed the
  complete repository gate: documentation and shipped-resource validation;
  199 Web editor tests and reproducible bundles; 481 Core plus 3 Search
  performance tests; 138 Contracts tests; 234 Application tests, 11 bridge
  tests, and 1 architecture measurement; 637 App tests; 7 executable CLI
  lifecycles; the sandboxed App-to-CLI loopback probe; Debug/symbol guards; and
  an optimized Release build in 181.51 seconds. This is automated
  disposable-fixture evidence, not human visual or clean-account acceptance.
- On 2026-08-15, five focused Core, Application, and App tests proved the
  unavailable-registration escape: removing one registration preserves exact
  research and incompatible portable-manifest bytes, preserves unrelated
  Triptychs and selects their next default, never opens a deleted vault or
  decodes its portable schema, returns the window model to unconfigured state,
  and fails closed while the Triptych has an active runtime. The Simplified
  Chinese control and confirmation labels also resolved from the shipped
  catalog. The existing isolated Restore Access XCUITest could not start
  because its approved static `Desktop/TestVaults` fixture was absent; this is
  no synthetic interaction or human visual acceptance evidence. The cross-layer
  integration then passed the complete gate: 199 Web editor tests; 476 Core
  plus 3 Search-performance tests; 138 Contracts tests; 233 Application, 11
  bridge, and 1 architecture-measurement tests; 635 App tests; 7 executable CLI
  lifecycles; the sandboxed App-to-CLI loopback probe; and an optimized Release
  build in 186.03 seconds. After a final durable-removal projection correction,
  the complete 635-test App suite passed again; the unchanged lower-layer, CLI,
  and Release results are from the immediately preceding complete gate.
- On 2026-08-15, the independent-CLI cutover passed 7 Bootstrap, 27 Settings
  architecture, 7 delivery-path, 11 loopback-bridge, and 7 executable Agent CLI
  lifecycle tests. The App no longer owns a CLI status or installer and copies
  one fixed official Agent instruction that accepts only the required product
  and compatible-version fields while ignoring additional JSON fields. A
  focused QA journey copied that instruction through the visible Settings
  button and verified the download, no-`sudo`, no-PATH-edit, and unknown-field
  clauses. A signed probe proved a sandboxed App and nonsandboxed standalone CLI
  communicate only over `127.0.0.1`; closed-App requests are unavailable and an
  invalid pairing code reaches the App without entering logs. This remains
  disposable focused evidence. The later published-asset download proves exact
  delivery bytes, not a clean-account Agent installation.
- On 2026-08-14, the existing-Note save cutover passed 228 focused tests: 86
  Core, 8 Contracts, 31 Application, and 103 App tests. The fixtures cover
  coordinated system replacement, exact BOM/CRLF readback, metadata changes
  remaining outside save authority, external-writer conflict, symlink and
  parent exchange, readback mismatch, pre- and post-replacement interruption,
  `SIGKILL` restart reconciliation, move propagation, removal of
  cleanup-warning presentation, and rejection of unsupported pre-use recovery
  data without mutation. Documentation authority also passed. The frontend I/O
  guard was then aligned with its existing App architecture allowlist, and its
  owning synchronization test passed. The subsequent complete-gate attempt
  passed 199 Web tests, 472 Core tests, 3 Search performance tests, and 138
  Contracts tests before one parallel Application test failed to observe
  watcher-readiness evidence before activation reconciliation completed. The
  opening boundary was then repaired so the first complete publication follows
  that reconciliation. A controlled barrier proved the Workspace remains
  Opening while reconciliation is paused; both progressive-opening tests passed
  together, and the same parallel Application batch passed 223/223. The latest
  current-tree coverage above now includes that repair. 2026-08-25 root-authority
  passed; File Provider acceptance remains open.
- On 2026-08-13, the progressive-opening Application contract test proved that
  one selected live Vault publishes first, its Note remains loadable, Search
  fails closed with `workspaceStillLoading`, and the same handle later publishes
  a complete three-Vault Graph/Search generation. The window-projection test
  proved the corresponding opening-to-current atomic state transition, and the
  catalog test proved that deferred Search offsets complete without rereading
  source. The
  complete pre-existing Workspace runtime suite also passed 16/16 before the
  new focused case. This is deterministic implementation evidence, not packaged
  launch performance or human loading-state acceptance.
- A 2026-08-13 isolated Release diagnostic with RDF-1 and 267 visible Analysis
  Notes retained three warm Library samples of 785.8–819.0ms after one warm-up
  (median 797.8ms). Its unretained cold-page-cache sample was 1126.6ms. The
  diagnostic used the existing test driver against a dirty, ad-hoc-signed
  diagnostic bundle; it demonstrates margin for integration but is not the
  clean tagged packaged 5+30 G7 result.
- The 2026-08-13 integration verification passed the unchanged Web, Core,
  Contracts, Search-performance, bridge, architecture-measurement, App, CLI,
  sandbox, symbol-boundary, and Release-build gates. Its initial parallel
  Application batch stopped making progress after all but one existing test;
  that test passed alone in 0.51s and the complete Application batch then
  passed 222/222 serially. After updating one source-signature architecture
  assertion for the new opening-Vault parameter, App passed 604/604. This is a
  recovered complete gate, not evidence that the Xcode beta parallel runner's
  scheduling stall is resolved.
- The 2026-08-11 seeded-`tags` QA journey exercised the superseded YAML
  Properties design and is not acceptance evidence for schema-5 Metadata
  Profiles. Current keyboard, first-record, conflict, and researcher acceptance
  remain open below.
- The Research Action, Reading Lead note, and Researcher Evaluation sheet
  journey passed in 63.273 seconds on disposable fixtures and retained one
  screenshot per sheet.
- The Research Record reading/evidence and confirmed-deletion journey passed in
  76.419 seconds. After deletion of the final Record, the live accessibility
  tree exposed `scholium.researchRecords.empty`; reopening retained the
  controller's republished empty state.
- Focused native and attached-WKWebView tests cover shared interaction feedback,
  Search and editor floating controls, Callout focus, footnote/link preview,
  selection completion, semantic color, corner, typography, spacing, and
  component-cadence ownership.
- The 2026-08-10 Records/Review correction passed 3 focused App tests across 3
  owning suites. The bounded Note Review/Compare UI journey passed in 119.354
  seconds and proved automatic task presentation, same-set dismissal, Overview
  reopening, new-set reopening, stable Records frame, and no pointer-generated
  Compare focus. The complementary Response journey passed in 57.615 seconds,
  retaining progressive Method Feedback, stale draft recovery, and no
  pointer-generated Edit Response focus.
- One final isolated Debug QA read exactly 100 current-schema synthetic Records
  through ordinary **QA Topic → This Note Records**. Its accessibility tree
  exposed the native Records/Reading Leads tab group, `Record, 100 results`, and
  the ordinary product window; exploratory inspection additionally covered the
  aligned Response heading, nonduplicated Effects, and title-free Record detail.
- The latest complete serial UI profile, run 2026-07-28, covered the 74 journeys
  then present. It predates later interface batches; affected boundaries have
  focused engineering evidence, but the complete suite and genuine VoiceOver
  speech remain open.

Synthetic input and screenshots establish bounded engineering evidence only.
They do not replace physical keyboard, installed IME, Voice Control, Dictation,
genuine VoiceOver, Dark/Increase Contrast, 200% interface text, or researcher
visual acceptance.

## Focused Agent-inheritance evidence

On 2026-08-21, the Analyze/Fidelity boundary was decoupled. Focused contract
tests and the product build verify that a completed Analyze or other write does
not enter `awaiting_fidelity`, invoke `agent prepare-fidelity`, or require a
Fidelity child. The Analyze Method now owns a bounded fidelity self-check;
formal Check Fidelity remains an independently prepared, read-only Action only
when the researcher explicitly requests it. Ordinary authenticated Agent
continuation remains available, and no real research Note or private source was
used. The complete repository gate then passed documentation and shipped
resource validation; 199 Web editor tests; 439 Core tests plus 3 performance
tests; 146 Contracts tests; 249 Application tests, 13 bridge tests, and 1
architecture measurement; all 652 App tests; the 10 signed executable CLI
lifecycles; the sandboxed App-to-standalone-CLI bridge probe; and the optimized
Release build.

On 2026-08-27, the external-Agent operation reduction passed the complete
repository gate after its first attempt exposed and the focused 24-test
architecture suite corrected two delivery-boundary assertions. The final gate
passed documentation and 9 shipped-Skill roots; 206 Web editor tests and
reproducible bundles; 464 Core plus 3 performance tests; 150 Contracts tests;
284 Application tests, 16 bridge tests, and 1 architecture measurement; all 668
App tests; public symbol guards; all 16 signed executable CLI lifecycles; the
sandboxed App-to-standalone-CLI probe; and the optimized Release build. The CLI
fixtures execute all six Actions, required exact reads, bounded Search, owner-
routed initial Action/Method context, reload-only initial-delivery recovery,
required-only Result templates, Continue after Result, and exact expired-
credential pruning while preserving malformed and symlink entries. Query calls
create no durable reading history. The same signed CLI simulation proves every
Action's first start output contains the exact bundled Core runtime protocol and
exact Action-specific `SKILL.md` plus its installed folder; reload omits Core
while retaining that Method. This is disposable local engineering evidence, not
packaged clean-account use, scholarly adequacy, or human acceptance.

On 2026-08-21, independent-review hardening passed 34 Core storage tests, 19
Agent-start and portable-Record Contract tests, 104 Application/bridge tests,
and 2 real executable CLI start lifecycles. The disposable fixtures prove that
exact creation replay preserves a newer researcher Zotero relationship, an
existing relationship is excluded from an explicit `researcher_provided` Run
through Record formation, completed and cancelled creation Runs issue no new
Session, and a UUID-shaped unique Triptych name resolves before UUID fallback.
They also exercise the request-owned binding phase transitions and structured
`replay_conflict` response. Documentation authority and the Debug CLI build
passed. This is local automated evidence, not packaged clean-account or human
acceptance, and no real research vault was used.

On 2026-08-21, the external Analyze handoff repair passed 40 focused Contracts
tests, 39 Core storage and Search tests, 101 Application and bridge tests, and
2 executable standalone-CLI lifecycles with Xcode 27 beta and Swift 6.4. The
fixtures prove the strict snake-case Agent-start target, first-use CLI Session
directory creation and modes, an explicit `researcher_provided` source route
through completion and portable Record schema 11, exact `new_analysis` replay
without duplicate Notes or Runs, committed-source projection repair after a
post-commit refresh failure, structured safe bridge errors, and re-pairing the
same unfinished Run after an App-process restart. A Debug CLI build and the
documentation-authority validator also passed. This is disposable-fixture and
local executable evidence; it does not prove a packaged clean-account Agent
journey, real-vault use, or human acceptance. The complete repository gate was
not used because unrelated in-progress toolbar changes are present in this
worktree and would enter that evidence boundary.

The current-Run Material lineage cutover passed 57 focused tests across nine
owning Contracts, Application, and architecture-boundary suites with Xcode 27
beta and Swift 6.4. The tests cover the closed `inspect_materials` clause,
path-free typed source and Zotero response data, canonical Material-envelope
revalidation including a source change between inspection and Result
submission, current/changed/missing/unavailable continuation checks,
schema cutovers and round trips through Continue Result, authenticated Run
Context, bridge, and Local Execution, source-access containment, process-bound
Session regressions, and module/import ownership.

This proves the repository-level Material owner and lineage contract on
disposable fixtures. It does not prove checkout-external App/CLI installation,
production installed user-local bridge behavior, human accessibility, sustained research use, or
philosophical quality.

On 2026-08-29, the low-burden Research Context and Record-provenance cutover
passed 48 focused Contracts tests and 72 focused Application tests. The tests
prove App-derived evidence eligibility, retirement of Agent-declared
eligibility and reading-history fields, explicit frozen Material Note IDs,
changed-only participant exclusion from Synthesis Material Attention, and one
authenticated Run reading multiple Notes across pagination before finalizing a
target-only Record. The complete gate passed 206 editor, 467 Core, 3
performance, 153 Contracts, 287 Application, 16 bridge, 1 architecture, 670
App, and 16 CLI tests; Debug, Release, sandbox bridge, and UI
`build-for-testing` also passed. This is disposable automated evidence, not
human acceptance.

On 2026-08-29, four fresh-Agent quality baselines passed on disposable
Triptychs. Analyze used live Zotero, Synthesize wrote one Topic, Critique read
the exact Work plus four Analyses and one Topic, and Discuss preserved one
Researcher opening and one Agent turn. Each formed one schema-15 Record and
terminal execution. Analyze and Synthesize made their single expected Note
write; Critique and Discuss made none. Discuss used Finish, revoked its Session,
and required no post-Finish End. Independent reviews, including source-PDF
checks, found no critical or material defect and respectively two, three, one,
and one minor findings. Discuss's minor finding concerned a compressed bridge
from carrier-account incompleteness to response-level explanatory priority.
These runs accept one baseline per Action, not field coverage or sustained
Method adequacy. Synthesize setup also exposed a private-directory ordering
defect when `doctor` first touched an explicit `SCHOLIUM_HOME`; the CLI now
creates its Home and Application Support parents at mode `0700`, and the focused
real-executable lifecycle regression passed.

The subsequent Researcher State continuation cutover passed 44 focused tests
across eight owning Contracts, Application, Core-store, bridge, and architecture suites
with the same toolchain. The tests prove that a parent-Run state reference is
removed from child handoff items and reference checks, a typed requery
requirement survives Result, bridge, authenticated Context, and Local Execution
round trips, and the child query receives its own Run scope and the current
replacement Settlement. They also retain the source-family continuation and
Research Context regressions and reject retired outer schemas.

This establishes requery rather than state handoff for the current target-Note
view. It does not prove that the view is complete, that a researcher judgment
is correct, or that a future provider retrieves every relevant current owner.
  Settle contributes only its portable judgment and exact fingerprint; it has
  no machine-local source version or recovery pin.

The provider-replacement and summary-attribution alignment passed 44 focused
tests across seven Search, Contracts, Application, bridge, and architecture
suites with Xcode 27 beta and Swift 6.4. One nonempty disposable provider uses
a fixed summary candidate rather than production Search, checks the authorized
Workspace snapshot, and produces current, stale, and unavailable outcomes. A
fixed-query mismatch remains an Invalid Query rather than returning an
unrelated candidate. The current item matches production summary discovery on
owner, unknown actor,
role, fingerprint, exact match range, Run/Triptych scope, currentness,
evidential layer, and retrieval reason. Query delivery persists neither guessed
researcher authorship nor provider/query identity, while an explicit handoff
reference survives Continue Research revalidation.

This proves provider-neutral semantics for one deliberately different
nontrivial fixture mechanism, not the quality of a second production retrieval
strategy. It also confirms the current writer boundary: plain/quoted summary
discovery is source-located, block/folded or range-ambiguous summary projection
fails closed, and the current Note revision remains actor-unknown unless a
separate existing operation or Record owner proves authorship. No block-scalar
support, field-level writer history, or attribution database was added.

The bounded Records-window repair passed its one owning frame test. One
disposable ordinary-product QA with 100 portable Records then preserved the
same `X=355 Y=110 W=760 H=680` frame through list, detail, and returned list;
the proof shell was not used.

The Note-level Review foundation passed 89 focused tests across four Contracts,
Core, and Application suites with the Xcode 27 toolchain. Evidence covers
schema-8 Record round trip and schema-7 rejection; strict schema-1 Note Review;
one-Run/one-Record participant facts; cumulative coverage; Review A isolation
from Note B; a late Record reopening pending work; no-change Action completion;
first-committed Agent baselines; Review-independent direct Undo; exact source
and Record-manifest rejection; post-commit reconciliation; and researcher edits
not resurrecting covered activities. Documentation authority, diff checks, and
the Debug product build passed for this stage. Interface owning tests, bounded
UI journeys, localization validation, and the one current-tree final gate are
recorded only after their later stages complete.

The interface cutover then passed 142 focused tests across ten App suites. It
covers progressive Add/Edit Response, Evaluation-first optional Method
Feedback, atomic draft and stale-state protection, read-only Changes,
window-lifetime exact Undo, removal of Action-sheet Result review, Overview's
Attention/Review/About order, the Document task boundary, exact-window routing,
notification isolation, Action lifecycle, and Records frame stability. The
first pass exposed one retired `Review Result` Action-sheet assertion; the
final batch passed after deleting that requirement. Documentation authority,
interface localization, diff checks, and the Debug product build passed.

Three complementary ordinary-product UI Automation journeys then passed
together in 230.634 seconds. They cover one multi-Note Record visible from its
origin and changed Note; stable Records frame through list, detail, Compare,
and return; read-only View/Compare not completing Review; one Note clearing two
older activities while another remains pending; a later Agent change reopening
Review; progressive Evaluation-first Response editing with optional Method
Feedback; atomic durable save; stale external Response preserving the local
draft; and one deduplicated no-change Result arrival without Note Review.

The single final ordinary-product QA uses a disposable Triptych initialized
before fixture injection. Its portable store contains exactly 100 unique
schema-8 Records, all associated with QA Topic: 60 have confirmed Topic
changes, 40 have no source change, 20 also change QA Work, 25 contain an
Evaluation, and 12 also contain Method Feedback. The live **This Note** Records
AX tree reported `100 results`; opening a saved-Response Record exposed its
Evaluation, Method Feedback, and Improve Current Method route. After the real
workspace watcher rebuilt the research snapshot, QA Topic Overview reported
`Needs Review · 3 Agent activities`. This is disposable Debug QA evidence, not
a packaged release or researcher visual acceptance.

This remains bounded development evidence, not an installed App/CLI journey or
human acceptance. Genuine VoiceOver, physical
Full Keyboard Access, 200% mixed-script, Dark appearance, Increase Contrast,
Reduce Transparency, Reduce Motion, and researcher visual acceptance remain
open.

## Search case pack

These cases are the current researcher-review set for deciding whether static
query completion is sufficient. They do not define a second Search contract.

### Case A: Metadata provenance and discovery

Given a Topic with authored YAML `summary`, managed `aliases`, and an unknown
custom YAML key, verify that Search reports exact source provenance only for
`summary`, reports no Markdown range for `aliases`, excludes the unknown key,
and treats neither retrieval reason as evidence.

### Case B: Direct relation direction

Given one authored support edge and one incompatibility edge, verify from/to
direction, source occurrence, undirected explanation, Graph-unavailable failure,
and the absence of transitive expansion or evidential claims.

### Case C: Record statement location

Given a Research Record with attributed researcher and Agent statements, verify
provider selection, speaker/field match reason, exact statement destination,
scope authorization, stale refusal, and App/CLI parity.

## Performance evidence

On 2026-08-14, the approved Edit gate boundary was aligned with the shipped
cold-launch behavior: launch settles on a no-document Workspace, Library opens
the frozen 5,000-word Note into interactive Review as unmeasured setup, and the
collector then measures the researcher's first Edit request to the matching
visible and accessible editor. The focused Debug QA scenario completed all five
excluded warm-ups and 30 retained samples
without an invalid journey. Retained samples measured 335.648ms p50, 363.570ms
nearest-rank p95, 328.895ms mean, and 371.997ms maximum; correctness, the
`< 750ms` p95 limit, and the `< 1,000ms` every-sample limit passed. Report
SHA-256 is `8dc94f93a3f2b3428185396239bcb47373e3a4578d69be8c66ae874509c5fa31`.
The release owner records the first-use Edit metric as completely passed and
closes its implementation acceptance. The report retains its accurate
`scenario_only` evidence class: this scoped decision does not convert it into a
packaged product-gate report or accept latency and memory series that were not
rerun.

On 2026-08-14, the working-tree first-use Review metric began at a verified
no-document Workspace. The collector requires a real
Library selection of the frozen 5,000-word RDF-1 Note and reports the complete
activation-to-interactive phase decomposition. Its focused eight-test
`PerformanceProbe` suite, summary self-test, documentation validator, shell
syntax check, fail-closed threshold preflight, and UI-driver test build passed.
The cooled ad-hoc QA 5+30 scenario then completed all 35 ordered records with
no invalid trial, passed Review correctness, and preserved the exact 800-Note
RDF-1 tree. Its 30 retained samples measured 572.096ms p50, 742.752ms
nearest-rank p95, 612.138ms mean, and 1,442.219ms maximum. The release owner
therefore approved first-use Review at p95 `< 1,000ms` with no every-sample
maximum. This working-tree scenario supports the target decision but is not G7
product-gate evidence.

On 2026-08-13, the exact-tagged packaged `v0.1.0-beta.5` G7 run completed the
then-required latency and memory series without an invalid trial or visible-
correctness failure. Warm Library and Search passed; warm Review recorded
360.937ms p95 and failed its current limit. Key-to-paint, Edit/Source
transition, cached preview, warm Edit, and visible projection passed. Its cold
Review/Edit boundaries and RSS rule were later replaced by the current §21.4
first-use and convergence contracts, so that report establishes neither current
first-use nor current memory acceptance. G7 remains open pending one complete
rerun against the current contract.

The subsequent bounded working-tree remediation removes a duplicate initial
Vault open, avoids loading the Review mathematics runtime and fonts for prose,
removes repeated accessibility snapshots from the retained-memory driver, and
adds fail-closed packaged 100,000-CJK and accessibility-environment evidence.
An ad-hoc-signed dirty Release diagnostic then passed the packaged CJK journey
in 13.864 seconds and restored the complete 800-Note RDF-1 manifest exactly.
Its observer-free memory journey kept the same stable process roles; the final
ten-sample span was 1,605,632 bytes versus 3,473,408 bytes for the preceding
span, and the final-tail medians grew 0.236%. Under the corrected bounded,
decelerating convergence rule this is a pass. These diagnostics validate the
repair paths but do not replace the cooled, clean, exact-tagged packaged rerun.

On 2026-08-24 Search corrected its stale benchmark to canonical `keywords`,
managed Metadata, and 50 ordered nonzero results. Schema 11 compacted checked
offsets and pushed canonical filters into the existing query. On 2,056 Notes,
database size fell 49.37 to 23.43 MB and property-only p95 285.6 to 56.6 ms.
This is local regression evidence, not packaged G7 or researcher acceptance.

## Upgrade and distribution evidence

The current complete-gate snapshot above includes the deployment-remediation
working tree. The canonical
Debug UI smoke passed, followed by focused Restore Access application
termination and portable Analysis/Zotero routing journeys. Headless coverage also
proved that fresh machine registration preserves portable Triptych, Vault, and
Note identities without rewriting the manifest, and that renewed folder access
rebinds one machine-local Vault path. These are disposable-fixture and ad-hoc
development proofs, not clean-account installed-artifact or human acceptance.

The exact `v0.1.0-beta.8` tagged tree produced the ad-hoc-signed sandboxed App
inside `Scholium-v0.1.0-beta.8-macos-arm64.dmg` and the independent
`Scholium-CLI-macos.zip`, each with matching provenance and checksum. Strict
signature checks found App Sandbox on the App, no App Group, no CLI executable
or `.local` entitlement in the App, and no App Sandbox or App Group on the CLI.
The verified, read-only-mounted DMG exposed exactly the App and Applications
alias. The exact CLI ZIP was expanded, installed under an isolated user-local
prefix, and invoked by basename from an unrelated working directory. GitHub
published the exact tagged source and four release assets, and independent
post-publication downloads matched both SHA-256 files. This is exact-tag DMG
release evidence and supersedes the earlier dirty diagnostic packaging proof.

Distinct-build upgrade fixtures preserve exact vault bytes and reject unsupported
newer schemas without authorizing a compatibility path. Local source-first
assembly has passed metadata, license, resource, path-disclosure, signature-
structure, version-matched CLI, DMG, CLI ZIP, checksum, and optimized
Release-build checks with disposable inputs. The released bundle is ad hoc
signed. Clean-account artifact testing, packaged performance, packaged visual
acceptance, the timed-out first-launch UI journey, Agent field trials, and final
researcher acceptance remain open after their bounded Beta-release waiver.

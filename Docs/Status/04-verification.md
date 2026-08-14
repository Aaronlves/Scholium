# Implementation Status: Verification Evidence

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Latest dated proof boundary.

## Current verification snapshot

**Environment:** 2026-08-15, Xcode 27 beta, Swift 6.4, macOS 27.0 SDK.

The independent-CLI cutover's current-tree integration attempt validated the
closed documentation manifests and shipped Skill resources; TypeScript checking
and 199 Web editor tests; reproducible editor, mathematics, and Mermaid bundles;
475 Core tests plus 3 Search performance tests; 138 Contracts tests; 231
Application tests, 11 bridge tests, and 1 serialized architecture measurement;
and 626 of 627 App tests. Its only failure was a source-boundary test that still
tried to read the deliberately deleted `CommandLineToolContracts.swift`; that
obsolete read was removed and the owning test then passed 1/1. The complete gate
was not rerun after that repair, so this is not represented as one uninterrupted
complete-gate pass.

A subsequent fresh diagnostic Release build completed in 177.08 seconds and
produced separate sandboxed App and standalone CLI archives. The package smoke
extracted and installed the CLI into an isolated user prefix, launched it by
basename from an unrelated working directory, and validated its provenance. A
packaged UI journey proved that a clean isolated launch enters Bootstrap while
the production machine state remains unchanged. Focused Settings UI and signed
loopback-bridge probes also passed against disposable fixtures.

This evidence is not a clean tagged, Developer ID signed, notarized release; an
external Agent download from the published GitHub asset; a complete UI-suite or
human accessibility exercise; a source-fidelity review of private research; or
researcher acceptance.

## Focused interface evidence

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
  disposable focused evidence, not an external Agent download or clean-account
  installation.
- On 2026-08-14, the existing-Note save cutover passed 228 focused tests: 86
  Core, 8 Contracts, 31 Application, and 103 App tests. The fixtures cover
  coordinated system replacement, exact BOM/CRLF readback, metadata changes
  remaining outside save authority, external-writer conflict, symlink and
  parent exchange, readback mismatch, pre- and post-replacement interruption,
  `SIGKILL` restart reconciliation, checkpoint and move propagation, removal of
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
  complete current-tree coverage above now includes that repair. Real packaged
  File Provider acceptance remains open.
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
- On 2026-08-11, one isolated Debug QA journey created an Analysis first with
  no role seed and then with `tags: [seeded]`. Both commands bypassed a naming
  or Properties sheet, presented Edit, exposed keyboard focus at the exact body
  insertion point, persisted the first typed marker in the body, and preserved
  the expected source bytes. The seeded Note also exposed the `seeded` Tags
  capsule in Overview while the journey remained in Edit. XCUITest timing
  includes its own menu and polling overhead, so this is behavioral evidence
  rather than a visible-latency measurement or researcher acceptance.
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

The current-Run Material lineage cutover passed 57 focused tests across nine
owning Contracts, Application, and architecture-boundary suites with Xcode 27
beta and Swift 6.4. The tests cover the closed `inspect_materials` clause,
path-free typed source and Zotero response data, canonical Material-envelope
revalidation for Context Use including a source change between inspection and
Result submission, current/changed/missing/unavailable continuation checks,
schema cutovers and round trips through Continue Result, authenticated Run
Context, bridge, and Local Execution, source-access containment, process-bound
Session regressions, and module/import ownership.

This proves the repository-level Material owner and lineage contract on
disposable fixtures. It does not prove checkout-external App/CLI installation,
production installed user-local bridge behavior, human accessibility, sustained research use, or
philosophical quality.

The subsequent Researcher State continuation cutover passed 44 focused tests
across eight owning Contracts, Application, Core-store, bridge, and architecture suites
with the same toolchain. The tests prove that a parent-Run state reference is
removed from child handoff items and reference checks, a typed requery
requirement survives Result, bridge, authenticated Context, and Local Execution
round trips, and the child query receives its own Run scope and the current
replacement Settlement. They also retain the source-family continuation and
Context Use regressions and reject retired outer schemas.

This establishes requery rather than state handoff for the current target-Note
view. It does not prove that the view is complete, that a researcher judgment
is correct, or that a future provider retrieves every relevant current owner.
The Settle recovery pin remains outside this academic view and was not promoted
into importance, stance, or adoption.

The provider-replacement and summary-attribution alignment passed 44 focused
tests across seven Search, Contracts, Application, bridge, and architecture
suites with Xcode 27 beta and Swift 6.4. One nonempty disposable provider uses
a fixed summary candidate rather than production Search, checks the authorized
Workspace snapshot, and produces current, stale, and unavailable outcomes. A
fixed-query mismatch remains an Invalid Query rather than returning an
unrelated candidate. The current item matches production summary discovery on
owner, unknown actor,
role, fingerprint, exact match range, Run/Triptych scope, currentness,
evidential layer, and retrieval reason; guessed researcher authorship fails
Context Use, while the valid reference survives Record and Continue Research
revalidation without persisting provider or query identity.

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

### Case A: Property provenance and discovery

Given a Topic with an explicit top-level `summary` and an unknown custom YAML
key, verify that Search can explain presence and exact string-value matches
without granting the custom key canonical Property semantics or treating the
summary as evidence.

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

The latest isolated Search v7 regression report recorded a cold rebuild of
778.043 ms, warm-query p95 of 28.332 ms, incremental-publication p95 of
21.065 ms, database size of 46,254,760 bytes, and process peak RSS of
144,310,272 bytes on the deterministic 800-Note fixture. These are regression
measurements, not the packaged G7 gate or approved release limits.

## Upgrade and distribution evidence

The current integration snapshot above includes the deployment-remediation
working tree but is not one uninterrupted complete-gate pass. The canonical
Debug UI smoke passed, followed by focused Restore Access application
termination and portable Analysis/Zotero routing journeys. Headless coverage also
proved that fresh machine registration preserves portable Triptych, Vault, and
Note identities without rewriting the manifest, and that renewed folder access
rebinds one machine-local Vault path. These are disposable-fixture and ad-hoc
development proofs, not clean-account installed-artifact or human acceptance.

The same working tree produced ad-hoc-signed sandboxed App and independent CLI
diagnostic ZIPs with matching provenance and checksums. Strict signature checks
found App Sandbox on the App, no App Group, no CLI executable or `.local`
entitlement in the App, and no App Sandbox or App Group on the CLI. The exact
CLI ZIP was expanded, installed under an isolated user-local prefix, and invoked
by basename from an unrelated working directory. The exact App artifact entered
Bootstrap from empty isolated machine state without changing production state.
Developer ID/notarization and a clean external account remain acceptance gaps.
The canonical GitHub `latest/download` CLI URL returned HTTP 404 on 2026-08-15,
so publication of the same-named asset is a current deployment blocker.

Distinct-build upgrade fixtures preserve exact vault bytes and reject unsupported
newer schemas without authorizing a compatibility path. Local source-first
assembly has passed metadata, license, resource, path-disclosure, signature-
structure, version-matched CLI, ZIP, checksum, and optimized Release-build
checks with disposable inputs. The tested bundle was ad hoc signed; clean-account
artifact smoke testing, packaged performance, publication, notarization if
adopted, and release acceptance remain open.

# Implementation Status: Remaining Work

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns remaining implementation, acceptance, performance, and release work; sibling chapters do not restate it.

## Remaining implementation and release work

### Research Skill and Agent co-construction acceptance

**Proposal target**

The approved 2026-08-04 Skill/Agent co-construction proposal required an
implementation-precondition audit and four dependent vertical stages. The
separate Search Foundation engineering exit was the nonrevertible starting
baseline; its schema-8 performance measurement remains historical evidence,
not a label for the current schema-9 index.

**Canonical target**

Specification Sections 2, 5, 8, 13, 16–17, 18, 20, 21 and Architecture
chapters 01, 02, 04, and 05 now own the adopted target: current primary
Markdown Skill registration, exact-Wikilink Practices, academic-only Profiles
and Result Contracts, one Triptych collaboration policy, process-bound local
pairing/Sessions, Run-owned Bounded Write Sets, provider-neutral Research
Context, one canonical result/Record, Record-owned Researcher Evaluation, and
canonical YAML `summary` through the same Search owner.

**Historical implementation at audit start**

The audited starting snapshot implemented catalog/package schema 4, Working Method binding
v2, Action Profile schema 1 with platform capability declarations, permission
schema 1 with per-Skill digest overrides, Local Execution v3 single-Target
runs, Agent Note Change request/allowed correlation plans and one child Run per
extra document, coordination grants over the Application Support Unix socket,
and Record schema 4 without Researcher Evaluation. The bridge has submit,
status, and cancel coordination but no Pairing Code or Connection Session.
`ResearchContext.swift` contained only existing evidential-layer and Note
reference values. This paragraph is chronology, not current behavior or an
alternative product rule.

**Current implementation**

All four automated implementation stages are now reachable through one owner
chain. Registration schema 2, exact primary Markdown/Practice resolution,
academic Profiles, one collaboration policy, citation-style configuration,
Search v6/schema 9 `summary`, process-bound Pairing/Session, App Group bridge,
Local Execution schema 8, provider-neutral Research Context, Run-owned Bounded
Write Sets, nonreusable per-write capabilities, Result submission, Continue
Research, strict Record schema 5, Researcher Evaluation, bounded Method
feedback, and a separately paired one-target Method-improvement Run are wired
through App, CLI, and shared Application capabilities. The
old package/catalog/installer/history, binding-v2, capability Profile,
per-Skill permission, coordination grant/correlation/child-Run, workflow CLI,
parallel Critique-output, custom Action, and old Record decoders are deleted.
Portable registration no longer contains machine paths; its machine-local
locator is Triptych-bound and bookmark-backed.

**Owner, target, and delete condition ledger**

| Audit-start owner | Current owner | Physical delete evidence |
| --- | --- | --- |
| Package catalog/repository/installer/history | Registration + exact primary Markdown + machine-local folder locator + one undo point | Types, sources, resources, CLI routes, previews, and compatibility tests deleted |
| Working Method binding v2/package ID | One hidden registration relation per closed Platform Action | Binding decoder/encoder and package ID absent; schema-1 path registration rejected |
| Practice selections/resource names | Exact Method Wikilinks + Practice Markdown | First-use resolver is sole route; selection/Connections route absent |
| Profile modules and capabilities | Platform Action Definition + flat academic Profile/Result Contract | Profile capability/module/custom-Action fields and UI branches absent |
| Triptych default + per-Skill digest override | One Triptych collaboration policy | Per-Skill override/digest/fallback contracts and settings absent |
| Coordination grant/request authentication | Pairing Code + process-bound Connection Session | Old grant/correlation/child-Run types and bridge operations absent |
| Application Support socket discovery | App Group socket/rendezvous | Production private-container discovery absent; App Group contract excludes research bytes |
| Single Target + request/plan/child Runs | One Run + Bounded Write Set + independent operations | Extension and two-document transaction fixtures exist; child authority absent |
| Function/package/Profile snapshot | Registration/Method/Practices/folder path + Result Contract | Authenticated schema-3 `reload` is exact; no package revisions/resources encoded |
| Separate Search/read/Graph/Property/Record calls | One Application Research Context with replaceable providers | Provider calls Application owners; no parser/index/response store exists |
| Completion fields + Record schema 4 | One Run result + strict Record schema 5/Source Reference | Finalization is singular/idempotent; schema 4 is rejected |
| No Evaluation owner | One optional current partition in exact Record | Both editors share revision/fingerprint CAS and one storage writer |
| Method comment without an execution owner | One current improvement Run in the parent Local Execution record | Explicit App start, authenticated CLI context/submission, exact Method/Practice transaction, terminal receipt, and no queue/history |
| Search v5/schema 8 without summary | Search v6/schema 9 under the same owner | Summary field/range/reason/App/CLI/Saved Search/rebuild paths share the existing index |

**Field migration ledger**

- Primary `SKILL.md` bytes and researcher-authored Practice Markdown remained
  exact. Existing method package folders become ordinary folders; no sibling
  file is deleted or rewritten by semantic cutover.
- Profile text, choices, order, and included/optional/required meaning moved to
  flat academic fields. Note/Material/source selectors and machine facts move
  to Platform Action definitions. Read/write roles, operations, Property
  boundaries, and capability declarations deliberately do not migrate as
  hidden authority.
- Current permission mapped only to the one Triptych policy when its effective
  researcher choice is determinate. Per-Skill digest approval never migrates
  into a secret fallback.
- Repository-owned Record fixtures and callers moved directly to the new
  strict schema. Unsupported pre-release record bytes remain untouched and
  unread; no product compatibility decoder is added.
- `summary` is optional and never backfilled. Index/Record/machine values can
  neither create nor overwrite it.

**Implemented stage boundaries**

1. Stage 1 cut over registration/Practice/Profile/policy ownership and added
   canonical `summary`, Source Reference, Context Use, and Result Contract.
2. Stage 2 added secure local Pairing/Session, App Group bridge, layered Run
   delivery, restart invalidation, replay/scope/user rejection, and hidden
   credential channels.
3. Stage 3 added Research Context, Bounded Write Set, independent multi-document
   operations, one result, conflict/recovery, and Continue Research.
4. Stage 4 added Action-specific defaults, Researcher Evaluation, bounded
   Method feedback, one separately authenticated Method-improvement Run with
   exact-revision recovery, shared UI editors, and disposable experiment seams
   without a production Research Memory backend.

**Required next evidence or work**

The 2026-08-04 automated implementation closure passed the complete repository
gate, optimized Release build, isolated source-first package smoke, documentation
authority and localization validators, and diff check. A separate final
proposal-conformance pass found no P0/P1; it removed stale current Search-v5
labels and aligned the sandbox probe with the generic authorization-denial wire
contract before the final gate. Production residue scans found no retired
package/workflow/permission/Profile-module/Agent-note-change owner and no
Research Memory, Agent-only parser/ranker/index, or direct-JSON context side
path.

Developer ID signed and externally installed App/CLI operation through the
production App Group, long-term research use, independent blind philosophical
review, genuine VoiceOver/Full Keyboard Access/200% mixed-script acceptance,
and final experiential acceptance remain separate human/distribution evidence.
The explicit direct-relation XCTest host regression also remains pending even
though its isolated product journey passed. All automated fixtures remain
disposable and nonprivate.

### Physical editor input

**Implemented boundary**

The 2026-07-31 common Edit/Source input cut removes the native per-transaction immutable full-source
copy and `@Published editingSource` round trip. `EditorExactSourceBuffer` applies checked UTF-16
deltas in place, retained reconstruction reads that mirror, and complete source crosses into
Document state only at save, conflict, recovery, or another explicit lifecycle boundary. One
deadline-driven autosave task moves its deadline during input; complete CodeMirror history is
captured only at explicit view reconstruction.

**Required next evidence or work**

Recheck physical English and installed Chinese IME input in an isolated QA. The exact-buffer and
real-WKWebView regressions are structural evidence, not human visible-latency acceptance or a
release threshold.

### Editor semantics and components

**Implemented boundary**

`MarkdownSemanticDocument` remains the Contracts-owned committed projection. The locked dialect and
one Lezer-backed Edit catalog now provide typed roles, nesting, exact UTF-16
construct/marker/visible/target/alias ranges, including the ATX separator boundary and composite
footnote definitions. One mode compartment keeps Source free of every Edit projection.
`live-projection-index` owns the immutable mutation-sensitive catalog. Index construction now asks
CodeMirror's parser for bounded whole-document completion before reading that catalog; a regression
places inline mathematics beyond the initial 3,000-unit viewport and proves it remains indexed,
while a later parser-only transaction remains the completion path when the budget is exceeded.
Direct CodeMirror StateFields own semantic line geometry, top-level inter-block gaps, frontmatter,
tables, display mathematics, inert raw HTML, Callouts, and footnote-reference locators; the bounded
viewport plugin owns inline presentation only. Review and Edit share document, quotation, code,
table, Callout, mathematics, inline-role styling, and content-owned base direction; Review alone
owns the rendered footnote section. `live-selection` owns both the committed projection snapshot and
geometry-neutral text paint. `source-direction` owns the viewport-bounded per-line Source adapter
without semantic projection; the common CodeMirror configuration owns per-line cursor direction and
syntax-tree bidi isolation. The comparison fixture treats the definition marker as a mode-specific
exact-source object while its body uses ordinary Edit projection at that one source position and
retains zero undeclared must-match difference. Construct-scoped click and reveal, a zero-length
Wiki-syntax caret without selection-like bracket decoration, exact raw-HTML and Callout activation,
symmetric separator navigation and direct pointer entry across the complete authored separator line,
direct definition-body projection, compact list markers, quotation inset parity, 200% pointer
mapping, mode convergence, Source exact bytes and line direction, real RTL pointer placement and
insertion in Source/Edit, no selection-match highlighting, focus persistence, exact 100,000-CJK CRLF
editing, and the complete WKWebView suite have automated coverage. A synthetic composition boundary
proves that a requested mode remains unpublished until composition ends; it does not substitute for
an installed IME. Display mathematics is centered, italic, automatically numbered at the physical
right, and locally scrollable on both surfaces. Rendered Edit footnote sections, collapsed paragraph
separators, per-list gap widgets, second Callout activation ownership, and ViewPlugin-owned vertical
geometry are absent. Researcher visual evidence and its limits are recorded once in Verification
Baseline.

List prefixes and task items are cached `LiveProjectionIndex` range sets.
Topology-safe prose edits map them without another list scan, and horizontal
source entry uses indexed boundary queries rather than copying and sorting
every block and list range on each Arrow key. Review and Edit consume one
marker-track contract; read-only and editable task controls retain checked
state and exact prose geometry, while pointer and keyboard/menu toggles share
one exact-marker rule across supported list markers.

**Required next evidence or work**

Researcher reacceptance of corrected Arabic/Hebrew Review/Edit/Source behavior; real pointer and
keyboard experiential acceptance of bidi cursor and selection behavior, completed-selection toolbar
timing, standard Edit/Source secondary-click editing, construct-scoped syntax, the
direct footnote-definition workflow, compact list rhythm, H1 rule placement, and the post-migration
mode handoff; speech, text-service, installed CJK/RTL/IME, composition recovery, inactive Edit
researcher review, and retained-memory journeys remain open. Syntax/parser changes must extend
shared fixtures first.

### Complete interface gate

**Implemented boundary**

The runner has explicit `smoke` and `complete` profiles; complete dynamically enumerates tests,
builds once, and runs serially. Each launch receives isolated `SCHOLIUM_HOME`, `CFFIXED_USER_HOME`,
session identity, disposable fixture data, and disabled system restoration. The 2026-07-28 run
executed all 74 current journeys; its three wait/focus harness failures and compact-width
conditional skip passed focused revalidation after their test corrections.

**Required next evidence or work**

Genuine VoiceOver speech remained conditionally skipped. Physical Full Keyboard Access, installed
IME, researcher visual review, real system-setting acceptance, and release-app execution remain
open.

### Performance

**Implemented boundary**

Privacy-safe instrumentation, strict validation, exact WebKit attribution, fail-closed sampling, and
RDF-1 v2 exist. Editor hot paths use one incrementally maintained exact-source/CRLF mirror, one
cached immutable mutation-sensitive projection index, bounded inline updates,
construct/physical-line selection signatures that skip decoration work while the visible projection
is unchanged, direct CodeMirror `Text` line access for Enter/Tab/Backtab/link activation, coalesced
bridge v9 reports, nonpublished selection, and one-shot Read restore. A 2026-07-31 input cut
uses a physical-line-local semantic-topology proof without component-local regex/mapping
authorities; ordinary prose beside rich inline Markdown maps the central index, while deletions,
structural markers,
cached-content constructs, and changed or uncertain topology still rebuild. Review link-preview
arrival now updates a bounded in-page map instead of causing a second complete `loadHTMLString`; a
real WKWebView test preserves page identity across that update. The cold-start cut removes repeated
UTF-16 scans, per-Work identity reads, and serial three-vault preparation; deterministic
100,000-CJK, RDF-1, refresh-concurrency, Search, and visible-library diagnostics pass. On Mac16,12 /
macOS 27.0, a Debug V8 regression microbenchmark of 200 tail insertions into a mixed-CRLF
approximately 100k source reported 4.960–9.871 ms across current observations. These internal
scenario samples and structural regressions are not visible-latency
measurements or release thresholds. Three Debug launch samples and incomplete 3/5-sample memory
prefixes remain nonrelease evidence.

The 2026-08-03 selection-surface cut bounds Review excerpt/context extraction
at the DOM Range instead of stringifying the whole preceding and following
document; it also skips equivalent Edit-toolbar state writes and keys
CodeMirror position measurement for replacement. In one Mac16,12 / macOS 27.0 /
Xcode 27.0 Debug real-WKWebView diagnostic with 320 synthetic paragraphs and
a 27-character selection, counted
Selection/Range string output fell from 218,118 characters to zero and one
observed completion fell from approximately 4 ms to 2 ms. Twenty-four
equivalent Edit-toolbar updates fell from 168 observed attribute mutations to
zero. These are regression diagnostics for that fixture and build, not visible
latency acceptance or a product gate.

The 2026-08-04 list-navigation cut replaced whole-Note range merging and
sorting on each horizontal Arrow key with central immutable-index boundary
queries. In six fresh Debug V8 observations on the same Mac16,12 / macOS 27.0 /
Xcode 27.0 environment, 100 trailing-boundary queries over 10,000 synthetic
list prefixes took 74.597–131.773 ms with the former merge/sort algorithm and
0.081–0.162 ms with the indexed query. This is a deterministic regression
diagnostic, not a visible-latency or release threshold.

**Required next evidence or work**

Complete the 51-sample memory scenario, add visible Editor latency actions, approve thresholds,
freeze/tag/package the source, and run the 5-warm-up/30-sample G7 protocol on R1.

### Search

**Implemented boundary**

Contract v6 retains one Note Triptych corpus, adds the Application-owned Record provider, Property
and direct-relation clauses, and deletes semantic `status` projection and the parallel direct-
connection path. Finite syntax, visible-semantic projection, CJK verification, exact identity, rank
reasons, This Note occurrences, provider-aware freshness, Saved Search needs-editing, CLI parity,
and atomic generations remain implemented. Field/canonical-value completion is reachable; the typed
scope-first context for Property-key and Note-identity candidates is not yet supplied by Application.
Contracts and the Application response carry a typed Search explanation, but the current Search
surface drops that response value and reparses visible query text to construct its own shorter
explanation. Normalization, ordering, and limitation details therefore do not yet satisfy the
canonical Explain Query presentation contract.

**Required next evidence or work**

Retain the Application response explanation through the window projection, render it without a
view-owned parse path, and complete its normalization, ordering, and limitation details. Then
complete the 30-sample GUI first-paint protocol, remaining disposable UI matrix, dynamic scoped-
candidate completion only if real use warrants it, and human pointer/VoiceOver/Voice Control/
Dictation/CJK IME/visual/ranking and research-use acceptance. A repeatable XCTest host run for the
already observed direct-relation journey also remains verification-infrastructure closure work.

### Research Guidance recovery

**Implemented boundary**

Primary Methods, exact-Wikilink Practices, academic Profiles, one Triptych collaboration policy,
one code-catalog citation style, one previous Method/Practice edit, and settled Note retention are
reachable and fail closed on invalid state. Package installation/history and per-Skill policy are
retired rather than recoverable product surfaces. External Method/folder paths use a private
Triptych-bound bookmark locator and never enter portable registration.

**Required next evidence or work**

Verify moved/evicted external Method bookmarks in a packaged sandbox and retain process-interruption,
late-write, one-previous-edit, and machine-locator corruption evidence. Unsupported pre-release
registration/Profile bytes stay untouched and fail closed; no binding-v2 reset or compatibility UI
will be added.

### Interface writing

**Implemented boundary**

D-112 defines the short-label, exceptional-explanation, and nonduplication contract. Current default
Action rows still show routine summaries and reuse them as hover help; the remaining help and
accessibility-hint call sites have not received a complete responsibility audit.

**Required next evidence or work**

Remove duplicated explanation, keep authority and recovery detail in its owning presentation, then
verify localization, 200% reflow, keyboard use, and genuine VoiceOver.

### Distribution

**Implemented boundary**

Local source-first packaging, resource/signature validation, CLI execution, ZIP, and checksum smoke
exist. Debug, QA, and release assembly all copy the D-097 canonical application icon named by the
bundle plist.

**Required next evidence or work**

Clean exact tag, external install, canonical-icon Finder/Dock inspection, published source/artifact
provenance, and G9. Developer ID and notarization remain outside the current source-first Beta gate
unless a later distribution channel adopts them.

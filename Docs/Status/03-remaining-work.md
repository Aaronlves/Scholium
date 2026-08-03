# Implementation Status: Remaining Work

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns remaining implementation, acceptance, performance, and release work; sibling chapters do not restate it.

## Remaining implementation and release work

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

**Required next evidence or work**

Complete the 51-sample memory scenario, add visible Editor latency actions, approve thresholds,
freeze/tag/package the source, and run the 5-warm-up/30-sample G7 protocol on R1.

### Search

**Implemented boundary**

Contract v4 retains one Triptych corpus and the v3 lexical behavior while deleting semantic `status`
projection and query support. Finite syntax, visible-semantic projection, CJK verification, exact
identity, rank reasons, This Note occurrences, CLI parity, atomic generations, and direct Related
remain implemented.

**Required next evidence or work**

Complete the 30-sample GUI first-paint protocol, disposable UI matrix, and human
pointer/VoiceOver/Voice Control/Dictation/CJK IME/visual/ranking acceptance.

### Research Guidance recovery

**Implemented boundary**

Working Methods, Researcher Skills, Action Profiles, staged disabled-first installation, independent
Triptych copies, standing policies, and guarded package maintenance are reachable and fail closed on
invalid state.

**Required next evidence or work**

Complete retained staged-install/cross-volume recovery cleanup and define the researcher-visible
quarantine/reset route for malformed binding-v2 or Profile state; retain process-interruption and
late-write evidence.

### Interface writing

**Implemented boundary**

D-112 defines the short-label, exceptional-explanation, and nonduplication contract. Current default
Action rows still show routine summaries and reuse them as hover help; the remaining help and
accessibility-hint call sites have not received a complete responsibility audit.

**Required next evidence or work**

Remove duplicated explanation, keep authority and recovery detail in its owning presentation, then
verify localization, 200% reflow, keyboard use, and genuine VoiceOver.

### 1.0 Codex handoff

**Implemented boundary**

Copy-first Beta handoff is separate and reachable.

**Required next evidence or work**

Implement supported-app/root validation, new-task adapter, locator-only composer, explicit
submission/copy fallback, retry/cancel/Unicode/accessibility/reactivation, and unchanged-run
recovery. Do not begin Run with Codex.

### Distribution

**Implemented boundary**

Local source-first packaging, resource/signature validation, CLI execution, ZIP, and checksum smoke
exist. Debug, QA, and release assembly all copy the D-097 canonical application icon named by the
bundle plist.

**Required next evidence or work**

Clean exact tag, external install, canonical-icon Finder/Dock inspection, published source/artifact
provenance, and G9. Developer ID and notarization remain outside the current source-first Beta gate
unless a later distribution channel adopts them.

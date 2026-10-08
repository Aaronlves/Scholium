# Architecture: Documents and Editor

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Retained
document ownership, exact-source transport, and nonauthorizing rendering.

## Documents and CodeMirror

Document owns vault/Note-keyed sessions. Transfer moves the same owner; document
identity survives attachment while transport identity rotates. Dirty, composing,
conflicted, saving and recovery states pin sessions. Destination leases precede
release; close flushes before membership removal. Clean unleased sessions discard
source, Undo, rendered content and previews without a closed-Note presentation
cache. Window navigation visits own revision-bound return positions separately
from open document sessions. Equal paths across vaults remain distinct.

`DocumentController` owns one persisted window-wide mode. Sessions retain
editor/flush identity, checked exact mirror, committed revision, presentation/
pending intent, allocation/configuration, source-bound scroll, save and conflict/
retry/comparison state across mode/layout/theme changes. Hidden hosts cannot
receive input/accessibility focus. Mount committed Review only for Review/read
recovery; reconstruct after Edit/Source. Mode presentation awaits acknowledgment;
unsafe Review retains editor/recovery.

The document host owns one visible native surface. Review and editor keep
separate viewport observations; mode handoff alone copies anchors or fallback
fractions. Unmount Review outside Review or read recovery; restore its saved
position when Review returns.

Detachment atomically freezes input and captures exact source, selection and
history. Detached saves require unchanged document/revision/generation proof;
cancelled transitions resume only their matching suspension. Committed snapshots
update clean detached sessions atomically. Dirty sessions retain exact bytes for
conflict comparison. External events reconcile all tabs by stable identity before
changing paths/projections; clean deleted sessions release, unsafe sessions retain
their buffers.

Managed creation installs exact committed source and initial intent together.
Initialization/focus acknowledgments and mapped selection must match before
readiness; failure preserves source behind retry/Source. Clean external publication
replaces pending source/boundary together. Revision changes invalidate stale
readiness; Review/recovery HTML caches source and authorized local-image revisions.
Document owns lightweight position/focus,
not another writable path-mapped presentation record.

### Editor boundary contract

Edit and Source share CodeMirror state, selection, composition and Undo; Review
projects committed source. Writable authority remains exact Markdown, never HTML.
LF editor, exact UTF-16 source and UTF-8 coordinates remain distinct. The immutable
exact-source StateField and inverse effects preserve BOM/newlines through Undo/Redo.
Trusted paste reads original AppKit Unicode, avoiding WebKit NFC, through a
document/generation/selection-bound CodeMirror request.

Swift retains a checked exact mirror and generation. Ordered deltas prove deleted
spans and exact insertions before atomic application. Full-buffer capture is
reserved for persistence, conflict, recovery, reconstruction and commands requiring
it; ordinary input does not echo/materialize the whole Note. Unexplained current-
identity disagreement pins the session dirty and coalesces a complete editor read
before save. Both runtimes enforce the same source limit; escaped transport
capacity is checked separately.

Requests bind protocol/request, session/document, fingerprint, generation and
expiration. Mutations serialize and recheck identity after suspension; snapshots
may observe later generations. Expired/composing work cannot mutate. Outbound
source uses structured page-world arguments/JSON, never executable interpolation
or Foundation object decoding that loses leading BOM.

A save acknowledges one immutable committed snapshot. Newer input stays dirty
and schedules another save rather than being overwritten. Proven commits remain
retained until editor acknowledgment; lost acknowledgments replay idempotently
against that exact commit, not by reissuing an uncertain filesystem write.
Full-buffer reconciliation precedes save/departure. Clean external source may enter
through generation-checked non-history replacement; dirty source enters Conflict.
Review handoff relinquishes focus and requires a clean, noncomposing, conflict-free
final flush. Close/quit cannot classify a dirty Review session as clean.

Replacement navigation captures the selected flush/reconstruction policy once;
it does not duplicate history/position capture. Content-process termination reloads
the controlled page and restores a matching bounded snapshot. If unavailable,
recovery uses the checked mirror/last selection, never disk over dirty source.
Undo-history loss is distinct from source loss. Invalid reconstruction cannot
silently normalize or repair source.

One atomic CodeMirror configuration owns Edit/Source facets and all projection
extensions/listeners. Initialization or absent facet fails closed to Source.
Source has no semantic widgets or Live Preview overlays, while keeping shared
exact navigation/editing. Pending native input cannot independently toggle DOM
mode. Lezer topology completion is bounded; incomplete parsing remains incomplete
until the parser transaction, with no regex fallback or second Markdown parser.

CodeMirror owns real ranges, caret, text commands, copy and IME. Selection paint
is a separate disposable character-range projection; it cannot extend selection
into widgets, gaps, blank separators or virtual line endings. Review owns native
DOM Selection and read-only highlights. Pointer selection is evaluated as completed
context only at pointer-up; keyboard selection remains immediate. Projected entry
maps to one exact source position in the same state, not an independent range.
Direction adapters consume one content/bidi model without replacing text or
altering composition, selection, insertion, deletion or Undo.

Markdown commands are atomic Undo transactions preserving other bytes.
Multi-selections refuse protected frontmatter, literals/code/comments/raw HTML
and ambiguous or malformed boundaries. Filename drafts use identity-checked
native moves; errors remain.

### Source locations and transient interaction

The document session owns fingerprint-bound semantic scroll continuity and fallback
fraction for each document surface. Only lifecycle edges create restoration
requests; ordinary reports update only the active surface and do not publish a
second scroll state. A mode handoff explicitly transfers the current source
anchor before Review restoration. One tokenized claim is acknowledged only after
successful current-load restoration. Cancellation/failure/report echoes cannot
consume or recreate requests. Review and editor map the same exact source contract
to native geometry; invalid mappings fall back, never guess textual matches.
Arrival requires matching document/load identity and actual destination completion.

Review selection maps only source-identical complete blocks. Formatted/synthesized
content remains unmappable rather than searched back into source. Document-bound
locations recheck revisions and generations before selection/reveal. Superseded
requests fail; unmappable editable passage requests may use Source. Current-Note
Search consumes an immutable checked editor snapshot without flush, save or index
publication; navigation validates freshness before a non-history reveal.

Previews/completion/Find retain originating session/window, request and geometry
identity; scroll, exit, departure and teardown dismiss them. Swift owns graph
resolution, committed previews, containment and URL policy; WebKit reports
anchors/geometry only. Stale/ambiguous results are discarded. CodeMirror owns Find/replacement;
Review matching is read-only. Completion/insertion rechecks context, generation,
selection and protected ranges for one Undo. Receipts are revocable projections,
not buffers.

Typed WebEditor preview/completion/selection ports share arbitration of one native
surface. Review admits bounded read-page extensions; Chat owns reply lifecycle,
projection, WebView and events outside the neutral reader.

Application's `ZoteroDocumentIntegration` implements Contracts' callback port,
composed by `WorkspaceStore`; Zotero owns picker/CSL. `MarkdownEditorSession` and
`zotero-transaction.ts` stage exact source/selection and companion metadata in one
CodeMirror history, including metadata-only Undo and dirty state. Managed snapshots
bind compact `cite:` occurrences to checked companions; standalone documents keep
embedded fields. Contracts/editor project readable source, never vendor HTML;
native routing rejects reserved citation URLs. Completion confirms cleanup only;
cancellation revokes acceptance and drains callbacks. Document notices inspect
committed Review source/companion or the retained editor pair. Persistence belongs
to [Source Storage](05-source-storage-and-read-models.md#vault-write-and-prewrite-recovery-boundary).

Writing continuation shares the retained editor's inline suggestion owner, with
separate generation-bound request/cancellation messages. A short post-input pause
may request only an unfinished current sentence; completed sentences and structural
contexts suppress AI while local completion remains independent. Window composition
captures the checked current sentence inside its paragraph and insertion receipt,
packs bounded Related-Content background, and rechecks identity, focus, conflict
and configuration before generation and publication. Its one-result retrieval cache
is bound to runtime, Note, complete Search generation, exact seed revision and focus;
it is neither another index nor query history. Returned text and status stay request-bound
through inline preview; identity guards clear both. Machine-local Writing Assistance preferences share the model with explicit
selection actions and remain independent of conversation settings.

Attachment preparation joins the existing editor insertion and scoped rollback
in [Source Storage](05-source-storage-and-read-models.md#shared-read-models-and-source-properties).
Quick Look retains only its scoped URL lease until dismissal/replacement/teardown.
Review/Edit share native image admission. Generation-bound catalogs alter
presentation only; CodeMirror owns geometry, remeasurement and exact-source activation.

### Shared document rendering

Contracts owns the committed semantic document and immutable editing dialect.
Swift supplies committed Review, graph and diagnostic meaning. TypeScript may
incrementally parse uncommitted source for immediate projection/transformation
only. Shared fixtures require agreeing spans/meanings; unsupported dialects fail
closed. Source syntax remains owned by the Specification, not adapter heuristics.

One frontmatter-aware Markdown language owns complete source. Valid YAML remains
in the same editor/history; unclosed frontmatter suppresses semantic projections
without hiding exact text. Typed extension nodes locate constructs; no consumer
infers them outside proved syntax ranges. Normalized parser views map every node
back to exact original half-open UTF-16 coordinates, preserving BOM, CRLF, Unicode
and final newlines. Marker/visible/parent ranges distinguish source from layout.

Review and Edit use one YAML presentation contract, with representative roles and
CSS classes pinned by the shared frontmatter parity fixture. `FrontmatterPresentation`
is Review's bounded lexical projection for already bounded authored YAML lines; Edit
uses the equivalent CodeMirror projection and rejects implicit bare keys that Review
does not present as keys. `NoteDocument`/Yams remains the sole semantic parser and
source authority; neither presentation adapter can parse, repair, authorize or edit
metadata.
Graph publishes directed authored occurrences; incoming/outgoing are projections
of the same exact occurrence, not deduplicated philosophical meaning.

One central semantic/topology index owns literal and construct ranges. Components
derive projections from it, not parallel regex invalidation. Proved topology-safe
prose changes may map ranges incrementally; structural or uncertain changes rebuild
conservatively. Complete whole-Note topology cannot be assumed from a viewport tree.
Direct CodeMirror fields own block/line geometry; viewport plugins own inline
projection only. Authored separators remain exact rows, not source-less duplicate
spacing. Semantic widgets, selection, pointer mapping and scrolling share native
measurement. One Live Presentation Layout coordinator owns presentation-only
geometry continuity: projection owners mark an affected source range with a
typed effect, and the coordinator captures a stable source-line viewport anchor
before decoration exchange from CodeMirror's logical line-block measurement,
then corrects it in a later read/write measure cycle. Callout fold state remains
session-local in its projection field, but it does not own scroll or pointer
state. No decoration state is mutated by an independent geometry cache, and no
projection owner performs a second scroll correction.

Read/Edit share semantic components/presentation. Application owns byte-checked
Appearance/snippet storage and explicit reload. Stale/invalid external edits preserve
loaded state and reject stale GUI saves. Both hosts transport protected components,
dynamic presentation and sanitized user CSS in distinct ordered layers. Document-bound
style/font measurement preserves WebView, EditorState, source, composition and Undo.
Source fonts configure the same editor.

Review emits sanitized read-only DOM. In-page projection updates preserve selection
and scroll; only source/style/capability page identity can replace the page.
Inactive Edit constructs map to source; activation exposes exact Markdown in the
same EditorState. Tables and mathematical/diagram output never become writable
round-trip models. Callout folds are session-local and source-neutral; hiding a
body cannot hide the active caret. Footnote preview resolves the current definition
only; normalized continuation content maps back to exact source, and shared fixtures
check block ownership as well as IDs.

### Embedded renderers and trust

Raw HTML stays escaped/inert exact source. KaTeX is pinned and locally bundled with
allowlisted read-only fonts. It renders bounded untrusted input with trust disabled
and HTML/MathML output, no remote resources; failure retains escaped source and
diagnostics. Only original delimiter spans are editable.

Mermaid is pinned/local and loaded lazily by a versioned document-bound bridge
request. Review begins with escaped source-located fences; inactive Edit uses
source-backed block projections. Source installs none. Activation reveals the exact
fence; cancellation/teardown aborts stale rendering. Serialized calls protect
runtime-global configuration.

The diagram adapter bounds source/lines/edges and permits strict static local
rendering only: no authored initialization, HTML labels, links/callbacks, external
resources or diagram-local styling. Returned SVG is parsed and rejected for active/
embedded content, scripts, links, events, external URLs, unsafe CSS or selectors.
Only validated nodes mount once in isolated, bounded app-controlled presentation;
binding callbacks and secondary HTML sinks are forbidden. Local fragment marker
references remain admissible. Protected semantic variables own theme. Missing
authored accessibility descriptions retain source-based alternatives and visible
diagnostics, never inferred philosophical content. Bundled dependency/license
provenance follows the actual build graph.

### Measurement boundary

Bounded content-free diagnostics exclude researcher identifiers. Visible-paint
samples end at native/WebKit presentation. Process attribution verifies launchd
ownership/executable identity, never names/PPID guesses. Source-free network-denied
priming grants no source/runtime authority. Isolated performance driving and
packaged evidence follow [Specification §21.4](../Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
Status owns dated results. Focused checks cannot pass the complete gate.

## Editor responsibility map

| Boundary | Owner; excluded responsibility |
| --- | --- |
| Document workflow | `DocumentController` / `DocumentSessionStore`: identity, modes, save/conflict; no DOM. |
| Editing authority | CodeMirror / `exact-source-history.ts`: source, selection, composition, Undo; no filesystem. |
| Checked transport | `MarkdownEditorSession`: mirror, request admission, recovery. `MarkdownEditorWebView.Coordinator`: page lifecycle/routing; no second buffer. |
| Native viewport | `DocumentEditorHost`: active surface. `MarkdownEditorMountView`: cancellable page acquisition. `DocumentWebViewContainer`: geometry/input/accessibility. |
| Native environment | `DocumentWebEnvironment`: attached-page system-color/inset projection; no source, scroll or hit-testing. |
| Web presentation | Semantic projections, `scroll-coordinator.ts`, `live-presentation-layout.ts`: rendering/restoration; no save authority. |
| Independent controls | `document-title.ts`: filename drafts/rename receipts, shared composition gate; no Markdown edits. `EditorWritingContinuationController`: cancellable requests/publications, bridge-owned admission. |
| Read capabilities | `SafeMarkdownReadWebView` / `ScholiumReadPageExtension`: committed projection; Chat owns reply extensions. |

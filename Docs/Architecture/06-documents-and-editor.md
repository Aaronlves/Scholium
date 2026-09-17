# Architecture: Documents and Editor

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Retained
document ownership, exact-source transport, and nonauthorizing rendering.

## Documents and CodeMirror

Document owns vault/Note-keyed sessions. Transfer moves the same owner; document
identity survives attachment while transport identity rotates. Dirty, composing,
conflicted, saving and recovery states pin sessions. Destination leases precede
release; close flushes before membership removal. Clean unleased sessions discard
source, Undo, rendered content and previews, retaining only bounded volatile
position state. Equal paths in different vaults remain distinct.

Each document session owns one persistent editor/flush identity, checked exact
mirror and committed revision, atomic presentation phase, pending intent,
allocation/configuration, source-bound scroll anchor, save tasks and conflict/
retry/comparison state. Review and allocated editor hosts retain identity across
mode/layout/theme changes; hidden hosts cannot receive input or accessibility
focus. Requested mode is not presented fact until matching acknowledgment.

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
readiness and refresh hidden Review. Document owns lightweight position/focus,
not another writable path-mapped presentation record.

### Editor boundary contract

Edit and Source share one CodeMirror EditorState, selection, composition and Undo
owner. Review projects a committed revision. Exact Markdown remains writable
authority: normalized LF editor coordinates and exact BOM/CRLF/LF bytes are distinct.
The immutable exact-source StateField and inverted transaction effects preserve
original newline bytes through Undo/Redo. Mapping between normalized positions,
UTF-16 source coordinates and UTF-8 ranges never reconstructs bytes from HTML.

Swift retains a checked exact mirror and generation. Ordered deltas prove deleted
spans and exact insertions before atomic application. Full-buffer capture is
reserved for persistence, conflict, recovery, reconstruction and commands requiring
it; ordinary input does not echo/materialize the whole Note. Unexplained current-
identity disagreement pins the session dirty and coalesces a complete editor read
before save. Both runtimes enforce the same source limit; escaped transport
capacity is checked separately.

Every request binds protocol, request, session/document, fingerprint, generation
and expiration. Mutation requests serialize and recheck identity after suspension;
nonmutating snapshots may observe later generations. Expired/composing work cannot
mutate source. Requests pass source as structured page-world arguments/encoded
JSON, never interpolated executable JavaScript. Foundation object decoding is not
used on outbound source values because leading BOM must survive exactly.

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

Each Markdown command creates one atomic transaction/Undo event, preserving all
bytes outside proved edit ranges. Multi-selection transformations refuse protected
frontmatter, code/literal/comment/raw-HTML and malformed/ambiguous boundaries.
Filename editing is an identity-checked native move request, never a Markdown title
writer. Failed rename retains its draft error.

### Source locations and transient interaction

The document session owns fingerprint-bound semantic scroll continuity and fallback
fraction. Only lifecycle edges create restoration requests; ordinary reports do
not publish a second scroll state. One tokenized claim is acknowledged only after
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

Previews/completion/Find are transient and retain their originating session/window,
request and geometry identity. Scroll, context exit, document change and teardown
dismiss through that owner. Swift owns graph resolution, committed preview content,
containment and URL policy; WebKit reports anchors/geometry only. Stale/ambiguous
preview results are discarded. Find matching/replacement remains CodeMirror-owned;
Review matching is read-only. Completion and reference insertion validate current
context, generation, selection and protected ranges before one Undo transaction.
Insertion receipts are revocable projections, never a second buffer.

Attachment preparation joins the existing editor insertion and scoped rollback
in [Source Storage](05-source-storage-and-read-models.md#shared-read-models-and-source-properties).
Quick Look retains only its scoped URL lease until dismissal/replacement/teardown.

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
Graph publishes directed authored occurrences; incoming/outgoing are projections
of the same exact occurrence, not deduplicated philosophical meaning.

One central semantic/topology index owns literal and construct ranges. Components
derive projections from it, not parallel regex invalidation. Proved topology-safe
prose changes may map ranges incrementally; structural or uncertain changes rebuild
conservatively. Complete whole-Note topology cannot be assumed from a viewport tree.
Direct CodeMirror fields own block/line geometry; viewport plugins own inline
projection only. Authored separators remain exact rows, not source-less duplicate
spacing. Semantic widgets, selection, pointer mapping and scrolling share native
measurement. No decoration state is mutated by an independent geometry cache.

Read and Live consume one semantic component/presentation contract. Application
owns byte-checked Appearance/snippet storage and explicit reload; stale/invalid
external edits preserve loaded state and cannot be overwritten by stale GUI saves.
The host transports protected components, dynamic presentation and sanitized user
CSS as distinct ordered layers on both surfaces. Style/font measurement remains
document-bound and does not recreate WebView, EditorState, source, composition or
Undo. Source font preferences configure the same exact editor.

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

Content-free diagnostics are bounded and do not log researcher identifiers.
Visible-paint samples end at measured native/WebKit presentation, not internal
work. Process-set attribution validates launchd ownership/executable identity,
not process names or PPID guesses. Source-free network-denied priming creates no
source/runtime authority. Isolated performance driving and packaged evidence
follow [Specification §21.4](../Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
dated results belong to Status. A focused series cannot pass the complete gate.

## Source entry points

- `Scholium/Features/Document/DocumentController.swift`: retained document workflows.
- `Scholium/Views/Note/MarkdownEditorSession.swift`: checked native bridge/recovery.
- `WebEditor/editor.ts` and `WebEditor/reader.ts`: controlled Web composition.
- `ScholiumContracts/MarkdownSemanticDocument.swift`: committed source semantics.

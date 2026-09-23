# Architecture: Documents and Editor

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Retained
native document sessions, exact-source ownership, and nonauthorizing rendering.

## Documents and native editing

`DocumentController` and `DocumentSessionStore` own vault/Note-keyed sessions,
autosave, committed revisions, conflict and recovery. Transfer moves the same
session; equal paths across vaults remain distinct. Dirty, composing, conflicted,
saving and recovery states pin sessions. Destination leases precede release;
close flushes before membership removal. Clean unleased sessions release source,
Undo and presentation, retaining only bounded volatile position state.

Read and Edit use one retained native text view and one editing session. Mode,
layout, appearance, Inspector and derived-content changes do not recreate that
owner. The native host owns visibility, geometry, focus and accessibility beneath
the toolbar. An inactive host cannot receive input or accessibility focus.
Document identity and requested mode must match before presentation is ready.

Detachment freezes input and captures exact source, selection and history.
Detached saves require unchanged document/revision/generation proof; cancellation
resumes only the matching suspension. Clean committed snapshots update detached
sessions atomically. Dirty buffers remain available for conflict comparison.
External events reconcile stable identities before changing paths; clean deleted
sessions release, unsafe sessions retain their buffers.

Managed creation installs committed source and initial focus intent together.
Readiness requires a valid source mapping and native selection/focus placement.
Failure retains exact source for Retry Edit and recovery. Clean external updates
replace source and its revision together; they cannot replace dirty input.

### Editor boundary contract

`ScholiumEditor.EditorTextView` owns native text input, selection, composition and
Undo. `ExactSourceProjection` owns original UTF-8 bytes and the LF editing view;
`rawSource` is the normalized projection, never a persistence candidate. Explicit
sequential UTF-16 replacements and command batches preserve untouched BOM,
LF/CRLF/CR tokens, Unicode representation and final-newline state. Undo snapshots
retain exact-source provenance. Rendering and syntax attributes do not enter
source history or reconstruct Markdown.

`MarkdownEditorSession` adapts the native owner to Scholium's document contracts:
identity, generation, immutable source capture, focus, source locations and
command admission. Coalesced source-state notifications report revision and
composition/capture availability. A capture verifies native storage, the editing
projection and exact bytes agree. Unmapped edits or unexplained disagreement
remain visibly unsaved; they never authorize a filesystem write. Source limits
apply to native insertion and capture as well as Application mutation.

Every delayed action retains document/session identity, starting fingerprint and
generation, then rechecks after suspension. Composition owns provisional input;
mode changes, commands and incoming results cannot replace it. A source locator
maps through the exact projection, rejecting BOM, CRLF and Unicode-scalar interior
boundaries rather than rounding them. Native selection and geometry remain
projections of the same source, not independent writable state.

A save acknowledges one immutable committed snapshot. Newer input remains dirty
and schedules another save. Proven commits are retained until their matching
editor acknowledgment; uncertainty never retries the filesystem mutation blindly.
Full-buffer reconciliation precedes save, close and departure. Clean external
source may enter by generation-checked non-history replacement; dirty source
enters Conflict. Read entry requires a noncomposing, conflict-free final flush.
A read-only presentation cannot classify an unsaved session as clean.

Recovery preserves the retained exact buffer and selection, never disk over dirty
source. Undo-history loss and source loss remain distinct. Reconstruction cannot
silently normalize or repair source. Each admitted Markdown command is one
atomic transaction/Undo event and refuses protected or ambiguous source ranges.
The toolbar's native filename popover uses the existing identity-checked move
operation in either mode. It owns its rename draft and retains rejection; the
native text session owns body focus, source selection and Undo.

### Source locations and transient interaction

The session retains revision-bound source selection and viewport anchors. Only
navigation and lifecycle edges request restoration; passive observations do not
create another scroll owner. Read/Edit handoff retains the same native view and
maps the current exact anchor without resetting history. Invalid mappings use a
bounded positional fallback, never text search presented as an exact match.
Arrival requires matching document/load identity and actual native completion.

Native TextKit owns caret placement, copy, selection and IME. Pointer-selection
geometry stays stable through the complete drag; selection-driven and queued
layout work resumes after tracking. Completed pointer selection publishes context
at pointer-up; keyboard selection remains immediate. Presentation changes neither
expand the authoritative selection nor create source-less editable rows.

Previews, completion and Find retain their originating session/window, request,
generation and geometry. Context departure and teardown dismiss stale surfaces.
Swift owns graph resolution, committed preview content, attachment containment and
URL policy; the native text view supplies only validated ranges and geometry.
Read Find is nonmutating. Edit replacement and reference insertion validate the
current context, selection and protected ranges before one Undo transaction.
Insertion receipts remain revocable projections, never another buffer.

Writing continuation keeps the existing request/cancellation owner and native
suggestion presentation. Window composition captures the checked current sentence,
retrieval context and insertion receipt, then rechecks identity, focus, conflict,
composition and configuration before publishing. Related-content caching binds
the complete Search generation and exact seed revision; it is not a new index.
Returned text and status remain request-bound and outside source until acceptance.

Attachment preparation uses the existing insertion receipt and scoped rollback
in [Source Storage](05-source-storage-and-read-models.md#shared-read-models-and-source-properties).
Quick Look retains only its scoped URL lease until dismissal or replacement.

### Shared document rendering

Contracts owns the committed semantic document and editing dialect. Edmund's
parser supplies transient native styling and command ranges; it grants no
metadata, link or research authority. Shared dialect fixtures establish source
spans and semantic agreement. Unsupported or malformed constructs retain visible
exact source without guessing a replacement interpretation.

Valid YAML and body share one history. Unclosed frontmatter suppresses semantic
projection without hiding source. `NoteDocument`/Yams remains the semantic parser;
style adapters never repair or reserialize metadata. Graph publishes authored
occurrences, including repeated links, rather than inferred philosophical meaning.
Tables, formulas, diagrams and previews are read-only projections of exact source;
activation edits the original ranges. Footnote and link-annotation content remains
bound to its authored occurrence and definition, never a second document.

Read/Edit share native semantic styling and structured Document Appearance.
Application owns byte-checked profile storage and explicit reload; invalid or
stale external configuration preserves loaded state and rejects stale saves.
Font and layout changes preserve the native view, source, selection, composition
and Undo. Document CSS snippets are not a reachable styling surface.

### Embedded renderers and trust

Native document rendering keeps raw HTML inert. Math, diagrams and embedded
resources retain bounded local rendering, cancellation, diagnostics and exact
source fallback. A renderer cannot gain filesystem or network authority from
authored destinations. Missing, prohibited or unsupported output remains source;
rendered objects never become writable round-trip models.

Chat and bounded link previews retain `SafeMarkdownReadWebView` and the
controlled local reader runtime. `DocumentWebViewContainer` and
`DocumentWebEnvironment` own only those remaining WebKit surfaces. Chat owns its
reply extension and transcript lifecycle outside the neutral reader. This reader
cannot become an alternative Note editor or source/history owner.

The reader's KaTeX, Mermaid, styles and font assets remain pinned and locally
bundled. Mathematical input is bounded and trust-disabled. Diagram requests are
versioned and document-bound; serialized rendering protects runtime globals.
Authored initialization, external resources, scripts, links/callbacks and unsafe
HTML/SVG/CSS are rejected. Only validated bounded output mounts. Authored
accessibility descriptions remain source-owned; their absence receives a
source-based fallback and diagnostic, never inferred research content.
Dependency notices follow the actual retained build graph.

### Measurement boundary

Bounded diagnostics exclude researcher identifiers. Native document and retained
Web reader measurements identify their own presentation boundary. Process
attribution verifies executable identity, not names or PPID guesses. Packaged
performance and acceptance follow
[Specification §21.4](../Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
Status owns dated evidence. Focused native tests do not establish a release gate.

## Editor responsibility map

| Boundary | Owner; excluded responsibility |
| --- | --- |
| Document workflow | `DocumentController` / `DocumentSessionStore`: identity, modes, save/conflict; no text layout. |
| Editing authority | `ScholiumEditor.EditorTextView` / `ExactSourceProjection`: input, exact bytes, selection, composition and Undo; no filesystem. |
| Native adapter | `MarkdownEditorSession`: checked capture, command admission, source locations and recovery; no second editing history. |
| Native viewport | `NativeMarkdownEditorView` / `NativeEditorContainer`: geometry, input and accessibility beneath the toolbar. |
| Independent controls | Native toolbar filename popover and `NativeEditorInteractions`; neither owns document source. |
| Read-only Web content | `SafeMarkdownReadWebView` / `ScholiumReadPageExtension`: bounded Chat/external projection; no Note editing authority. |

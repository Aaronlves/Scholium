# Architecture: Documents and Editor

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Document sessions,
CodeMirror/WebKit, exact source, rendering, and editor performance.

## Documents and CodeMirror

Each window's `DocumentController` owns a `DocumentSessionStore` keyed by the
registered vault and stable Note UUID. Renames retain editor state; windows
never share it.

The store acquires destination leases before release. Dirty, conflict,
save-in-flight, retryable-recovery, and recovery-buffer states pin a session.
Tab close flushes before membership removal; a clean unleased, unpinned session
discards editor, source, Undo, HTML, and previews. Only an in-memory
64-entry scroll LRU survives close; memory pressure reduces it to 16 or clears
it, and app relaunch does not retain it. Vault-qualified keys prevent equal
paths in different Triptych vaults from sharing state.

`DocumentController` defaults `currentPresentationMode`
to Edit. Writable selections inherit it; unavailable Notes present
Review. Chrome reports the session's actual mode. Sessions retain only
editor safety state, not path-mapped presentation.

Each retained `DocumentSessionModel` owns:

- its persistent `MarkdownEditorSession` and flush token;
- the exact editor mirror and committed revision;
- one atomic `DocumentPresentationState`: active runtime phase, the current
  presentation's pending editor intent, retained configuration, and surface
  allocation;
- a revision-bound semantic source scroll anchor plus normalized fallback;
- autosave and in-flight save tasks with stale tokens;
- rendered Review projection state; and
- save error, conflict, retry, and comparison presentation state.

CodeMirror remains authoritative while editing. The boundary uses
generation-bound full-buffer reads at explicit lifecycle edges, an
incrementally mutated native exact-source mirror, fingerprint-gated save,
committed-text synchronization, conflict comparison, and
flush-before-agent-work. The Swift
model retains these facts across SwiftUI view reconstruction; it never
reconstructs writable Markdown from HTML, parsed YAML, or another projection.
`DocumentConflictSnapshot` supplies exact editor/disk inputs to the Contracts-
owned `ExactSourceComparisonBuilder`, the sole line-diff owner. Document still
owns conflict actions and buffer authority, while the
comparison value and future shared sheet remain pure disposable presentation.

`DocumentEditorHost` is the persistent presentation boundary for one selected
document session. Review is mounted continuously; after first editor allocation,
the retained CodeMirror surface is also mounted continuously. Review, Edit,
and Source transitions change opacity, stacking, hit testing,
accessibility exposure, and first-responder focus rather than view identity.
`MarkdownEditorSession.presentedMode` advances after typed acknowledgement.
Editor readiness belongs to one document identity. Pending Edit/Source shows
an opaque document plane above live WebKit until measured positioning completes.
Same-document mode changes
retain CodeMirror; another document cannot inherit its readiness. First
ordinary Edit focuses the exact body start after YAML, or an exactly mapped
Review selection. A retained/restored open Note returns to its valid title/body
target and selection; an explicit locator takes precedence. Source retains its
exact-source selection.
Focus request revisions prevent delayed navigation callbacks from overriding newer focus requests.
Managed New Note skips Review-first presentation. `DocumentController`
installs its snapshot, exact source, active Edit phase, and body-start offset in
one MainActor transaction. Until typed acknowledgement, the host exposes
neither Review nor Empty Note. Typed initialization maps one collapsed
body-boundary selection into CodeMirror UTF-16 and returns it with the mode.
Native code verifies that range, converges style and scroll, awaits focus, then
publishes readiness, announces once, and consumes the intent. A clean external
publication first replaces the pending buffer and body boundary together.
Failure blurs the hidden editor and retains committed source behind **Retry
Edit** and **Source**; retry replaces only that WebView from the checked mirror.
Pending editor intent is not an active mode. An Edit or Source intent supplied
to a newly selected session remains inside the Review phase until
`DocumentController` begins the editing lifecycle; only that atomic transition
allocates the retained surface and makes
the session writable. Conversely, finishing editing commits one transition to
Review while retaining the hidden editor's last Edit/Source configuration.
The session therefore publishes no separately mutable `isEditing`, mode,
retained-mode, or surface-allocation flags.
`NoteContentView` observes that exact `DocumentSessionModel` directly; it does
not depend on an ancestor's forwarded change notification to reveal a new
mode. This ensures the editor surface is invalidated as soon as the persistent
session changes instead of waiting for an unrelated pointer or layout event.
The hidden surface cannot receive pointer, keyboard, or accessibility input.
The fingerprint-bound Review HTML is prepared and loaded when the committed
revision changes even while Edit or Source is visible. Hidden Review scroll
reports cannot mutate the shared scroll anchor, and a newly committed revision
invalidates older Review readiness before the handoff becomes visible.
Clean external revisions synchronize the retained editor through the same
generation-checked path; dirty buffers still enter Conflict. A complete
generation also reconciles every open tab by stable identity. A clean document
that disappeared externally releases its tab and activates a surviving
neighbor or the no-document state, while dirty, conflicted, retryable,
save-in-flight, or recovery-buffer sessions retain their exact bytes. The
generation gate is checked before any document or path projection changes, so
an older event cannot close or rename a newer tab. Window resizing, split
changes, theme, text scale, document measure, and ordinary SwiftUI
reconstruction may reconfigure presentation but cannot recreate the retained
`WKWebView` or `EditorState`. Retained-surface memory remains a measured
acceptance concern rather than permission to weaken this lifecycle contract.

### Editor boundary contract

The editor is an app-private typed boundary, not a generic event bus. One exact
Markdown source is the only writable authority. Edit and Source share one
persistent CodeMirror `EditorState`; Review renders a fingerprint-bound
committed revision. CodeMirror owns active editing state, selection,
composition, and undo history. Because CodeMirror normalizes line separators,
the Web boundary keeps one checked `ExactSourceMirror` beside that state. Its
normalized editor text and exact line-ending-preserving text use CodeMirror's
persistent `Text` rope rather than immutable JavaScript String concatenation.
Its text preserves the loaded BOM, CRLF/LF form, Unicode, and final newline; a
sorted derived CRLF-offset index maps CodeMirror UTF-16 positions without
rescanning the Note. Each ordinary input transaction validates only its exact
deleted span and applies all accepted deltas atomically. Complete-document
reconciliation remains a save, synchronization, command, or recovery boundary,
not a per-keystroke path. The mirror cannot initiate edits or create a second
selection, composition, or Undo owner. Swift independently maintains its
checked boundary mirror in mutable UTF-16 storage from accepted
generation-ordered deltas, including a cached UTF-8 byte count and the derived
CRLF index. Ordinary input therefore neither copies the complete source nor
publishes it through SwiftUI. The document model receives only dirty/activity
state for autosave scheduling; complete immutable source snapshots are
materialized only for persistence, conflict, recovery, reconstruction,
explicit commands, or diagnostics. The mirror reconciles against complete
editor text before persistence.

`MarkdownEditorSession` alone owns the retained
WebView lifecycle, checked source mirror, generation, recovery, and pending
requests. `MarkdownEditorBridgeAdapter` owns typed inbound decoding and
outbound JavaScript dispatch;
`MarkdownEditorNativeWebView` owns AppKit
attachment, image paste, and the context menu; and
`MarkdownEditorWebView` composes SwiftUI/WebKit and routes messages. Debug-only
WebKit probes and interaction drivers live in `MarkdownEditorSessionTesting*`.
`editor.ts` remains the sole Web composition root and source/identity
owner. `live-projection-index` owns the semantic catalog,
`projected-widget-registry` pointer mapping, `live-selection` selection paint,
and bounded components semantic widgets and layout. Source direction, actions,
previews, suggestions, and scroll share one `EditorView`. None may
persist Markdown or create another `EditorState`.
`scroll-coordinator` owns the view's scroll observation and immediately notifies
the composed selection-action controller to dismiss its floating surface;
anchor reporting remains independently debounced.

Secondary click follows one public event path. A CodeMirror DOM `contextmenu`
handler preserves an existing clicked selection or moves the sole
`EditorSelection` to the clicked exact-source position, prevents WebKit's
generic menu, and posts the finalized mode, context, and viewport anchor.
`MarkdownEditorNativeWebView` then presents one compact AppKit menu containing
standard Cut, Copy, Paste, and Select All selectors followed, only for a
collapsed Edit caret, by available clicked-construct commands. It never installs
an `NSEvent` right-mouse monitor, queries WebKit private descendant views for a
premature menu, or opens a replacement menu beside WebKit's own menu.

`live-projection-index` owns whole-Note topology rather than only the current
viewport. Before reading its catalog, construction asks CodeMirror's native
incremental parser for bounded completion through the document end. This keeps
the parser's viewport-limited initialization tree from being mistaken for a
complete catalog. If that bounded attempt cannot finish, the index temporarily
uses the current tree and the later parser-only state transaction rebuilds it;
there is no regex fallback or second Markdown parser.

Edit and Source are one atomic CodeMirror configuration boundary. One
`Compartment` owns the mode facet, root/content accessibility attributes,
wrapping and gutters, and every Live Preview projection field, plugin, widget
provider, navigation keymap, and cached-preview overlay.
The editor initializes in fail-closed Source configuration, and an absent mode
facet also resolves to Source; exact document bytes are therefore never loaded
through Live Preview merely because an Edit request has not arrived yet.
Overlay DOM and document-level listeners are created and destroyed with their
Live Preview `ViewPlugin` lifecycle rather than remaining hidden across Source.
Swift publishes
one coherent requested mode; `MarkdownEditorSession` serializes bridge work,
publishes the acknowledged mode as fact, and continues toward the newest
request if an older request completes in flight. No imperative DOM class or
second native mode flag may separately reconstruct presentation. Source keeps
the common parser for exact-source navigation and editing commands but installs
no Live Preview state field, semantic widget, projection keymap, overlay, or
semantic typography highlighter. Selection-match highlighting is absent;
adjacent-bracket matching highlighting is likewise absent because it would
create a second selection-like presentation beside Markdown delimiter
projection without changing the actual insertion point. Selection belongs
only to the researcher's explicit range. Live Preview invalidation follows
document, viewport, selection, presentation, and title/body focus. Title/body
transitions refresh syntax exposure; window focus does not, preventing inactive
WebKit from erasing projections through an empty visible range.

Selection meaning and selection paint are deliberately separate. CodeMirror's
`EditorSelection` remains the sole Edit/Source range, command, copy, IME, and
accessibility owner. CodeMirror's cursor layer is the sole Edit/Source caret
painter; WebKit's native caret remains transparent so projection remeasurement
cannot leave a compositor ghost at an obsolete baseline. CodeMirror's stock
selection rectangles remain suppressed: one mode-neutral decoration source
marks only selected source characters on each physical line and excludes line
endings, authored blank lines, widgets, padding, and semantic gaps. The
synchronized native DOM selection stays visually transparent. Source adds
active-line and gutter markers only for collapsed selections, so a triple-click
range ending after a line break cannot mark the next logical line. Review
likewise retains WebKit's
native `Selection`, while a CSS Custom Highlight
mirrors only intersected nonempty text-node subranges. Its contextual action
converts the retained DOM Range to a document-coordinate anchor and remeasures
that anchor on viewport resize. The
static Review DOM is not mutated, copied text is unchanged, and block padding
or virtual line endings cannot acquire selection paint. Both adapters consume
the same resolved Accent mix; `==text==` instead consumes the fixed shared
Markup-highlight token.

Writing direction is content-owned at the adapter boundary. Static Review DOM
places `dir="auto"` on researcher-authored text blocks and `dir="ltr"` on code,
mathematics, and inert raw-HTML source. Live semantic lines and every fragment
component use the same attributes. Source has a viewport-bounded decoration
plugin that adds only `dir="auto"` to rendered exact-source lines; it owns no
replacement, typography, or vertical geometry. The shared editor configuration
enables CodeMirror's per-line text-direction facet and official syntax-tree
bidi-isolate extension, so the DOM order, visual cursor, selection, and neutral
Markdown punctuation use one direction model. These decorations never replace
or lock text; Edit and Source continue to route pointer, keyboard, selection,
composition, insertion, deletion, and Undo through the same CodeMirror state.
Raw HTML remains escaped or an
inert literal projection and cannot become a parallel rendering authority.

The bridge type itself is editor-only: `MarkdownEditorMode` contains Edit and
Source, while the researcher-facing `NotePresentationMode` additionally owns
Review. `MarkdownEditorSession` publishes one
`MarkdownEditorPresentationState` snapshot containing Web-content readiness,
document loading/ready phase, acknowledged editor mode, and error. Pending mode
and exact document input remain private session state. The SwiftUI adapter's
`lastModeInput` is only a one-way diff cache that prevents an unchanged view
input from being resent after a session publication; it never initializes or
recovers a session and never converts a bridge acknowledgement into Document
state. The parent view's source is a lifecycle snapshot, not a per-transaction
echo. Reattaching the same retained document initializes from the session's
exact mirror, while a different document uses the newly proposed source.
Initial exact input is staged without publishing during `makeNSView`;
the page-ready boundary publishes loading once and starts initialization. A
matching recovery snapshot is selected by the session's exact document,
starting-fingerprint, and source identity, including after Web-content process
termination or SwiftUI view reconstruction.

Every bridge request carries bounded protocol, request, session, document,
fingerprint, and generation identity. Mutations are serialized; invalid
requests cannot mutate source. A rejected current-identity forward delta pins
the session dirty and coalesces a full CodeMirror read before revision-checked
autosave. Both runtimes cap source at 8 MB UTF-8. Source crosses
`WKWebView.callAsyncJavaScript` through
structured arguments in the page content world; it is never interpolated into
executable JavaScript.

The typed bridge sends source deltas immediately in generation order, includes a
nonmutating exact UTF-16 source-range reveal operation, and carries an optional
initial selection in the same typed initialization transaction. Identity remains
strict while snapshot queries may observe a later generation than the caller
knew. A save acknowledges one immutable committed snapshot: if input advanced
during the repository write, the newer buffer remains dirty and schedules the
next autosave instead of being rejected as a replaced session. Source-mutating
bridge operations remain serialized; nonmutating snapshot and presentation
queries do not wait behind that queue. It coalesces
selection-only reports to the latest envelope per animation frame, with a 50 ms
offscreen watchdog. Each typed inbound envelope is decoded once; source deltas
avoid `Codable` re-encoding. It carries exact selection and coordinates but
includes command availability only when changed. Swift keeps coordinates as
non-Observable session state and publishes semantic or lifecycle changes only.
The incremental native exact-source mirror is the live recovery authority.
Complete CodeMirror history is captured only at an explicit view-reconstruction
boundary, never on an idle timer during ordinary input. Every awaited request
binds a session epoch and revalidates WebView,
document, fingerprint, and nondecreasing generation. Selection snapshots are
valid only for that identity and generation; a committed fingerprint rebases
fallback recovery before scheduling bounded history capture.

Its diagnostic snapshot is a fixed 256-sample buffer of metric names, durations,
and counts only—never research content or identifiers. Scroll frames aggregate
once per session and clear their User Timing entries. Visible-paint samples use
`requestMeasure` plus the next animation frame; throttled missing samples are
not replaced by internal-work durations. UI automation and exact process-set
measurement remain the authorities for visible response and retained memory.
Process attribution uses the originator's launchd service map and verifies each
executable; PPID or process-name matching is insufficient for WebKit workers.

Ordinary input does not materialize the complete CodeMirror document. The
update listener supplies only transaction deltas and their deleted start-state
spans to `ExactSourceMirror`; Enter, Tab, Backtab, and direct link activation
query CodeMirror `Text` lines around the active ranges. One immutable sorted
mutation-sensitive interval set is cached with `LiveProjectionIndex` and reused
by every projection field. Plain edits outside raw HTML map its existing ranges;
full source strings remain reserved for bounded semantic constructs or explicit
whole-document commands that actually require them. The native receiver applies
the same small deltas directly to `EditorExactSourceBuffer`; one
deadline-driven autosave task moves its deadline during continued typing
instead of being cancelled and recreated for every English or IME transaction.
Its dirty-path publication changes only when the path changes. Document
navigation and Review reuse fingerprint-bound semantics from
`WorkspaceNoteSnapshot`; stale input reparses; SwiftUI `body` never does.

The retained-memory journey uses a run-specific app handshake. Initial load
and each typed Live Preview/Source transition publish progress after bridge
acknowledgement; the external sampler records the attributed app/WebKit process
set and acknowledges before the driver advances. Its QA transport addresses
the retained session directly to prevent SwiftUI request coalescing. The runner
supplies a predeclared bounded transition count and the summarizer applies the
two-tail convergence rule in [Specification §21.4](../Specification/10-release-and-open-decisions.md#214-packaged-performance-gate).
A separate attached-WKWebView journey checks the dirty buffer, accessibility
chrome, and diagnostic ring; it cannot establish memory convergence or visible
p95.

The connected Editor driver measures visible or accessible boundaries.
A Document uses a source-free, network-denied view to prime
nonpersistent WebKit and allowlisted font during opening.
First-use Review takes it after selection instead of constructing the primed
page context; bounded expiry otherwise releases it. Initial navigation skips a
redundant loading publication; replacement retains it. Multi-`WKProcessPool`
is unused.

Edit/Source excludes Command-R and ends after matching bridge acknowledgement
and layout. Key-to-paint registers before native delta delivery and publishes
after frame plus task for the accepted session/generation. Cached preview ends
after its surface paints. Warm Edit reuses the prepared Editor. First-use Edit
launches to no document, reaches the 5,000-word Note's interactive Review as
setup, then times the Edit request. Both end at the matching visible,
accessible Editor. Visible projection times one synchronous CodeMirror refresh.
QA-only notifications drive those paths; `PerformanceProbe` enforces metric,
fixture, duration, and sample budget.

`generate-rdf1.py` owns manifest-listed RDF-1 bytes;
`run-performance-benchmarks.sh` owns isolated driving, predeclared sampling,
inventory recheck, evidence class, and production-state nonmutation. Packaged
Release honors `SCHOLIUM_HOME` only with the marker. Warm metrics reuse
processes; launch/first-use metrics relaunch. Records retain timing,
correctness, and provenance without research content. Gate mode requires a
clean-tag package and may capture either the complete campaign or one focused
replacement series. `summarize-performance-results.py` accepts only the bounded
product-gate plans, labels a focused report Incomplete, and can pass G7 only
when every series and shared correctness check are present. Scenario omissions
remain explicit. Limits and evidence rules belong to [Specification
§21.4](../Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
dated evidence belongs to [Status](../IMPLEMENTATION_STATUS.md).

`ScholiumContracts` owns durable Markdown meanings and the immutable editing
dialect. TypeScript may parse an uncommitted buffer for immediate projection
and exact transformations, but cannot invent persistence, link meaning,
callout, or diagnostic semantics. Every Markdown command creates one
CodeMirror transaction and one undo event. Multi-selection transformations are
atomic and refuse frontmatter, code, raw HTML, comments, protected literals,
and malformed ranges whose boundaries cannot be proved. Outside proven edit
ranges, BOM, newline style, final newline, YAML, comments, unknown syntax, and
malformed source remain exact.

At autosave and explicit source-snapshot or document-departure boundaries,
Swift requests complete CodeMirror text and reconciles it with the checked
mirror. A clean external revision may replace the buffer through a
generation-checked non-history transaction; a dirty buffer stays exact and
enters Conflict. Mode changes and structural commands wait for marked-text
composition and are discarded if document identity or generation changes.
Outbound bridge requests cross WebKit as encoded JSON text and are parsed in
JavaScript. They do not pass source strings through Foundation's
`JSONSerialization.jsonObject`, because that conversion removes a leading
U+FEFF from a string value and would violate the exact-source contract.

Document-replacement navigation performs that exact full-buffer flush once,
then discards selection, scroll, recovery, and Undo serialization belonging to
the replaced tab. Transitions that preserve tab membership capture retained
editor state once before reconstruction. The transition coordinator does not
run a second capture after the flush path has already applied the selected
policy.

After WebKit content-process termination, the retained session reloads its
controlled document and restores a matching bounded CodeMirror snapshot. If
that snapshot is unavailable, it reconstructs from the checked mirror and last
selection; it never rereads disk over a dirty buffer. Undo-history loss is
reported separately from source loss.

The retained `DocumentSessionModel`, never writable Markdown or a path-keyed
view, owns scroll continuity. `EditorScrollAnchor` binds source position,
semantic block, relative position, fallback fraction, and fingerprint.
Ordinary reports update non-published `ObservedScrollPosition`; only load,
mode handoff, WebView rebuild, or navigation creates a numbered
`ScrollRestoreRequest`. Its single tokenized claim is acknowledged only after
successful current-load restoration, so failure, cancellation, or the
resulting scroll report cannot consume or recreate it.

CodeMirror maps exact-source CRLF offsets to its geometry. Review maps the same
contract through a load-time registry of source-located DOM blocks, using
`elementFromPoint` and the range map rather than full-DOM measurement on every
scroll. Invalid ranges or fingerprints fall back to the normalized fraction.
Live/Source also use CodeMirror's native snapshot. Reconstruction freezes a
handoff anchor, and delayed restoration requires the same document or Review-load
generation. It never depends only on throttle-prone animation frames.

Markdown owns written annotation, including semantic Callouts; Scholium has no
parallel comment store, margin widget, or passage-discussion anchor. Review is
read-only. Edit exposes Markdown formatting and source-owned constructs;
Source exposes exact text. `ScholiumSystemSymbol` is the icon catalog, and
`ScholiumWebSymbolAssets` injects its data-URI masks into WebKit surfaces.

Transient surfaces do no whole-Note work. Selection observation reports bounded
information for document statistics and navigation; it creates no persisted
research object. `DocumentWebViewContainer` owns viewport geometry and exposes
WebKit and native floating siblings in one accessibility tree.
`DocumentFloatingSurfaceController` owns Liquid Glass preview, suggestion and selection-action
containers. `SelectionActionBar` uses native controls and a menu, without another composer. The selection bridge revalidates identity before Chat admission;
`replacePassage` checks source and range, preserving editor Undo.
`MarkdownReviewSourceSelection` maps DOM offsets only when the complete rendered
block equals its source span, excluding a terminating newline. Unsupported
rendering remains unmappable; no excerpt search or source reconstruction occurs.
`DocumentController` owns document-bound location requests carrying checked revisions.
Switching documents invalidates them; only matching acknowledgements consume them.
Review validates its revision and bounded DOM candidate before selection. Editor
uses its exact-source offset map and generation-checked bridge; one request-scoped
view task applies navigation or reports failure. Unmappable Chat ranges use Source;
ordinary line arrival keeps its transient marker. Versioned projections preserve source, focus, and viewport geometry;
preview builders stay detached from the document DOM. Scroll, resize, teardown,
and context exit dismiss through the originating controller. Completion geometry
uses one keyed CodeMirror measure with an idle fallback when WebKit throttles
animation frames. Review activity deactivation clears transient selection paint.

`input-suggestions` owns the Edit-only CodeMirror Wikilink, slash, and chained
Callout-role completion. Slash filtering is local. Bounded Wikilink queries use
the typed bridge and generation-owned `EditorLinkCompletionIndex`; CodeMirror
owns the sole AX listbox, transactions, caret, and Undo; native rows forward bounded activation. Superseding query, document,
mode, WebKit termination, or teardown cancels native work; identity gates reject
stale replies, and Source removes the extension. No catalog, registry, DOM menu
state, or writable source is duplicated.

The native `DocumentFindPanel` owns Command-F, query/options, replacement disclosure,
and focus intent. `DocumentFindSearchField` supplies AppKit input/menu behavior;
CodeMirror owns exact matching and replacement, and Review uses its read-only
coordinator. The overlay reserves no document layout or scroll space.
CodeMirror's hidden panel transports state only.

**This Note** receives an immutable editor source snapshot containing note,
session, source, and revision identifiers. Search reads that value without a
flush, autosave, repository mutation, or index publication. Result navigation
checks the request freshness, session, revision, and fingerprint before
issuing a CodeMirror `revealSourceRange` transaction with no history entry;
cross-document navigation continues through the ordinary dirty-buffer,
autosave, and conflict coordinator.

### Shared document rendering

`MarkdownSemanticDocument` is the one Contracts-owned semantic projection.
`MarkdownEditingDialect` serializes the same supported syntax and
delimiter rules to CodeMirror. Swift parses committed revisions for Read,
graph, diagnostics, and persistence-adjacent consumers. TypeScript incrementally
parses the uncommitted buffer for immediate Live Preview only, and shared
fixtures require its source spans and meanings to agree with Contracts.
`MarkdownEditingDialect` carries the source syntax owned by §§5 and 12.
Shared fixtures test both parsers against those rules. The TypeScript adapter
fails closed when it receives a dialect it does not implement.

Complete note source uses one CodeMirror language owner from `yamlFrontmatter`
around the locked Markdown language. Closed frontmatter is an incremental YAML
subtree, including diagnostics; body remains Markdown. Live Preview keeps valid
frontmatter in place and adds source-located YAML marks only; it never creates a
second editable surface. An unclosed opening suppresses semantic projections
but keeps exact text in place. Table, callout, footnote, mathematics, and
preview adapters honor this fail-closed guard.

That Markdown content language is extended through the locked Lezer API with
typed Wikilink, named/inline footnote, callout, inline/display
mathematics, highlight, and Obsidian-comment nodes. Live consumers do not infer
those constructs outside the corresponding syntax ranges. The shared
cross-runtime fixture projector parses a normalized LF/BOM-free view only for
Lezer compatibility and maps every node boundary back to the exact original
UTF-16 offset, so CRLF, leading BOM, Unicode decomposition, and final-newline
form remain source-authoritative. These nodes locate editing syntax; Swift
`MarkdownSemanticDocument` and `GraphSnapshot` remain the authorities for
diagnostics, identity, authored link occurrences, and committed Read output.
`GraphSnapshot` publishes only directed source-to-destination occurrences.
Outgoing and Incoming are two projections of the same occurrence, preserving
its whole span, link span, optional annotation, and local context without
deduplication or inferred meaning.

The mode-neutral presentation catalog is explicit rather than assumed.
Contracts publishes source-located CommonMark/GFM blocks plus strong,
emphasis, strikethrough, highlight, inline-code, link, and image nodes. The
TypeScript catalog extends those base roles with the editing dialect's
Callouts, footnotes, mathematics, comments, Wikilinks with optional annotations, and protected
literals. Each catalog entry carries its exact half-open UTF-16 range, exact
marker ranges, visible ranges, parent and nesting role, and, where applicable,
heading level, list depth, task marker, link target, and alias range. Opening
ATX-heading and quotation prefixes include their required separator. Heading
style follows the live syntax catalog, including empty ATX headings; only
Setext underlines use marker-line geometry. Inactive
Edit gives short delimiter ranges zero measure; active Edit exposes their
exact glyphs inline. A measured leading prefix can borrow available whitespace
only when its width alone would wrap prose. The activation retains that placement
until concealment; technical and long source uses ordinary wrapping. Semantic blocks exclude terminal CR/LF; task-list prose starts
after its marker. LF and BOM/CRLF/Unicode fixtures enforce those boundaries.
Incomplete extension markers remain ordinary editable source; only opened
block mathematics and comments produce fail-closed malformed diagnostics.

`LiveProjectionIndex` derives list-prefix and task-item ranges with the
semantic catalog and maps them through topology-safe prose edits. A prefix
stays on its marker line and stops before any parent marker. Projected and
exact prefixes consume one protected track, so neither owns prose geometry.
Horizontal entry queries the sorted indexes instead of merging and sorting
whole-Note ranges per Arrow key. Pointer and command paths consume one pure
task-marker transition in `transformations`; the widget dispatches only that
exact three-character source change.

Live vertical geometry uses direct CodeMirror `StateField` decorations. One
immutable `LiveProjectionIndex` owns the typed catalog plus sorted frontmatter,
literal, code-block, table, Callout, footnote-reference, and mathematics ranges. Direct
fields own semantic line classes, measured source separator lines, inter-block gaps,
frontmatter, tables, display mathematics, raw HTML, Callouts, and footnote
reference markers.
At a typed block boundary that already contains authored Markdown separators,
each exact blank line remains a normal prose-height CodeMirror row and no
source-less gap is emitted. Only a boundary without an authored separator uses
a zero-content block widget. Edit does not copy Review paragraph-end padding;
its authored blank rows provide that separation instead. Heading padding and
projected component spacing continue to use generated Appearance values.
Review and inactive Edit therefore share local block geometry but may differ in
cumulative vertical position by at most one Edit row per authored blank line
before the block. A blank row keeps the same block size and line height before
entry, while active, and after its first visible input, so its line box cannot
overflow into the following row. Its source-offset-bound pointer target spans
at least the manuscript paragraph gap without contributing additional layout
height. Only top-level lists receive semantic
gaps; list-item paragraphs and nested lists retain prose line height without
internal gaps. The visible line maps to its exact source offset, while
selection, navigation, deletion, composition, and Undo keep their existing
source semantics. DOM, height map, pointer mapping, selection, and scrolling
therefore have one geometry owner. A prefix-maximum interval
index handles nested half-open overlap and containment without mutating
StateField-owned arrays. Plain bounded insertions outside constructs map
existing positions only after a physical-line-local semantic-catalog
comparison proves that Markdown topology is unchanged. This replaces
marker-proximity guessing, so ordinary prose beside emphasis, links,
citations, or other syntax does not rebuild the complete document projection
merely because a marker is nearby. Deletions, structural markers,
cached-content constructs such as mathematics, and any changed or uncertain
local topology rebuild conservatively. The central index is the sole topology
owner; component fields derive their table, mathematics, raw-HTML, Callout,
and footnote projections from it rather than maintaining parallel regex
invalidation rules. A new background Lezer tree may refresh structure once;
selection and viewport transactions reuse it.

The remaining `ViewPlugin` is an inline adapter only. It projects visible
ranges plus a 2,000 UTF-16 buffer and never supplies block widgets, source-line
geometry, or semantic gaps. Indexed literals and fenced-code ranges avoid scanning
from line one. Selection changes replace only merged old/new neighborhoods
within that margin, not the visible buffer or structural index. Widget equality
preserves DOM; height work stays inside CodeMirror's measurement cycle.

Read and Live Preview consume one presentation contract:

- `ScholiumWebDesignTokens.documentPresentationCSS` derives default Appearance
  CSS from `DocumentAppearanceSettings.defaultSettings`;
- `StyleOperations` validates and explicitly reloads editable `appearances.json`
  in Application Support; coordinated, byte-checked writes reject stale edits.
  Reload failure retains the loaded appearance; the frontend derives its CSS;
- `DocumentSourceAppearance` stores the unrestricted installed font and size;
  escaped CSS transports them to Source without replacing the editor;
- protected render-component CSS owns common callout, link, table, footnote,
  and mathematics roles;
- Read emits static semantic DOM from the committed semantic document; and
- the Live adapter maps the same roles to bounded CodeMirror decorations and
  widgets without replacing active source, selection, composition, or undo.

Both modes use strict line breaking, normal word boundaries, and emergency
long-token wrapping. CodeMirror `break-spaces` preserves each Edit space without
a visible-whitespace decoration. Footnote locators bind following punctuation;
Appearance alone owns numeric rhythm.

Native chrome and Review use the resolved filename title. Live Preview's
borderless field sends the exact editor envelope and expected title; native
validates both before `moveNote`. Success follows stable identity; failure
retains the accessible draft error. It never writes Markdown; headings stay
below it and Source has no title projection.

`NoteContentView` loads attachments into the retained Document session. Overview
renders Quick Look thumbnails with leases released on completion/cancellation.
SwiftUI's `quickLookPreview` owns the system window and opening actions.
`DocumentAttachmentQuickLookSession` only retains the URL and read lease;
system dismissal, replacement, and sidebar teardown release it once.
No custom preview panel, toolbar, or external-opening controller remains.
Overview and File share DocumentController's attachment operation and session
busy state. No attachment widget or message remains in the editor/reader bridge.


Review page identity excludes asynchronously derived link previews. Only fingerprint, CSS, or capability changes replace the page;
in-page updates are read-only and preserve selection and scroll.
`reader.bundle.js` owns the Read DOM,
`SafeMarkdownReadWebView` owns its configuration, and coordinators own
cancellable work. Layout never reconstructs the retained
`WKWebView` or `EditorState`.

The Host owns three ordered CSS layers on both surfaces: app/protected
components, dynamic presentation (including the selected typed Appearance),
then sanitized advanced user CSS. The bridge keeps the latter two in distinct
controlled elements, coalesces changes into one CodeMirror measure, and reports
scroll only afterward. Font-ready measurement stays bound to the same document,
preserving geometry and equal cascade authority across Read and Live.
Each Window forwards the shared style store's change signal into its existing
view model, so selecting or saving an Appearance updates open Read and Live
surfaces through those controlled style elements without replacing the retained
WebView, EditorState, buffer, selection, composition, or undo history.

Expanded Edit Callouts retain CodeMirror source lines in every selection state.
The semantic-line field owns the continuous header/body surface, and the inline
projection exposes only the active physical line's exact markers. A direct
Callout field supplies reusable heading/disclosure widgets and collapsed-body
ranges; source-mapped session-local fold choices never modify Markdown. Selection
inside a body exposes it. Explicit collapse moves the caret to its header rather
than hiding the input position. Ordinary pointer and keyboard text navigation
remain with CodeMirror rather than mapping the entire Callout to its final byte.
Review continues to use the shared fragment renderer and Callout stylesheet.

`syntax-presentation` owns retained short delimiter marks and bounded visual
transitions. Hidden marks remain atomic for cursor traversal and inaccessible;
exposed marks retain the exact editable characters. Its view plugin measures
visible tokens and maintains only disposable animation/placement state. It
reconciles caret geometry during motion, cancels on input/composition, and removes
listeners and animation frames with the mode. Technical objects retain their
own projections and use local appearance transitions instead of width motion.
Raw HTML remains inert exact source in persistent lines in Edit and Source.

Semantic tables follow that adapter boundary. Read emits a protected scroll
container with a real `table`, `thead`, column-scoped `th`, `tbody`, and
alignment roles. Inactive Live tables use the same `tables.css` roles through
a direct CodeMirror `StateField` block replacement, because a widget that
changes vertical geometry cannot be supplied as an indirect viewport
decoration. Each displayed cell retains its source offset; pointer or keyboard
entry removes the projection and reveals the exact Markdown table in the same
EditorState. The table DOM is never a writable or round-trip source.

Edit has no footnote end-section projection. Review owns the end section,
navigation, and return; both preview controllers resolve locator hover or focus
to an inert current-definition preview. A Live `StateField` derives IDs,
ordinals, repetitions, inline notes, and bounded continuations while excluding
non-prose ranges and replaces inactive references. Activation selects the exact
definition or inline range. Definitions remain editable as composite
Lezer blocks with nested projections at their source location. There is no
hidden or reconstructed content or second pointer geometry. Named insertion
appends an unused numeric definition; inline insertion wraps each selection in
`^[…]`. Each is one transaction and Undo event. Invalid forms are not repaired.

One Live-selection StateField separates CodeMirror's continuously authoritative
pointer range from the projection snapshot. Ordinary `select.pointer`
transactions update the real range without changing syntax decorations; one
mouse-up effect commits the final range after CodeMirror's own event handler.
Triple-click starts in an immediate phase because paragraph selection is one
discrete projection gesture, but the same phase remains non-idle until mouse-up,
preserving the pointer-selection completion boundary.
Review mirrors this completion boundary with one pointer-active flag around its
native DOM Selection; selection paint may follow the gesture, while completed
selection context is evaluated only after pointer-up. Keyboard selection has no pending pointer phase
and remains immediate. Projected widgets map pointer-down to one collapsed exact
source position and commit the matching projection snapshot in that same
pointer-down transaction, never a constructed range or a deferred boundary
caret. Modified projected links activate from this same owner before selection
begins; direct links reveal source, and Source retains its ordinary
modifier-click path. No manual mousemove range, timer-delayed projection, or
independent Callout activation state exists.

Continuation normalization removes exactly one two-space or tab ownership
indent and preserves every deeper space. Nested lists, block quotations, and
fenced code therefore retain their structure in the committed Review renderer.
Review alone renders the one-definition footnote preview and owns return
navigation; raw HTML stays inert. Shared
fixtures compare definition content as well as identifiers so Swift and
TypeScript cannot silently choose different block ownership.

Mathematics uses a locally bundled, exactly pinned KaTeX runtime and matching
CSS/fonts. Bundled fonts use a read-only filename allowlist scheme, never
filesystem/network access or base64 HTML. Review and Editor load the math runtime
only for a source/preview candidate; a later validated request refreshes only
disposable projection. The first admissible integration must use `htmlAndMathml`,
`trust: false`, bounded `maxExpand` and `maxSize`, no remote resources, and
escaped plain-source diagnostics for failures. KaTeX output is a projection;
only the original delimiter span is editable or writable. Inactive display
mathematics is a direct StateField block replacement; its component remains
marginless in Edit while the shared semantic-gap field owns the equivalent
Review flow spacing. Raw HTML retains its literal line presentation without a source/widget swap.

Mermaid uses one separately bundled, exactly pinned, mode-neutral local runtime
and one shared component stylesheet. Neither WebView injects the approximately
3.46 MB runtime at document start. The first real Mermaid projection sends a
versioned, document-bound request through its existing native bridge; Swift
installs the app-owned bundle into that page world once and resolves the one
shared page promise. A page with no Mermaid projection therefore creates no
Mermaid runtime. Contracts Read first emits ordinary
escaped, source-located fenced-code DOM. Its thin adapter recognizes only the
exact `mermaid` info-string token, replaces that one block after the runtime
settles, and preserves its source coordinates before the Read scroll registry
and readiness boundary are finalized. Live derives the same fenced ranges from
the central projection index and owns inactive Mermaid geometry through a
direct `StateField` block replacement. Activation removes the widget and
exposes the complete exact fence in the retained `EditorState`; no render is
requested while the selection remains inside it. Leaving the whole block
constructs one projection from the latest source. Destroying an inactive Live
widget aborts its request; the serialized runtime skips an aborted request
before parsing or rendering rather than accumulating stale off-screen work.
Source has no Mermaid field.

The locked Mermaid runtime, rather than a Scholium-maintained diagram-family
list, decides which built-in static syntaxes parse. Calls are serialized because
Mermaid configuration is process-global. The adapter enforces source and line
bounds, an edge bound, strict security, local-only execution, deterministic identifiers, no
HTML labels, no authored initialization directives, no links or callbacks, no
external-resource syntax, and no diagram-local custom styling. Generated SVG
is parsed again into a node before insertion: scripts, active or embedded
content, links, event handlers, external URLs, shadow-host selectors, and
unsafe CSS values reject the whole output; local fragment marker references
alone remain. Only a node marked by that successful pass can be mounted, once,
inside an open Shadow DOM whose app-owned sizing, paint containment, and static
motion rules bound generated Mermaid CSS. The same boundary preserves the
intrinsic size of narrow SVGs, proportionally caps wide or overly tall SVGs at
the document and viewport measures, and replaces generated multicolor scales
with protected semantic document variables plus an app-owned final Mindmap
override in both Review and inactive Edit. Review and Edit use no second
`innerHTML` sink for the returned SVG. The returned binding callback
is never invoked. Failure keeps escaped source and a text diagnostic. Missing
authored `accTitle` or `accDescr` keeps a source-based assistive alternative and
adds an ordinary visible diagnostic, not a repeatedly announced live region,
rather than synthesizing philosophical meaning.
Runtime theme input comes only from the protected document-background,
surface, system Accent, primary-text, and separator semantic variables; Edit rebuilds
its inactive widget when presentation or system appearance changes, and Read
rerenders the retained source-backed figure on the same system changes. The
esbuild input graph deterministically regenerates the distributed Mermaid and
transitive-package license notice, so packaging cannot silently omit a newly
bundled runtime dependency.

Link previews are revision-bound Edit requests. Review resolves footnote preview
and navigation against its committed sanitized projection. Swift owns graph
resolution, committed preview content, containment, and external-URL policy.
WebKit owns source-range anchors, modifier feedback, geometry, and transient
presentation. Edit recognizes Command-hover whether modifier or pointer arrives
first; source activation and document change dismiss it. One bounded surface
presents link-annotation templates in Review and inactive Edit without inserting
prose into document flow.
Responses carry session, document, revision, generation, request, and target
identity; stale or ambiguous responses are discarded. A Review footnote preview
contains one referenced definition, never the whole footnote section.

Boundary verification and remaining human acceptance belong to
[Implementation Status](../IMPLEMENTATION_STATUS.md).

The editor does not introduce Milkdown, ProseMirror, a hidden rich-text model,
HTML-to-Markdown persistence, normalization or repair, a floating formatting
toolbar, arbitrary media management, embedded AI chat or suggestions,
real-time collaboration, a new SwiftPM target, or a generic editor plugin
framework.

Frontmatter stays above the app-owned title in the same CodeMirror source and
history; opening and reconstruction never position the title.

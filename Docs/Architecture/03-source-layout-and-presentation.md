# Architecture: Source Layout and Presentation

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns source layout, native presentation, interface ownership, and localization; sibling chapters do not restate it.

## Source layout

- `Scholium/UI/Foundation` contains semantic color roles, metrics, shapes,
  motion, and accessibility-aware surface modifiers.
- `Scholium/UI/Components` contains stateless Scholium building blocks plus
  the bounded native window-shell adapters described below.
- `Scholium/UI/PreviewCatalog` contains the retained deterministic Debug-only
  research-workflow catalog for the modular Skill-run sheet, categorized
  Research Guidance, bounded write-set permission, pairing, returned result,
  Researcher Evaluation, and resizable Triptych-keyed Research Records window.
  It resolves or mutates no production
  state and is reachable only through one suppressed Debug window and an
  explicitly enabled QA command. Completed Sidebar, Inspector, generic-state,
  complete-window, and paired-window acceptance harnesses are removed after
  their approved target deltas and current adoption evidence are recorded.
  Preview code is development-only and does not enter the released interface.
- `ScholiumContracts` contains boundary values, capability protocols,
  deterministic source transformations, immutable snapshots, events, and
  delivery-safe errors. It has no filesystem, database, network, UI, watcher,
  store, or global mutable authority.
- `ScholiumCore` contains internal I/O and persistence implementations plus the
  app-default method resource bundle; it is not a public SwiftPM product.
- `ScholiumApplication` contains runtime configuration and pooling, capability
  actors, the typed event stream, CSS/App Support I/O, Obsidian appearance
  projection, and Zotero transport.
- `Scholium/Features` contains the Discovery, Document, Research, Properties,
  and Settings delivery controllers and per-window editor sessions.
- `Scholium/App/Window` contains `WindowShellState`,
  `WindowCommandObservation`, `WindowEditorFlushCoordinator`, mutually
  exclusive window presentation
  routing, and the document-transition,
  presentation-persistence, workspace-session, and immutable-projection
  coordinators. These
  coordinators do not duplicate a feature controller or writable document
  owner.
- Feature-root view files remain inside `Scholium/Views`. The application and
  window roots may receive the complete `WindowModel`; feature roots receive
  their one controller, and reusable leaves receive immutable values and
  closures.

## Presentation

`WindowPresentationRouter` owns four typed channels:

- one mutually exclusive `WindowSheetRoute`;
- composable `WindowOverlayRoute` values for loading and Search;
- one `WindowAlertRoute`; and
- one typed `WindowFileImportRequest`.

Replacing a sheet route replaces its complete payload atomically. Conditional
dismissal uses the route identity, so a stale callback cannot dismiss a newer
sheet. Route payloads carry note paths only as navigation projections; they do
not own document sessions. Note creation is not a sheet route; lifecycle sheets
remain only for operations that require researcher-supplied destinations or
researcher input. Put Back is a direct reversible Source List command and never
enters the sheet router. Its immutable `NoteLifecycleTarget` is the complete
mutation authority, so it does not flush an unrelated writable editor
while a read-only lifecycle presentation is attaching or detaching. A committed
category move removes the moved Note's document page; if it was selected, the
Document controller clears selection and the native tab container presents its
existing no-document host without implicitly activating another page. The
native Outline cell owns the pointer-hover Put Back `NSButton` and its
hit-test-transparent semantic Sidebar material veil above the full-width hosted
title; SwiftUI retains only row content, context menu, and accessibility
actions. The same
native button remains visible while its Outline row owns keyboard focus; one
Outline coordinator exclusively consumes row-focus requests. Hover
reconciliation stores a stable row ID and resolves it against current Outline
rows so removal never asks AppKit to materialize a stale row object.

`ContentView` has one `.sheet(item:)`, one typed alert presentation, and one
persistent `ScholiumWorkspaceSplitView` root for each configured workspace
window. Its bounded AppKit bridge creates the three-item split described above;
role-owned backgrounds fill each container while Library, Document, and
Apparatus content stays foreground in the live safe area. Bootstrap never
constructs this split. Loading and document states replace hosted content, not
the shell. The composition root passes the complete `WindowModel` explicitly;
`ContentView` observes the presentation, Search, Research, Document, tab,
projection, Agent-request, CSS, and workspace-session owners it actually
reads, while reusable feature leaves remain on narrow values/controllers.
`WorkspaceWindowCoordinator` receives the exact window and split,
installs toolbar/delegate state, and registers readiness/flushing. No singleton,
window search, notification, polling, delayed correction, or width calculation
participates.

Research Records is a separate, nonrestored SwiftUI `WindowGroup` keyed by
Triptych UUID. Its root resolves the exact Triptych capability from
`WorkspaceStore` and consumes only that Triptych's snapshots; focused Workspace
or document changes cannot retarget it. A transient
`ResearchRecordsWindowCoordinator` routes explicit Note-scoped or
Triptych-scoped presentation requests, global-Search Record/statement
selection, and same-Triptych Note openings without retaining Record data. Each
Triptych window owns one `ResearchRecordBrowserModel`: Application Record-query
requests, a disposable recommendation index, independent Scope and View,
presentation filters, selection, and at most one cancellable comparison task.
It owns no Record parser, flattened Record corpus, ranking, or freshness rule.
The native resizable list/detail
split has a 760 × 680 default frame and 700 × 520 minimum. Its left list is a
secondary navigation surface, not a Workspace Sidebar, and receives no Sidebar
toolbar treatment. The standard titlebar shows the window identity without a
feature toolbar. The Navigation plane owns a local View index above its List
and a borderless Scope menu in the list-context row; the independent controls
do not introduce a full-width header across the Document plane. List scroll
backgrounds are hidden so the semantic Navigation plane remains continuous.

The window renders finished portable Discussion and nonconversational Action
records, preserves attribution and evidence-class qualifications, exposes
tombstones, and routes live participating Notes only to a same-Triptych
Workspace. Pin replaces only `is_pinned`; recommendation disposition and note
updates replace only their selected occurrence; **Delete Record…** requires a
second confirmation before Core permanently removes only the selected portable
record under the same descriptor-relative coordination boundary. Ordinary
Markdown annotations remain in the document and never become separate
chronology. The window never enters the trailing split item and never owns
checkpoints, a document buffer, autosave, undo, conflict, retained trash, or a
second recommendation store. Its diff and recommendation grouping are
disposable projections over retained exact bytes. Closing Research Records
therefore cannot reveal or resize Research Inspector or mutate its presentation.
Its visible Scope remains This Note/Triptych; a Record found through global
This Vault Search reapplies Triptych Scope before selection without adding a
third auxiliary-window Scope or changing the shared provider semantics.

Attention is one native transient SwiftUI popover owned by each exact
`WindowModel`, not an app-wide Scene, sheet, inline Library destination,
utility panel, or always-on-top surface. Per-Workspace
`AttentionPresentationState` owns only filter, selected item, selected Scope,
and optional current-Note subset; `AttentionPopoverSession` adapts that state
and the current immutable queue to the Sidebar and Inspector anchors without
duplicating either. The adapter observes only the exact assignment and
workspace-projection owners plus the single dismissal-duration setting; it
borrows closed refresh and resynthesis effects and never observes or retains
the complete `WindowModel`. `AttentionScopeCounts` is a read-only projection
of the same catalog and machine-local dismissal ledger. Sidebar consumes only the
selected Scope's conditional alert; ScopeIndex labels never consume or expose
the count, and zero contributes no row or gap. The Document toolbar consumes
no Attention count, observation, item, action, reserved width, or popover
anchor. A missing first catalog remains checking, and a failed first load
presents Attention Unavailable with Retry rather than zero. Inspector may add
the active Note, and a Sidebar Scope change clears that Note subset. SwiftUI's
transient popover behavior owns outside-click and Escape dismissal; Inspect and
Resynthesize dismiss before routing through the same exact `WindowModel`.
**Window → Attention** asks the exact `WorkspaceWindowCoordinator` for a visible
contextual route: the nonzero selected-Scope Sidebar alert first, then the
nonempty current-Note Inspector summary. Without either visible anchor the
command is disabled; it never synthesizes a toolbar or detached presentation
route. The application-wide lifecycle registry records exact Workspace focus
changes so the newly active Workspace resets query, kind, Note subset, and
selected task without treating popover key-window changes or app deactivation
as Workspace switches. No global window search, notification, model registry,
detached Attention Scene, NSWindow attachment, or toolbar compatibility state
participates. Inspector alone consumes the document-adjacent apparatus surface;
Library has no literature-recommendation row, footer, count, or reserved gap.
The Document toolbar sends a Note-scoped Records request, while the Research
menu sends a Triptych-scoped request. Both target the same UUID-keyed auxiliary
window and neither changes Sidebar, Location, selection, filter, sort,
disclosure, Attention, or Inspector state.

Ordinary Scope and Location navigation uses a
`DiscoveryLocationRequest(.stagedReplacement)`. `DiscoveryController` retains
the last committed Scope/Location pair until completion and still rejects late
request identities. `WindowModel.currentWorkspaceVaultSnapshot` first consumes
the narrow `WindowWorkspaceProjectionController.vaultSnapshot(id:)` query; the
Application operation is only an initial-construction fallback. A complete
target pair and Source List commit together, while staged failure retains the
prior projection and reports through the existing toast path. Explicit refresh
continues to use the content-loading/error presentation.

Snapshot assembly derives Material Changed Since Use only from the latest
completed Synthesize Action record for a Topic/Material pair whose
agent-reported, Application-validated actually-used set contains that Analysis.
It compares the recorded exact revision with the current active, resolved
Analysis revision; selected-but-unused, deleted-record, tombstoned, deleted,
and identity-unresolved inputs create no condition. Each item ID also
distinguishes its affected Topic. The dismissal key includes the Triptych and
binds only Material identity, recorded revision, and current revision within
it. Inspect opens the current Analysis; Resynthesize rechecks that latest
record before opening the ordinary Synthesize sheet with the Analysis
preselected; Leave Unchanged stores only that exact condition key in
machine-local presentation preferences. A later current revision therefore
becomes visible again, and Settings can explicitly restore the decision. None
of these projections mutates Markdown or the portable record, and the warning
expresses no philosophical verdict.

The Research Inspector receives immutable `ResearchOverviewPresentation` and
`ResearchActionsPresentation` values composed at the window root. It owns no
workspace refresh, Comment, Critique, availability, or run state. Its Overview,
Connect, and Actions modes share the one native trailing split
item and one per-window `ResearchInspectorMode`; legacy stored strings are
normalized only while restoring that window. Mode changes and note/tab changes
never reconstruct the retained Document host. `ResearchOverviewPresentation`
contains at most one normalized Zotero navigation key for the current Analysis;
the view neither derives nor displays protected machine data.

The public Action panel uses one typed `researchAction` sheet route carrying
only a stable Target reference, Action ID, and presentation ID. The router owns
sheet exclusivity; `ResearchActionController` owns transient Profile-module
values and rejects stale availability or preparation results. `NoteContentView`
retains only the focused `openResearchAction(id:selection:)` action for menu and
keyboard invocation; it contains no Action presentation or bottom inset. The
sheet always exposes the app-owned Target, revision, authority, checkpoint,
conflict, and recovery boundary before rendering the Profile's closed native
modules. One **Copy Handoff** footer action first revalidates and freezes the
Action internally, then copies the complete researcher-to-Agent handoff. No
Agent-application picker, bookmark, persistence owner, or launch path
participates. A prepared Run keeps the same copy action available to retry it.
Its **Copy New Handoff** recovery invalidates the prior pairing and
copies the replacement without presenting the one-time code as a separate
field. A separate End Action route cancels the unfinished Run, whereas Done
only dismisses the sheet. Launcher availability and the sheet's fresh Profile
resolution
are separate: cancelling or failing a sheet cannot erase the Inspector, while
only the fresh Profile can prepare. The sheet cannot dismiss while preparation
is crossing its durable boundary. Presentation invalidation may still reject a
late noncooperative result or initial handoff; its undelivered Run receives
best-effort background cancellation and never becomes a visible recovery or
global barrier. An explicit prepared-Run cancellation that is interrupted
retains a per-run barrier until it succeeds or becomes its own visible,
retryable recovery entry in Actions. One recovery can therefore never
overwrite another. When a
window temporarily has no current Note, a recovery-only Apparatus keeps those
window-owned cleanup entries reachable without inventing a Target or Action.
Protected Function mapping occurs only in Application composition. The public
route and controller are Action-owned. Neither leaf receives `WindowModel`,
Core, or Application authority.

### Interface localization

The application target owns interface localization. `Package.swift` declares
English as the default localization. `Localizable.xcstrings` stores ordinary
SwiftUI interface copy and compiler-derived format keys; `Interface.xcstrings`
stores stable operational keys whose meaning must not depend on English copy.
`ScholiumL10n` resolves both tables from the target resource bundle. SwiftUI
consumes resources directly; AppKit adapters, status/error delivery, and
`String` presentation properties localize at their application-owned
delivery boundary.

Translation keys and stable application identities are distinct. Persistence
keys, accessibility identifiers, command IDs, enum raw values, vault-relative
paths, and internal execution IDs never change with locale. Researcher-authored
prose, note titles, quotations, citations, imported text, exact source, and
filesystem paths bypass the interface catalog and render verbatim. Purely
internal vocabulary that has no researcher-facing presentation is not a
translation surface. App-default and researcher-owned Skill/Practice names
render verbatim; surrounding application labels and explanations
remain localizable. Translator comments record interface context without
becoming product authority.

`sync-interface-localization.sh` builds the application and synchronizes the
catalogs from the compiler's `.stringsdata`; lightweight `%arg` extraction is
never treated as the runtime interpolation key. `validate-interface-localization.sh`
checks semantic-key parity, normalized source coverage, format-placeholder
preservation, complete Simplified Chinese state, and catalog compilation.
Because literal SwiftUI controls resolve against the outer app bundle, QA and
release packaging mirror the compiled localization folders from the SwiftPM
resource bundle into `Contents/Resources` while retaining the package bundle
for explicit `Bundle.module` lookups. `Info.plist` declares `en` and `zh-Hans`.

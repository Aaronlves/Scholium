# Implementation Status: Completed Migrations

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns completed architecture migrations and preserved invariants; sibling chapters do not restate it.

## Completed architecture migrations

No open architecture migration remains in the current ledger. Add a new item
only when live ownership, dependency, lifecycle, transaction, recovery, or
measured-performance evidence justifies it; file size alone is not an item.
The original batch-by-batch sequence and detailed proof notes remain in Git.

### Migration batches 1

**Current boundary**

`WorkspaceSourceOperationGate` owns cancellation-aware source/refresh leases inside the existing
`WorkspaceHandle` actor. Raw flags and unchecked waiters are absent.

**Invariant retained**

Cancellation before acquisition cannot gain later authority; an acquired durable transaction
finishes or recovers.

### Migration batches 2–4

**Current boundary**

One per-workspace `ResearchFunctionCoordinator`, organized into preparation, delivery, evidence,
completion, and host files, owns the protected Research lifecycle.

**Invariant retained**

One Workspace isolation domain, Local Execution writer, source gate, snapshot publisher, and
completion/recovery transaction.

### Migration batches 5

**Current boundary**

`AgentNoteChangeClaimCoordinator` owns cross-window claims; one `AgentNoteChangeWindowController`
owns each exact window's request, expiry, decision tasks, and sheet route.

**Invariant retained**

At most one claim per request, exact-Triptych routing, durable Application decisions, and
stale-result rejection after teardown.

### Migration batches 6 and 12

**Current boundary**

`WindowWorkspaceProjectionController` owns the exact-window immutable projection;
`WindowSearchController` owns Search execution, cancellation, freshness validation, and Saved Search
persistence.

**Invariant retained**

One Application source writer, increasing event generations, one visible Search projection, exact
unsaved This Note search, and no root-level duplicate tasks.

### Migration batches 7

**Current boundary**

Package repository, capability-document stores, and the pure resolver are separate;
`ResearchSkillTransactionCoordinator` remains the sole cross-store transaction owner.

**Invariant retained**

Package/binding/Profile mutations and recovery stay atomic; retained Function-era bytes are bounded
compatibility input and never regain write or execution authority.

### Migration batches 8

**Current boundary**

Native editor session, bridge/WebView adapters, test probes, and three TypeScript presentation
components are physically separate.

**Invariant retained**

One writable Markdown authority, one `MarkdownEditorSession`, one retained `WKWebView`, and one
CodeMirror `EditorState`.

### Migration batches 9

**Current boundary**

Research Guidance pages and large Application/UI test families are split by responsibility around
their existing state and fixture owners.

**Invariant retained**

File organization adds no state owner, runtime, transaction, or duplicate test suite.

### Migration batches 10

**Current boundary**

Recommended Bibliography is Triptych-owned and freezes a bounded selected-Note scope with exact
revisions.

**Invariant retained**

One portable store writer, exact source revalidation, prior-result retention, and no Markdown or
Zotero mutation.

### Migration batches 11

**Current boundary**

Sidebar and Inspector each own one stable visibility item in the single native Document toolbar;
pane content owns no duplicate Hide control.

**Invariant retained**

One native split, one toolbar, native collapsed-state authority, one applicable route, stable item
topology, and real pointer/accessibility reachability.

### Migration batches 13

**Current boundary**

`WindowShellState` and `WindowWorkspaceController` own window-shell and Triptych-session facts;
delivery composes narrow Research capability ports instead of the removed aggregate
`ResearchUseCases`. Unconsumed protocol façades and the unused `PendingResearchState` projection are
deleted.

**Invariant retained**

One window identity, one Workspace capability generation, one document/source authority, and no
change to durable record decoding or protected Function execution.

### Migration batches 14

**Current boundary**

`WindowEditorFlushCoordinator` owns one exact window's current and aggregate editor-flush
registrations behind `WorkspaceEditorFlushRegistry`; the root no longer directly registers,
unregisters, or initiates Triptych-wide editor flushes through `WorkspaceStore`.

**Invariant retained**

Flush precedes reconstruction capture and content replacement; transient host detachment retains the
selected editor; Triptych/runtime and restored-window identity changes rebind both capabilities
atomically; close removes them only after content is safe.

### Migration batches 15

**Current boundary**

Window root, Content, Research Record, and toolbar hosts observe their bounded owners directly;
`WindowModel` no longer fans every child `objectWillChange` into all consumers.
`WindowCommandObservation` invalidates only the focused window's command presentation for
command-facing owner changes and stores no product state. The scene derives child observers only
after SwiftUI has retained the exact root owners.

**Invariant retained**

Focused menu labels and availability remain current; child presentation changes do not invalidate
the composition root; toolbar topology stays stable while its hosted controls observe exact shell
visibility; independent windows retain independent observation scopes.

### Migration batches 16

**Current boundary**

`AttentionPopoverSession` observes only the exact Workspace assignment, immutable Workspace
projection, and dismissal-duration setting it renders; refresh and resynthesis remain closed
borrowed effects. The adapter no longer retains or observes `WindowModel`.

**Invariant retained**

Sidebar and Inspector anchors share one transient session; current Scope and Note filtering,
stale-data recovery, exact navigation, and per-window isolation remain unchanged.

### Migration batches 17

**Current boundary**

`WindowSearchController` publishes only its Saved Search state and no longer relays
`DiscoveryController.objectWillChange`; Search presentation consumers observe the exact Discovery
owner directly.

**Invariant retained**

Search execution, serialized Saved Search persistence, result-freshness rejection, ordinary Find
scope, and one visible Search projection remain unchanged.

### Migration batches 18

**Current boundary**

`ResearchController` publishes only research records, checkpoint/recovery state, and its active
document; it no longer republishes shell, `ResearchActionController`, or
`RecommendedBibliographyController` changes. Content and leaf views observe those exact owners
directly.

**Invariant retained**

Inspector mode and visibility, Action presentation and cancellation, Research Record,
checkpoint/recovery, and bibliography lifecycles remain independently owned and window-scoped.

### Migration batches 19

**Current boundary**

The pre-migration audit classified all 35 direct `WindowModel` calls to `WorkspaceStore`. Three
restore/save calls that bypassed the existing persistence owner now belong to
`WindowSessionPersistenceCoordinator` behind `WindowSessionPersistenceStore`. The 32 retained calls
are explicitly allowlisted as 12 composition/subscription, 7 window-intent/external-delivery, and 13
cross-owner Workspace activation/recovery calls; they remain in the composition root instead of
gaining a pass-through facade.

**Invariant retained**

Presentation restore, replaceable saves, and bounded final save share one owner; document flush and
window identity ordering remain unchanged; a new direct Store call now fails the architecture guard
until classified.

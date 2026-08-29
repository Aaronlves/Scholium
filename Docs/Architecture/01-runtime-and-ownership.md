# Architecture: Runtime and Ownership

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Runtime,
dependencies, state ownership, and windows.

## Architectural stance

Scholium is one local modular monolith with compiler-enforced frontend/backend
isolation. `ScholiumApp` and `ScholiumCLI` are delivery adapters over
`ScholiumApplication` plus internal `ScholiumCore`; both reach backend authority
only through Application capabilities and immutable `ScholiumContracts`
values. This in-process module and ownership boundary is not XPC or a service.

## Global ownership invariant

Every mutable fact, authorization policy, and workflow state has one
authoritative owner. That owner defines the fact's identity, lifetime,
mutation route, persistence, cancellation, teardown, and recovery behavior.
Other modules may read the owner's value, request a typed change, or translate
it for a delivery boundary; they must not copy its semantics into a competing
state field, policy, parser, or protocol.

Three roles remain distinct:

- **Authority** is the source of truth whose value or decision is binding.
- **Writer** is the sole owner-authorized mutation route for that authority.
- **Projection** is disposable derived state owned by the subsystem that
  builds and refreshes it; it never becomes a writable source or authorization
  source.

Coordinators may sequence owners and carry typed intents across boundaries,
but they do not become a second owner of the domain fact being coordinated.
When a responsibility crosses chapters, the owning chapter retains the
meaning and the neighboring chapter documents only its typed dependency and
translation boundary.

## Ownership

`ScholiumContracts` owns immutable boundary values, capability protocols,
structured errors, and deterministic exact-source parsing and projection.
`ScholiumCore` is an internal implementation target for repositories,
registries, SQLite indexes, watchers, coordinated mutations, durable stores,
exact Skill entries and ordinary references, and Zotero transport. The headless `ScholiumApplication`
target composes Core into delivery-neutral workspace lifetimes and use cases.
The macOS app and CLI depend only on Contracts and Application; Core is not a
library product and cannot be imported by either delivery target.

```text
ScholiumApp → ScholiumApplication → ScholiumCore → ScholiumContracts
ScholiumApp → ScholiumResearchRecordsFeature → ScholiumContracts
ScholiumCLI → ScholiumApplication → ScholiumCore → ScholiumContracts
ScholiumCLI → ScholiumCLIUpdate → ScholiumContracts

ApplicationBootstrapController (one app-owned storage gate)
├── Registry Recovery (preserve the damaged owning registry, then relink)
└── Ready (explicit validated Application Support URL)
    └── WorkspaceStore (macOS adapter and sole event-stream subscriber)
        ├── WorkspaceRuntime (one live runtime for the app delivery)
        ├── ResearchConnectionCoordinator (one process generation)
        ├── LocalAgentBridge (127.0.0.1 framed transport only)
        │   └── LocalAgentBridgeRequestRouter (wire-operation translation only)
        ├── SwiftUI WindowGroup (one Codable route per scene)
            ├── WindowModel (one per complete workspace window)
            │   ├── WindowShellState
            │   ├── WindowWorkspaceController (assignment, capability session,
            │   │   access recovery, and recovery cancellation)
            │   ├── WindowLibraryMutationController
            │   ├── WindowZoteroCoordinator
            │   ├── WindowCommandObservation (focused-command invalidation only)
            │   ├── WindowEditorFlushCoordinator
            │   ├── WindowCloseCoordinator
            │   ├── WindowSessionPersistenceCoordinator
            │   ├── DocumentTransitionCoordinator
            │   ├── WindowWorkspaceProjectionController
            │   ├── DiscoveryController
            │   ├── WindowSearchController
            │   ├── AttentionPresentationState
            │   ├── AttentionPopoverSession (exact Workspace adapter)
            │   ├── DocumentTabController
            │   ├── DocumentController
            │   │   └── DocumentSessionStore
            │   ├── ResearchController
            │   │   └── ResearchActionController
            │   ├── WindowPresentationRouter
            │   └── typed WindowIntent routing
            └── WorkspaceWindowCoordinator (one exact NSWindow/split boundary)

ScholiumApplicationDelegate
├── ScholiumWindowLifecycleRegistry (injected route readiness and flushers)
└── ResearchRecordsWindowCoordinator (transient Triptych routing only)

Research Records WindowGroup (one UUID value per Triptych)
└── ScholiumResearchRecordsRoot
    ├── direct WindowWorkspaceCapabilities for that Triptych
    ├── ResearchRecordBrowserModel (feature-owned Record query, collection
    │   route, filters, and rebuildable Reading Leads projection)
    └── ResearchRecordBrowserView (App-owned macOS presentation and Design
        System consumption)
```

`ScholiumResearchRecordsFeature` is a package-internal target that depends
only on `ScholiumContracts`. It owns the transient route, collection/filter
model, conservative Reading Leads index, continuation folding, and comparison-
task cancellation. Its collection index stores a lightweight scanning
projection without scholarly result or statement bodies rather than every
complete portable Record. Confirmed Research Record deletion first publishes a
reversible in-memory projection, then serializes the authoritative Application
mutation; success reconciles the removal, while failure restores the prior
projection. It imports neither
SwiftUI nor App delivery state.
`ScholiumApp` adapts those values to the semantic Design System and Application
capabilities; `ResearchRecordsWindowCoordinator` remains an App shell route
owner under `Scholium/App/Window` and retains no Record data. A typed
`.reviewResult` route carries one exact Record identifier and finalized-result
fingerprint; the feature model validates both and owns the resulting
window-lifetime direct-Undo grant. Multiple exact review requests may retain
independent per-Record grants through navigation in that same window. They are
neither persisted nor treated as source authority, and closing the window
destroys all of them.
The application-owned `ResearchResultNotificationCoordinator` observes
`WorkspaceResearchSnapshot.activities` and `resultArrivals`, folds one
process-local persistent activity per Run, deduplicates Results, replays each
window, and routes Review/Follow-up after all main windows close. A replaceable
`UNUserNotificationCenter` adapter receives only the private background body
and route IDs. Delivery never opens, retargets, focuses, or reviews before an
invoked action. Window/popover disappearance does not remove activity; only
completed Dismiss does. Execution, Record, per-Note Review, and source evidence
remain separate durable owners.

### Runtime bootstrap, refresh, and Search

`ApplicationBootstrapController` is the sole production route to
`WorkspaceStore`. Its states validate `Scholium/State-v1` beneath real per-user
Application Support before runtime construction; unsupported pre-release
parent bytes remain unread and nonauthorizing.
`WorkspaceStore.init(applicationSupportURL:)` is explicit and failable; there
has no temporary or empty-registry fallback. One malformed workspace
registration enters app-root Registry Recovery. Explicit relinking preserves
and verifies that owner. Newer, unsafe,
or unreadable state exposes Details and Retry only. Recovery never scans or
mutates vault Markdown. An
explicitly supplied QA root uses the same validation. `WorkspaceRuntime` then
has two configurations:
live reuses stable Triptych/vault runtimes, watchers, and derived refresh while
any app window needs them; snapshot performs one-shot loading without watchers
and shuts down after each CLI invocation.

The live macOS activation may ask `WorkspaceHandle.open` for one selected
`WorkspaceVaultSlot`. The handle constructs all three repositories, pooled
catalogs, watchers, and capability objects once, but first publishes an explicit
`WorkspaceSnapshotPhase.opening` snapshot from only that Vault's authoritative
catalog and portable identities. `DocumentOperations.load` is usable at this
phase; Search and Research Action resolution fail closed with
`workspaceStillLoading`, and absent Graph, Search, and Research projections are
not complete evidence. The handle owns one utility-priority opening-completion
task. Watcher events enter the existing bounded journals while a complete
three-catalog reconcile, Graph build, Search synchronization, research
projection, and atomic event publication run through the same refresh
coordinator and source-operation gate. The first live refresh that can replace
an opening snapshot completes its full post-observation activation reconcile
before building or publishing `.complete`; Search availability and watcher
readiness therefore cross one actor-owned completion boundary. The completion
task waits until the opening Vault's first Document crosses its native
visible-layout boundary, so
the full reconcile cannot contend with that initial presentation; a bounded
fallback still completes a Library-only window or a failed renderer. The
complete snapshot replaces the opening phase; no second repository, catalog,
watcher, index, or source owner is created. Cancellation and shutdown cancel
and await that task. Snapshot/CLI opens and live callers without a selected
opening Vault retain the complete one-shot path.

Each `WorkspaceHandle` owns one Note `TriptychSearchIndex` at
`Triptychs/<triptych-id>/indexes/search-v9.sqlite`; pooled vault runtimes own
repositories, watchers, and one shared `VaultSourceCatalog`, but no Search
index. The catalog retains exact `NoteDocument`, descriptor-observed file
metadata, `SourceVersion`, cached `MarkdownSemanticDocument`, and the
source-bound part of
`SearchDocumentProjection` as disposable state. Review and broken-link fields
are reapplied with a lightweight projection-hash update, so ordinary Search
deltas do not rebuild visible text and exact offset maps for unchanged notes.
An opening-Vault catalog pass retains the exact document and Library semantic
projection while deferring Search-specific visible text and offset maps. The
same catalog actor completes those missing maps from its retained exact
documents, without a second source read, before any complete Triptych Search
generation may publish.
Projection construction advances monotonic UTF-16 cursors, preserving exact
source mapping without repeatedly rescanning an accumulated String.
Watchers start before initial reconcile; precise events update entries. Event
loss or rebuilds reconcile fully; root replacement
invalidates the pool until Restore Access replaces it. `WorkspaceSnapshotBuilder`
consumes three immutable catalog
generations and still rebuilds the complete in-memory graph. The three
independent catalog actors may prepare concurrently inside one refresh cycle;
Graph construction, Search synchronization, snapshot publication, failure, and
retry remain ordered under the one coordinator worker. It does not reread or
reparse every Markdown file for an ordinary single-file save.

One `WorkspaceRefreshCoordinator` actor per handle serializes the complete
prepare → Search synchronize → snapshot publish cycle. Monotonic
`RefreshRequestID`s make an in-flight cycle cover only the requests it captured;
later requests coalesce into the next cycle, and cancelling one waiter cannot
cancel work required by another. Merged cycles prepare every requested source
path, not just the last payload. One `WorkspaceSourceOperationGate` value,
isolated by the owning `WorkspaceHandle` actor, gives source mutations and
refresh cycles mutually exclusive leases. Its tokenized waiters are
cancellation-aware, so cancellation before lease acquisition removes only that
waiter; cancellation after acquisition does not revoke a transaction that must
finish or recover. The extraction adds no actor hop and owns no I/O, rollback,
or publication. While a source-mutation lease is active, watcher invalidations
remain buffered until the filesystem transaction, portable identity, and other
path-bound stores agree, preventing a builder from observing the file/identity
gap. Search publication applies one transactional
`SearchIndexDelta` carrying a transactionally persisted workspace generation
and refuses stale generations, including across index reopen or another
process connection. A failed cycle preserves the last complete snapshot and index.
Repository save completion is deliberately earlier than this disposable
cycle. `DocumentOperations.commit` returns the revision-checked authoritative
`NoteDocument` as soon as the repository commit is proven. Direct untitled-note
creation likewise returns a `WorkspaceManagedNoteCommit` after exact source
and portable-identity setup, before complete derived publication. The owning
`WorkspaceHandle` queues both paths into one utility-priority source-commit
refresh task before releasing the source-mutation lease, coalesces later
commits, and publishes either the refreshed snapshot or typed stale derived
state. Matching watcher work waits behind that owned task instead of starting a
competing refresh. A Graph, Note Search, catalog, or snapshot failure therefore
cannot become an Autosave Failed result or ask the editor to replay a committed
mutation. Same-generation research and file workflows instead call
`DocumentOperations.save`, which explicitly waits for derived publication.
Every other document create, import,
source-and-derived save, move, folder mutation, system-Trash deletion, and
identity resolution returns a `WorkspaceMutationOutcome` once its
authoritative commit is proven. Disposable refresh or post-move identity-
recovery failures travel as nonretryable warnings beside that committed value;
they never replace it with a generic thrown error. GUI and CLI callers
acknowledge the committed source and direct recovery through Refresh or
identity repair without repeating the mutation. Multi-file GUI import
aggregates both warning classes across every committed file instead of
discarding per-file identity recovery state, and the batch remains bound to
its initiating Workspace so a Triptych switch stops remaining imports instead
of routing them through replacement capabilities. Its exact Window owns the
single batch task; an actual window close cancels remaining files without
reclassifying prior commits as failures. Create, import, and duplicate
also treat portable-identity setup as part of their creation transaction: an
exact rollback failure is observed rather than discarded. A proven retained
source becomes the committed outcome with an identity warning; unreadable
source presence becomes an explicit uncertain error that forbids blind
recreation.
Portable control bootstrap claims each missing file with a no-replace create;
another process's winning bytes are loaded and validated rather than replaced.
Every `identities.json` mutation carries the exact read preimage through one
coordinated swap and decoded readback proof, so a stale move, reconciliation,
or creation writer cannot erase a newer portable Note identity.
Direct relation queries are publishable only when the Graph and Note Search
manifest hashes agree. A relation clause is part of one structured AND query;
Graph absence, staleness, or mismatch fails that complete query closed rather
than returning its lexical clauses as a broadened substitute. An ordinary
lexical query remains independently available from its last complete compatible
Note generation. There is no parallel direct-connection Search presentation;
explicit relation clauses are the only Search consumer of Graph neighborhoods.
`DiscoveryOperations` owns vault-qualified Link/Relationship and bounded Graph
queries; CLI only formats results.
Privacy-safe measurements record enumerate/read/parse/source-
projection counts and durations, identity and research-state projection,
graph construction, dynamic Search projection and synchronization, snapshot
assembly, source-byte size, publication, and total duration without source
content or identifiers. Per-vault source durations are work sums and may
overlap; total duration remains wall clock. Snapshot assembly reuses the exact
same generation's reconciled portable-identity state for Critique association;
only `.resolved` identities participate, so ambiguous, pending, unresolved, or
failed recovery remains closed without one storage lookup per Work.

`ScholiumContracts` owns contract-v9 parsing and typed clauses, the closed
Note/Record provider and capability tables, provider-mismatch diagnostics,
completion and Explain Query descriptions, discriminated results, visible
semantic `SearchDocumentProjection`, exact source mappings, CJK query
projection, requests, responses, availability, and generation/freshness
identities. Structured projection joins validated Metadata with authored YAML
`summary` and `keywords`: YAML matches retain ranges, managed values have none,
and unknown YAML is not queryable. Core owns the Note
provider's disposable SQLite schema, staging/validation/recovery, read
transactions, cancellation, deterministic ranking, and in-memory **This Note**
matcher. The portable Record store supplies exact decoded schema-17 Records,
schema-1 Note Reviews, and their source-byte fingerprints; Application owns the rebuildable Record query
projection and provider routing, authorizes visible scope before query, and is
the only Search capability exposed to GUI and CLI. No adapter, window model, or
Agent route owns another parser, resolver, Record corpus, or ranking rule.

Saved Searches persist only raw query, visible presentation scope, and Search
contract version. `WindowSearchController` owns execution cancellation,
freshness, serialized persistence, and load failure. Explicit recovery uses the
same-directory exact-state preserver before clearing that failure;
`DiscoveryController` owns the visible completion/result selection. Search
views and their composition consumer observe `DiscoveryController` directly;
`WindowSearchController` never republishes Discovery changes as its own. None
of that window state, parsed AST, resolved anchor, result bytes, or generation
enters the persisted definition.

### Application capabilities and delivery

Application composes a private `WorkspaceHandle`; the macOS adapter exposes
`DocumentUseCases`, `DiscoveryUseCases`, and one app-owned
`WindowResearchCapabilities` value composed from the narrow Record,
Skill/Profile, collaboration, Action/Run, Research
Context, evaluation, and source-access ports plus immutable
identity/assignment values. Contracts declares no aggregate Research mega-port.
Configuration preflights roots and reads the portable manifest before
registration. `WorkspaceRegistry` is the single machine-local owner of
Triptych membership, role Vault UUID/path/bookmark bindings, default selection,
and portable-container access. Valid Triptych and role Vault UUIDs remain
authoritative. Missing manifest creates identity. Rejected selection or
manifest leaves the one registration unchanged; renewed access replaces its
exact bookmark binding.
`WorkspaceStore` coalesces duplicate runtime
installation, retains one event subscription before publishing activation,
starts it with the handle's explicitly phased latest `WorkspaceSnapshot`, and accepts only increasing
generations. Commands remain direct capability calls, not event-bus messages.

`WorkspaceStore` owns the live runtime, accepted Application-event
subscription, latest explicitly phased immutable snapshots used by direct app adapters,
cross-window editor-flush registry, and macOS adapters. The app-wide registry
implements the client-owned `WorkspaceEditorFlushRegistry` port. One
`WindowEditorFlushCoordinator` per exact window owns the current editor and
aggregate-window registration identities, Triptych/window rebinding, stale
current-editor validation, and teardown; `WindowModel` neither stores those
registrations nor calls the concrete Store's register, unregister, or
Triptych-wide flush methods. `WorkspaceStore` publishes one
generation-gated `WorkspaceEvent` map to windows; derived-refresh status and
generation remain inside that event rather than separate window-facing
mirrors. Each window receives one atomic capability generation. CSS/App
Support, Obsidian reads, and Zotero HTTP stay behind Application actors; the
store owns no Core authority.

`WorkspaceStore` owns bridge startup, shutdown, and cross-window editor flush;
`LocalAgentBridgeRequestRouter` alone translates the closed wire-operation set
through the Application runtime, flush port, and permission-claim projection.
The App listens only on `127.0.0.1`; Pairing Codes and Sessions authorize it
without an App Group. `ResearchConnectionCoordinator` owns process-local
credentials, while each Run stays with its `WorkspaceHandle`. Neither
transport nor router owns Run context, source, recovery, or durable decisions.

### Window state and feature controllers

`WindowModel` is the per-window composition root.
`WindowShellState` alone owns selected workspace, Inspector mode, Library
disclosure, initial restore, peripheral visibility, text scale, appearance,
toast, and shell status. `WindowWorkspaceController` alone owns Triptych
selection, registration, capability generation, identity, access recovery,
and restoration. It calls `WorkspaceStore` for configuration, activation
snapshots, registration, permissions, and Vault configuration, then a
typed installer lets the root bind that accepted generation into feature
owners without selecting or mutating the session.
`WindowLibraryMutationController` owns Note/Folder preparation and mutation
through `LibraryMutationUseCases`; `DocumentController` forwards no Library
writes. `WindowZoteroCoordinator` owns cancellable search/binding and committed
messages. `ZoteroBindingPanelMutationOwner` owns save/clear lifetime and busy
state; its view owns error/recovery presentation. `WindowModel` wires these
owners but proxies no operation.

`WindowSessionPersistenceCoordinator` owns restore and replaceable/final saves;
after native close it refuses every write. `WindowCloseCoordinator` owns attempt
identity, content-before-presentation sequencing, and once-only teardown.
`WorkspaceWindowCoordinator` alone finalizes it from AppKit `windowWillClose`;
SwiftUI disappearance only detaches presentation. `DocumentTransitionCoordinator`
owns and cancels serialized transition tasks. `WindowEditorFlushCoordinator`
owns ordered current-editor and aggregate-window registrations. They survive
preparation so cancelled application termination remains retryable, and end
only after AppKit commits the close. `ResearchActionController` owns the exact
window's transient write-set subset sheet and the read-only projection of
direct Continue Research children beneath the current parent Action. It owns no
finalized-result or researcher-response presentation. The Records-only
`ResearcherResponseEditorSheet` owns one local Evaluation-plus-Method-Feedback
draft for the exact rendered Record, its dirty state, operation lifetime,
discard confirmation, and stale recovery. Explicit and implicit dismissal
remain blocked until save or authoritative reload resolves. The comparison
sheet separately owns only its current document-fold, equal-range-fold,
selection, loading, and per-document operation presentation. These transient
values are keyed to one Record and current sheet lifetime; none owns durable
authorization, source bytes, Record, Response, or Note Review state.
`WindowSearchController` owns Search/temporary Find execution and
cancellation, provider-aware exact result-freshness validation, generation or
Record-manifest reruns, and serialized Saved Search loading and persistence. It
coordinates the `DiscoveryController` completion/result projection while
borrowing only a checked current document snapshot and navigation/presentation
effects from the window root;
consumers observe the two owners independently rather than using the execution
controller as an invalidation relay.
`WindowModel` composes owners and routes cross-feature intents without relaying
child `objectWillChange`. Views and `AttentionPopoverSession` observe their
bounded owners directly. The scene root first retains `WindowModel` and
`WorkspaceWindowCoordinator` as `StateObject`s, then passes those stable
instances into `ScholiumWindowObservedRoot`; child `ObservedObject`s are never
derived from a newly constructed root instance that SwiftUI may discard.
Direct `WorkspaceStore` use in `WindowModel` is limited to composition,
subscription, and exact-window external delivery. An
executable allowlist requires a fresh ownership audit for every new call family.
`WindowCommandObservation` owns no product state: it advances
one window-local revision only for the shell, assignment, Library source,
document/projection, and Research Action facts that affect focused command
labels or availability. Commands still read and mutate the existing owners.
`DocumentController` alone owns
selection and document workflow state; `ResearchController` owns the current
research-record projection and durable-recovery listing. Shell and Research
Action state remain independently observable
owners; `ResearchController` neither republishes nor duplicates them.
`DocumentTransitionCoordinator` serializes workspace and document replacement,
flushes the exact active editor before mutation, coalesces rapid workspace input
to the last requested destination, and commits only after the destination
Library projection and retained selected tab are valid. `WindowModel` then
changes the Shell selection, Document mode owner, active tab group, selected
Document, and Inspector projection in one main-actor commit. A preparation,
save, conflict, or destination-validation failure leaves the originating
workspace session selected and unchanged.
Research Records windows bypass focused `WindowModel` state and read only the
capabilities and immutable snapshot for their keyed Triptych. Their coordinator
retains pending presentation requests and same-Triptych navigation endpoints,
never Record data or authorization. `ContentView`, Inspector, Actions, and
Research Records leaves observe only the owner whose state they render.
The feature model begins at `.collection`; selecting one Record or Reading
Lead replaces the collection through a typed transient route. Closing the
window drops that route and every presentation filter without altering the
portable store. A Continue Research child remains available by exact ID and
Search, but the feature folds it beneath its direct parent instead of
projecting a peer collection row.
`WindowWorkspaceProjectionController` is the exact-window owner of the
immutable research catalog, resolved Metadata catalog, per-vault snapshots, selected Library's
Notes/tags/authors/revisions and property-filter options, graph, Note
Search generation, derived-refresh status,
and catalog refresh lifecycle. It accepts only the active runtime and increasing
event generations, stages a complete `State`, and publishes that state once.
The selected Library's revision map reuses each immutable document's existing
fingerprint and never rehashes exact source merely to construct a window value.
Research-configuration invalidation advances event order without replaying an
unchanged projection; a deleted Note remains in the visible projection only
while its exact dirty editor owns conflict recovery. `WindowModel` forwards
read-only values and applies typed presentation effects, but exposes neither the
controller's backing cache nor a second writable source authority. A cached
Note lookup treats a supplied stable Note ID as exclusive identity authority;
only a caller that has no stable ID may resolve by path. A moved Note therefore
cannot be replaced in the current document, tab, Search evidence, or Library
reveal path by a different Note that later occupies its former path.

### Library projection and source-ahead mutations

The Library and File menus send focused New Note commands to
`WindowLibraryMutationController`, which owns exclusion, flush ordering, and
the Application call. `WindowModel` receives only committed projection and
navigation effects. Application
atomically advances through occupied default paths; the view never scans or
writes the vault. After the source and identity commit, the exact window
installs one `sourceAhead` `WorkspaceNoteSnapshot` for presentation and marks
derived state stale; its graph-count values are nonauthorizing placeholders and
Research Actions remain closed. The matching complete generation replaces this
overlay through the ordinary event gate. The window therefore activates the
new stable identity without blocking on Triptych-wide identity reconciliation
or graph construction and without creating a second source authority. The
managed creator snapshots the current Settings revision and prepared role
source before committing; GUI, researcher CLI, and Agent adapters never compose
their own headers. A failed final source-and-identity proof persists one
coordinated recovery record; researcher creation freezes only its exact path
and reserved identity, while Agent creation separately links its Run operation.
Machine-local recovery duties are independently bounded files behind one
cross-process record-store lock, so accumulated pending duties cannot consume a
new duty's write budget. Managed identity reconciliation and portable Zotero
binding writes share a separate control lock; recovery may add or remove only
its own reserved identity in one identities-file CAS. Any other identity at the
path stops reconciliation even when its bytes match. The exact in-memory
receipt rolls back only the reserved-identity mutation if final source or
binding proof fails; no foreign identity preimage is displaced.
The window selects Edit and requests the exact body offset after the durable
source commit. Bridge initialization applies the mapped
collapsed selection without focus and returns the exact selection with its mode
acknowledgement; native code verifies both, converges presentation, then
publishes readiness only after a final focus acknowledgement. Only
after activation, `DiscoveryController` clears excluding Library filters,
unions the destination's folder ancestors into window-local disclosure, and
publishes one generation- and scope-bound reveal request. `SidebarView` consumes
that request by scrolling to the selected row without taking keyboard focus.
The same presentation path follows every successful active-Note activation:
`WindowModel` asynchronously stages the exact Note vault and Library source,
rejects a stale target after any newer navigation, preserves filters when the
Note already passes them, and otherwise clears only that excluding filter set
before requesting the minimum scroll needed to expose the row. The adjacent
adaptive expand/collapse button mutates only the current `WindowShellState`
disclosure scope and does not own a second reveal route.
Folder disclosure and subtree expansion remain `DiscoveryController` state. A
disclosure commits its flat visible-row projection without a list-wide layout
animation; the row's
single chevron alone consumes the shared, Reduce-Motion-aware
`ScholiumMotion.disclosure` recipe also used by Connect. This prevents departing
Note labels from interpolating through their owning Folder while retaining one
stable row identity and one controller-owned disclosure set. Core enumerates real
directories so empty classifications survive projection, but folder paths never
enter the portable identity store. Direct New Folder creation atomically claims
one default directory name. Empty-folder creation and empty-folder moves publish
only a new folder inventory snapshot; they preserve the current Search and graph
generations because no Markdown source or note location changed. Rename and
Move flush Triptych-wide editors, preflight the complete descendant-note
inventory, and commit one
descriptor-relative no-replace directory rename. `TriptychFolderMoveCoordinator`
applies exact resolved-link rewrites against one future graph with rollback and
durable recovery; Application then rebinds every descendant stable note ID in
one control-store write and resumes existing idempotent path migrations. Other
directory contents move with the inode and are not parsed. System-Trash folder
deletion instead freezes the complete directory manifest, including hidden,
non-Markdown, and empty-directory entries, then submits the directory once
through `VaultMutationCoordinator` and Foundation's native Trash API. A managed
Critique outside the directory remains a separately receipted native move.
Copy Relative Path
and Reveal in Finder remain delivery actions over an existing folder or note
vault-relative path and create no Core authority.
When the accepted Workspace source cohort and graph manifest are coherent, a
Folder move uses that exact in-memory cohort and reparses only graph-identified
incoming-link candidates; a pending, source-ahead, or structurally stale cohort
falls back to the complete filesystem read and graph derivation. The repository
still re-enumerates and fingerprint-checks every descendant immediately before
the directory rename. After commit, the coordinator returns each descendant's
exact committed source, including any safe link rewrite. The exact window moves
its Folder inventory and Note snapshots as one explicit `sourceAhead`
projection, while the Application queues the sole complete derived generation
before releasing the source lease. Matching watcher events therefore converge
through that owned refresh rather than delaying the native outline or starting
a competing rebuild. Until that generation arrives, Application merges durable
source-ahead identity records with the last complete snapshot by stable Note ID
when it builds a Folder descendant plan. A just-created Note and Notes moved by
an earlier Folder transaction therefore follow their current source paths;
Core still re-enumerates the directory and rejects an incomplete inventory.
Note and Folder rows publish distinct own-process drag identities so local drop
sessions can advertise Move only for the matching exact vault and a valid
destination. Folder target validation rejects its current parent, itself, and
its descendants before calling the same Application-owned folder Move path;
the drag layer never enumerates descendants or writes source. The populated
hierarchy's `NSOutlineView` is the sole drag source and Folder-row destination
owner: its data source writes the process-private pasteboard payload, AppKit
provides autoscroll and full-row source-list feedback, and the delegate accepts
only exact Folder-row targets. A native AppKit destination behind the stable
Library header alone accepts a vault-root move; root Note rows and outline
whitespace reject it. The surrounding SwiftUI hierarchy does not register a
competing drop destination. Acceptance revalidates the current
revision, destination occupancy, and in-progress identity before dispatch. Core's
root-scoped `VaultPathResolver` remains the sole owner of mounted-volume case and
Unicode-normalization comparison behavior; `WorkspaceSnapshotBuilder` projects
those immutable facts through `WorkspaceVaultSnapshot` without asking the UI to
probe the filesystem. `SidebarTreeDropInventory` precomputes typed Note and
Folder comparison keys from that policy and uses them for no-op, current-parent,
self, descendant, and occupied-target preflight. A missing policy fails closed,
while every accepted move still repeats containment, collision, identity, and
revision checks inside Core immediately before commit. A stale or repeated
gesture therefore cannot advertise or start a second move, and presentation
preflight never becomes filesystem authority.

`WindowModel` owns one exact-window `LibraryTreeProjectionCache`. It returns an
immutable version whose revision advances only when the ordered Note cohort or
Folder inventory changes; recreating a `SidebarView` for document loading,
selection, focus, disclosure, or toolbar state reuses the prior tree. The
projection registers each real Folder ancestor once, builds parent-child
adjacency before recursion, and supplies the same roots, disclosure sets, and
deterministic removal-focus order to the header and native outline. The Outline
coordinator performs complete structure comparison and item reconciliation only
when that projection revision changes; ordinary presentation updates still
refresh the currently available reusable rows. Native expansion reconciliation
likewise runs only when the desired disclosure set or outline structure changes;
an unrelated configuration application neither rescans every item twice nor
replays AppKit expansion. `WindowModel` filters and orders
the Note sequence before the cache lookup. Modified-time ordering reads a Note
title only for an actual timestamp tie; title ordering retains its existing
fallback. The tree projection preserves
that order within each Folder without receiving a second comparator closure.
`SidebarContext` derives its vault identity from the disclosure scope and names
the shared create/move/drop gate as Library mutation capability, so parallel
immutable inputs cannot disagree about the active vault or authority.
Populated hierarchy ownership is split by responsibility:
`SidebarOutlineSourceList` configures the `NSOutlineView`, its coordinator owns
data-source/delegate reconciliation, the row layer owns native reuse and hover,
and the native-drop layer owns process-local pasteboard decoding plus the
Library-header root target. AppKit-authored menus, tooltips, and accessibility
values pass through one explicit locale projection; researcher Folder and Note
titles remain verbatim. Library-only filtering is rendered by one stateless
`SidebarLibraryFilterMenu` from an immutable options value plus the current
`DiscoveryFilterState`; every change returns one complete replacement intent
to `DiscoveryController`, which remains the sole filter and ordering owner.
An ordinary Note move flushes the registered editor only when that exact Note
is active. Every identity-dependent interface command first captures one
`NoteMutationTarget`: its vault-qualified document ID, stable Note ID, and
exact source revision remain one value through Window, controller, use case,
and Application. Application re-resolves the stable identity under the source
mutation lease before a move or deletion can commit, so path reuse cannot
retarget a stale row or sheet command. The CLI retains its explicit
vault-qualified path plus exact-revision boundary. Context menus and
accessibility actions are rendered from one semantic Note-command projection;
only the surface-specific non-drag Move alternative differs.
`WorkspaceHandle` first asks `IncomingLinkRewriter` to plan from one
coherent exact-source Workspace snapshot and its graph: the graph supplies only
candidate incoming occurrences, and only those source documents are reparsed
and resolved against the current and future catalogs. An incomplete,
source-ahead, or structurally stale snapshot cannot authorize this path and
falls back to the complete filesystem read and graph re-derivation. After the
source/link/identity transaction commits, the exact window installs the moved
source at its destination as an explicit source-ahead projection, activates and
reveals it immediately, and lets the complete derived refresh converge in the
background.
Document, Search, and presentation are window-local. Library hierarchy,
filters, sort, Document tabs, live Document mode, and Inspector mode
are partitioned by the three Triptych workspaces; Sidebar/Inspector visibility,
split geometry, toolbar, and window frame remain outer-window state. Controllers
do not mutate one another. Separate
`WorkspaceSettingsModel` groups workspace, machine, Zotero, and Research
Guidance capabilities without constructing a document window. Its delivery-
neutral snapshot carries both `TriptychSettings` and exact `SettingsRevision`;
every save returns a replacement snapshot, so two Settings windows cannot
silently last-writer-win.

### Document tabs and native shell

Each window has one `DocumentTabController`, partitioned internally into
Analyses, Topics, and Works groups with one selected page per group. An `.unspecified`
`NSTabViewController` in the middle split item hosts document pages; a
Document-owned selector renders the tabs. `.toolbar` is forbidden because it
would replace `NSWindow.toolbar` and create a second toolbar owner. Tabs create
no window, model, split, Library, or Apparatus. The controller owns only order,
per-workspace selection, and document references; inactive groups remain
retained but are not projected into the native container. `DocumentController` and
`DocumentSessionStore` retain sessions and apply the flush/reconstruction guard.
Apparatus derives from the active document, keeps window-owned visibility, and
restores the selected workspace's mode. Only New Window creates a shell. The
Document presentation owns one live Review/Edit/Source selection per workspace,
defaults each to Review, and carries that selection across Note and tab changes.
`WindowSessionSnapshot` stores the selected workspace plus three
`WindowWorkspaceSessionSnapshot` values containing role-partitioned tab order,
selection, scroll positions, Document mode, and Inspector mode.
Unsupported session bytes fail closed rather than entering a compatibility
decoder.

Each configured scene constructs one `ScholiumWorkspaceSplitView`: one
`NSSplitViewController` with three direct `NSSplitViewItem` siblings for
Library, Document, and Apparatus. The split and each item's one opaque semantic
background fill the frame beneath AppKit's transparent titlebar. The standard
SwiftUI toolbar background is hidden, with no background-extension effect or
duplicate color source. Native titlebar behavior remains, and each content
controller is a foreground sibling inside the system safe area. The Library
container alone adds one full-bounds, noninteractive structural-depth host above
its content. That host clips the Document-owned shadow to the Library plane and
contains no split geometry, visibility, toolbar, or semantic state; collapsing
the native Sidebar removes the complete container projection with it.

The one `NSWindow.toolbar` is divided into Library, Document, and Apparatus
sections by native tracking separators. Before split attachment,
`WorkspaceWindowCoordinator` installs an inert toolbar and later replaces its
items in place. Sidebar retains one borderless hosted `NSToolbarItem` at the
logical trailing edge of the Library section immediately before its tracking
separator; Inspector retains its matching item immediately before the
Apparatus separator. Their hosted views observe `WindowShellState` and switch
accessible Show/Hide label, value, ink state, and explicit exact-window action
without changing toolbar item topology or adding a persistent active enclosure.
Pane content contains no duplicate visibility control. No
split-content titlebar host remains: under full-size content that host rendered
beneath the toolbar's pointer hit-testing layer even when accessibility could
still discover it. Stable native toolbar controls satisfy §18.2 without adding
a geometry owner or painted titlebar layer.

AppKit owns resizing, compression, dividers, collapse, fullscreen, frame
restoration, and drag limits; the Codable route owns scene identity. No width
binding, window search, persisted divider geometry, or continuous correction
intervenes. Library receives the specified 300pt native content minimum,
without a preferred/maximum width or second geometry owner. Apparatus uses a
standard resizable `NSSplitViewItem` with the 270pt system Inspector minimum,
no application-defined maximum, and its initial collapsed state installed
before the item enters the native split. A controller-lifetime adapter offers
the provisional 320pt ideal exactly once when the first explicit reveal
finishes and Document can retain at least that width. The adapter is never
called by the split resize callback, so the offer cannot override a user drag.
The offer is neither persisted nor replayed; all later resizing, hiding,
showing, and restoration remain AppKit-owned. No item receives a Scholium
fraction, holding priority, or restoration state. A scene/window minimum
remains contingent on the complete adaptation matrix.

Apparatus remains the semantic Inspector, but does not use
`NSSplitViewItem(inspectorWithViewController:)`: on macOS 14 and later that
factory is a fixed-width presentation whose committed drag behavior returns to
the system Inspector thickness. Explicit toolbar and View commands set the
retained split item's native collapsed state directly; divider interaction only
changes width and never enters the collapse path. Because the nested split may
sit outside the responder chain, the visibility route is a borderless hosted
item, not the platform-wrapped standard toolbar item, and bridges with the View
command through the exact per-window coordinator. Selected-document state
supplies availability when showing, while a visible Inspector can always be hidden.
`WindowShellState` mirrors native visibility for commands, toolbar labels, and
restoration. The toolbar controller installs one stable item list; its hosted
controls observe shell visibility without reasserting split state or storing
width.

### Inspector ownership

The Inspector has exactly three current-note modes: Overview, Connect, and
Actions. Overview presents a current-Note Notifications summary whose one
button routes to the exact Workspace's unified popover, followed by role-aware About fields;
About keeps selectable values and routes editing through its heading button.
For Analysis, `WorkspaceSnapshotBuilder` joins portable Zotero binding by Note
UUID; the window supplies exact library/key and `ZoteroBridge`. About exposes
link/manage and bound open/refresh actions without inline machine data.
`ZoteroBindingPanelView` searches local items or prepares exact binding,
rendering an immutable plan. Complete keys never fall back to collection
search; refresh directly addresses bound user/group item.
`ZoteroBindingOperations` revalidates source, exact server/library/item,
binding/Metadata revisions; writes absent fields for Link and Fill or previewed
differences for Refresh; reports partial commit; refreshes derived state after
mutation. UI owns no mapping/writes; frontmatter is excluded. Connect
projects direct and
derived relations as single full-row targets, pins the original collapsible
group header within its sole vertical scroll, and retains the distinct source
anchor as a named secondary action without a trailing glyph. Actions resolves
the public role-valid closed Platform Action matrix, presents it under quiet
Research and Review headings, and keeps Settle under
Judgment. Every launcher remains the same direct full-row operation and invokes
its exact Inspector-supplied window route; focused routing belongs to menu
commands rather than row activation. Pointer activation does not write keyboard
focus, while keyboard traversal and deliberate restoration retain it.
Availability is bound to the exact current Note,
clears while it is being rechecked, and rejects a late result from a previous
Target. Completed work remains in the separate Research Records window, while
Agent handoff is presented by the selected Action. A quiet row for each
portable active Discussion that includes the current Note resumes passage-anchored, whole-note,
and focal-note exchange, while Settle remains a separate researcher-owned
current-state operation. Active Discussions never appear in Research Records;
finished Discussions and completed Actions do, while removed Records have no
projection. The
Inspector may navigate or open another
note in the owning workspace's Document tabs, but it never owns a document buffer, editing,
autosave, undo, or conflict state. Those remain exclusively in the Document
surface and its existing controllers.

### Container decision rule

Before changing a window/container boundary, engineering must:

1. name the state that should remain stable and the content that should change;
2. inspect the current ownership and controller hierarchy;
3. verify the applicable public AppKit or SwiftUI container contract against
   current documentation and a minimal isolated prototype;
4. record which controller owns lifetime, selection, persistence, and layout;
5. integrate the proven container without parallel state or geometry owners.

For content tabs, `NSTabViewController` is the mechanism authority; its
prototype is not visual authority. `NSWindowTabGroup` selects whole windows,
and `WindowGroup` creates scene state, so neither meets the page-only contract.
`NSDocument` is not adopted as a second persistence owner: Application and
Document retain Markdown, autosave, conflict, and recovery authority.

### Bootstrap scene

Bootstrap is a separate data-routed `WindowGroup`; `ScholiumBootstrapModel`
owns launch resolution and `WorkspaceSetupView` for first/new/missing setup,
never the workspace split, toolbar, or `WindowModel`. After first registration,
the model keeps workspace routing closed while optional Agent preparation
copies immutable instructions. Prompt-copy and confirmation remain
presentation-local and create no durable readiness, machine-status, or
research-access owner. No Application service embeds, locates, fingerprints,
executes, installs, updates, or removes a CLI.

Packaging emits a sandboxed App archive and an independent CLI archive with
`scholium`, its Core resource bundle, and a user-local installer. Both carry
matching provenance. The CLI has no App Sandbox or App Group entitlement. The
CLI update module owns verified, recoverable self-update and has no App
authority. It promotes a complete transaction before replacement; the packaged
installer is first-install-only. The App retains sandboxing, user-selected read-write access,
app-scoped bookmarks,
Zotero client access, and loopback server access. One home-relative exception
exposes only `Library/Application Support/Scholium`; the App has no `.local`
access or embedded CLI. The copied Agent instruction limits installation to
`~/.local/bin/scholium` and its adjacent resource bundle and never authorizes
`sudo`, `PATH`, shell-profile, Agent-configuration, or quarantine mutation.
Agent preparation starts Application registration before
presenting Agent; its local gate prevents Ready until registration succeeds,
while Application owns the transaction and failure. Bootstrap and Workspace
use nonoptional Codable route bindings with a `defaultValue`; the route's
`windowID` is their only session identity. Workspace restoration is automatic,
while Bootstrap restoration is disabled. It recovers only Triptych and
peripheral presentation; ordinary cold launch opens no Document unless an
explicit route names one. Success waits for native window readiness before
dismissing Bootstrap; failure preserves setup. Restore Access rebinds expired authorization or asks
`WorkspaceRegistry` to remove one inactive machine-local registration without
reading vaults before ordinary Bootstrap.

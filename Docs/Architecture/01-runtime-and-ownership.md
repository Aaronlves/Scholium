# Architecture: Runtime and Ownership

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Modules,
workspace publication, window lifetimes, and native delivery.

## Architectural stance

Scholium is a local modular monolith, not a service or XPC architecture.
Compiler-enforced dependencies separate delivery from backend authority:

```text
ScholiumApp ──────────┐
                     ├→ ScholiumApplication → ScholiumCore → ScholiumContracts
ScholiumAgentHelper ─┘
```

Contracts owns immutable boundary values, capability protocols, closed schemas,
errors, deterministic source parsing and transformations. It has no I/O, UI,
store, watcher or mutable global authority. Core owns repositories, registries,
indexes, watchers, coordinated mutations, portable stores and transport
implementations. Application composes those owners into delivery-neutral
workspace lifetimes and use cases. Core is not a public library product; App
and helper reach it only through Application capabilities.

## Global ownership invariant

Every mutable fact and authorization policy has one owner of its identity,
lifetime, writer, persistence, cancellation and recovery. A coordinator sequences
owners through typed intents; it does not copy domain semantics. Disposable
projections may be rebuilt, but never authorize writes or become writable source.
The table below records cross-boundary ownership, not a class inventory.

## Ownership

| Boundary | Authoritative owner |
| --- | --- |
| Runtime construction and machine-state admission | App bootstrap; Application runtime and registry |
| Triptych source-operation ordering and complete publication | One Application workspace handle |
| Pooled vault source observation | Core repositories, watchers and source catalogs |
| Source transactions and recovery | [Source Storage](05-source-storage-and-read-models.md) |
| Window assignment and immutable event consumption | Window workspace/session and projection owners |
| Document buffer, save and conflict | [Documents and Editor](06-documents-and-editor.md) |
| Library selection/filter/order | Window Discovery owner, independently of Document |
| Native window geometry and committed close | Exact-window AppKit coordinator |
| Chat execution and configuration | [Agent Collaboration](02-agent-collaboration.md#native-chat-client) |

### Runtime bootstrap, refresh, and Search

Bootstrap validates the actual machine-local state root before constructing
the store. Construction is explicit and failable: malformed registration enters
Registry Recovery; unsafe, unreadable or newer state does not produce an empty
registry or temporary fallback. Relinking validates the existing owner without
scanning or mutating research Markdown. QA roots use the same validation.

Live runtimes reuse pooled vault repositories, catalogs and watchers while
windows need them. Snapshot runtimes load once without watchers and shut down
after the isolated operation. Root replacement latches a pooled vault unavailable
until explicit access restoration replaces its authorization.

An opening workspace may publish only the selected vault's authoritative catalog
and portable identities. Document load and exact current-buffer Search are usable;
lexical Search may use its last complete compatible index after filtering by
current fingerprints and stable identities. It reports Limited. Triptych-wide
structured, property and direct-link queries fail closed while their complete
projections are absent. No partial index becomes a complete generation.

One owned completion task converges to a complete snapshot after observation
reconciliation. Initial document visible-layout readiness delays competing full
reconcile, with a bounded fallback for Library-only or failed-renderer cases.
Shutdown cancels and awaits completion; it never creates a second source runtime.

Each workspace handle owns one Note Search index; pooled vault catalogs retain
exact documents, descriptor-observed file facts, source versions and disposable
semantic/search projections, not another index. Watchers start before reconcile.
Precise events update catalog entries; event loss triggers complete reconcile.
Compatible cached projections require fresh source reads and fingerprint proof.
Independent vault preparation may overlap, but Graph construction, index
synchronization and snapshot publication remain ordered in one refresh cycle.

One refresh coordinator serializes prepare → Search synchronize → snapshot
publish. Requests arriving after a cycle captures its cohort belong to the next
cycle; cancellation of one waiter cannot cancel another's work. Merged cycles
retain all requested source paths. One cancellation-aware source-operation gate
excludes refresh while filesystem, identity and path-bound transaction state
disagree. Cancellation before acquisition removes the waiter; after acquisition
it cannot revoke a transaction that must finish or recover. Index deltas persist
monotonic workspace generations transactionally and reject stale publication,
including after reopen or from another connection. Failure retains the last
complete snapshot/index.

Authoritative source completion is distinct from derived publication. Autosave
commit and direct creation return proven source/identity before background
refresh; workflows needing a coherent generation explicitly await it. Every
proven mutation returns its committed value plus nonretryable derived/identity
warnings rather than a generic error that invites repeating the write. Creation
rollback failure distinguishes proven retained source from uncertain presence;
neither permits blind recreation. One owned source-commit task is queued before
the mutation lease releases and coalesces matching watcher work.

Contracts owns the shared Search grammar, provider capability table, source
coordinates and typed results; Core owns disposable index validation, exact
predicate evaluation, lexical ranking and read transactions; Application
authorizes visible scope. Adapters own no parallel parser or ranking. Candidate
evaluation and page hydration share one read transaction. Eligibility precedes
counting, global ranking precedes pagination, and successful branches alone
supply witnesses. Paragraph predicates retain their existential boundary.
Direct-link queries require agreeing Graph/Search manifests and fail closed
rather than broadening to lexical clauses. Each link predicate resolves within
its own scope; uncertain candidates remain distinct from confirmed totals.
Application prepares request-local two-step Related-Content paths over that
cohort, replacing only the seed's outgoing projection with unsaved source.
Core admits matching paragraphs and applies bounded graph proximity to their
Note ranking; delivery explains paths without interpreting them as evidence.

Saved Searches persist raw query, visible scope and contract version only, not
ASTs, resolved anchors, result bytes or generations. Execution, cancellation and
serialized persistence belong to the window Search owner; Discovery owns visible
completion/results and is observed independently. Store failure blocks overwrite
until explicit exact-state-preserving recovery.

### Application capabilities and delivery

The machine-local workspace registry owns Triptych membership, role-vault
identities, paths/bookmarks, defaults and portable-container access. Registration
preflights roots and portable manifests; rejected selection leaves registration
unchanged, and renewed access replaces only the exact binding.

The App store owns live runtime subscriptions, macOS adapters and the shared
editor-flush registry, not Core authority. Subscription begins before activation
publication; windows accept one atomic capability generation and increasing
immutable event generations. Commands call capabilities directly, not an event
bus. One exact-window flush coordinator owns current/aggregate registration,
rebinding and teardown; the window composition root holds no second registry.
Application contains CSS/App Support I/O, Obsidian reads and Zotero transport.

The process-global authenticated App bridge serves only currently open workspace
capabilities. It owns neither workspace nor Agent lifecycle. Request and token
admission belong to [Agent Collaboration](02-agent-collaboration.md#delivery-path).

### Window state and feature controllers

The window model composes bounded owners and typed cross-feature effects. Shell
owns assignment presentation, pane visibility, disclosure, modes, appearance and
persistent operation issues; workspace owns registration, access and capability
generation; projection owns immutable catalog/snapshot consumption; Document
owns document workflow; Research owns Settlement and borrowed recovery/receipt
presentation. Controllers do not mutate or republish one another's state.
Views observe the owners they read directly. Stable scene-owned roots are
retained before child observation; command invalidation carries no product state.

Projection stages complete state and publishes once for the active runtime and
increasing event generation. A supplied stable Note ID is exclusive identity
authority; path lookup is allowed only without an ID. Path reuse cannot replace
a moved Note in tabs, Library reveal or Search evidence. Dirty externally deleted
Notes remain visible only while their exact editor owns conflict recovery.

One transition queue serializes guarded document and Library navigation. It
flushes source before replacement and rechecks destination/supersession after
suspension. A staged Library role change commits browse/shell state only, retaining
Document and tabs. Failure preserves origin and recovery. Native committed close
owns once-only teardown: content flush precedes final presentation save;
SwiftUI disappearance detaches presentation only. Cancelled close retains flush
registration so the attempt remains retryable; persistence refuses writes after
native close.

### Library projection and source-ahead mutations

Library owns immutable tree selection/filter/order separately from active Document.
Native outline input emits identity-bound commands; rows and sheets never write
source. Mutation targets keep vault/document identity, stable Note ID and exact
revision together. Application re-resolves identity inside the source lease,
preventing stale gestures or sheets from acting on reused paths.

After a proven create or move, the exact window may install source-ahead Note
and Folder projections for immediate activation/reveal. Placeholder graph values
authorize nothing; complete generation replaces them. Creation reserves only its
own identity; control-store compare-and-swap and scoped rollback cannot displace a
foreign identity, even at identical source bytes. Link rewrites advance exact
affected identities before another batch item. Batches retain per-item outcomes,
stop remaining work on failure and exclude completed effects from fresh retries.
Import tasks bind their initiating workspace/window; reassignment or committed
close stops remaining files without reclassifying prior commits.

Folder moves freeze descendant inventory, commit one descriptor-relative
no-replace rename, rewrite proved incoming links and rebind identities. Other
directory contents move with the inode without parsing. A coherent exact-source
cohort/Graph may limit reparsing to candidate incoming Notes; incomplete or
source-ahead state requires complete derivation. Core always re-enumerates and
checks descendants before commit. Folder-only changes preserve unchanged
Graph/Search generations. Trash uses the separate complete-manifest transaction
in [Source Storage](05-source-storage-and-read-models.md#system-trash-and-coordinated-source-boundary).

The tree cache advances only for ordered Note/Folder inventory changes and is
shared by outline/header consumers. Presentation changes cannot trigger a second
tree owner. AppKit owns hierarchy, selection, disclosure, drag feedback and row
geometry; immutable comparison policy comes from Core's authorized volume.
Process-local drag preflight never becomes filesystem authority; execution repeats
containment, destination, identity and revision checks. Empty directories remain
visible; attachment storage exclusion is shared with MCP without changing files.

### Document tabs and native shell

Each window has one ordered tab collection and guarded selection across vaults.
Native content tabs render committed state; Document owns retained sessions.
Transfer moves the same session, autosave and observation owner after source
capture and old-WebView detachment. Failed transfer restores membership. Separate
document windows retain the same close/quit source guards without inheriting
sidebars or native whole-window tab grouping. Final persistence stores only open
tab identities and fingerprint-bound lightweight position/focus, never source,
Undo or closed-tab state.

One native split and toolbar persist per workspace window. AppKit owns attachment,
safe areas, resize, dividers, collapse, fullscreen and restoration. Pane changes
replace hosted content, not editor or shell identity. Hidden hosts lose input,
accessibility and responder participation. Window state mirrors native visibility
for commands but does not continuously reassert geometry. Focus Layout captures
and restores peripheral/toolbar state once; native fullscreen locks that
transaction and restores preceding windowed focus on exit or failed entry.

Toolbar, overflow and menu availability share one exact-window derivation and
dispatch guard. Target changes close revision-bound popovers. Invalidation detaches
targets/subscriptions and cannot reinstall. No secondary geometry owner tracks
width, corrections or titlebar overlays. Semantic document style is transported
to WebKit; native control appearance remains platform-owned.

### Presentation

One exact-window router owns mutually exclusive sheet, alert, loading overlay and
file-import channels. Payload replacement is atomic and identity-checked dismissal
cannot close a newer route. Routes carry navigation projections, not document
sessions or write permission. Each scene's native file presenter serializes panels
against that exact window; it never searches windows or grants sibling-directory
access. Feature owners retain drafts, validation, bookmarks and mutations.

Quick and auxiliary Search share one query/result owner; native fields retain
composition/focus. Auxiliary windows, native previews and transient surfaces
belong to their originating window and close/detach with it. Preview geometry and
read-only content grant no source authority.

Attention is an immutable workspace projection with presentation-only dismissal.
The notification popover is window-local. One App-level system notification owner
handles authorization, coalescing and exact opaque routes. Confirmed mutation and
live Chat execution owners submit events; refresh, restored history and expired
turns cannot manufacture them. Validity is checked before prompting and delivery;
receiving windows revalidate exact receipt/conversation. Cold handoff is memory-only
and consumed once. Persistent operation issues remain with their owning window or
Settings field, never notification delivery.

### Inspector ownership

Research retains Links query/direction/group/position and one disposable Related
Material session per window. They consume source-bound immutable projections,
not another graph, writable metadata store or runtime. Recommendation requests
bind context, document/runtime identity and revocable insertion receipts. Document
departure resets them even while hidden; hiding cancels work. Publication rechecks
identity and automatic follow also checks editor focus/mode. Stale responses may
refresh/retry once; insertion rechecks current generation/caret in the Editor.
Retained cards preserve context until successful replacement. Source opening or
Chat staging revalidates revisions and cannot overwrite dirty destination source.
Exact passages and readable projections remain distinct.

### Settings authority

Settings composes existing workspace, document, notification, shortcut, writing,
Zotero and Chat owners; it creates no workspace runtime. Immutable snapshots
carry exact settings revisions and writes return replacements. Captured scope or
revision mismatch requires explicit reload, not last-writer-wins. Native retained
page hosts preserve drafts while inactive hosts lose input/accessibility/default
actions. Background font discovery publishes names only, coalesces invalidation
and rejects stale completion. Search uses static interface metadata, never research
content or permission. The AppKit fixed sidebar container owns native material,
titlebar/toolbar section association and divider geometry; SwiftUI owns selection
and discovery.

Shortcuts have one command catalog/validated preference writer; menus consume it.
The application hotkey event adapter owns hardware-event normalization, while the
command-key-equivalent router owns native-menu transport for registered document
shortcuts. It is reached only through the active visible document boundary,
outside composition; the shared WebKit container supplies that boundary and guard
but does not match shortcuts or own actions. CodeMirror retains local
editing/history. Selection Actions have one machine-local preference owner; views
retain unsaved drafts only.
Chat settings borrow the selected Triptych's connection/configuration owner.
External-host setup copies verified helper commands and reveals bundled resources;
it neither executes setup nor claims host configuration success.

### Interface localization

The App owns interface translation catalogs and localizes at delivery boundaries.
Stable operational keys are distinct from ordinary compiler-derived format keys;
neither changes command IDs, persistence keys, accessibility IDs or paths.
Authored prose, Note/Folder/Skill names, quotations and exact source render verbatim.
Catalog synchronization consumes compiler string data and validates key/format
parity. Packaging mirrors compiled localization resources into the outer App for
native literal controls while retaining the module bundle for explicit lookups.

### Shared presentation and boundary enforcement

Shared semantic colors, typography, symbols and adaptation values have one owner;
native-to-document tokens transport resolved values rather than create a second
palette/configuration. Numeric coincidence does not justify shared ownership.
Reusable leaves receive immutable values/actions and own no workflow, permission,
navigation or operation lifetime. Native adapters own only attachment, delegates,
geometry and teardown. Package/import/I/O checks enforce delivery isolation;
Contracts purity is checked against executable Swift syntax rather than text
matches. Debug proofs consume production components without production mutation.

### Container decision rule

Container changes identify stable state and native lifetime/selection/layout
owners, verify the public SDK contract in an isolated prototype, then integrate
without a parallel domain or geometry owner. Content tabs are not whole-window
tab groups; native document infrastructure is not a second persistence writer.

### Bootstrap scene

Bootstrap is a separate routed scene without workspace split or document owner.
It retains create/connect drafts and delegates exclusive structure preparation
and registration to Application. Successful registration waits for native
workspace readiness before dismissal; failures preserve the populated form.
Route identity belongs to the Codable window route. Cold launch restores only
workspace/peripheral presentation unless an explicit document route names a Note.
Access restoration renews exact registry authorization without early vault reads.

App and bundled helper share provenance/update lifetime. Helper entry points are
delivery only, with no independent runtime, installer or research-file access.
Artifact requirements and dated outcomes belong to Specification and Status.

## Source entry points

- `Package.swift`: compiler dependency boundary.
- `ScholiumApplication/WorkspaceRuntime.swift`, `WorkspaceHandle.swift`, and
  `WorkspaceRefreshCoordinator.swift`: workspace lifetimes and publication.
- `Scholium/App/ApplicationBootstrapController.swift` and `Scholium/App/Window`:
  App composition and native delivery.
- `Scholium/Features/Settings/WorkspaceSettingsModel.swift` and
  `Scholium/Views/WorkspaceSettingsView.swift`: Settings composition.
- `Tools/Scripts/verify.sh`: executable architectural boundary checks.

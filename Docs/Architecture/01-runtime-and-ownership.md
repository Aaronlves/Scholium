# Architecture: Runtime and Ownership

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Modules,
workspace publication, window lifetimes, and native delivery.

## Architectural stance

Scholium is a local modular monolith.

```text
ScholiumApp ──────────┐
                     ├→ ScholiumApplication → ScholiumCore → ScholiumContracts
ScholiumAgentHelper ─┘
```

Contracts owns immutable boundary values, capabilities, schemas, errors and
deterministic source parsing/transformations, without I/O, UI, stores, watchers
or mutable global authority. Core owns repositories, registries,
indexes, watchers, coordinated mutations, portable stores and transport
implementations. Application composes delivery-neutral workspace lifetimes and
use cases; App and helper access Core only through Application capabilities.

## Global ownership invariant

Each mutable fact and authorization policy has one owner for identity, lifetime,
writing, persistence, cancellation and recovery. Coordinators sequence typed intents
without copying domain semantics. Disposable projections never authorize writes
or become writable source.

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

Bootstrap validates machine-local storage before construction. Malformed registration
enters Registry Recovery; unsafe, unreadable or newer state never yields an empty
registry or temporary fallback. Relinking validates ownership without scanning or
mutating Markdown. QA uses the same validation.

Live runtimes pool vault repositories, catalogs and watchers for borrowing windows.
Snapshot runtimes load once without watchers and shut down after use. Replaced
roots remain unavailable until explicit access restoration renews authorization.

Live opening publishes the requested vault's catalog and portable identities
as `.opening`; `WorkspaceSearchIndexOwner` remains lazy. Document load and exact
unsaved-buffer This Note Search bypass indexes. Lexical This Vault Search
filters admitted compatible results by current fingerprints and stable identities,
reporting Limited; unprepared vaults and Triptych queries fail closed.

One completion task awaits Document visible-layout readiness or a two-second
fallback, then admits Search and reconciles before coherent `.complete`.
Admission failure retains `.opening` and typed diagnostics until explicit retry.
Shutdown cancels admission before draining producers and late indexes.

Application derives Search manifests from source-free catalog metadata, links,
descriptor facts and versions. Watchers precede reconciliation; precise events
update entries, event loss forces full reconciliation. Search compares manifests,
prepares changed Notes in a bounded ordered window and releases inserted source.
One writer validates source versions before publication; readers retain committed
generations. Cached projections require fresh reads and fingerprints. Vault
preparation overlaps; Graph, Search and publication remain ordered.

One coordinator serializes generations. Background catalog preparation
produces immutable candidates outside the source-operation gate; validated
owner-token CAS installs them. Reads never reconcile implicitly. The gate
protects readiness, source/identity capture, explicit moves and final publication.
Cohort validation precedes identity capture, then Graph/Search outside the gate.
Source transactions advance a Handle-owned token; final admission
rechecks it before SourceVersion validation and SQL commit, retaining authority
through App publication. Superseded work recaptures after rollback. Cohorts retain
publication kind and paths; waiter cancellation cannot cancel another caller.
Admitted source transactions finish or recover. Monotonic generations reject stale
reopened publication; failure preserves snapshots and last good indexes.

Runtime owns automatic maintenance after live `.complete`; membership listing does
not force maintenance. Storage actions serialize forced work, preserving errors.
Core inventories metadata; process-shared leases exclude live owners. Library
activation or rebuild resumes Search; metadata borrowing preserves pause.
Shutdown drains Settings and handles, then closes vault pool before cleanup,
preserving locks and Triptych/Vault roots.

Authoritative source completion is distinct from derived publication. Autosave
commit and direct creation return proven source/identity before background
refresh; workflows needing a coherent generation explicitly await it. Every
proven mutation returns its committed value plus nonretryable derived/identity
warnings rather than a generic error that invites repeating the write. Creation
rollback failure distinguishes proven retained source from uncertain presence;
neither permits blind recreation. One owned source-commit task is queued before
the mutation lease releases and coalesces matching watcher work.

Contracts owns Search grammar, lexical comparison and boundaries, provider capabilities,
source coordinates and results; Core owns disposable index validation, exact
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
Application contains CSS/App Support I/O, Obsidian reads and the native Zotero
local-API integration.

The process-global authenticated App bridge serves only currently open workspace
capabilities. It owns neither workspace nor Agent lifecycle. Request and token
admission belong to [Agent Collaboration](02-agent-collaboration.md#delivery-path).

### Window state and feature controllers

The window model composes bounded owners and typed cross-feature effects. Shell
owns assignment presentation, pane visibility, disclosure, modes, appearance and
persistent operation issues; workspace owns registration, access and capability
generation; projection owns immutable catalog/snapshot consumption; Document
owns document workflow; Research owns borrowed recovery/receipt
presentation. Controllers do not mutate or republish one another's state.
Views observe the owners they read directly. Stable scene-owned roots are
retained before child observation; command invalidation carries no product state.

Projection stages complete state and publishes once for the active runtime and
increasing event generation. A supplied stable Note ID is exclusive identity
authority; path lookup is allowed only without an ID. Path reuse cannot replace
a moved Note in tabs, Library reveal or Search evidence. Dirty externally deleted
Notes remain visible only while their exact editor owns conflict recovery.

One transition queue and adapter serialize document/Library navigation.
All navigation, including current-tab reselection/cross-window forwarding,
revokes older destination authority before routing. Started source work drains;
forwarded destination/history/position commits recheck both owners after suspension.
Staged Library role changes retain Document/tabs; failure preserves origin/recovery.
Native committed close owns teardown. Selected input freezes through final flush,
presentation persistence and close; cancellation resumes only its matching suspension.
SwiftUI disappearance detaches presentation; closed windows reject persistence.

### Library projection and source-ahead mutations

Library owns immutable tree selection/filter/order separately from active Document.
Native outline input emits identity-bound commands; rows and sheets never write
source. Mutation targets keep vault/document identity, stable Note ID and exact
revision together. Application re-resolves identity inside the source lease,
preventing stale gestures or sheets from acting on reused paths.

After a proven create or move, the window installs source-ahead Note/Folder
projections. Application advances source-inventory revisions after successful
rebuild; metadata preserves them. Creation returns its base revision. Window
projection retains committed source until newer inventory confirms existence or
deletion; placeholder graph values authorize nothing. Identity compare-and-swap
and scoped rollback preserve foreign identities, including identical bytes.
Link rewrites advance affected identities between batch items. Batches retain
per-item outcomes, stop on failure and exclude completed effects from retries.
Import binds its initiating workspace/window; reassignment or committed close
stops remaining files without reclassifying prior commits.

Folder moves freeze descendant inventory, commit one descriptor-relative
no-replace rename, rewrite proved links and rebind identities. Other
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

Each resolved scene owns one window, ordered tabs and guarded cross-vault selection.
Document owns sessions and Find; the native toolbar projects committed tabs.
WindowModel validates selected target, session and registration for editor commands;
stale teardown cannot revoke a replacement. Transfer moves session, autosave and
observation after capture and WebView detachment. Close rechecks identity; transfer
failure restores membership, and teardown preserves transferred Find. The lifecycle registry
holds termination admission through flushes and native reply; close/quit excludes
transfers. Separate windows share source guards without sidebars or native grouping.
Persistence retains open identities and fingerprint-bound position/focus, never
source, Undo or closed tabs.

The App coordinator queues Finder, File and Chat requests and resolves registered
Note ownership before external opening. App scene routing connects without windows;
scenes reject implicit URL creation. Native launch and restoration own window admission.
ExternalMarkdownWindowRegistry owns file-window deduplication
and close/quit admission. Each external model owns its editor, observation,
conflict and import presentation; ExternalMarkdownFileSession owns guarded file
I/O. Import captures checked source, then uses workspace creation and Note opening.

One native split and toolbar persist per workspace window. AppKit owns attachment,
safe areas, resize, dividers, collapse, fullscreen and restoration. Pane changes
replace hosted content, not editor or shell identity. Hidden hosts lose input,
accessibility and responder participation. Window state mirrors native visibility
for commands but does not continuously reassert geometry. Focus Layout captures
and restores peripheral/toolbar state once; native fullscreen locks that
transaction and restores preceding windowed focus on exit or failed entry.
Collapsing a focused peripheral hands input to the current document's focus owner
when available; an empty document region retains window/menu focus.

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

Attention is an immutable workspace diagnostic consumed by Library Integrity
filters. Windows own notification popovers. The App notification owner
handles authorization, delivery coalescing, opaque routes and per-window click
tasks. Only confirmed mutations and current Chat events submit notifications;
refresh, restored history and expired turns cannot manufacture them. Validity is
checked before prompting and delivery; ready matching windows revalidate exact
receipt/conversation. Replacement or closure cancels prior click tasks. Cold
handoff is memory-only and consumed once. Window and Settings issues remain
independent of notification delivery.

### Inspector ownership

Research owns disposable Links location, Related discovery and kept snapshots,
not another graph/store/runtime. Changed locations alone publish. Related requests
bind context, document/runtime identity and revocable insertion receipts;
departure resets discovery, hiding cancels work. Publication rechecks identity;
automatic follow checks focus/mode. Stale responses may refresh once; insertion
rechecks generation/caret. Kept snapshots survive document/results changes,
clearing on unbind/reset/Triptych replacement. Links capture verifies source and
occurrence; exact/readable text stay distinct. Kept opening is seed-independent.
Opening/Chat staging revalidate revisions without overwriting dirty destinations;
delayed keep/open checks runtime/owner identity. Kept text never persists.

### Settings authority

Settings borrows capabilities; `WorkspaceRuntime` drains metadata reads
before releasing scopes. Matching Handles remain authoritative. Unopened reads borrow
registered portable access without vault/watcher/index activation;
Core admits manifests before identities/catalog/settings through anchored
no-follow reads. Recovery retains the Handle's revision-bound writer.
`WorkspaceSettingsModel` owns selection/generations, captured-assignment reads and
confirmed identity/revision; mismatches cancel, stale recovery reloads.
Selected Writing/Agents/Zotero pages borrow the existing registry's Triptych
controller; native hosts retain drafts. Active consumers own automatic reads;
admitted shared work retains its owner.
Inactive panes exclude input, accessibility/default actions. `StorageSettingsModel`
retains measurements/feedback and retires unconfirmed plans on pane/target changes.
Font discovery publishes names, coalesces invalidations and rejects stale results.
Search/links/anchors index static interface metadata, never research content or
permission. AppKit owns toolbar/safe area/temporary result selection; SwiftUI owns
category/query/destination.

One command catalog/validated preference writer feeds menus. The hotkey adapter
normalizes hardware events; the command-equivalent router matches document
shortcuts only at the active visible document boundary, outside composition.
WebKit supplies that boundary/guard without matching commands. CodeMirror owns
editing/history. Selection Actions has one machine-local preference writer;
views retain unsaved drafts. `ChatSidebarPreferences` owns This-Mac visibility
independently of execution; connections borrow Triptych owners. External-host
setup copies verified commands/reveals bundled resources, never executing setup
or claiming success.

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

Bootstrap is a routed scene without workspace split or document ownership.
It retains create/connect drafts and delegates structure preparation and
registration to Application. Handoff requires native attachment; document
transfers require ready content. Missing registration or explicit creation opens setup; access
and opening errors retain recovery. Route identity is Codable. Cold launch
restores presentation unless an explicit route names a Note. Access restoration
renews exact registry authorization before vault reads.

App delegate retains `ApplicationUpdateController`, wrapping Sparkle.
Termination owns save/citation admission. Packaging embeds/signs its framework
and installer services. App/helper/resources update together; Scholium's connection
helper has no independent runtime or research-file access.

## Source entry points

- `Package.swift`: compiler dependency boundary.
- `ScholiumApplication/WorkspaceRuntime.swift`, `WorkspaceHandle.swift`, and
  `WorkspaceRefreshCoordinator.swift`: workspace lifetimes and publication.
- `Scholium/App/ApplicationBootstrapController.swift` and `Scholium/App/Window`:
  App composition and native delivery.
- `Scholium/Features/Settings/WorkspaceSettingsModel.swift` and
  `Scholium/Views/ScholiumSettingsView.swift`: Settings composition.
- `Tools/Scripts/verify.sh`: executable architectural boundary checks.

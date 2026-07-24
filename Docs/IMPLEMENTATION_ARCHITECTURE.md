# Implementation Architecture

**Scope:** module, runtime, state-ownership, and delivery boundaries  
**Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)

This subordinate implementation reference explains how the current code is
divided and how mutable state flows through it. It does not redefine Scholium
workflows, interface labels, visual decisions, vault formats, or
research-governance rules. [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)
owns dated conformance and verification evidence; the package graph, live code,
tests, and scripts remain the final implementation evidence.

## Architectural stance

Scholium is one local modular monolith with compiler-enforced frontend/backend
isolation. `ScholiumApp` and `ScholiumCLI` are delivery adapters over
`ScholiumApplication` plus internal `ScholiumCore`; both reach backend authority
only through Application capabilities and immutable `ScholiumContracts`
values. This in-process module and ownership boundary is not XPC or a service.

## Ownership

`ScholiumContracts` owns immutable boundary values, capability protocols,
structured errors, and deterministic exact-source parsing and projection.
`ScholiumCore` is an internal implementation target for repositories,
registries, SQLite indexes, watchers, coordinated mutations, durable stores,
Skill resources, and Zotero transport. The headless `ScholiumApplication`
target composes Core into delivery-neutral workspace lifetimes and use cases.
The macOS app and CLI depend only on Contracts and Application; Core is not a
library product and cannot be imported by either delivery target.

```text
ScholiumContracts
       ↑
ScholiumCore ← ScholiumApplication
                       ↑
              ScholiumApp / ScholiumCLI

ApplicationBootstrapController (one app-owned storage gate)
└── Ready (explicit validated Application Support URL)
    └── WorkspaceStore (macOS adapter and sole event-stream subscriber)
        ├── WorkspaceRuntime (one live runtime for the app delivery)
        └── SwiftUI WindowGroup (one Codable route per scene)
            ├── WindowModel (one per complete workspace window)
            │   ├── WindowWorkspaceController
            │   ├── WindowSessionPersistenceCoordinator
            │   ├── DocumentTransitionCoordinator
            │   ├── DiscoveryController
            │   ├── DocumentTabController
            │   ├── DocumentController
            │   │   └── DocumentSessionStore
            │   ├── ResearchController
            │   │   └── ResearchFunctionController
            │   ├── WindowPresentationRouter
            │   └── typed WindowIntent routing
            └── WorkspaceWindowCoordinator (one exact NSWindow/split boundary)

ScholiumApplicationDelegate
└── ScholiumWindowLifecycleRegistry (injected route readiness and flushers)
```

`ApplicationBootstrapController` is the only production composition route to
`WorkspaceStore`. Its Starting, Ready, and Storage Unavailable states validate
the real per-user Application Support directory before constructing any
runtime. `WorkspaceStore.init(applicationSupportURL:)` is explicit and
failable; there is no temporary-directory fallback. An explicitly supplied QA
root uses the same validation. `WorkspaceRuntime` then has two configurations:
live reuses stable Triptych/vault runtimes, watchers, and derived refresh while
any app window needs them; snapshot performs one-shot loading without watchers
and shuts down after each CLI invocation.

Each `WorkspaceHandle` owns one `TriptychSearchIndex` at
`Triptychs/<triptych-id>/indexes/search-v4.sqlite`; pooled vault runtimes own
repositories, watchers, and one shared `VaultSourceCatalog`, but no Search
index. The catalog retains exact `NoteDocument`, descriptor-observed file
metadata, `SourceVersion`, cached `MarkdownSemanticDocument`, and the
source-bound part of
`SearchDocumentProjection` as disposable state. Review and broken-link fields
are reapplied with a lightweight projection-hash update, so ordinary Search
deltas do not rebuild visible text and exact offset maps for unchanged notes.
Projection construction advances monotonic UTF-16 cursors, preserving exact
source mapping without repeatedly rescanning an accumulated String.
Watchers start before the initial
reconcile; precise add/edit/delete/rename events update affected entries, while
event loss, root replacement, or explicit rebuild requests force a full
stat/reconcile. `WorkspaceSnapshotBuilder` consumes three immutable catalog
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
path, not just the last payload. An exclusive source-mutation gate buffers
watcher invalidations until the filesystem transaction, portable identity, and
other path-bound stores agree, preventing a builder from observing the
file/identity gap. Search publication applies one transactional
`SearchIndexDelta` carrying a transactionally persisted workspace generation
and refuses stale generations, including across index reopen or another
process connection. A failed cycle preserves the last complete snapshot and index.
Direct Related items are publishable only when the Graph and Search manifest
hashes agree. Privacy-safe measurements record enumerate/read/parse/source-
projection counts and durations, identity and research-state projection,
graph construction, dynamic Search projection and synchronization, snapshot
assembly, source-byte size, publication, and total duration without source
content or identifiers. Per-vault source durations are work sums and may
overlap; total duration remains wall clock. Snapshot assembly reuses the exact
same generation's reconciled portable-identity state for Critique association;
only `.resolved` identities participate, so ambiguous, pending, unresolved, or
failed recovery remains closed without one storage lookup per Work.

`ScholiumContracts` owns contract-v4 parsing, the visible semantic
`SearchDocumentProjection`, exact source mappings, CJK query projection,
requests, responses, diagnostics, availability, and generation IDs. Core owns
the disposable SQLite schema, staging/validation/recovery, read transactions,
cancellation, deterministic ranking, and in-memory **This Note** matcher.
Application resolves presentation scope to execution scope and is the only
search capability exposed to GUI and CLI. Saved Searches persist only query
and presentation scope. Selection, request cancellation, and Related loading
are window-controller state rather than persisted search definition.

Application composes a private `WorkspaceHandle`; the macOS adapter exposes
only `DocumentUseCases`, `DiscoveryUseCases`, and `ResearchUseCases` plus
immutable identity/assignment values. `WorkspaceStore` coalesces duplicate runtime
installation, retains one event subscription before publishing activation,
starts it with a complete `WorkspaceSnapshot`, and accepts only increasing
generations. Commands remain direct capability calls, not event-bus messages.

`WorkspaceStore` owns the live runtime, accepted subscription, immutable GUI
snapshots, cross-window editor-flush registry, and macOS adapters. Each window
receives one atomic capability generation. CSS/App Support, Obsidian reads, and
Zotero HTTP stay behind Application actors; the store owns no Core authority.

The Beta agent-application handoff is one app-wide macOS presentation adapter
owned by `WorkspaceStore`. `AgentApplicationHandoffController` coordinates the
copy-first UI state, explicit `NSOpenPanel` selection, launch result, and
recovery actions. `MacAgentApplicationSystem` alone resolves the app-scoped
security bookmark and invokes `NSWorkspace`; the remembered reference is a
small mode-0600 Application Support preference, never Triptych or vault state.
No Application or Core use case receives the selected application or launch
result, and no Function record treats launch as execution state.

`WindowModel` is the per-window composition and focused-command root.
`WindowWorkspaceController` resolves the requested Triptych and stable vault
identities, `WindowSessionPersistenceCoordinator` owns replaceable and final
presentation saves, and `DocumentTransitionCoordinator` owns transition
generation plus flush/capture ordering. `WindowModel` applies their typed
results, routes Search/temporary Find, presentation, and cross-feature intents,
but no longer owns those three state machines. `DocumentController` alone owns selection and
document workflow state; `ResearchController` owns research generations,
initial Dialogue projection, checkpoint-list failures, and durable-recovery
listing. `WindowModel` exposes computed projections, not duplicated storage.
Direct New Note requests remain focused-window commands: the Library and File
menu send a target folder value to `WindowModel`, which flushes the current
editor and calls the Application-owned untitled-note use case. Application
atomically advances through occupied default paths; the view never scans or
writes the vault and no presentation route participates. Folder disclosure and
subtree expansion remain `DiscoveryController` state. Core enumerates real
directories so empty classifications survive projection, but folder paths never
enter the portable identity store. Direct New Folder creation atomically claims
one default directory name. Empty-folder creation and empty-folder moves publish
only a new folder inventory snapshot; they preserve the current Search and graph
generations because no Markdown source or note location changed. Rename, Move,
and Move to Trash flush Triptych-wide
editors, preflight the complete descendant-note inventory, and commit one
descriptor-relative no-replace directory rename. `TriptychFolderMoveCoordinator`
applies exact resolved-link rewrites against one future graph with rollback and
durable recovery; Application then rebinds every descendant stable note ID in
one control-store write and resumes existing idempotent path migrations. Other
directory contents move with the inode and are not parsed. Copy Relative Path
and Reveal in Finder remain delivery actions over an existing folder or note
vault-relative path and create no Core authority.
Document, Search, and presentation are window-local; Library hierarchy and
selection, Sidebar/Apparatus visibility, and Apparatus mode belong to the outer
window, never a tab. Controllers do not mutate one another. Separate
`WorkspaceSettingsModel` groups workspace, machine, Zotero, and Research
Guidance capabilities without constructing a document window.

Each window has one `DocumentTabController`. An `.unspecified`
`NSTabViewController` in the middle split item hosts document pages; a
Document-owned selector renders the tabs. `.toolbar` is forbidden because it
would replace `NSWindow.toolbar` and create a second toolbar owner. Tabs create
no window, model, split, Library, or Apparatus. The controller owns only order,
selection, and document references; `DocumentController` and
`DocumentSessionStore` retain sessions and apply the flush/reconstruction guard.
Apparatus derives from the active document but keeps window-owned visibility
and mode. Only New Window creates a shell.
`WindowSessionSnapshot.selectedDocument` alone restores selection; legacy
tab/history fields decode only and vanish on encode.

Each configured scene constructs one `ScholiumWorkspaceSplitView`: one
`NSSplitViewController` with three direct `NSSplitViewItem` siblings for
Library, Document, and Apparatus. The split and each item's one opaque semantic
background fill the frame beneath AppKit's transparent titlebar. The standard
SwiftUI toolbar background is hidden, with no background-extension effect or
duplicate color source. Native titlebar behavior remains, and each content
controller is a foreground sibling inside the system safe area.

The one `NSWindow.toolbar` is divided into Library, Document, and Apparatus
sections by native tracking separators. Before split attachment,
`WorkspaceWindowCoordinator` installs an inert toolbar and later replaces its
items in place. Each peripheral has one real `NSToolbarItem`: while its pane is
visible, the item is ordered outside the corresponding separator and presents
Hide in that pane's titlebar section; when collapsed, the same route moves
inside the separators and presents Show in the Document section. The toolbar
controller diffs item identifiers from native collapsed state, so no duplicate
route or second toolbar exists. No split-content titlebar host remains in the
current construction: under full-size content it rendered beneath the
toolbar's pointer hit-testing layer even when accessibility could still
discover it. This tracked-toolbar transfer is the current safe implementation,
but it does not satisfy D-091's pane-ownership requirement; the status ledger
records that migration debt without treating this workaround as target authority.

AppKit owns resizing, compression, dividers, collapse, fullscreen, frame
restoration, and drag limits; the Codable route owns scene identity. No width
binding, window search, opening correction, or persisted divider geometry
intervenes. Library alone receives the specified 300pt native content minimum,
without a preferred/maximum width or second geometry owner. Other split items
receive no Scholium thickness, fraction, priority, or restoration state. A
scene/window minimum remains contingent on the complete adaptation matrix.

Apparatus uses `NSSplitViewItem(inspectorWithViewController:)`; production does
not mutate its geometry, safe area, separator, or collapse policy. The native item and
`toggleInspector(_:)` own transitions. Because the nested split may sit outside
the responder chain, the collapsed Show route is a borderless hosted item, not
the platform-wrapped standard toolbar item, and bridges with the View command
through the exact per-window coordinator. Selected-document state supplies
availability. `WindowModel` mirrors native visibility for commands,
restoration, and toolbar reconciliation but never reasserts it or stores width.

The Inspector has exactly three current-note modes: Overview, Connect, and
Actions. Overview projects compact Attention and role-aware About fields;
Zotero has no Inspector projection. Connect projects direct and derived
relations. Actions projects recorded Research Activity and direct role-valid
full-row operations, with Discuss and Write under a static Work with Agent
heading. Current Comment exchanges and Function-backed Discussion appear in
the separate read-only Research Record window; removed archives have no
projection. The Inspector may navigate or open another
note in the Document tabs, but it never owns a document buffer, editing,
autosave, undo, or conflict state. Those remain exclusively in the Document
surface and its existing controllers.

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

Bootstrap is a separate data-routed `WindowGroup`; `ScholiumBootstrapModel`
owns launch resolution and `WorkspaceSetupView` for first/new/missing setup,
never the workspace split, toolbar, or `WindowModel`. Bootstrap and Workspace
use nonoptional Codable route bindings with a `defaultValue`; the route's
`windowID` is their only session identity. Workspace restoration is automatic,
while Bootstrap restoration is disabled. Success opens one workspace and waits
for that route's native coordinator readiness before dismissing Bootstrap;
failure or early unregister preserves setup. An existing
Triptych with lost folder authorization stays in the workspace and replaces
only that authorization through Restore Access.

## Research Function boundary

Research Functions follow the same in-process compiler boundary as every other
delivery-neutral capability:

```text
ResearchFunctionsInspectorView / ResearchFunctionPanelView
        ↓ immutable presentation values and closures
ResearchFunctionController (one window)
        ↓ ResearchFunctionClient
ResearchFunctionUseCases (Contracts)
        ↓
ResearchFunctionCoordinator (Application)
        ↓
Core skill, checkpoint, record, and repository authorities
```

`ScholiumContracts` owns `ResearchFunctionID`, Target/Material/scope, Fidelity
checks, availability/repair codes, runs, submissions, fingerprints, and
`ResearchFunctionUseCases`. Workspace `ResearchUseCases` composes record,
checkpoint, Skill, function, and bibliography capabilities. Contracts contain
no labels, symbols, package storage, YAML inspection, or layout.

D-106's staged public layer now begins in `ScholiumContracts` with validated
`ResearchActionID`, public execution kinds and Target roles, role-filtered
default definitions, and a fail-closed versioned `ResearchActionSnapshot`.
That snapshot contains no `ResearchFunctionID`. A separate versioned
`ResearchActionRecordIdentity` fixes the complete Action projection allowed in
future portable records to the Action ID alone; execution kind, Target role,
and protected Function identity are not record fields. An internal-only
`ResearchActionFunctionMapping` in `ScholiumApplication` maps Analysis and
Synthesis to Develop, Write to Revise, and the remaining public execution
kinds to their protected Function mechanisms after role validation. The same
internal adapter now derives the exact bundled Action from Function plus
Target role for the retained coordinator. Core Skill resolution accepts that
Action identity explicitly: Analysis Develop resolves `scholium-analyze`,
Topic Develop resolves `scholium-synthesize`, and a package bound to one fails
closed for the other. The existing Function use cases, UI, CLI, binding v1,
and machine-local records remain the current runtime. No Action snapshot
becomes execution authority, and no current record store writes the new
identity until the later resolver and portable-record cutovers; those cutovers
must use the record identity contract rather than serializing a Function ID.

The product Skill catalog schema 4 separates protected mechanism from ordinary
method prose. `ResearchSkillClass.method` packages each declare exactly one
public Action plus the retained internal Function. Discuss is an ordinary
Method and `scholium-discussion-protocol` is its automatic mechanism-only
adapter. Analyze, Synthesize, Write, Critique, Content Fidelity, and optional
hidden Manuscript are similarly distinct bundled Method references. System
Skills own authority and persistence boundaries; they cannot supply the
intellectual procedure. The old conditional Development, Revision, and
Manuscript resource selectors remain decodable only for legacy machine-local
records and are no longer offered by current Functions; each Method now loads
its complete adaptive core, with Write feedback guidance included by default.
Before a new Triptych manifest is committed, `ResearchSkillStore` installs six
independent editable packages under `.scholium/skills/` and atomically writes
`research-working-method-bindings-v2.json`; Manuscript is represented by an
explicit disabled state. The initializer is idempotent for an exact interrupted
bootstrap and never runs automatically for a Triptych with an existing
manifest. Application exposes the same absence-checked operation as the
explicit repair primitive for the later categorized Settings interface.

Action execution resolves only that Action-keyed v2 document. Its
`installed_default`, `researcher_skill`, and `disabled` states are explicit;
absence, malformed data, missing packages, invalid packages, and role/Action
incompatibility fail closed without a bundled fallback. The bundled package is
read only during initial installation or explicit restore. The retained
Function-keyed `research-skill-bindings.json` file and APIs remain readable for
legacy Settings and temporary citation/bibliography compatibility. Its primary,
supplemental, and Practice fields cannot select or compose an Action's Working
Method.

One delivery-neutral `ResearchFunctionCoordinator` per workspace owns
availability, preparation, completion, cancellation, and record projection. It
resolves/rechecks identities, inputs, Action-specific Methods, protected
resources, checkpoints, records, and final fingerprints and rolls back partial
work. Current preparations load one complete Method plus the exact required
System references and never enter conditional-resource finalization. The
legacy selection payload remains Codable for machine-local state, but no
public Use Case, CLI command, next action, or rendered packet exposes its
retired finalizer. Public `ResearchOperations` delegates here;
Dialogue/Critique have no alternate preparation path.

Rendered function input keeps three typed layers distinct: `taskDirective`
contains the explicit public Action, retained Function transport, read/write
sets, a separately typed Critique-output binding when applicable, and exact
loaded Skill package/resource revisions; a validated
`methodContract` supplies bounded method guidance; and provenance-labelled
`researchData` carries Markdown, YAML-derived values, citations, bibliographic
metadata, and records only as serialized data. The current packet schema has
no Action Profile, so protected Core prose neither invents one nor treats that
future field as a missing current requirement. Researcher Skills may change
method, never fingerprints, checkpoints, conflict handling, containment,
recovery, or typed permissions. Agent completion is revalidated against those
Application-owned constraints regardless of text found in any data field.

For an Analysis Target carrying canonical `zotero_item_key`, preparation reads
that exact item once through Application's local read-only `ZoteroOperations`,
adds `scholium-zotero-integration` to the resolved phase, and embeds a labelled
`ZoteroBibliographicContext` in the durable `ResearchFunctionSnapshot`.
Warnings are data in that snapshot and never fail preparation. Resume reuses
the stored context; a new run rereads Zotero. No fetched field enters Markdown,
Inspector, Search, or a cross-task metadata cache.

Write preparation records only a pending Fidelity handoff. Post-edit completion
stores the final Target fingerprint as `awaitingFidelity`; Application creates
or reuses an independent read-only child with the same inputs. An agent must
submit its evidence. Parent advancement validates and links that child (or
identical completed evidence); direct write-run Fidelity outcomes are rejected.
Exact evidence keys prevent duplicate storage or scheduling.

Core separates Skill discovery/bindings (`ResearchSkillStore`), dependency and
instruction assembly (`ResearchWorkflowAssembler`), checkpoints
(`TriptychCheckpointStore`), current Function-backed Discussion, Comment,
Critique, and Research Activity. The clean cutover retains no Human Review,
Qualification, pre-Function Dialogue, ResearcherComment, or app-owned
Annotation store; repositories alone mutate revision-checked source.
`RecommendedBibliographyStore` alone owns its atomic portable JSON and never
mutates notes or Zotero. No omnibus function store exists.

CLI decodes Contracts, invokes the same Application use cases, and encodes the
canonical function and bibliography command families. No pre-1.0 aliases
remain. `AgentCommandAction` uses argument vectors; CLI rendering never owns
eligibility, Skill routing, checkpoints, write sets, or shell command strings.

`CommandLineToolInstaller` is an app-wide Application capability. It verifies
and atomically copies the packaged `Contents/Helpers/scholium` executable into
the user-local command directory and refuses symbolic-link destinations. The
Settings feature receives status/install closures only; SwiftUI does not copy
executables or inspect the filesystem. Packaging and QA scripts build and sign
the app and its helper together.

Application-icon identity is product-owned by `SCHOLIUM_SPEC.md` §19.5, not by
SwiftUI state, document Appearance, or a runtime resolver.
`Tools/Packaging/ScholiumIcon.icns` is the sole derived bundle icon named by
`Tools/Packaging/Info.plist`. Debug, QA, and release assembly copy that same
repository resource; no build lane synthesizes or selects an alternate icon.

All SwiftPM scratch and Xcode DerivedData live in isolated lanes beneath the
ignored repository-local `.build/`; none may use `/tmp`. This requires the
checkout to remain outside File Provider-managed locations.

Per-window `ResearchController` owns a `ResearchFunctionController` containing
only Target, draft inputs, progress/cancellation/errors, presentation identity,
and stale-response tokens. A narrow client composes document flush/selection
capture with async use cases; the controller owns no repository, filesystem,
document controller, or authoritative research data.

Recommended Bibliography follows a separate Triptych-library capability
boundary:

```text
RecommendedBibliographySection (fixed at Library bottom)
        ↓ compact presentation values and closures
RecommendedBibliographyController (one window)
        ↓ RecommendedBibliographyClient
RecommendedBibliographyUseCases (Contracts)
        ↓
RecommendedBibliographyCoordinator (Application)
        ↓
ResearchSkillStore + RecommendedBibliographyStore + Zotero read adapter (Core)
```

The controller is a sibling of `ResearchFunctionController` under the
per-window `ResearchController`. The current Application preparation path
still locks an Analysis identity and fingerprint; replacing that migration
bridge with a Triptych-owned preparation identity is tracked in Implementation
Status rather than treated as an alternative target contract. Application
snapshots the complete Source Analyzer method, validates completion tokens and
evidence, and performs conservative duplicate discrimination without note or
Zotero mutation. Core owns portable storage,
package resolution, path safety, and matching inputs. The App owns goals,
purpose, focus, stale-response rejection, refresh presentation, and compact
rows. Prior results remain visible through refresh and failure.

## Source layout

- `Scholium/UI/Foundation` contains semantic color roles, metrics, shapes,
  motion, and accessibility-aware surface modifiers.
- `Scholium/UI/Components` contains stateless Scholium building blocks plus
  the bounded native window-shell adapters described below.
- `Scholium/UI/PreviewCatalog` contains deterministic Debug-only component
  matrices for ready, empty, loading, error, conflict, and long-text states,
  plus named appearance and accessibility review entry points. Preview code is
  development-only and does not enter the released interface.
- `ScholiumContracts` contains boundary values, capability protocols,
  deterministic source transformations, immutable snapshots, events, and
  delivery-safe errors. It has no filesystem, database, network, UI, watcher,
  store, or global mutable authority.
- `ScholiumCore` contains internal I/O and persistence implementations plus the
  protected Skill resource bundle; it is not a public SwiftPM product.
- `ScholiumApplication` contains runtime configuration and pooling, capability
  actors, the typed event stream, CSS/App Support I/O, Obsidian appearance
  projection, and Zotero transport.
- `Scholium/Features` contains the Discovery, Document, Research, Properties,
  and Settings delivery controllers and per-window editor sessions.
- `Scholium/App/Window` contains mutually exclusive window presentation
  routing plus the document-transition, presentation-persistence, and
  workspace-resolution coordinators. These coordinators do not duplicate a
  feature controller or writable document owner.
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
classification.

`ContentView` has one `.sheet(item:)`, one typed alert presentation, and one
persistent `ScholiumWorkspaceSplitView` root for each configured workspace
window. Its bounded AppKit bridge creates the three-item split described above;
role-owned backgrounds fill each container while Library, Document, and
Apparatus content stays foreground in the live safe area. Bootstrap never
constructs this split. Loading and document states replace hosted content, not
the shell. `WorkspaceWindowCoordinator` receives the exact window and split,
installs toolbar/delegate state, and registers readiness/flushing. No singleton,
window search, notification, polling, delayed correction, or width calculation
participates.

Research Record is a separate, nonrestored SwiftUI `UtilityWindow`. Its root
receives the current native focused object observed at the app scene boundary;
each Workspace supplies its `WindowModel` with `focusedSceneObject`. No model
registry, notification, generation counter, presentation coordinator, custom
focused key, or manually retained window model participates. The window
projects Research Activity, Comment exchanges, Write attribution, Critique
association, provenance, and current Function-backed Discussion through a
narrow `ResearchRecordContext`. Ordinary Markdown annotations remain in the
document and never become separate chronology. It never enters the trailing
split item and never owns checkpoints, a document buffer, autosave, undo, or
conflicts.
Closing Research Record therefore cannot reveal or resize Research Inspector.

The Library-owned Attention queue is an inline Library destination, not a sheet
route. Research Inspector may project only the active note's compact Attention
summary. Recommended Bibliography is likewise rendered at the fixed Library
bottom; its current Analysis-locked Application preparation identity is
migration debt recorded in Implementation Status.

The Research Inspector receives immutable `ResearchOverviewPresentation` and
`ResearchFunctionsPresentation` values composed at the window root. It owns no
workspace refresh, Comment, Critique, availability, or run state. Its Overview,
Connect, and Actions modes share the one native trailing split
item and one per-window `ResearchInspectorMode`; legacy stored strings are
normalized only while restoring that window. Mode changes and note/tab changes
never reconstruct the retained Document host.

The Research Function panel uses one typed `researchFunction` sheet route
carrying only a stable Target reference, function ID, and presentation ID. The
router owns sheet exclusivity; `ResearchFunctionController` owns the session
and draft. `NoteContentView` retains only the focused
`openResearchFunction(id:selection:)` action for menu and keyboard invocation;
it contains no Function presentation or bottom inset. Actions launches
the same sheet and restores focus only when that mode supplied the initiating
button. Neither leaf receives `WindowModel`, Core, or Application authority.

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
paths, and Research Function IDs never change with locale. Researcher-authored
prose, note titles, quotations, citations, imported text, exact source, and
filesystem paths bypass the interface catalog and render verbatim. Purely
internal vocabulary that has no researcher-facing presentation is not a
translation surface. Product Skill package names and researcher-owned Skill
names also render verbatim; surrounding application labels and explanations
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

## Product Skill resources and maintenance

`ScholiumCore/Resources/Skills/` is the sole canonical product-skill tree and
the exact resource directory copied into the `ScholiumCore` SwiftPM bundle.
There is no repository-level source mirror or synchronization step. Catalog
schema 4 separates protected System mechanism from ordinary bundled Methods.
Discuss, Analyze, Synthesize, Write, Critique, Content Fidelity, and optional
Manuscript each declare exactly one public Action and one retained protected
Function. Discuss method prose is separate from its automatic Discussion
protocol. Catalog metadata also exposes capabilities—including
`bibliography-recommendation`—and citation styles while retaining modes only
for internal package assembly.

Function-method activation remains a legacy Settings-facing capability.
`ResearchFunctionSkillSelection` can still decode and revise the preserved v1
file so old data remains inspectable, but `ResearchWorkflowAssembler` ignores
its primary, supplemental, and Practice selections. New Application operations
edit, disable, replace, and explicitly restore an Action's v2 Working Method
through exact package and binding revisions. Direct edit and restore exchange
the complete package through descriptor-relative operations, recheck the v2
binding before and after package mutation, and publish the displaced package
through the existing machine-local Research Guidance snapshot lifecycle.
Same-volume archival moves the displaced inode; cross-volume archival uses a
verified complete copy and retains the hidden portable inode so a late write
cannot be discarded. Snapshot listing reports the retained package's observed
revision separately, and a corrupt retained stage cannot hide the valid
machine-local snapshot. A binding exchange that commits but cannot complete
verification is reported as recovery-required without rolling the package back
into a state that could contradict the active binding. Every prepared run
captures the resulting exact package and loaded-resource revisions. The
categorized Methods and Researcher Skills interface remains a later
production-Settings cutover.

Action assembly seeds protected Core, Research Integration, and Discussion
mechanism independently of any editable Method dependency list. A Triptych
Method may be self-contained or name its own bounded resources; it is never
required to mirror bundled `references/` filenames. Package identity and all
resource bytes are captured as one coherent revision, so an interposed
external Skill edit fails closed instead of producing a mixed snapshot.
Practice resources remain exact selections, and Fidelity resources remain
bounded to the checks selected for that run.

The split Methods load a complete adaptive core and expose no secondary
researcher or agent mode choice. Legacy
`ResearchFunctionConditionalResource` and selection payloads remain decodable
for existing machine-local records, but every current Function advertises an
empty resource vocabulary, validation rejects nonempty selections, and the
old selection command is absent from public CLI/help. Current
Analyze, Synthesize, and Write requests also require the exact current Target
as their sole write Target; additional Note writes require later independent
child phases rather than a widened parent grant.

Researcher Skill evolution is an independent Research Guidance maintenance
slice. Contracts carry the expected revision, complete
`ResearchSkillProposedPackage`, evaluation, and confirmation token; Application
enforces explicit request and confirmation. Core validates the proposal against the same bounded package and
dependency graph as installed local Skills, snapshots the entire opted-in
Triptych-local package, replaces it through descriptor-relative operations,
reads it back, and rolls back on failure. Bundled packages remain immutable.
This path is never selected by a Research Function.

Snapshot inventory is global to Research Guidance rather than derived from the
selected Skill. Core enumerates snapshots through stable directory descriptors
and no-follow reads, returns valid snapshots together with typed per-entry
issues, and never lets one corrupt entry hide other recovery sources. Restore
accepts an explicitly expected present-or-missing current state, validates the
snapshot as a Researcher Skill, and uses atomic replace or guarded missing-
package installation. An existing displaced package becomes a new undo
snapshot before replacement; a missing package has no displaced state. The UI
confirms complete-package replacement before invoking this authority.
Direct Working Method edit and bundled restore publish their displaced package
in this same UUID/manifest/package format, so existing listing and restore
operations remain the sole machine-local recovery owner rather than creating a
second portable history inside `.scholium`. Cross-volume fallback is the narrow
exception: the verified snapshot records that its displaced hidden package is
still retained under `.scholium/skills`; automatic cleanup is intentionally
not claimed while an external participant may hold its inode open.

## Vault write and prewrite-recovery boundary

`MarkdownRelativePath` is the typed authorization input for research Markdown.
It preserves display spelling, treats backslash as a literal character, and
rejects absolute paths, empty or dot components, NUL, and non-Markdown targets.
`VaultPathResolver` scopes lookup to one canonical root and uses a
volume-sensitive `VaultPathComparisonKey` only for case/Unicode collision
decisions; neither rewrites Markdown or stored display paths.

`VaultDescriptorAccess` opens one root descriptor for each top-level operation,
walks every parent with `openat` plus `O_NOFOLLOW`, and opens leaves with
`O_NOFOLLOW | O_NONBLOCK`. Immediate `fstat` accepts regular files only.
Enumeration supplies candidates, never final authorization. Vault loads,
fingerprints, precommit checks, postcommit readback, and recovery verification
all use this descriptor-relative boundary. `FilePresence` distinguishes
present, `ENOENT` absence, and inaccessible/error; only confirmed absence may
complete deletion.

`VaultMutationCoordinator` performs short `NSFileCoordinator` accessors around
that descriptor authority. Create and move use exclusive rename. Existing-file
update holds the original descriptor, writes and synchronizes a same-directory
candidate, copies metadata with descriptor APIs, preserves the candidate
content mtime, rechecks the exact preimage, uses displaced-byte-preserving swap,
and verifies bytes, mode, owner/group, ACL/xattrs, flags, birth metadata, and
the parent-directory synchronization boundary. Ordinary xattrs and Finder tags
remain byte-exact. For the LaunchServices-managed `com.apple.quarantine`
attribute only, verification accepts a valid system normalization when its
security flags and event identifier are unchanged and its timestamp does not
move backward; malformed values or authority changes still fail closed.
Unsupported swap fails closed.
Any post-swap identity, readback, metadata, permission, or synchronization
uncertainty attempts a guarded swap-back, keeps observed staging evidence, and
returns `commitUncertain`; Application persists a `.noteSave` Transaction
Recovery record and never reports Saved.

`PrewriteRecoveryLedger` is Core-only machine state under
`Vaults/<vault-id>/recovery-v2/`. Immutable fingerprinted objects are indexed by
SQLite WAL with full synchronization, bounded to ten entries per path, and
protected by remap journals and permanent-delete tombstones. A damaged database
is quarantined and rebuilt from verified objects. Legacy `versions/` bytes stay
unchanged during all-or-nothing v1 migration and become read-only after the
completion marker. This ledger has no delivery-facing versions/restore API;
Checkpoint restore remains the only visible recovery mechanism.

## Shared read models and metadata

`WorkspaceNoteSnapshot` is the shared immutable read model for a workspace
note. It carries vault-qualified identity, exact `NoteDocument`,
descriptor-observed file metadata, a fingerprint-bound title projection, and
graph counts. The app does not maintain a second mutable `Note` or YAML value
model; the only app wrapper distinguishes a workspace snapshot from an
Unclassified `NoteDocument` without copying either source.

Contracts' `PropertyContract` catalog is the sole canonical vocabulary and
ownership authority. It defines role-specific keys, value kinds, empty
creation requirements, allowed values, cross-field constraints, and validation.
`ResearchUnitDeclaration` separately parses Analysis Completion versus
Topic/Work Scope, and `ResearchNoteTitleResolver` supplies one role-aware
identity fallback to Workspace, Search, Link Graph, and Research Functions.
App's independent `AboutProfileCatalog` owns default display choices and order;
`PropertyPresentation` adds labels, help, grouping, and control style only.
Property edits are validated through Contracts and applied by Application as targeted
`NoteDocument` changes. `FrontmatterPatchPlanner` first validates complete YAML
with Yams, then proves a unique bounded plain key. Ordinary scalar edits replace
only the value token; the role-aware Research Unit uses bounded member and array
replacements; and a missing key is appended only at a proven top-level or child
block-mapping boundary. Flow roots, quoted/duplicate or complex keys,
merge/anchor/alias involvement, block scalars, structured scalar continuations,
and ambiguous indentation return a typed refusal that directs the researcher
to Source. Refusal leaves every Markdown byte unchanged; successful patches
preserve BOM, newline/final-newline style, comments, unknown YAML, formatting,
and all bytes outside the proven range.

## Documents and CodeMirror

`DocumentController` is per-window and owns its `DocumentSessionStore`, keyed
by `DocumentSessionKey`, which
contains the registered vault UUID and stable note UUID. Path and title changes
therefore do not replace editor state. Separate windows receive separate
stores, even when they open the same stable document identity.

The store reconciles full-session leases before releasing the previous target.
Dirty, conflict, save-in-flight, retryable-recovery, and recovery-buffer states
pin a session. Closing any tab flushes its target before membership removal;
clean zero-lease, zero-pin sessions detach WebKit and discard full editor,
source, undo, HTML, and preview state immediately. Only a 64-entry lightweight
presentation LRU survives close; memory pressure reduces it to 16 or clears it
without evicting leased or pinned safety state.

Each retained `DocumentSessionModel` owns:

- its persistent `MarkdownEditorSession` and flush token;
- the exact editor mirror and committed revision;
- Read, Live Preview, or Source mode;
- a revision-bound semantic source scroll anchor plus normalized fallback;
- autosave and in-flight save tasks with stale tokens;
- rendered Read projection state; and
- save error, conflict, retry, and comparison presentation state.

CodeMirror remains authoritative while editing. The boundary uses full-buffer
reads, delta-mirror comparison, fingerprint-gated save, committed-text
synchronization, conflict comparison, and flush-before-agent-work. The Swift
model retains these facts across SwiftUI view reconstruction; it never
reconstructs writable Markdown from HTML, parsed YAML, or another projection.

`DocumentEditorHost` is the persistent presentation boundary for one selected
document session. Read is mounted continuously; after first editor allocation,
the retained CodeMirror surface is also mounted continuously. Read, Live
Preview, and Source transitions change opacity, stacking, hit testing,
accessibility exposure, and first-responder focus rather than view identity.
`NoteContentView` observes that exact `DocumentSessionModel` directly; it does
not depend on an ancestor's forwarded change notification to reveal a new
mode. This ensures the editor surface is invalidated as soon as the persistent
session changes instead of waiting for an unrelated pointer or layout event.
The hidden surface cannot receive pointer, keyboard, or accessibility input.
Clean external revisions synchronize the retained editor through the same
generation-checked path; dirty buffers still enter Conflict. Window resizing,
split changes, theme, text scale, document measure, and ordinary SwiftUI
reconstruction may reconfigure presentation but cannot recreate the retained
`WKWebView` or `EditorState`. Retained-surface memory remains a measured
acceptance concern rather than permission to weaken this lifecycle contract.

### Editor boundary contract

The editor is an app-private typed boundary, not a generic event bus. One exact
Markdown source is the only writable authority. Live Preview and Source share
one persistent CodeMirror `EditorState`; Read renders a fingerprint-bound
committed revision. CodeMirror owns active editing state, selection,
composition, and undo history. Swift owns a checked mirror reconstructed from
accepted UTF-16 deltas and reconciled against complete editor text before
persistence.

Every bridge request is bounded and carries protocol, request, session,
document, fingerprint, and generation identity. Mutating requests are
serialized. Unknown operations, stale identities, generation gaps or repeats,
invalid or overlapping ranges, and oversized messages or results are rejected
without mutation. Source crosses `WKWebView.callAsyncJavaScript` through
structured arguments in the page content world; it is never interpolated into
executable JavaScript.

Bridge v5 sends source deltas immediately in generation order and adds a
generation-checked, nonmutating exact UTF-16 source-range reveal operation. It coalesces
selection-only reports to the latest envelope per animation frame, with a 50 ms
offscreen watchdog. Each envelope carries exact selection and coordinates but
includes command availability only when changed. Swift keeps coordinates as
non-Observable session state and publishes semantic or lifecycle changes only.
Recovery capture follows document/history and lifecycle changes, not cursor
motion. Every awaited request binds a session epoch and revalidates WebView,
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

The retained-memory scenario uses an app-owned, run-specific handshake rather
than inferring readiness from XCUITest timing. The initial editor load and each
requested Live Preview/Source transition append one progress record only after
the typed JavaScript bridge acknowledges the mode. The external sampler
attributes and records the complete app/WebKit process set, appends an
acknowledgment, and the UI driver advances only after that acknowledgment.
Its QA-only mode-request transport updates the active retained document
session directly so repeated transitions cannot be coalesced by SwiftUI's
one-shot presentation request; the normal WebView update, CodeMirror
transition, and bridge acknowledgment remain the measured implementation.

The retained-state correctness layer is deliberately separate from that
external authority. A real WKWebView integration journey drives 50 typed
Source/Live mode transitions through one attached session and requires the
dirty buffer, accessibility mode chrome, and bounded performance ring to remain
coherent. It does not infer process-memory convergence or visible p95 latency.

`ScholiumContracts` owns durable Markdown meanings and the immutable editing
dialect. TypeScript may parse an uncommitted buffer for immediate projection
and exact transformations, but cannot invent persistence, relationship,
callout, or diagnostic semantics. Every Markdown command creates one
CodeMirror transaction and one undo event. Multi-selection transformations are
atomic and refuse frontmatter, code, raw HTML, comments, protected literals,
and malformed ranges whose boundaries cannot be proved. Outside proven edit
ranges, BOM, newline style, final newline, YAML, comments, unknown syntax, and
malformed source remain exact.

Before autosave, manual Save, Read, Dialogue, or Critique flushes,
Swift requests complete CodeMirror text and reconciles it with the checked
mirror. A clean external revision may replace the buffer through a
generation-checked non-history transaction; a dirty buffer stays exact and
enters Conflict. Mode changes and structural commands wait for marked-text
composition and are discarded if document identity or generation changes.
Outbound bridge requests cross WebKit as encoded JSON text and are parsed in
JavaScript. They do not pass source strings through Foundation's
`JSONSerialization.jsonObject`, because that conversion removes a leading
U+FEFF from a string value and would violate the exact-source contract.

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

CodeMirror maps exact-source CRLF offsets to its geometry. Read maps the same
contract through a load-time registry of source-located DOM blocks, using
`elementFromPoint` and the range map rather than full-DOM measurement on every
scroll. Invalid ranges or fingerprints fall back to the normalized fraction.
Live/Source also use CodeMirror's native snapshot. Reconstruction freezes a
handoff anchor, and delayed restoration requires the same document or Read-load
generation. It never depends only on throttle-prone animation frames.

Written annotation is authoritative Markdown, including an ordinary semantic
Callout when a separate visible note is useful; Scholium owns no parallel
annotation store, overlay, or CodeMirror margin widget. Comment requires an
exact source selection and opens a passage-scoped researcher-agent exchange.
Agent replies remain pending until the researcher chooses Finish, which alone
projects Commented activity. Critique binds all finished Comments attached to
the exact current Target revision, narrowed to overlapping ranges for Passage
scope.
`Command-F` opens Scholium's shared **This Note** Search;
the embedded CodeMirror Find panel is not part of the product.

**This Note** receives an immutable editor source snapshot containing note,
session, source, and revision identifiers. Search reads that value without a
flush, autosave, repository mutation, or index publication. Result navigation
checks the request freshness, session, revision, and fingerprint before
issuing a CodeMirror `revealSourceRange` transaction with no history entry;
cross-document navigation continues through the ordinary dirty-buffer,
autosave, and conflict coordinator.

### Shared document rendering migration

`MarkdownSemanticDocument` remains the one Contracts-owned semantic projection;
the editor migration extends it rather than creating a second render-document
authority. `MarkdownEditingDialect` serializes the same supported syntax and
delimiter rules to CodeMirror. Swift parses committed revisions for Read,
graph, diagnostics, and persistence-adjacent consumers. TypeScript incrementally
parses the uncommitted buffer for immediate Live Preview only, and shared
fixtures require its source spans and meanings to agree with Contracts.
The dialect explicitly carries the case-sensitive named/inline footnote
syntax, two-space-or-tab continuation ownership, and first-reference ordinal
rule as well as callouts, Vector Links, and mathematics. The TypeScript adapter
fails closed when it receives a footnote dialect it does not implement.

Complete note source uses one CodeMirror language owner built from
`yamlFrontmatter` around the locked Markdown language. Closed frontmatter is a
real incremental YAML subtree even when the YAML contains diagnostics; the
body remains the Markdown subtree. If an opening delimiter has no closing
delimiter, Live Preview makes no semantic projection, keeps the exact source
editable, and presents an accessible Source-mode instruction. Table, callout,
footnote, mathematics, and preview adapters all honor this fail-closed guard.

That Markdown content language is extended through the locked Lezer API with
typed Wiki/Vector-Link, named/inline footnote, callout, inline/display
mathematics, highlight, and Obsidian-comment nodes. Live consumers do not infer
those constructs outside the corresponding syntax ranges. The shared
cross-runtime fixture projector parses a normalized LF/BOM-free view only for
Lezer compatibility and maps every node boundary back to the exact original
UTF-16 offset, so CRLF, leading BOM, Unicode decomposition, and final-newline
form remain source-authoritative. These nodes locate editing syntax; Swift
`MarkdownSemanticDocument` and `GraphSnapshot` remain the authorities for
diagnostics, identity, relationship meaning, and committed Read output.

The mode-neutral base catalog is also explicit rather than assumed. Contracts
publishes source-located CommonMark/GFM blocks plus strong, emphasis,
strikethrough, inline-code, link, and image nodes; the TypeScript projector maps
the corresponding Lezer nodes to the same kinds and exact UTF-16 ranges.
Semantic blocks do not own their terminal CR/LF sequence, and task-list prose
owns the text after its task marker. Shared LF and BOM/CRLF/Unicode fixtures
enforce that boundary. Incomplete inline extension markers remain ordinary
editable source, matching mature Markdown failure behavior; only structurally
opened block mathematics and comments produce fail-closed malformed
diagnostics.

Live block projections use direct CodeMirror `StateField` decorations because
their replacement widgets change vertical geometry. One immutable
`LiveProjectionIndex` owns sorted frontmatter, literal, code-block, table,
Callout, and footnote ranges. A prefix-maximum interval index handles nested
half-open overlap and containment without mutating StateField-owned arrays.
Plain bounded insertions outside constructs map existing positions; deletions,
structural markers, and uncertain block boundaries rebuild conservatively. A
new background Lezer tree may refresh structure once; selection and viewport
transactions reuse it.

The inline `ViewPlugin` parses visible ranges plus a 2,000 UTF-16 buffer and
reuses decorations while it still covers the viewport. Indexed literals and
fenced-code ranges avoid scanning from line one. Selection changes replace only
merged old/new neighborhoods within that margin, not the visible buffer or
structural index. Widget equality preserves DOM; height work stays inside
CodeMirror's measurement cycle.

Read and Live Preview consume one app-owned presentation contract:

- `ScholiumWebDesignTokens.documentPresentationCSS` supplies appearance and
  document-rhythm variables to both WebKit surfaces;
- `StyleOperations` persists typed, named Appearance configurations under
  Application Support and the frontend projects the selected configuration to
  deterministic CSS without placing configuration in a research vault;
- protected render-component CSS owns common callout, link, table, footnote,
  and mathematics roles;
- Read emits static semantic DOM from the committed semantic document; and
- the Live adapter maps the same roles to bounded CodeMirror decorations and
  widgets without replacing active source, selection, composition, or undo.

The modes need not share one DOM tree. A shared component contract plus thin
static-Read and editable-CodeMirror adapters preserves Read semantics and
accessibility while keeping Live Preview an editor. Layout changes may update
presentation variables and container size but must not reconstruct the retained
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

Inactive Live callouts share Read's `.scholium-callout` DOM and stylesheet.
`LiveBlockActivation` records the half-open range and entry edge: downward
entry selects `from`, while upward or rendered-body entry selects `to` before
CodeMirror resumes ownership. The atomic replacement is noninclusive at both
boundaries. Its slot uses measured padding, never block margins or fixed height;
fold, style, and pointer changes measure before further coordinate mapping.
Footnote definitions remain excluded so their end-section widget is the sole
nested-block owner.

Semantic tables follow that adapter boundary. Read emits a protected scroll
container with a real `table`, `thead`, column-scoped `th`, `tbody`, and
alignment roles. Inactive Live tables use the same `tables.css` roles through
a direct CodeMirror `StateField` block replacement, because a widget that
changes vertical geometry cannot be supplied as an indirect viewport
decoration. Each displayed cell retains its source offset; pointer or keyboard
entry removes the projection and reveals the exact Markdown table in the same
EditorState. The table DOM is never a writable or round-trip source.

Footnotes use the same projection rule. Read and Live share `footnotes.css`,
the reference-number role, end-section structure, logical-direction spacing,
and contrast behavior. A direct Live `StateField` derives case-sensitive
identifiers, first-reference ordinals, repeated occurrences, inline notes, and
bounded two-space/tab continuations from the current buffer while excluding
YAML, code, HTML, and comments. Inactive references become numbered inline
widgets; the first inactive definition is hidden at its exact source range and
appears in one semantic end-section widget. Activating a reference or endnote
item places the caret at its source offset and removes only the affected
projection. Duplicate, undefined, and unreferenced forms are not repaired, and
neither the widget DOM nor its rendered inline content can become writable
Markdown authority.

Continuation normalization removes exactly one two-space or tab ownership
indent and preserves every deeper space. Nested lists, block quotations, and
fenced code therefore retain their structure in both the committed Read
renderer and Live's display-only `markdown-fragment` adapter. The same adapter
renders the one-definition footnote preview; raw HTML stays inert. Shared
fixtures compare definition content as well as identifiers so Swift and
TypeScript cannot silently choose different block ownership.

Mathematics uses a locally bundled, exactly pinned KaTeX runtime and matching
CSS/fonts. The first admissible integration must use `htmlAndMathml`,
`trust: false`, bounded `maxExpand` and `maxSize`, no remote resources, and
escaped plain-source diagnostics for failures. KaTeX output is a projection;
only the original delimiter span is editable or writable.

Link, Vector-Link, and footnote previews are revision-bound requests. Swift
owns graph resolution, target selection, committed preview content, containment,
and external-URL policy. WebKit owns only the source anchor, visible geometry,
and transient presentation. Responses carry session, document, revision,
generation, request, and target identity; stale or ambiguous responses are
discarded. Footnote requests return one referenced definition, never the whole
footnote section, and the definition uses the same safe Markdown-fragment
presentation as the Live end section.

The boundary requires pure TypeScript coverage for protocol validation, exact
transformations, projection, clipboard conversion, composition, and
accessibility structure; Swift coverage for Contracts parity, protocol
encoding, controller convergence, and a real WKWebView lifecycle; and isolated
QA coverage for native commands, commit-before-navigation, recovery, conflict,
and exact-buffer preservation. Real assistive technologies, text services, and
installed IMEs remain manual acceptance where synthetic events cannot prove
operating-system behavior. Current evidence belongs only in
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

The editor does not introduce Milkdown, ProseMirror, a hidden rich-text model,
HTML-to-Markdown persistence, normalization or repair, a permanent formatting
toolbar, arbitrary media management, embedded AI chat or suggestions,
real-time collaboration, a new SwiftPM target, or a generic editor plugin
framework.

## Design-system implementation

[SCHOLIUM_SPEC.md §19](SCHOLIUM_SPEC.md#19-scholarly-editorialism-and-design-variables)
owns palette meanings, typography, opaque surface language, motion, the
adaptive editorial grid, and accessibility rules. The app implements that
contract in `Scholium/UI/Foundation` through `ScholiumColorVariables`,
`ScholiumColorResolver`, derived `ScholiumColorRole`s, `ScholiumGrid`,
`ScholiumMetrics`, `ScholiumMotion`, and `ScholiumInterfaceTypography`.

Accent and Paper are the only configurable inputs. One resolver derives every
appearance role, including the shared Library/Apparatus surface, for native and
generated WebKit CSS. Matching `editor.css` fallbacks preserve deterministic
first paint. Functional/status anchors stay private. Tests enforce the input
boundary, mappings, parity, contrast, and relationship variants; no static
appearance palette or JSON mirror exists.

`ScholiumGrid` is the single native authority for the 4pt rhythm, bounded 2pt
optical exception, semantic spacing, and component anchors. `ScholiumMetrics`
maps responsibilities to those roles without copying values; no geometry JSON
mirror exists.

- AppKit owns window, toolbar, split, divider, collapse, fullscreen, and frame
  geometry. The Library's 300pt content minimum is native split-item state, not
  grid spacing or persisted divider state;
- `ScholiumMetrics.Onboarding` owns the separate Bootstrap window and setup-form
  measures;
- `ScholiumMetrics.Workspace` owns the configured-workspace initial size, not a
  minimum;
- `ScholiumMetrics.Document` names the explicit CSS-pixel top inset and
  per-window text-scale range; and
- `ScholiumDocumentRhythm`, the unit-explicit
  `ScholiumDocumentPresentationConfiguration`, and `ScholiumWebDesignTokens`
  supply one responsive `rem`/CSS-pixel typography and minimum-inset contract
  to Read, Live Preview, and Source. `DocumentAppearanceSettings` owns one
  normalized **48–96ch** line-width value with a **72ch** default; generated
  presentation CSS exports it as `--scholium-document-line-width` together
  with an internal derived half-width length so the supported WebKit runtime
  does not depend on CSS division. Read/Live resolve it against Body type and
  Source against retained exact-source type. The shared CSS centers that
  measure subject to the mode-specific minimum inline inset, while dynamic
  presentation updates reuse the existing CodeMirror remeasure path rather
  than reconstructing editor state.

`ScholiumMotion` exposes purpose-named animations and returns no animation
when Reduce Motion is active. It does not install a global animation policy.
The existing `ScholiumInterfaceTypography` namespace remains the sole
interface typography namespace.

## Component boundaries

`Scholium/UI/Components` implements the component distinctions established by
the specification. Reusable feature components remain stateless leaves
receiving immutable values and typed closures; feature roots retain state and
action routing. The bounded AppKit window-shell adapters are infrastructure
exceptions: they own native controller and split-item lifetimes, weak
exact-window attachment, toolbar/delegate installation, explicit split
intents, and native visibility mirroring, but no
Triptych, document, or researcher-visible semantic state. `WindowModel` and its
feature controllers remain those state owners. This document records that
dependency direction, while the specification owns the stable rule for when
Scholium-specific components or distinct research surfaces are appropriate.

## Boundary enforcement

`ScholiumContractsTests`, `ScholiumApplicationTests`, and the architecture and
composition suites in `ScholiumAppTests` exercise their respective module,
runtime, window, document, presentation, and design-system boundaries.
`Tools/Scripts/verify.sh` adds package-graph, source-import, I/O, and public
symbol-graph guards so delivery targets cannot reacquire Core-owned authority.

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for dated evidence,
reachable behavior, and remaining acceptance work. This document intentionally
does not duplicate test counts or claim that a historical pass proves the
current checkout.

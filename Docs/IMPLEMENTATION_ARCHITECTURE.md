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
        ├── SwiftUI WindowGroup (one Codable route per scene)
            ├── WindowModel (one per complete workspace window)
            │   ├── WindowWorkspaceController
            │   ├── WindowSessionPersistenceCoordinator
            │   ├── DocumentTransitionCoordinator
            │   ├── DiscoveryController
            │   ├── AttentionPresentationState
            │   ├── AttentionPopoverSession (exact Workspace adapter)
            │   ├── DocumentTabController
            │   ├── DocumentController
            │   │   └── DocumentSessionStore
            │   ├── ResearchController
            │   │   ├── ResearchActionController
            │   │   └── RecommendedBibliographyController
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
subtree expansion remain `DiscoveryController` state. A disclosure commits its
flat visible-row projection without a list-wide layout animation; the row's
single chevron alone consumes the shared, Reduce-Motion-aware
`ScholiumMotion.disclosure` recipe also used by Connect. This prevents departing
Note labels from interpolating through their owning Folder while retaining one
stable row identity and one controller-owned disclosure set. Core enumerates real
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
but it does not satisfy `SCHOLIUM_SPEC.md` §18.2's pane-ownership requirement;
the status ledger
records that migration debt without treating this workaround as target authority.

AppKit owns resizing, compression, dividers, collapse, fullscreen, frame
restoration, and drag limits; the Codable route owns scene identity. No width
binding, window search, persisted divider geometry, or continuous correction
intervenes. Library receives the specified 300pt native content minimum,
without a preferred/maximum width or second geometry owner. Apparatus clears
the system Inspector item's fixed maximum, installs its initial collapsed state
before adding the item to the native split, and uses a controller-lifetime
adapter that offers the provisional 320pt ideal exactly once after the first explicit
reveal, only when Document can retain at least that width. The offer is neither
persisted nor replayed; all later resizing, hiding, showing, and restoration
remain AppKit-owned. No item receives a Scholium fraction, holding priority, or
restoration state. A scene/window minimum remains contingent on the complete
adaptation matrix.

Apparatus uses `NSSplitViewItem(inspectorWithViewController:)`; production does
not replace its native minimum, divider, safe area, separator, or collapse
policy. The one initial ideal-width offer above is released immediately after
application; the native item and `toggleInspector(_:)` own transitions. Because
the nested split may sit outside
the responder chain, the collapsed Show route is a borderless hosted item, not
the platform-wrapped standard toolbar item, and bridges with the View command
through the exact per-window coordinator. Selected-document state supplies
availability. `WindowModel` mirrors native visibility for commands,
restoration, and toolbar reconciliation but never reasserts it or stores width.

The Inspector has exactly three current-note modes: Overview, Connect, and
Actions. Overview presents a current-Note Attention summary whose one button
routes to the exact Workspace's Attention popover, followed by role-aware About fields;
About keeps selectable values and routes editing through its heading button.
For a current Analysis only, the window root normalizes its non-empty protected
Zotero item key and supplies one immutable navigation value plus the existing
`ZoteroBridge` presentation effect. About renders that value as one quiet
**Open in Zotero** row without exposing the key, fetched metadata, matching, or
confirmation. Connect projects direct and
derived relations as single full-row targets, pins the original collapsible
group header within its sole vertical scroll, and retains the distinct source
anchor as a named secondary action without a trailing glyph. Actions resolves
the public role-valid Action matrix, presents the
canonical defaults under quiet Research and Review headings, keeps visible
custom Profiles in one Researcher Skills group, and keeps Settle under
Judgment. Every launcher remains the same direct full-row operation and invokes
its exact Inspector-supplied window route; focused routing belongs to menu
commands rather than row activation. Pointer activation does not write keyboard
focus, while keyboard traversal and deliberate restoration retain it.
Availability is bound to the exact current Note,
clears while it is being rechecked, and rejects a late result from a previous
Target. No Research Activity chronology, Work with Agent wrapper, or Research
Record launcher is projected there. A quiet row for each portable active
Discussion that includes the current Note resumes passage-anchored, whole-note,
and focal-note exchange, while Settle remains a separate researcher-owned
current-state operation. Only finished Discussions appear in the current
read-only Research Record window; removed archives have no projection. The
Inspector may navigate or open another
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

## Research Action and protected execution boundary

Research Actions follow the same in-process compiler boundary as every other
delivery-neutral capability. The protected Function adapter remains below the
public presentation and use-case boundary:

```text
ResearchActionsInspectorView / ResearchActionPanelView
        ↓ immutable presentation values and closures
ResearchActionController (one window, production UI)
        ↓ ResearchActionClient
ResearchActionUseCases (Contracts)
        ↓ internal Action-to-Function adapter
ResearchFunctionCoordinator + Action resolver (Application)
        ↓
Core skill, checkpoint, record, and repository authorities
```

The old Function controller, panel, presentation route, and public use cases are
deleted. `ScholiumContracts` owns public Action identity, Target/Material/scope,
Fidelity checks, availability/repair codes, runs, submissions, and fingerprints.
Workspace `ResearchUseCases` composes record, checkpoint, Skill, Action,
permission, source-access, and bibliography capabilities. Protected Function
types remain only behind Application as the mechanism used by the Action
adapter. Contracts contain no application-defined labels, symbols, package
storage, YAML inspection, or layout. Researcher-owned Profile labels are
declarative data, not interface code.

The §8 Research Action public layer begins in `ScholiumContracts` with validated
`ResearchActionID`, public execution kinds and Target roles, role-filtered
default definitions, a unified native parameter model, and a fail-closed
schema-v2 `ResearchActionSnapshot`. Each preparation freezes the exact Target,
ordinary Method package and loaded-resource revisions, resolved Profile and
Profile-document revision, validated parameter values, and concrete readable
and writable note envelope. The snapshot contains no `ResearchFunctionID`. A separate versioned
`ResearchActionRecordIdentity` fixes the complete Action projection allowed in
future portable records to the Action ID alone; execution kind, Target role,
and protected Function identity are not record fields.

`ResearchActionProfile` schema 1 adds a bounded declarative configuration
contract without making it executable. It permits only note picker, passage
anchor, Material selector, source reference, bounded text, Boolean, and
enumeration modules. Profile, module, choice, and capability objects reject
unknown fields; every label, identifier, list, property boundary, selection,
text limit, module count, and choice count has an explicit byte or count
ceiling. Raw package and file-size preflight belongs to the later installation
boundary rather than the Codable value. The capability declaration contains
readable roles and a candidate existing-note write ceiling only. Its two
operations are Markdown modification and property-limited modification; it
contains no grant, policy, destructive lifecycle operation, conflict overwrite,
or executable payload. Property-limited modification rejects every key owned
by Scholium's protected machine-property catalog.
Applicable Targets remain readable, picker roles stay inside that
scope, execution kinds impose their direct-write role maximum, and Analyze
requires one matching required source-reference module. These declarations do
not grant authority. The Application resolver intersects them with the exact
current request and live identities to produce one nonreusable preparation
envelope. Machine-local standing policy is a separate decision factor and
cannot enlarge that envelope.
Property-only mutation is rejected by the current resolver because the retained
coordinator cannot yet prove a property-bounded source delta.
`ResearchActionProfileDocument` stores at most 256
Action-keyed bindings in `.scholium/research-action-profiles-v1.json`. Core
reads and atomically replaces that one bounded file through no-follow directory
descriptors, exact expected-revision checks, readback validation, and a
package/Profile compatibility check. The document may bind researcher-owned
Action identities and the optional bundled Manuscript Action only; it cannot
replace the six default bundled Action identities. Storage and its production
Settings editor remain nonexecuting configuration, while the Action resolver
consumes an exact Profile snapshot only during availability and preparation.
Once
a file exchange commits, any failed directory flush, readback, cleanup, or
canonical-path identity proof returns an unsafe-document error; bytes visible
through the old descriptor never become a reported Settings success.

`ResearchSourceReference` schema 1 is the only source-access value permitted in
an Action/Function snapshot or future portable record. It contains a closed
route, stable source ID, exact Zotero parent/attachment keys when applicable,
one display-only filename, and a source fingerprint. Its decoder rejects
unknown fields, route/key mismatch, path-shaped labels, and malformed
fingerprints. It has no bookmark, absolute path, or source bytes. The transient
`ResearchSourceBindingRequest` is deliberately non-Codable because its selected
file URL belongs only to the current machine-local operation.

Core's per-Triptych `ResearchSourceAccessStore` owns the corresponding private
binding at `Application Support/Triptychs/<id>/source-access/`. It writes a
single-link mode-0600 atomic file beneath a mode-0700 directory. Owned path
components are traversed through `openat` without following symlinks. Bookmarks
request read-only security scope; binding and every reopen acquire that scope
before filesystem inspection and balance every successful start. Source reads
open the complete path with macOS `O_NOFOLLOW_ANY`, require an
`fstat`-verified regular file, hash
exactly its starting size, then reject growth, truncation, path substitution,
alias, symlink, directory, stale bookmark, unreadable state, or fingerprint
change. A valid reselection repairs private permission drift without losing
peer bindings and atomically replaces corrupt app-owned bytes. Persisted
absolute paths and bookmark data remain only in this machine-local store. A
changed or inaccessible source is never replaced with the Analysis note.

An internal-only `ResearchActionFunctionMapping` in `ScholiumApplication` maps
Analysis and Synthesis to Develop, Write to Revise, and the remaining public
execution kinds to their protected Function mechanisms after role validation.
The same internal adapter derives the exact bundled Action from Function plus
Target role inside the protected coordinator. Core Skill resolution accepts that Action
identity explicitly: Analysis Develop resolves `scholium-analyze`, Topic
Develop resolves `scholium-synthesize`, and a package bound to one fails closed
for the other. `ResearchActionUseCases` now resolves and prepares default and
researcher Actions and embeds the resulting Action snapshot before protected
execution. Binding v1 never enters this path. The Inspector, Research menu,
common modular sheet, CLI, and delivery contracts enter only through Action
identity. Every Action run uses the separated Local Execution v2 boundary
below; unsupported pre-production run files remain byte-unchanged, invisible,
and unable to authorize current work.

The product Skill catalog schema 4 separates protected mechanism from ordinary
method prose. `ResearchSkillClass.method` packages each declare exactly one
public Action plus one internal protected mechanism. Discuss is an ordinary
Method and `scholium-discussion-protocol` is its automatic mechanism-only
adapter. Analyze, Synthesize, Write, Critique, Content Fidelity, and optional
hidden Manuscript are similarly distinct bundled Method references. System
Skills own authority and persistence boundaries; they cannot supply the
intellectual procedure. The old conditional Development, Revision, and
Manuscript resource selectors remain internal to protected stored execution
records and are never offered by current Actions; each Method now loads
its complete adaptive core, with Write feedback guidance included by default.
Before a new Triptych manifest is committed, `ResearchSkillStore` installs six
independent editable packages under `.scholium/skills/` and atomically writes
`research-working-method-bindings-v2.json`; Manuscript is represented by an
explicit disabled state. The initializer is idempotent for an exact interrupted
bootstrap and never runs automatically for a Triptych with an existing
manifest. Application exposes the same absence-checked operation as the
explicit repair primitive for the later categorized Settings interface.

`ResearchSkillInstallationStore` owns the app-wide, short-lived staging
boundary for researcher-selected local directories. It walks the selected
directory through no-follow descriptors, accepts only bounded regular UTF-8
`SKILL.md` and one-level `references`, `templates`, or `evals` resources, and
rejects linked, multiply linked, executable, scripted, nested, oversized, or
structurally malformed input. Directory enumeration stops as soon as the
bounded entry ceiling is exceeded rather than first collecting an unbounded
directory listing. Its public preparation contains only a display
name, bounded file inventory and fingerprints, method metadata, proposed
Action placement, and the explicit fact that an Action Profile is still
required; source paths and bytes remain Core-private and expire from memory.
`WorkspaceRuntime` resolves the explicitly selected Triptychs and supplies
their existing `ResearchSkillStore` actors. Core preflights every destination,
publishes each independently copied package with descriptor-relative
`RENAME_EXCL`, then repeats the bounded file/link/mode/readback validation.
Preflight and post-publication validation both reject a package identifier
still named by an active Action binding or by a retained capability binding;
malformed binding state fails closed. If a later destination fails, every
proved task-owned directory is moved out of the executable package namespace
to a hidden same-volume recovery quarantine. The quarantined inode is not
recursively deleted, so a late write through an already-open descriptor is
preserved. A missing or moved package, replaced Skills root, identity mismatch,
or otherwise unprovable rollback produces a typed recovery-required error.
Installation creates no binding, Profile, permission approval, or execution
state, so an unbound package starts disabled and later edits cannot synchronize
across Triptychs silently. Production Research Guidance Settings now presents
the staged inventory in a native sheet and requires explicit destination
Triptych selection. Cleanup and presentation of installation recovery
quarantines remain later Research Guidance work.

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

### Portable Research Record storage v1, record schema 3, and Local Execution v2

`PortableResearchRecordStore` owns one JSON file per intellectual record under
`.scholium/research-records/v1/records/`; `active/` owns one file per unfinished
portable Discussion. The retained empty `trash/` directory is legacy reserved
storage, not a current lifecycle or projection. Confirmed record deletion
isolates the exact reread JSON with a descriptor-relative rename inside
`records/`, verifies the isolated bytes, unlinks only that file, and restores an
interrupted pre-unlink rename on startup. A
separate `settlements/` directory stores exactly one replaceable current-state
file per Note. Settle therefore no longer appends an application-authored
history event, and Changed Since Settled is derived against the current
Markdown revision during snapshot assembly without writing a pending-state
event. Before the portable state commits, `VaultRepository` pins the exact
current bytes in the existing immutable-object prewrite ledger under the stable
Note identity. Identical fingerprints reuse one pin. The Triptych-scoped
machine-local `ResearchRecoveryPolicyStore` revision-checks the 10/30/50/no-
automatic-deletion policy; lowering a limit applies only the exact pin IDs in a
fresh preview. After confirmation it durably retains that approved ID set until
idempotent cross-vault removal completes, so interruption can resume without
silently including a later pin. Ordinary prewrite retention cannot collect
pinned entries, and removing a pin later permits unreferenced temporary evidence
to be collected. Each pin has a descriptor-relative, file-and-parent-synced
manifest with exact-byte fingerprint and a persistent per-Note monotonic order;
wall-clock time is display metadata only. SQLite is a derived projection:
startup validates each manifest against immutable bytes and replaces any row
whose note, entry, time, or order differs through one immediate transaction and
UPSERT. One advisory lock plus a partial unique SQLite index coordinate order
allocation across ledger instances. Every exact-valid manifest protects its
entry independently of projection; ambiguous order or projection failure sets
a write blocker and suspends automatic cleanup. Portable replacement errors
distinguish proved pre-rename refusal from post-rename uncertainty, and only
the former permits task-owned pin rollback. The retention journal accepts the
same bounded 100,000-ID set that its 8 MiB secure-file ceiling can encode.
Precommit deletion removes only the exact journaled Settle state and
aborts on a concurrent replacement; rollback never overwrites a newer state,
while postcommit privacy cleanup always removes late state for every deleted
Note identity. Portable record contracts whitelist Action identity, exact
Method/Profile revisions, the path-free Source Reference when present,
participating Note revisions, attributed statements, agent-reported
actually-used Materials, Application-confirmed changes, and discrepancies.
Every new Action record also identifies its primary Target Note. Completion
accepts actually-used Material IDs only as a unique subset of the frozen,
exact-revision Material selection; merely selecting a Material never creates
use evidence. The portable record stores the Material's frozen revision and
role, not a later projection. Strict record validation cross-checks the use's
Note identity, qualified reference, role, title, and revision against its
participant fact while still retaining a later deletion tombstone as history.
For current Action runs, the protected optional representation distinguishes
retained Function-era absence from an explicit report; the Action decoder
requires the field, and record construction rejects absence instead of
coalescing it to `[]`. Schema 3 adds the closed `fidelity_completion` value:
Action permits `not_required`, `completed`, or `unverified`, while Discussion
requires `not_applicable`. Application derives that process fact from terminal
state plus exact-revision Fidelity evidence; it does not copy an Agent verdict.
Schema 1/2 record files are isolated as unsupported and remain unchanged. The
`v1` directory name continues to version this storage layout rather than the
individual JSON schema.
They have no generic metadata escape hatch and cannot encode a
protected Function ID, assembled instructions, raw key, bookmark, absolute
path, diff, token count, transport log, or window state. Strict decoding is
recursive through Note identities, fingerprints, passage anchors, line-only
Comment references, Method resources, and Source references; unknown nested fields and path-shaped
resource names fail closed rather than surviving as ignored JSON.

The Inspector's already-visible Action availability initializes the common
sheet synchronously; declared Note and Source modules load their bounded data
inside the visible sheet rather than blocking its presentation. Same-Target
availability refresh retains its rows but disables them until revalidation
finishes. The sheet submits the execution kind, semantic Profile revision, and
researcher Profile-document revision it presented. Application resolution
compares all three before parameters or authority are constructed, so an old
same-kind sheet cannot acquire broader readable roles, write operations, or
property authority after Settings changes.

Portable reads and writes combine per-process actor isolation, one
machine-local advisory lock, `NSFileCoordinator`, and descriptor-relative
no-follow access. Writes additionally use a same-directory temporary file,
file and directory synchronization, atomic rename, and exact readback.
Enumeration isolates malformed record files instead of hiding valid peers.
Store reopen removes incomplete app-owned staging files while holding the same
lock and portable coordination boundary. The lock lives below the verified
Application Support Triptych directory; it is not portable authority.

`PortableResearchDiscussion` is the single current exchange model. A
lightweight Comment statement carries only the exact Note fingerprint and a
one-based inclusive line range; it stores no selected prose or source offsets.
The Web surface keeps its textarea until an identity-bound native acknowledgement;
failures preserve the entered text, and committed-refresh failures acknowledge
the durable write without inviting a duplicate. Review resolves rendered text to
its real Markdown source line only as transient input.
Older passage statements retain their exact anchors for compatibility, and the
participant list may also contain whole-note or focal Note context. Appending a turn rewrites only that active
file; closing the sheet performs no storage action. Finish validates current
participant revisions, creates exactly one `kind: discussion` record, and
removes the active file under the shared coordination lock. A matching
active/finished pair left by process interruption is reconciled on reopen;
conflicting pairs fail closed. Anchor refresh reattaches only at one reliable
source location and otherwise records `needsReattachment`. Permanent deletion
purges active Discussions containing the deleted identity and retains finished
records with a participant tombstone. Passage continuation resolves the
current path from the stable primary Note identity instead of retaining a
historical path. A machine-local deletion marker shares the portable advisory
lock so another Scholium process or helper cannot create or advance an active
Discussion after deletion has entered its committing transaction.
If synchronization introduces more than one active Discussion for a primary
identity, the store reports every conflicting file, all ID-addressed reads and
mutations fail closed, and the workspace publishes no active Discussion row
until the conflict is repaired.

`LocalResearchExecutionStore` owns one schema-v2 file per Action run at
`Application Support/Triptychs/<id>/research-execution-v2/`. It may retain the
protected Function snapshot, assembled instructions, grant digest, static
Discuss transport contract, and completion evidence. Scholarly Discussion
turns never enter this private execution file. Raw grant keys remain non-Codable and are
delivered only in memory. Completion authorization for a new Action consults
only this store, so a matching legacy grant cannot authorize it. A write
report, consumed grant, completion, and submission digest advance in one
atomic replacement of their single run file; there is no durable
completed-grant/missing-completion intermediate state. Permanent
Note deletion preflights this store and, after the commit decision, removes
every execution containing the deleted Note or its associated Critique;
finished portable records remain under their separate tombstone lifecycle.

Every new preparation path writes Local Execution v2 and creates one portable
record only after a terminal validated nonconversational completion. It never
writes `research-activity.json` or `dialogue.json`. Legacy activity, Dialogue,
binding, and grant files are not migrated, rewritten, or imported as current
authority. Legacy Comment and Dialogue content is no longer projected into the
current exchange model. No decoder, projection, recovery workflow, or product
entry exposes those pre-production files; their bytes remain untouched.
Critique preparation
writes a machine-local handoff intent under
`research-execution-v2/critique-handoffs/<run>.json` before its portable
association becomes staging. The intent contains only Triptych, run, an
optional legacy checkpoint identity, and the canonical digest of the frozen
snapshot plus prepared instructions.
Portable prose can create the exact Local v2 run after interruption only when
the complete Critique invariants and that machine-local digest match. Missing,
remote, changed, malformed, or
conflicting evidence remains portable testimony with a health issue and cannot
grant execution authority. Exact duplicate staging is reconciled
deterministically, and completion retry idempotently repairs missing actionable
findings.
Discussion agent replies are appended only to the portable active exchange;
completion validates that attributed evidence, while Finish remains a separate
researcher action with no legacy activity projection. The production Action
surface uses the public role matrix and declarative Profile modules. The
independent record browser consumes only finished portable records. Application
comparison resolves each recorded
start and end fingerprint independently from an exact current snapshot,
machine-local prewrite recovery object, or checkpoint file. If either digest
cannot be matched to retained bytes, comparison is unavailable. The line
projection is non-Codable, created only after an explicit request, and discarded
on close, selection change, or cancellation; no diff hunk enters portable or
machine-local record storage.
While any active Discussion exists, the current document surface rereads the
portable projection at a bounded interval. A cooperating CLI reply can
therefore update current state while the Discussion sheet is closed. Selecting
Discuss opens a Method-bound exchange directly. A Comment-only draft instead
passes once through the ordinary Action resolver, reuses its stable Discussion
ID as the Local-v2 run ID, and atomically adds the exact Action/Method identity
and request statement without losing earlier Comments. Subsequent handoffs
reload that run's machine-local instructions. Actions has no duplicate
active-Discussion row. A finished
or removed record dismisses the stale route.

Current Action opening flushes only the current editor registration. The Action
request carries the execution kind shown in the sheet, and Application
resolution rejects a changed kind before preparation. No current Action creates
an automatic whole-Triptych checkpoint; each mediated repository write instead
prepares, verifies, and retains only the exact bytes it actually displaces.
`WorkspaceStore.flushEditors(in:)` remains for explicit Triptych-wide lifecycle
operations and invokes at most one aggregate registration per window.

Rendered function input keeps three typed layers distinct: `taskDirective`
contains the explicit public Action, its validated native parameter values,
retained Function transport, read/write
sets, the safe source reference when Analyze applies, a separately typed
Critique-output binding when applicable, and exact loaded Skill
package/resource revisions; a validated
`methodContract` supplies bounded method guidance; and provenance-labelled
`researchData` carries Markdown, YAML-derived values, citations, bibliographic
metadata, and records only as serialized data. The machine-local Function
snapshot embeds the complete schema-v2 Action snapshot. The agent-facing
directive receives the resolved Action and parameter values but not the full
Profile document or its storage revision; neither Skill prose nor transport
text may reconstruct or enlarge that frozen Application authority.
Researcher Skills may change
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

Analysis Develop now maps to Analyze before preparation and requires one
freshly resolved source binding before and after checkpoint/Method resolution,
again on delivery, and before completion. A legacy Analyze snapshot without a
safe source reference remains decodable evidence but cannot resume or complete.
Topic Develop remains Synthesize and has no source requirement.
The assembled machine-local delivery packet may include the validated absolute
file path as a transient locator; the durable `ResearchFunctionSnapshot`
retains only `ResearchSourceReference`. Application exposes bind, inspect, and
remove operations, while the later modular source-picker interface is not yet
connected. For the Zotero route, `ZoteroOperations` permits only exact bodyless
loopback GETs, refuses redirects, verifies the exact response URL, parent and
attachment keys, absolute query-free local file URL, and exact selected path,
and repeats that identity check through completion. Permanent note deletion
preflights this private store before mutation and removes the note's locator in
the committing recovery phase. Zotero unavailability blocks this source route
even though ordinary bibliographic metadata warnings remain nonblocking.

Write preparation records only a pending Fidelity handoff. Post-edit completion
stores the final Target fingerprint as `awaitingFidelity`; Application creates
or reuses an independent read-only child with the same inputs. An agent must
submit its evidence. Parent advancement validates and links that child (or
identical completed evidence); direct write-run Fidelity outcomes are rejected.
Exact evidence keys prevent duplicate storage or scheduling.

Core separates Skill discovery/bindings (`ResearchSkillStore`), machine-local
source access (`ResearchSourceAccessStore`), dependency and
instruction assembly (`ResearchWorkflowAssembler`), checkpoints
(`TriptychCheckpointStore`), portable Discussion, Critique, and Research Record
storage. The clean cutover retains no Research Activity decoder/store, Human
Review, Qualification, pre-Function Dialogue, ResearcherComment, or app-owned
Annotation store; unsupported pre-production files remain unread and
repositories alone mutate revision-checked source.
`RecommendedBibliographyStore` alone owns its atomic portable JSON and never
mutates notes or Zotero. No omnibus function store exists.

CLI decodes Contracts, invokes the same Application use cases, and encodes the
canonical Action and bibliography command families. No pre-1.0 aliases remain.
`AgentCommandAction` uses argument vectors; CLI rendering never owns
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

Per-window `ResearchController` owns a `ResearchActionController` containing
only the selected public Action/Profile, draft inputs,
progress/cancellation/errors, presentation identity, and stale-response tokens.
A narrow client composes document flush/selection capture with async use cases;
the controller owns no repository, filesystem, document controller, protected
Function identity, or authoritative research data.

Recommended Bibliography follows a separate Triptych-library capability
boundary:

```text
SidebarRecommendedBibliographySection (fixed Sidebar utility outside Source List scroll)
        ↓ compact presentation values and closures
RecommendedBibliographyController (one window)
        ↓ RecommendedBibliographyClient
RecommendedBibliographyUseCases (Contracts)
        ↓
RecommendedBibliographyCoordinator (Application)
        ↓
ResearchSkillStore + RecommendedBibliographyStore + Zotero read adapter (Core)
```

The controller is a sibling of `ResearchActionController` under the
per-window `ResearchController`. The current Application preparation path
still locks an Analysis identity and fingerprint; replacing that migration
bridge with a Triptych-owned preparation identity is tracked in Implementation
Status rather than treated as an alternative target contract. Application
snapshots the complete Source Analyzer method, validates completion tokens and
evidence, and performs conservative duplicate discrimination without note or
Zotero mutation. Core owns portable storage,
package resolution, path safety, and matching inputs. The App owns goals,
purpose, focus, stale-response rejection, refresh presentation, and compact
rows. Candidate rows route only to a matched Analysis or Dismiss; they no
longer open Zotero directly. Prior results remain visible through refresh and
failure.

## Source layout

- `Scholium/UI/Foundation` contains semantic color roles, metrics, shapes,
  motion, and accessibility-aware surface modifiers.
- `Scholium/UI/Components` contains stateless Scholium building blocks plus
  the bounded native window-shell adapters described below.
- `Scholium/UI/PreviewCatalog` contains the retained deterministic Debug-only
  research-workflow catalog for the modular Skill-run sheet, staged installer,
  categorized Skill settings, Agent change request, and fixed-size secondary
  Research Record. It resolves or mutates no production
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
researcher input.

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
registry, notification, presentation coordinator, custom focused key, or
manually retained window model participates. Each presentation owns one
`ResearchRecordBrowserModel`: one disposable deterministic in-memory index plus
search, Note/date/Skill/Action/participant filters, selection, and at most one
cancellable comparison task. Reopening
resets to the current Note when available and the
researcher can remove that scope to browse the complete Triptych. The window
renders finished portable Discussion and nonconversational Action records,
preserves attribution and evidence-class qualifications, exposes tombstones,
and deep-links live participating Notes through the focused Workspace. Pin
replaces only `is_pinned`; **Delete Record…** requires a second confirmation
before Core permanently removes only the selected portable record under the
same descriptor-relative coordination boundary. Ordinary Markdown
annotations remain in the document and never become separate chronology. The
fixed 760 × 680 window never enters the trailing split item and never owns checkpoints, a
document buffer, autosave, undo, conflict, or retained trash state. Its diff is
disposable presentation over retained exact bytes, not a second writable source.
Closing Research Record therefore cannot reveal or resize Research Inspector.

Attention is one native transient SwiftUI popover owned by each exact
`WindowModel`, not an app-wide Scene, sheet, inline Library destination,
utility panel, or always-on-top surface. Per-Workspace
`AttentionPresentationState` owns only filter, selected item, selected Scope,
and optional current-Note subset; `AttentionPopoverSession` adapts that state
and the current immutable queue to the Sidebar and Inspector anchors without
duplicating either. `AttentionScopeCounts` is a read-only projection of the
same catalog and machine-local dismissal ledger. Sidebar consumes only the
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
participates. Recommended Bibliography is the fixed, intrinsic-height sibling
below the Library Source List scroll. It shares the Sidebar's navigation
surface and adds one structural boundary but owns no Scope, Location, selection,
filter, sort, disclosure, or lifecycle state. Inspector alone consumes the
document-adjacent apparatus surface. Its current Analysis-locked Application
preparation identity remains migration debt recorded in Implementation Status.

Ordinary Scope and Location navigation uses a
`DiscoveryLocationRequest(.stagedReplacement)`. `DiscoveryController` retains
the last committed Scope/Location pair until completion and still rejects late
request identities. `WindowModel.currentWorkspaceVaultSnapshot` first consumes
the immutable snapshot already published into `workspaceVaultSnapshotsByID`;
the Application operation is only an initial-construction fallback. A complete
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
modules. Copy Only and Copy and Open remain fixed footer actions. Either first
revalidates and freezes the Action internally, then performs the chosen
handoff; a prepared run keeps both actions available to retry the exact frozen
instructions. Launcher availability and the sheet's fresh Profile resolution
are separate: cancelling or failing a sheet cannot erase the Inspector, while
only the fresh Profile can prepare. The sheet cannot dismiss while preparation
is crossing its durable boundary. A late noncooperative result is reclaimed
through typed cancellation. Interrupted preparation and cancellation retain a
per-run cleanup barrier; no later Action can begin until each late result has
either cancelled successfully or become its own visible, retryable recovery
entry in Actions. One recovery can therefore never overwrite another. When a
window temporarily has no current Note, a recovery-only Apparatus keeps those
window-owned cleanup entries reachable without inventing a Target or Action.
Protected Function mapping occurs only in Application composition. The public
route and controller are Action-owned, and the superseded Function route,
controller, panel, and record projection are absent. Neither leaf receives
`WindowModel`, Core, or Application authority.

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
captures the resulting exact package and loaded-resource revisions.

The production Research Guidance pane now owns one persistent category list
for Methods, Researcher Skills, Permissions, Sources and Integrations, and
Recovery and Technical. Methods exposes direct edit, disposable bundled
comparison, disable, compatible replacement, explicit restore, hidden
Manuscript activation and direct edit, and explicit default installation for
an established Triptych with no v2 document. Researcher Skills exposes local
package editing,
structural validation, staged directory installation, package deletion guarded
by every current or retained binding, and Action Profile creation, confirmed
deletion, global ordering, seven bounded modules, declared role/source/write
requirements, and a nonexecuting native sheet preview. An Action ID already
owned by any Profile cannot be silently claimed by another Skill. Root-owned
Skill drafts are keyed by Triptych and package; Action Profile drafts are keyed
by Triptych, package, and Action. They survive Skill, category, and Settings-tab
navigation until the researcher saves or discards them without crossing a
Triptych boundary. Methods, Researcher Skills, and Recovery publish asynchronous
reload results only after cancellation and active-Triptych identity checks; the
New Local Skill sheet is dismissed when that identity changes. Deleting an
unused Skill rechecks binding, Profile, root, package identity, and complete
package revision before an atomic
isolation move; production then archives the exact package through the
machine-local recovery store rather than recursively deleting possibly late
external writes. Applying one Profile to other Triptychs
preflights a compatible independently installed package and writes independent
copies; it never synchronizes Skill bytes. Permissions stores one Triptych
default plus deliberate per-Skill overrides in machine-local Application
Support. Bootstrap states the quiet Ask Me Every Time default and points to
this later Settings route without requiring a policy choice. Superseded
Function-era Settings construction was deleted at the clean cutover.

`ResearchPermissionPolicyStore` owns one strict schema-v1 file per Triptych at
`Triptychs/<id>/research-guidance/standing-permissions-v1/` under Application
Support. A missing file means Ask Me Every Time without creating state. The
store uses descriptor-relative no-follow traversal, private directory/file
modes, an advisory cross-process lock, exact expected revisions, atomic
replacement, directory synchronization, identity proof, and decode/readback
validation. Corrupt, cross-Triptych, linked, over-permissive, or stale state
fails closed; no permission policy is portable research data or a bearer grant.

Application derives every per-Skill approval digest from the current
Triptych-local package revision and the complete set of current Action/Profile
role revisions. Settings carries the exact digest it displayed only as an
expected value; Application re-derives and rejects a stale envelope before
saving. Missing overrides inherit the Triptych default; an explicit override
whose Skill or any Profile changed becomes Ask Me Every Time and cannot fall
through to a broader default. The same derivation is repeated for evaluation,
so a caller-supplied stale digest cannot authorize work. Ask Me Only for Works
requires a researcher decision for every request containing a Work write role,
while Triptych-wide can only permit a later validated bounded grant after all
independent System, Skill, Profile, request, identity, and revision
intersections pass. The initial Target selected
by deliberately clicking an Action is already authorized and is not prompted
again. These policies govern only Scholium-mediated continuations; they neither
monitor a model's reasoning or network activity nor police direct external file
edits, which remain ordinary filesystem concurrency.

`AgentNoteChangeRequest` schema 1 is the non-authorizing coordination contract
for one additional-note or child-Action request. It binds a caller-provided
request UUID to the exact Triptych and parent Local Execution v2 run; the
parent and requested Action, Method Skill, Profile, and Profile-document
revisions; a bounded canonical set of stable Note identities and
expected fingerprints; existing-note operations; and one bounded attributed
agent reason. The request carries no display title or lifecycle assertion;
the Application derives both from current state before presentation. The
Application authenticates the parent against the local run,
rejects requests that do not expand its frozen scope, and re-resolves the
requested Action, package, Profile, role, operation, identity, lifecycle, and
source revision. A cancelled, stale, awaiting-Fidelity, or otherwise
incomplete parent completion closes an unresolved request; a normal complete
parent may remain provenance for a separately authorized continuation. A live
mismatch records only a terminal stale disposition; it never widens the parent
snapshot or grant.

`AgentNoteChangeRequestStore` keeps one strict file per request under
`Application Support/Triptychs/<id>/agent-change-requests-v1/`. The store uses
private modes, descriptor-relative no-follow access, an advisory cross-process
lock plus in-process serialization, atomic replacement, and exact readback.
Request submission and current-state queries borrow the Workspace source-
mutation gate across authentication, source revalidation, and the store
operation, so permanent deletion cannot interleave a new orphaned request
between parent-run discovery and privacy cleanup. Dates retain subsecond
precision so a valid decision immediately before expiry survives canonical
readback.
Exact replay of one request UUID returns the first record. Reusing that UUID
with different payload fails closed, and one parent run has at most one
unresolved request. Pending records expire after a bounded machine-owned
lifetime; decisions are pending, allowed subset, continue without changes,
cancelled, stale, or expired. A decision remains coordination state rather than
a completion key or child grant. Journaled permanent-deletion finalization
purges requests targeting the deleted Note and requests whose authenticated
parent execution contains it.

`AgentNoteChangePresentationCoordinator` is the one MainActor, App-wide owner
of native presentation claims. Each `WorkspaceWindowCoordinator` explicitly
registers its exact scene identity, live Triptych identity, key-window state,
presentation availability, focus route, and bounded present/update/dismiss
closures; the coordinator never searches the global AppKit window list. One
request ID can be claimed by only one matching window. The key matching window
wins, a closing window releases its claim for another live matching window,
and a busy window retains the request without replacing its existing sheet.
Exact bridge replay updates the claimed sheet, while
`show_note_change_request` only focuses that existing claim and never creates a
second presentation.

The shared `WindowSheetRoute` presents one native Agent Note Change sheet. It
derives current titles, roles, and revision state from the live Workspace
snapshot, exposes the requested Action, write operations, Method/Profile
revisions, subset selection, Allow These Notes Once, Continue Without Changes,
and Cancel the Run, and keeps stale or expired state readable. Before a researcher
decision, `WorkspaceStore` flushes registered editors for that Triptych and
Application reauthenticates the parent, Action, Method Skill, Profile, standing
policy subject, Note identities, roles, lifecycle, operations, and exact
fingerprints under the source-mutation gate. Bridge submission authenticates
and binds the request before any editor flush; only then may the App flush and
evaluate standing policy. Both manual and automatic decisions repeat frozen
request validation after policy evaluation, while automatic resolution also
requires a stable repeated policy evaluation whose subject package and
Action/Profile role revisions equal the frozen request. A qualifying standing
policy may resolve the exact validated request without a sheet. The sheet
resolves the current Profile button name and exact Skill display name for
researcher-owned Actions; Allow remains disabled while those names are loading
or unavailable, and raw package identity remains separately labeled technical
evidence. Identity lookup uses a bounded retry, and a later exact replay or
refresh retries a still-pending unavailable identity. At `expiresAt` it removes
the decision controls immediately and uses a
bounded durable-refresh retry before retaining the contract-derived expired
state. Either route records only coordination state; creating a separately
bounded child snapshot and grant remains the next implementation phase.
All in-App mutations of active Working Methods, Action Profiles, Skill package
content, Skill maintenance state, and standing policy borrow the same gate as
the final request validation and decision write. Actor reentrancy therefore
cannot place a configuration commit between those two operations.

Every new Local Execution v2 Action also receives one short-lived
`AgentCoordinationGrant`. The local execution persists only its SHA-256 digest,
bound Triptych, parent run, exact Action revision, and expiry; a non-Codable
authorization carries the plaintext key only in the live delivery packet.
`WorkspaceStore` owns one process-wide AF_UNIX listener
under its validated Application Support root. Its private parent is mode 0700
and the socket is mode 0600. The server holds an exclusive owner lock,
validates the peer with `getpeereid`, accepts one versioned length-prefixed JSON
request per connection, bounds frames and I/O time, and never logs request
bodies. The client validates socket type, owner, private modes, and server UID
before transmitting the key. App absence is a typed unavailable result; the
bridge neither launches the App nor queues work.

The serial listener owns at most one asynchronous request handler. At its
deadline it cancels the task and reports `outcome_unknown`: cancellation can
race a durable state transition, so the caller must converge by querying the
same request ID instead of inventing a new one. If the handler exits within a
bounded cancellation grace it is reaped before another request. If it ignores
cancellation, the listener closes and retains its exclusive owner lock until
the task finally exits; no later request can accumulate behind it. A
client-side I/O deadline after connection is classified the same way because
delivery cannot be disproved. `stopAndWait` reports failure after a bounded
wait; `WorkspaceStore` then leaves its still-borrowed Application runtime alive
rather than racing shutdown against that task. It also retains and logs a typed
bridge-startup diagnostic without disabling an otherwise valid runtime. Its
nonblocking deinitialization cleanup likewise retains both bridge and runtime
until owner release, then shuts the runtime down; it never destroys the runtime
under a cancellation-insensitive handler.

`scholium agent mcp serve` is handled before CLI snapshot-runtime creation and
uses MCP stdio framing only. It exposes `request_note_changes`,
`show_note_change_request`, and `cancel_note_change_request`; coordination keys
are tool arguments arriving on stdin, never command-line options. Submit,
status, and cancel authenticate the parent grant digest, while exact request
replay and cancellation remain idempotent. The first accepted request ID is
atomically bound into the parent Local Execution before request publication;
that ID may be retried, but no later ID can consume the key even after a
terminal decision. Tool failures retain a typed bridge
error code in structured MCP output. Status and cancel first read the stored
parent without applying expiry, authenticate the grant, and only then execute
the ordinary state-changing query. A bridge decision is still not a write
grant. An allowed schema-v2 decision stores only a versioned correlation plan:
one shared group ID plus reserved independent child run IDs for the exact
approved Note subset. Application then re-resolves current Action, Profile,
Method, Note identities, and fingerprints before preparing each child as its
own Local Execution v2 run. Every child has one frozen Target, its own
exact-Note continuation recovery checkpoint outside rolling automatic
retention, its own activity grant and completion validation, optional
final-revision Fidelity child, and durable parent/request/group lineage. The AF_UNIX response
delivers those live child packets only after their complete persisted evidence
matches the plan; plaintext keys remain delivery-only. Neither the plan nor
lineage is consulted as authority without the exact allowed request, current
parent, Action snapshot, checkpoint, and grant.

Revision-bound Resynthesize reuses the same independent Local Execution v2
child mechanics without impersonating an Agent change request. Application
rereads the completed Synthesize record, exact Topic Target, actually-used
Analysis revision, and current changed revision before reserving a new run.
That child owns a new activity grant, an exact-Topic **Before Resynthesis**
checkpoint, frozen Synthesize Action snapshot, cancellation/conflict/recovery
path, optional final-revision Fidelity, and `resynthesis` lineage back to the
source record. Its revision context is validation evidence, never a grant; the
child may write only the current Topic authorized by its own envelope.

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
This path is never selected by Action execution.

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
model; the app wrapper carries only the Application-owned workspace snapshot
without copying its exact source.

Contracts' `PropertyContract` catalog is the sole canonical vocabulary and
ownership authority. It defines role-specific keys, value kinds, empty
creation requirements, allowed values, cross-field constraints, and validation.
`ResearchUnitDeclaration` separately parses Analysis Completion versus
Topic/Work Scope, and `ResearchNoteTitleResolver` supplies one role-aware
identity fallback to Workspace, Search, Link Graph, and Research Actions.
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
- user-facing Review, Edit, or Source mode, backed by the stable internal
  `read`, `livePreview`, and `source` identifiers;
- a revision-bound semantic source scroll anchor plus normalized fallback;
- autosave and in-flight save tasks with stale tokens;
- rendered Review projection state; and
- save error, conflict, retry, and comparison presentation state.

CodeMirror remains authoritative while editing. The boundary uses full-buffer
reads, delta-mirror comparison, fingerprint-gated save, committed-text
synchronization, conflict comparison, and flush-before-agent-work. The Swift
model retains these facts across SwiftUI view reconstruction; it never
reconstructs writable Markdown from HTML, parsed YAML, or another projection.

`DocumentEditorHost` is the persistent presentation boundary for one selected
document session. Review is mounted continuously; after first editor allocation,
the retained CodeMirror surface is also mounted continuously. Review, Edit,
and Source transitions change opacity, stacking, hit testing,
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
Markdown source is the only writable authority. Edit and Source share one
persistent CodeMirror `EditorState`; Review renders a fingerprint-bound
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

Performance verification keeps target, mechanism, and evidence separate.
`Tools/Scripts/generate-rdf1.py` owns the deterministic RDF-1 bytes and
manifest; repository verification regenerates and verifies it beneath ignored
`.build/` state. `Tools/Scripts/run-performance-benchmarks.sh` owns the external
visible-boundary driver, five-warm-up/30-sample protocol, strict result
validation, scenario-versus-gate mode, and output inventory. Gate mode accepts
only the packaged app, requires release-owner threshold approval, and verifies
`ScholiumBuildProvenance.plist` against a clean exact tag and commit.

Metric runs use isolated app state and metric-specific processes. Warm Search
and Review reuse their post-setup process; launch and cold Review relaunch per
sample. The driver expands deterministic Library targets rather than routing a
Search result through Source mode. Native publication, AppKit layout, WebKit
navigation, bridge acknowledgement, paint, and exact app/WebKit process
attribution jointly define readiness. Run records contain only timing,
correctness counts, fixture identity, artifact identity, and environment
metadata—never queries, Note paths/titles, or research text. The target
thresholds and evidence-class rules live in `SCHOLIUM_SPEC.md` §21.4; dated
measurements and incomplete series live only in `IMPLEMENTATION_STATUS.md`.

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

CodeMirror maps exact-source CRLF offsets to its geometry. Review maps the same
contract through a load-time registry of source-located DOM blocks, using
`elementFromPoint` and the range map rather than full-DOM measurement on every
scroll. Invalid ranges or fingerprints fall back to the normalized fraction.
Live/Source also use CodeMirror's native snapshot. Reconstruction freezes a
handoff anchor, and delayed restoration requires the same document or Review-load
generation. It never depends only on throttle-prone animation frames.

Written annotation is authoritative Markdown, including an ordinary semantic
Callout when a separate visible note is useful; Scholium owns no parallel
annotation store or CodeMirror margin widget. Review and Edit own separate
transient selection toolbars: Review exposes only the in-place Comment
textarea, while Edit exposes common Markdown formatting and no Comment. Return
saves and closes a Review Comment, Shift-Return inserts a line, and Escape
cancels. Source exposes neither toolbar. Saving appends a line-only researcher statement to the
current active Discussion without opening a sheet, copying instructions, or
contacting an agent. Discuss later collects and presents these statements; its
agent request identifies their lines but never sends retained selected prose.
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
Dialect 4 explicitly carries the case-sensitive named/inline footnote syntax,
two-space-or-tab continuation ownership, first-reference ordinal rule, and the
Vector-Link v3 relation grammar alongside callouts and mathematics. Its four
kinds are neutral, supports, opposes, and incompatible. Support and opposition
are directed from the containing Note to the target; neutral and incompatibility
canonicalize their resolved endpoints and remain undirected. Only support and
opposition inverse presentation is derived after graph resolution. The
TypeScript adapter fails closed when it
receives a dialect it does not implement.

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
diagnostics, identity, relationship meaning, and committed Read output. Graph
contract 5 invalidates the retired reverse-support and directed-Questions
projection rather than decoding it as current state.

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
YAML, code, HTML, and comments. Inactive references become nonbutton numbered
inline markers; the first inactive definition is hidden at its exact source
range and appears in one semantic end-section widget. Placing the Edit caret at
a reference or endnote reveals only the affected source projection; it does not
preview or navigate. Duplicate, undefined, and unreferenced forms are not repaired, and
neither the widget DOM nor its rendered inline content can become writable
Markdown authority.

Continuation normalization removes exactly one two-space or tab ownership
indent and preserves every deeper space. Nested lists, block quotations, and
fenced code therefore retain their structure in both the committed Review
renderer and Edit's display-only `markdown-fragment` adapter. Review alone
renders the one-definition footnote preview and owns footnote navigation; raw HTML stays inert. Shared
fixtures compare definition content as well as identifiers so Swift and
TypeScript cannot silently choose different block ownership.

Mathematics uses a locally bundled, exactly pinned KaTeX runtime and matching
CSS/fonts. The first admissible integration must use `htmlAndMathml`,
`trust: false`, bounded `maxExpand` and `maxSize`, no remote resources, and
escaped plain-source diagnostics for failures. KaTeX output is a projection;
only the original delimiter span is editable or writable.

Link and Vector-Link previews are revision-bound Edit requests. Review resolves
footnote preview and navigation against its committed sanitized projection. Swift
owns graph resolution, target selection, committed preview content, containment,
and external-URL policy. WebKit owns only the source anchor, visible geometry,
and transient Edit presentation. Responses carry session, document, revision,
generation, request, and target identity; stale or ambiguous responses are
discarded. A Review footnote preview contains one referenced definition, never
the whole footnote section.

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

Accent and Paper are the only configurable inputs. Section 19.2's Paper is the exact
Light Document anchor; one resolver derives every other appearance role for
native and generated WebKit CSS. The complete Sidebar uses the Navigation
surface; Inspector uses a distinct Apparatus role whose tone is deliberately
much closer to Document than Navigation. Sticky Inspector headers and
relationship-glyph occlusion reuse that exact Apparatus role rather than a
floating-control surface. Matching `editor.css`
fallbacks preserve deterministic first paint. Functional/status anchors stay
private. Tests enforce the input boundary, mappings, parity, contrast, and
relationship variants; no static appearance palette or JSON mirror exists.

`ScholiumLibraryLocationPicker` owns the borderless native Location menu and
its single indicator without owning Location state. ScopeIndex and ModeIndex
pass their independent dimensions to `ScholiumEditorialIndexUnderline`, which
owns only the shared semantic color and visibility recipe. The Debug Editorial
Parchment acceptance board consumes these production components and resolved
roles; it is not a second design-system source.

The compact Recommended Bibliography component retains no explanatory subcopy
or horizontal candidate list. Its one native Button owns the full fixed band,
shows at most the first static citation preview, and opens the existing complete
surface. `ScholiumQuietRowButtonStyle` supplies the same raised hover/press
grammar used by Inspector summary/action rows without taking over each
consumer's purpose-owned height or insets.
`ScholiumMetrics.Library.bibliographyTopInset` and
`bibliographyBottomInset` map its asymmetric vertical rhythm to the shared grid;
the heading and accessibility group continue to carry Triptych-wide identity.
`ScholiumInterfaceTypography` owns the Folder, unselected Note, selected Note,
compact toolbar identity, bibliography preview, and bibliography empty-state
roles; leaf views no longer restate their sizes or weights.

`ScholiumGrid.Peripheral.contentInset` is the one 28pt outer page-edge source
for Library and Inspector. `ScholiumMetrics.Library` and
`ScholiumMetrics.Apparatus` map to it; their internal row, hierarchy, and section
variables remain separate.

`ScholiumLibrarySourceState` owns the common Library/Set Aside/Trash empty,
loading, and error page inset. It maps horizontal content to the peripheral
edge and vertical entry to `sourceStateVerticalInset`; it does not wrap
populated OutlineRows or alter their denser row-surface inset.

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

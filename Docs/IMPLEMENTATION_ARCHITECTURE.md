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

WorkspaceRuntime (one live runtime for the app delivery)
└── WorkspaceStore (macOS adapter and sole event-stream subscriber)
    └── SwiftUI WindowGroup (one Codable route per scene)
        ├── WindowModel (one per complete workspace window)
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

`WorkspaceRuntime` has two configurations: live reuses stable Triptych/vault
runtimes, watchers, and derived refresh while any app window needs them;
snapshot performs one-shot loading without watchers and shuts down after each
CLI invocation.

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

`WindowModel` is the per-window composition and focused-command root. It owns
Triptych assignment, Search/temporary Find, restoration, presentation, and
typed cross-feature intents. `DocumentController` alone owns selection and
document workflow state; `ResearchController` owns research generations,
initial Dialogue projection, checkpoint-list failures, and durable-recovery
listing. `WindowModel` exposes computed projections, not duplicated storage.
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
`NSSplitViewController` with three direct `NSSplitViewItem`/
`NSHostingController` siblings for Library, Document, and Apparatus. AppKit
owns window resizing, compression, divider mechanics, automatic Sidebar
collapse, collapse transitions, fullscreen, frame restoration, and drag limits.
SwiftUI's Codable route is the sole scene identity. No wrappers, width
bindings, global window searches, opening-frame corrections, or
Scholium-defined split minima/maxima intervene. A numeric minimum may exist
only once at scene level after the specification's complete adaptation matrix
proves it necessary.

Apparatus uses `NSSplitViewItem(inspectorWithViewController:)`. Production never mutates
its thickness, fraction, priority, collapse policy, full-height layout, safe
area, or separator. AppKit's standard item/
`NSSplitViewController.toggleInspector(_:)` owns the
transition. Because the nested split may be outside the responder chain, the
toolbar bridges that standard command and View-menu intent to the exact
per-window coordinator; selected-document state supplies availability. The
split's collapsed state is authoritative. `WindowModel` mirrors visibility for
commands/restoration but never reasserts it or stores Inspector width; the
coordinator receives explicit visibility intents and holds weak references to
the exact window and split.

The Inspector may project backlinks, related notes, Research Status, metadata,
provenance, Dialogue or Critique status, and other current-note context. It may
navigate or open another note in the Document tabs, but it never owns a document
buffer, editing, autosave, undo, or conflict state. Those remain exclusively in
the Document surface and its existing controllers.

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
ResearchStripView / ResearchFunctionPanelView
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

One delivery-neutral `ResearchFunctionCoordinator` per workspace owns
availability, preparation, resource finalization, completion, cancellation,
and record projection. It resolves/rechecks identities, inputs, resources,
checkpoints, records, and final fingerprints and rolls back partial work.
Unresolved conditional resources persist the normal identities as a read-only
preflight. `selectFunctionResources` must submit typed resources or an explicit
empty selection before mutation/completion; Core's
`finalizeFunctionPreflight` atomically extends the same snapshot with only
selected references/revisions. Public `ResearchOperations` delegates here;
Dialogue/Critique have no alternate preparation path.

Write preparation records only a pending Fidelity handoff. Post-edit completion
stores the final Target fingerprint as `awaitingFidelity`; Application creates
or reuses an independent read-only child with the same inputs. An agent must
submit its evidence. Parent advancement validates and links that child (or
identical completed evidence); direct write-run Fidelity outcomes are rejected.
Exact evidence keys prevent duplicate storage or scheduling.

Core separates Skill discovery/bindings (`ResearchSkillStore`), dependency and
instruction assembly (`ResearchWorkflowAssembler`), checkpoints
(`TriptychCheckpointStore`), Dialogue, Critique, and Human Review. Repositories
alone mutate revision-checked source.
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
  routing.
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
not own document sessions.

`ContentView` has one `.sheet(item:)`, one typed alert presentation, and one
persistent `ScholiumWorkspaceSplitView` root for each configured workspace
window. That bounded AppKit bridge creates one `NSSplitViewController`
containing three sibling `NSHostingController` surfaces. Bootstrap and setup
belong to their separate scene and never construct this split. Configured
loading and document states replace hosted content only; they never replace the
outer split. Its `WorkspaceWindowCoordinator` receives that exact native window
and split directly, installs the toolbar and close delegate, and registers the
route's readiness/flusher capability with the application-owned lifecycle
registry. No singleton split registry, window-list search, notification,
polling, delayed frame correction, or width calculation participates.

Research Record is a separate, nonrestored SwiftUI `UtilityWindow`. Its root
receives the current native focused object observed at the app scene boundary;
each Workspace supplies its `WindowModel` with `focusedSceneObject`. No model
registry, notification, generation counter, presentation coordinator, custom
focused key, or manually retained window model participates. The window projects Human Review,
anchored Comments, Dialogue, Critique association, and provenance through a
narrow `ResearchRecordContext`. It never enters the trailing split item and
never owns checkpoints, a document buffer, autosave, undo, or conflicts.
Closing Research Record therefore cannot reveal or resize Research Inspector.

The Library-owned Attention queue is an inline Library destination, not a sheet
route. Research Inspector may project only the active note's compact Attention
summary. Recommended Bibliography is likewise rendered at the fixed Library
bottom; its current Analysis-locked Application preparation identity is
migration debt recorded in Implementation Status.

The Research Function panel uses one typed `researchFunction` sheet route
carrying only a stable Target reference, function ID, and presentation ID. The
router owns sheet exclusivity; `ResearchFunctionController` owns the session
and draft. `NoteContentView` receives only a `ResearchStripPresentation` and an
`openResearchFunction(id:selection:)` closure. It never receives
`WindowModel`, `ResearchController`, or Application authority.

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
There is no repository-level source mirror or synchronization step. The official Workflow
layer contains Development, Critique, Revision, Content Fidelity, and
Manuscript; Dialogue remains System infrastructure and Human Review has no
skill. Catalog metadata exposes supported functions, capabilities—including
`bibliography-recommendation`—and citation styles while retaining supported
modes only for internal method selection.

Function-method activation is a separate Settings-facing capability over the
same boundary. `ResearchFunctionSkillSelection` represents an optional primary
replacement, supplemental packages, and exact Practice selections for one
semantic function. Application lists only valid compatible Triptych-local
Researcher Skills, validates role and Practice compatibility, and performs
revision-checked saves through `ResearchSkillStore`. The assembler composes the
persisted selection into the effective phase contract. The frontend receives
friendly candidate names only in Research Guidance; the Strip and CLI never
choose package IDs.

Conditional run resources use `ResearchFunctionConditionalResource` plus an
explicit `method`, `template`, or `checklist` kind.
`ResearchFunctionResourceSelectionSubmission` encodes `resources`; request
JSON encodes `conditional_resources`; selection JSON encodes `resources`.
Already-prepared runs complete from immutable snapshots. New Critique runs
never select the retired competing report template.

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

## Shared read models and metadata

`WorkspaceNoteSnapshot` is the shared immutable read model for a workspace
note. It carries vault-qualified identity, exact `NoteDocument`, file metadata,
review projection, and graph counts. The app does not maintain a second mutable
`Note` or YAML value model; the only app wrapper distinguishes a workspace
snapshot from an Unclassified `NoteDocument` without copying either source.

Contracts' `PropertyContract` catalog is the sole semantic metadata authority. It
defines canonical keys, value kinds, creation requirements, allowed values,
cross-field constraints, and validation. App
`PropertyPresentation` values add labels, help, grouping, ordering, and control
style only. Property edits are validated through Contracts and applied by
Application as targeted
`NoteDocument` changes, preserving unknown YAML, malformed-note
readability, formatting, and bytes outside the changed range.

## Documents and CodeMirror

`DocumentController` is per-window and owns its `DocumentSessionStore`, keyed
by `DocumentSessionKey`, which
contains the registered vault UUID and stable note UUID. Path and title changes
therefore do not replace editor state. Separate windows receive separate
stores, even when they open the same stable document identity.

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

Bridge v3 also exposes a bounded diagnostic-only performance snapshot. Its
256-sample ring contains metric names, durations, and numeric counts only; it
cannot carry Markdown, paths, titles, queries, preview content, or other
research data. CodeMirror-visible paint boundaries use `requestMeasure` and a
subsequent animation frame. Offscreen views may throttle those frames, so an
absent paint sample is not replaced with an internal-work duration. External
UI automation and process-set memory measurements remain the authority for
visible-response and retained-WebKit acceptance. Process ownership must be
resolved from the exact app originator's launchd service map and checked
against every executable before RSS is summed; PPID or process-name matching
is insufficient because WebKit XPC workers are launchd children.

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

Before autosave, manual Save, Read, Search, Dialogue, or Critique flushes,
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

Scroll continuity is owned by the retained `DocumentSessionModel`, never by a
path-keyed view or writable Markdown. `EditorScrollAnchor` binds a source UTF-16
position, nearest semantic block bounds, block-relative position, normalized
fallback, and document fingerprint. CodeMirror converts exact-source CRLF
offsets at the typed bridge and uses its document geometry; Read maps the same
contract onto source-located semantic DOM. A mismatched fingerprint or invalid
range is discarded and falls back to the normalized fraction. Live Preview
and Source additionally use CodeMirror's native scroll snapshot while sharing
one `EditorState`. Reconstruction freezes a separate handoff anchor before the
old surface can emit another scroll event, and delayed restoration is accepted
only while the same immutable CodeMirror document remains installed. WebKit
restoration must not depend solely on animation frames because offscreen or
reconstructing views may throttle them.

Add Comment is not a Markdown transformation: it captures an exact source
selection, opens the role-valid Review or Critique panel, and focuses its
anchored composer. `Command-F` opens Scholium's shared **This Note** Search;
the embedded CodeMirror Find panel is not part of the product.

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
their replacement widgets change vertical geometry. Initial construction is
fully indexed. When the index proves that a document contains no table,
callout, or footnote constructs, pure selection changes and ordinary bounded
insertions without a construct marker reuse the empty projection state;
deletions, large insertions, marker-bearing insertions, and every
construct-bearing document conservatively rebuild. This is a measured
no-construct typing fast path, not a claim that every projection is already
incremental.

Read and Live Preview consume one app-owned presentation contract:

- `ScholiumWebDesignTokens.documentPresentationCSS` supplies appearance and
  document-rhythm variables to both WebKit surfaces;
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

The Host remains the owner of presentation CSS. When that CSS changes text
scale, measure, insets, appearance roles, or user styling, the bridge updates
the one controlled style element and explicitly requests a CodeMirror measure;
it reports the resulting scroll position only after that measure. Font-ready
remeasurement is bound to the same immutable document. This prevents a visual
configuration change from leaving CodeMirror's height map and semantic scroll
anchor on different geometries.

Inactive Live callouts use the same semantic `.scholium-callout` DOM and
protected component stylesheet as Read. Entering a callout reveals its exact
source and returns ownership to CodeMirror. Named footnote-definition ranges
are excluded from top-level callout and table projection so nested blocks have
one owner: the semantic footnote end-section widget.

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
owns palette meanings, typography, opaque surface language, motion, and
accessibility rules. The app implements that contract through `ScholiumColorRole`,
`ScholiumLightPalette`, `ScholiumDarkPalette`, `ScholiumMetrics`,
`ScholiumMotion`, and `ScholiumInterfaceTypography` in
`Scholium/UI/Foundation`.

Native SwiftUI/AppKit surfaces resolve semantic roles dynamically. WebKit uses
the same kebab-case role vocabulary in
`Scholium/Resources/Editor/editor.css`; `SafeMarkdownReadWebView` consumes the
same declarations. Architecture tests enforce native/WebKit role parity,
reviewed appearance mappings, contrast floors, and specialized relationship
variants. The code and tests implement the specification values rather than
making this document a second palette authority.

Stable geometry is named by meaning rather than number:

- `ScholiumMetrics.Onboarding` owns the separate Bootstrap window and setup-form
  measures;
- `ScholiumMetrics.Triptych` owns the exact interface measures;
- `ScholiumMetrics.Workspace` owns the configured-workspace initial size, not a
  minimum;
- `ScholiumMetrics.Document` owns the provisional readable measure, scrolling
  top inset, and per-window text-scale range; and
- `ScholiumDocumentRhythm` and `ScholiumWebDesignTokens` supply one provisional
  responsive typography/inset contract to Read, Live Preview, and Source.

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

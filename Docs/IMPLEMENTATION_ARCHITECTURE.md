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

Scholium uses compiler-enforced frontend/backend isolation and modularization
inside one local modular monolith. `ScholiumApp` is the macOS frontend, while
`ScholiumApplication` and the internal `ScholiumCore` target form the headless
backend; `ScholiumCLI` is a second delivery adapter over the same backend.
Frontend and CLI code can reach backend authority only through Application
capabilities and immutable `ScholiumContracts` values. This is a module,
dependency, and state-ownership boundary within one process, not an XPC,
network-service, or distributed-system split. Modularization continues within
both sides: window and feature controllers divide frontend ownership, while
runtime and capability actors divide backend ownership.

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
    ├── WindowModel (one per complete workspace window)
    │   ├── DiscoveryController
    │   ├── DocumentTabController
    │   ├── DocumentController
    │   │   └── DocumentSessionStore
    │   ├── ResearchController
    │   │   └── ResearchFunctionController
    │   ├── WindowPresentationRouter
    │   └── typed WindowIntent routing
    └── separate-window routing by stable window ID
```

`WorkspaceRuntime` has live and snapshot configurations. Live activation
reuses one Triptych runtime and one vault runtime per stable identity, owns
watchers and derived refresh, and remains alive while any app window needs it.
Snapshot activation performs bounded one-shot loading and starts no watcher;
the CLI creates and deterministically shuts down one snapshot runtime per
invocation.

Application internally composes a concrete `WorkspaceHandle`. The macOS
adapter converts it to `DocumentUseCases`, `DiscoveryUseCases`, and
`ResearchUseCases` protocol values plus immutable identity and assignment
values; the adapter's raw-handle helpers are private and `WindowModel` never
stores the handle. `WorkspaceStore` coalesces concurrent explicit and
event-announced installation of the same runtime, establishes and retains the
one event subscription, then publishes the completed capability activation
without another suspension point. Every
event subscription begins with a complete `WorkspaceSnapshot`; accepted later
events carry increasing generations.
Commands remain direct capability calls, not messages on a generic event bus.

`WorkspaceStore` owns one live runtime, one accepted event subscription per
active Triptych, immutable GUI snapshots, the cross-window editor-flush
registry, and macOS presentation adapters. CSS/App Support persistence,
Obsidian appearance reads, and Zotero HTTP remain behind Application actors.
Each window receives a complete activation atomically, so a runtime replacement
cannot mix capability actors from different generations. It owns no Core
repository, index, watcher, or research store.

The Beta agent-application handoff is one app-wide macOS presentation adapter
owned by `WorkspaceStore`. `AgentApplicationHandoffController` coordinates the
copy-first UI state, explicit `NSOpenPanel` selection, launch result, and
recovery actions. `MacAgentApplicationSystem` alone resolves the app-scoped
security bookmark and invokes `NSWorkspace`; the remembered reference is a
small mode-0600 Application Support preference, never Triptych or vault state.
No Application or Core use case receives the selected application or launch
result, and no Function record treats launch as execution state.

Each `WindowModel` is the per-window composition and focused-command root. It
owns Triptych assignment, the ordinary Search scope and temporary Find
invocation, session restoration, presentation routing, and closed cross-feature
intent routing. `DocumentController` alone owns the selected document, including
path-only Unclassified and identity-recovery selections. It also owns the
per-window document workflow projection: presentation requests, save failure,
identity recovery, Human Review and Comment state, and lifecycle generations.
`ResearchController` owns research-request generations, Dialogue initial-note
projection, checkpoint listing failures, and durable recovery listing state.
`WindowModel` exposes these only as computed projections for composition and
focused commands. It owns no
duplicate window-tab membership or selection, navigation history, or Recent
Notes state. Document state, Search state, and modal presentation remain
independent per window. Library browsing, folder disclosure, Library selection,
Sidebar visibility, Apparatus visibility, and Apparatus mode are outer-window
state and never belong to a Document tab. Controllers never mutate one
another. Settings uses the separate
`WorkspaceSettingsModel` and does not construct a document window. Its
delivery-neutral capability boundary is divided into workspace, machine,
Zotero, and Research Guidance groups rather than one omnibus operation bag.

Each workspace window owns one `DocumentTabController`. The middle
`NSSplitViewItem` contains an `NSTabViewController` whose child view controllers
are document pages. Its tab style is `.unspecified`; a Document-owned selector
inside the middle column supplies the visible tab strip. `.unspecified` is a
required ownership boundary, not an aesthetic choice: AppKit's `.toolbar` tab
style replaces `NSWindow.toolbar` and makes the tab controller its delegate,
which would create a second toolbar owner and discard Scholium's approved
workspace toolbar composition. Opening or selecting a
Document tab never creates another `WindowGroup`, `NSWindow`, `WindowModel`,
split controller, Library, or Apparatus. `DocumentTabController` owns only tab
order, selected tab identity, and the document reference for each tab.
`DocumentController` and `DocumentSessionStore` retain exact document/editor
sessions. Selecting a tab activates the matching session after the existing
flush and reconstruction guard. Apparatus data is derived from the active
document while its visibility and mode remain window-owned. **New Window** is
the separate route that constructs another complete workspace shell.
`WindowSessionSnapshot.selectedDocument` is the sole restored document;
historical tab, Back/Forward, and Recent Notes fields exist only in the bounded
decoder and disappear on the next encode.

Every configured workspace scene constructs exactly one
`ScholiumWorkspaceSplitView`, whose
AppKit representable owns one `NSSplitViewController` with three sibling
`NSSplitViewItem`s. `NSHostingController`s embed the existing Library,
Document, and Apparatus SwiftUI feature roots directly. All three hosts retain
their normal AppKit sizing negotiation; none adds wrapper controllers,
centering corrections, live width bindings, one-time opening frames, or
Scholium-defined split-item minima and maxima. Library retains native
semantic-sidebar behavior and AppKit owns its initial width, compression, and
user-drag limits.

Apparatus remains a genuine contextual Inspector created with
`NSSplitViewItem(inspectorWithViewController:)`. Production construction does
not mutate the Inspector item's thickness, preferred fraction, holding
priority, collapse policy, full-height layout, safe-area adjustment, or
titlebar-separator style. Subsequent visibility changes use AppKit's standard
`.toggleInspector` toolbar item or `NSSplitViewController.toggleInspector(_:)`,
leaving animation, divider response, sibling resizing, and toolbar tracking to
AppKit. Because the representable's nested controller is not guaranteed to be
in the window's first-responder chain, the toolbar controller bridges the
automatically created standard item's command into the same window-owned
visibility state used by the View menu. The exact registered split controller
then performs AppKit's native `toggleInspector(_:)` transition. Responder-based
auto-validation is disabled for this bridged item, and
`DocumentController.selectedDocument` supplies its availability without
introducing Inspector geometry or a second visibility owner. The split item's
collapsed state is authoritative. `WindowModel`
mirrors the observed visibility for menus and the next window session; it does
not reassert that state on key-window transitions and never observes,
publishes, restores, or writes Inspector width. The exact-window registry
exposes only the live split view needed by the native toolbar's tracking
separators and visibility commands.

The Inspector may project backlinks, related notes, Research Status, metadata,
provenance, Dialogue or Critique status, and other current-note context. It may
navigate or open another note in the Document tabs, but it never owns a document
buffer, editing, autosave, undo, or conflict state. Those remain exclusively in
the Document surface and its existing controllers.

The application uses a platform-translation gate before changing window or
container architecture. A researcher description establishes the intended
visible behavior, not the implementation mechanism. Engineering must first:

1. name the state that should remain stable and the content that should change;
2. inspect the current ownership and controller hierarchy;
3. verify the applicable public AppKit or SwiftUI container contract against
   current documentation and a minimal isolated prototype;
4. record which controller owns lifetime, selection, persistence, and layout;
5. integrate the proven container without parallel state or geometry owners.

For content tabs, AppKit's established `NSTabViewController` contract is the
mechanism authority: each page is a child view controller and selection
replaces only that page. The mechanism prototype is not visual authority for
the production toolbar or selector. `NSWindowTabGroup` is rejected for this requirement
because its selected member is an entire `NSWindow`; SwiftUI `WindowGroup` is
also rejected because every opened scene receives new scene-local state.
Scholium does not adopt `NSDocument` as a second persistence owner: exact
Markdown, autosave, external-change conflicts, and recovery remain in the
existing Application and Document boundaries.

Bootstrap is a separate data-routed SwiftUI `WindowGroup` and never constructs
the workspace split or toolbar. Its narrow `ScholiumBootstrapModel` owns only
launch resolution, the first/new/missing-registration configuration purpose,
and `WorkspaceSetupView`; it never creates `WindowModel`. Successful
configuration opens one data-routed workspace scene and then dismisses
Bootstrap; failure leaves Bootstrap and its setup state intact. When a
configured Triptych still exists but one folder authorization is unavailable,
the existing workspace presents a typed, single-task Restore Access sheet and
replaces only that failed authorization. It never redirects that condition to
the five-step Bootstrap flow.

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

`ScholiumContracts` owns `ResearchFunctionID`, Target, Material, Whole/Passage
scope, Fidelity checks, availability and repair reason codes, prepared runs,
completion submissions, fingerprints, and the narrow `ResearchFunctionUseCases`
protocol. `ResearchUseCases` is the workspace-level composite of record,
checkpoint, skill, function, and Recommended Bibliography capabilities.
Contracts contain no labels,
symbols, package storage, YAML inspection, or UI layout.

`ScholiumApplication` owns one delivery-neutral `ResearchFunctionCoordinator`
per workspace. Its availability, preparation, resource-finalization, completion,
cancellation, and record-projection units resolve stable identities, revalidate
Target and Materials, resolve exact skill resources, coordinate checkpoints
and records, validate final fingerprints, and roll back partial preparation. A
resource-unresolved Strip request persists the normal run, checkpoint, and
Dialogue or Critique record as a read-only preflight. The agent must call
`selectFunctionResources` with explicit typed resources—or an empty base-only
selection—before mutation instructions or completion are available. Core
atomically extends that same persisted snapshot through
`finalizeFunctionPreflight`; it never replaces the run, checkpoint, record, or
preparation identity. Only the exact selected resource references and package
revisions enter the immutable execution handoff. The public
`ResearchOperations` delegates to it. Dialogue and Critique preparation enter
only through the typed Research Function API.

Write-capable preparation records only a pending Fidelity handoff. Its first
post-edit completion persists the exact final Target fingerprint as
`awaitingFidelity`, then Application creates or reuses an independent read-only
automatic Fidelity child against that final revision with the same Materials,
scope kind, Comments, and checks. This orchestration records no audit outcome:
an agent must still submit the child's actual evidence. A later parent
submission links the completed child, and Application can perform that link
automatically when identical completed evidence is already available.
Completion rejects direct Fidelity outcomes on the write run and validates the
child's identity, final fingerprints, evidence, checks, and completion before
monotonically advancing the parent. Exact evidence keys reuse completed
evidence instead of storing or scheduling a duplicate audit.

`ScholiumCore` keeps authorities separate: `ResearchSkillStore` owns package
discovery, metadata, bindings, and fingerprints; `ResearchWorkflowAssembler`
owns dependency closure and instruction assembly; `TriptychCheckpointStore`
owns checkpoint and recovery; Dialogue, Critique, and Human Review retain
separate stores; repositories remain the only exact revision-checked document
mutation authority. `RecommendedBibliographyStore` alone owns atomic portable
`.scholium/recommended-bibliography.json` state and never reads or writes note
bytes or Zotero. No omnibus function store is introduced.

`ScholiumCLI` decodes Contracts requests, invokes the same Application use
cases as the app, and encodes results for `function available`, `prepare`,
`show`, `select-resources`, `complete`, `prepare-fidelity`, and `cancel`.
No pre-1.0 Function command aliases remain. Preparations and completions expose delivery-neutral
`AgentCommandAction` argument vectors; CLI rendering never moves routing or
write policy into the delivery target. Separate `bibliography prepare`, `show`,
`complete`, and `cancel` commands delegate through
`RecommendedBibliographyUseCases`. The CLI never duplicates eligibility, skill
routing, checkpoint, or write-set policy.

`CommandLineToolInstaller` is an app-wide Application capability. It verifies
and atomically copies the packaged `Contents/Helpers/scholium` executable into
the user-local command directory and refuses symbolic-link destinations. The
Settings feature receives status/install closures only; SwiftUI does not copy
executables or inspect the filesystem. Packaging and QA scripts build and sign
the app and its helper together.

All SwiftPM scratch directories and Xcode DerivedData directories live beneath
the repository-local, ignored `.build/` directory. Development uses SwiftPM's
standard `.build` layout; verification, QA, localization, packaging,
performance, and upgrade-safety workflows use separate subdirectories so they
cannot delete one another's cache or index. This is safe only because the
checkout lives outside File Provider-managed Desktop, Documents, and
CloudStorage locations. Build caches and indexes must not be redirected to
`/tmp`.

The App keeps `ResearchController` as the per-window feature root. Its owned
`ResearchFunctionController` contains only the immutable active Target, panel
draft, selected Materials, scope, selected Comments and Fidelity checks,
progress, cancellation, errors, presentation identity, and stale-response
tokens. A narrow `ResearchFunctionClient` combines document flush and current
selection capture with async use-case closures at the window composition root;
the controller owns no repository, filesystem, document controller, or
authoritative research data.

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
outer split. `ScholiumWorkspaceSplitRegistry` weakly associates the exact window with
that split so the native toolbar can track both dividers without participating
in width calculation.

Research Record is a separate SwiftUI `UtilityWindow`. An app-level
presentation coordinator weakly retains the exact `WindowModel` that explicitly
opened it; this survives the utility window becoming key without copying or
extending the lifetime of document state. The window projects Human Review,
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
slice. Contracts carry the expected revision, complete proposed package,
evaluation, and confirmation token; Application enforces explicit request and
confirmation. Core validates the proposal against the same bounded package and
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
- retained scroll position;
- autosave and in-flight save tasks with stale tokens;
- rendered Read projection state; and
- save error, conflict, retry, and comparison presentation state.

CodeMirror remains authoritative while editing. The boundary uses full-buffer
reads, delta-mirror comparison, fingerprint-gated save, committed-text
synchronization, conflict comparison, and flush-before-agent-work. The Swift
model retains these facts across SwiftUI view reconstruction; it never
reconstructs writable Markdown from HTML, parsed YAML, or another projection.
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

After WebKit content-process termination, the retained session reloads its
controlled document and restores a matching bounded CodeMirror snapshot. If
that snapshot is unavailable, it reconstructs from the checked mirror and last
selection; it never rereads disk over a dirty buffer. Undo-history loss is
reported separately from source loss.

Add Comment is not a Markdown transformation: it captures an exact source
selection, opens the role-valid Review or Critique panel, and focuses its
anchored composer. `Command-F` opens Scholium's shared **This Note** Search;
the embedded CodeMirror Find panel is not part of the product.

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
- `ScholiumMetrics.Workspace` owns preferred and minimum configured-workspace
  window measures;
- `ScholiumMetrics.Document` owns the readable document measure; and
- `ScholiumMetrics.ContextSurface` owns the shared document-control geometry.

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
exact-window registration, and collapsed-geometry reconciliation, but no
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

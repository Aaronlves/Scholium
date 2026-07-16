# Implementation Architecture

**Scope:** module, runtime, state-ownership, and delivery boundaries  
**Product authority:** [PRODUCT_GUIDE.md](PRODUCT_GUIDE.md)  
**Interface authority:** [DESIGN_HANDBOOK.md](DESIGN_HANDBOOK.md)  
**Requirements authority:** [PRD.md](PRD.md)

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
    └── WindowModel (one per window)
        ├── DiscoveryController
        ├── DocumentController
        │   └── DocumentSessionStore
        ├── ResearchController
        │   └── ResearchFunctionController
        ├── WindowPresentationRouter
        └── typed WindowIntent routing
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
values; `WindowModel` never stores the handle. Every event subscription begins with a complete
`WorkspaceSnapshot`; accepted later events carry increasing generations.
Commands remain direct capability calls, not messages on a generic event bus.

`WorkspaceStore` owns one live runtime, one accepted event subscription per
active Triptych, immutable GUI snapshots, the cross-window editor-flush
registry, and macOS presentation adapters. CSS/App Support persistence,
Obsidian appearance reads, and Zotero HTTP remain behind Application actors.
Each window receives a complete activation atomically, so a runtime replacement
cannot mix capability actors from different generations. It owns no Core
repository, index, watcher, or research store.

Each `WindowModel` is the per-window composition and focused-command root. It
owns Triptych assignment, navigation, tabs, Recent Notes, session restoration,
presentation routing, and closed cross-feature intent routing. Discovery,
Document, and Research controllers own their independent window state and
borrow only their matching Application capability. Controllers never mutate
one another. Settings uses the separate `WorkspaceSettingsModel` and does not
construct a document window.

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
protocol. `ResearchUseCases` remains a compatibility composite of record,
checkpoint, skill, and function capabilities. Contracts contain no labels,
symbols, package storage, YAML inspection, or UI layout.

`ScholiumApplication` owns one delivery-neutral `ResearchFunctionCoordinator`
per workspace. Its availability, preparation, method-finalization, completion,
cancellation, and record-projection units resolve stable identities, revalidate
Target and Materials, resolve exact skill resources, coordinate checkpoints
and records, validate final fingerprints, and roll back partial preparation. A
method-unresolved Strip request persists the normal run, checkpoint, and
Dialogue or Critique record as a read-only preflight. The agent must call
`selectFunctionMethods` with explicit semantic references—or an empty base-only
selection—before mutation instructions or completion are available. Core
atomically extends that same persisted snapshot through
`finalizeFunctionPreflight`; it never replaces the run, checkpoint, record, or
preparation identity. Only the exact selected resource references and package
revisions enter the immutable execution handoff. The public
`ResearchOperations` facade delegates to it. Legacy Dialogue and Critique
entry points remain compatibility wrappers while callers migrate.

Write-capable preparation records only a pending Fidelity handoff. Its first
post-edit completion persists the exact final Target fingerprint as
`awaitingFidelity`. The external agent then prepares and completes an
independent read-only Fidelity run against that final revision with the same
Materials, scope kind, Comments, and checks; a later parent submission links
the child run ID. Completion rejects direct Fidelity outcomes on the write run
and validates the child's identity, final fingerprints, evidence, checks, and
completion before monotonically advancing the parent. Exact evidence keys
reuse completed evidence instead of storing or scheduling a duplicate audit.

`ScholiumCore` keeps authorities separate: `ResearchSkillStore` owns package
discovery, metadata, bindings, and fingerprints; `ResearchWorkflowAssembler`
owns dependency closure and instruction assembly; `TriptychCheckpointStore`
owns checkpoint and recovery; Dialogue, Critique, and Human Review retain
separate stores; repositories remain the only exact revision-checked document
mutation authority. No omnibus function store is introduced.

`ScholiumCLI` decodes Contracts requests, invokes the same Application use
cases as the app, and encodes results for `function availability`, `prepare`,
`select-methods`, `complete`, and `cancel`. It never duplicates eligibility, skill routing,
checkpoint, or write-set policy.

The App keeps `ResearchController` as the per-window feature root. Its owned
`ResearchFunctionController` contains only the immutable active Target, panel
draft, selected Materials, scope, selected Comments and Fidelity checks,
progress, cancellation, errors, presentation identity, and stale-response
tokens. A narrow `ResearchFunctionClient` combines document flush and current
selection capture with async use-case closures at the window composition root;
the controller owns no repository, filesystem, document controller, or
authoritative research data.

## Source layout

- `Scholium/UI/Foundation` contains semantic color roles, metrics, shapes,
  motion, and accessibility-aware surface modifiers.
- `Scholium/UI/Components` contains stateless Scholium building blocks.
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

`ContentView` has one `.sheet(item:)` and one typed alert presentation. The
deliberate `HSplitView` trailing-context workaround remains intact.

The Research Function panel uses one typed `researchFunction` sheet route
carrying only a stable Target reference, function ID, and presentation ID. The
router owns sheet exclusivity; `ResearchFunctionController` owns the session
and draft. `NoteContentView` receives only a `ResearchStripPresentation` and an
`openResearchFunction(id:selection:)` closure. It never receives
`WindowModel`, `ResearchController`, or Application authority.

## Product Skill resources and maintenance

`Skills/` is the canonical product-skill tree. The Core resource copy is a
generated mirror checked by a dedicated sync script. The official Workflow
layer contains Development, Critique, Revision, Content Fidelity, and
Manuscript; Dialogue remains System infrastructure and Human Review has no
skill. Catalog metadata exposes supported functions, capabilities, and
citation styles while retaining supported modes only for legacy decoding and
internal method selection.

Function-method activation is a separate Settings-facing capability over the
same boundary. `ResearchFunctionSkillSelection` represents an optional primary
replacement, supplemental packages, and exact Practice selections for one
semantic function. Application lists only valid compatible Triptych-local
Researcher Skills, validates role and Practice compatibility, and performs
revision-checked saves through `ResearchSkillStore`. The assembler composes the
persisted selection into the effective phase contract. The frontend receives
friendly candidate names only in Research Guidance; the Strip and CLI never
choose package IDs.

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
legacy aliases, cross-field constraints, and validation. App
`PropertyPresentation` values add labels, help, grouping, ordering, and control
style only. Property edits are validated through Contracts and applied by
Application as targeted
`NoteDocument` changes, preserving unknown YAML, aliases, malformed-note
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
- autosave and in-flight save tasks with stale tokens;
- rendered Read projection state; and
- save error, conflict, retry, and comparison presentation state.

CodeMirror remains authoritative while editing. The boundary uses full-buffer
reads, delta-mirror comparison, fingerprint-gated save, committed-text
synchronization, conflict comparison, and flush-before-agent-work. The Swift
model retains these facts across SwiftUI view reconstruction; it never
reconstructs writable Markdown from HTML, parsed YAML, or another projection.
The typed editor protocol, source-transformation rules, and WebKit recovery
contract are documented in the subordinate
[EDITOR_ARCHITECTURE.md](EDITOR_ARCHITECTURE.md).

## Design-system implementation

[DESIGN_HANDBOOK.md §5](DESIGN_HANDBOOK.md#5-visual-language) owns palette
values, semantic meanings, typography, materials, motion, and accessibility
rules. The app implements that contract through `ScholiumColorRole`,
`ScholiumLightPalette`, `ScholiumDarkPalette`, `ScholiumMetrics`,
`ScholiumMotion`, and `ScholiumInterfaceTypography` in
`Scholium/UI/Foundation`.

Native SwiftUI/AppKit surfaces resolve semantic roles dynamically. WebKit uses
the same kebab-case role vocabulary in
`Scholium/Resources/Editor/editor.css`; `SafeMarkdownReadWebView` consumes the
same declarations. Architecture tests enforce native/WebKit role parity,
reviewed appearance mappings, contrast floors, and specialized relationship
variants. The code and tests implement the Handbook values rather than making
this document a second palette authority.

Stable geometry is named by meaning rather than number:

- `ScholiumMetrics.Triptych` owns the exact interface measures;
- `ScholiumMetrics.Document` owns the readable document measure; and
- `ScholiumMetrics.ContextSurface` owns the shared document-control geometry.

`ScholiumMotion` exposes purpose-named animations and returns no animation
when Reduce Motion is active. It does not install a global animation policy.
The existing `ScholiumInterfaceTypography` namespace remains the sole
interface typography namespace.

## Component boundaries

`Scholium/UI/Components` implements the component distinctions established by
the Design Handbook. Components remain stateless leaves receiving immutable
values and typed closures; feature roots retain state and action routing. This
document records that dependency direction, while the Handbook owns the stable
rule for when Scholium-specific components or distinct research surfaces are
appropriate.

## Boundary enforcement

`ScholiumContractsTests`, `ScholiumApplicationTests`, and the architecture and
composition suites in `ScholiumAppTests` exercise their respective module,
runtime, window, document, presentation, and design-system boundaries.
`Tools/Scripts/verify.sh` adds package-graph, source-import, I/O, and public
symbol-graph guards so delivery targets cannot reacquire Core-owned authority.

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for dated pass records,
reachable behavior, and remaining acceptance work. This document intentionally
does not duplicate test counts or claim that a historical pass proves the
current checkout.

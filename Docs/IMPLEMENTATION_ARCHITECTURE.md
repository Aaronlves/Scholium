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
    ├── WindowModel (one per complete window scene/native tab)
    │   ├── DiscoveryController
    │   ├── DocumentController
    │   │   └── DocumentSessionStore
    │   ├── ResearchController
    │   │   └── ResearchFunctionController
    │   ├── WindowPresentationRouter
    │   └── typed WindowIntent routing
    └── NativeWindowTabCoordinator (AppKit grouping by stable window ID)
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
owns Triptych assignment, the ordinary Search scope and temporary Find
invocation, session restoration, presentation routing, and closed cross-feature
intent routing. `DocumentController` alone owns the selected document, including
path-only Unclassified and identity-recovery selections. `WindowModel` exposes
only a computed projection for composition and focused commands. It owns no
custom document tabs, navigation history, or Recent Notes state. Discovery,
Document, and Research controllers own their independent window state and
borrow only their matching Application capability. Controllers never mutate
one another. Settings uses the separate `WorkspaceSettingsModel` and does not
construct a document window.

Each native macOS tab is a complete `WindowGroup` scene with its own stable
window ID, `WindowModel`, presentation router, and `DocumentSessionStore`.
`TriptychWindowRoute` carries an optional initial document and source-window
anchor ID. `NativeWindowTabCoordinator` assigns one AppKit tabbing identifier,
registers weak `NSWindow` references by stable ID, and groups an **Open in New
Tab** scene with its source window when both are available. AppKit owns tab
selection, cycling, detaching, merging, and standard Window-menu commands.
`WindowSessionSnapshot.selectedDocument` is the sole restored document;
historical tab, Back/Forward, and Recent Notes fields exist only in the bounded
decoder and disappear on the next encode.

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
`ResearchOperations` facade delegates to it. Legacy Dialogue and Critique
entry points remain compatibility wrappers while callers migrate.

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
The undocumented `availability` and `select-methods` aliases decode Beta-era
clients only. Preparations and completions expose delivery-neutral
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

The App keeps `ResearchController` as the per-window feature root. Its owned
`ResearchFunctionController` contains only the immutable active Target, panel
draft, selected Materials, scope, selected Comments and Fidelity checks,
progress, cancellation, errors, presentation identity, and stale-response
tokens. A narrow `ResearchFunctionClient` combines document flush and current
selection capture with async use-case closures at the window composition root;
the controller owns no repository, filesystem, document controller, or
authoritative research data.

Recommended Bibliography follows a separate Analysis-only capability boundary:

```text
RecommendedBibliographySection (Research inspector)
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
per-window `ResearchController`. Application locks Analysis identity and
fingerprint, snapshots the complete Source Analyzer method, validates
completion tokens and evidence, and performs conservative duplicate
discrimination without note or Zotero mutation. Core owns portable storage,
package resolution, path safety, and matching inputs. The App owns goals,
purpose, focus, stale-response rejection, refresh presentation, and compact
rows. Prior results remain visible through refresh and failure.

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
skill. Catalog metadata exposes supported functions, capabilities—including
`bibliography-recommendation`—and citation styles while retaining supported
modes only for legacy decoding and internal method selection.

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
JSON encodes `conditional_resources`. Decoders continue accepting legacy
`methods`, while new encoders and public APIs emit only resource terms.
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

- `ScholiumMetrics.Onboarding` owns the narrow first-run setup measures;
- `ScholiumMetrics.Triptych` owns the exact interface measures;
- `ScholiumMetrics.Workspace` owns configured-window preferred and minimum
  measures;
- `ScholiumMetrics.Document` owns the readable document measure; and
- `ScholiumMetrics.ContextSurface` owns the shared document-control geometry.

`ScholiumMotion` exposes purpose-named animations and returns no animation
when Reduce Motion is active. It does not install a global animation policy.
The existing `ScholiumInterfaceTypography` namespace remains the sole
interface typography namespace.

## Component boundaries

`Scholium/UI/Components` implements the component distinctions established by
the specification. Components remain stateless leaves receiving immutable
values and typed closures; feature roots retain state and action routing. This
document records that dependency direction, while the specification owns the
stable rule for when Scholium-specific components or distinct research
surfaces are appropriate.

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

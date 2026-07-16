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

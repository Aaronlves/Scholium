# Frontend Architecture

**Status:** implemented as a compiler-enforced Contracts–Core–Application modular monolith
**Product authority:** [PRODUCT_GUIDE.md](PRODUCT_GUIDE.md)  
**Interface authority:** [DESIGN_HANDBOOK.md](DESIGN_HANDBOOK.md)

This document describes implementation ownership. It does not redefine
Scholium workflows, interface labels, vault formats, or research-governance
rules.

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
- `Scholium/UI/Components` contains stateless Scholium building blocks. It
  deliberately has no generic card type.
- `Scholium/UI/PreviewCatalog` contains deterministic Debug-only component
  matrices for ready, empty, loading, error, conflict, and long-text states,
  plus named appearance and accessibility review entry points. Xcode 27
  exposes the system contrast, transparency, and motion values as read-only
  environment values, so those named entries are exercised with the Canvas
  environment controls and the isolated QA app rather than a production
  override hook.
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

CodeMirror remains authoritative while editing. Existing full-buffer reads,
delta-mirror comparison, fingerprint-gated save, committed-text
synchronization, conflict comparison, and flush-before-agent-work behavior are
unchanged. The Swift model retains these facts across SwiftUI view
reconstruction; it never reconstructs writable Markdown from HTML, parsed
YAML, or another projection.

## Design variables

The native color variables are `ScholiumColorRole` in
`Scholium/UI/Foundation/ScholiumDesignSystem.swift`. The current roles are:

`documentBackground`, `navigationBackground`, `surfaceBackground`,
`raisedSurfaceBackground`, `primaryText`, `secondaryText`, `mutedText`,
`separator`, `accent`, `accentHover`, `notificationHighlight`, `attention`,
`information`, `attentionForeground`, `destructive`, `destructiveForeground`,
`confirmed`, `confirmedForeground`, `agentAuthorship`, `connectionNeutral`,
`connectionSupport`, and `connectionIncompatible`. The `Foreground` status
roles resolve to the same normal-appearance semantic color and to the reviewed
stronger variant under Increase Contrast.

`ScholiumLightPalette` and `ScholiumDarkPalette` are the reviewed primitive
palettes beneath those roles. Feature and component code consumes semantic
roles, never primitive swatches or literal hex values. The principal mapping
is:

| Semantic role | Light | Dark | Use |
| --- | --- | --- | --- |
| Document | `#FFFCF5` | `#302A26` | Ivory Leaf / Walnut opaque reading surface |
| Navigation | `#EFE9DF` | `#3A2B2B` | Parchment / Cordovan navigation fallback |
| Surface | `#F7F1E7` | `#3A322D` | Vellum / Leather opaque panel fallback |
| Raised surface | `#DED3C5` | `#423831` | Selected, hovered, or raised emphasis |
| Primary text | `#17191C` | `#F4E8D5` | Carbon Ink / Parchment prose and labels |
| Secondary text | `#514D48` | `#D4C2AD` | Descriptions and secondary information |
| Muted text | `#706B65` | `#B6A38F` | Metadata and quiet icons |
| Separator | `#C8BCAE` | `#807064` | Binding rules and structural boundaries |
| Accent | `#A94C22` | `#EF8D5B` | Vermilion/Luminous Copper actions, links, and active emphasis |
| Accent hover | `#7A2917` | `#F5AA7B` | Hover, pressed, and stronger accent emphasis |
| Notification | `#B47617` | `#E1B64F` | Ochre highlights and new-item emphasis; not warning |
| Information | `#315F88` | `#84B0D4` | Lapis informational and source-location cues; not evidence |
| Attention | `#976015` | `#E0AB61` | Stale state, caution, and needed attention |
| Confirmed | `#2C7048` | `#7FC39A` | Confirmed positive workflow state only |
| Destructive | `#A13235` | `#EA817C` | Failures, blockers, destructive effects, and Unqualified status |
| Agent authorship | `#5D568F` | `#B5A6DC` | Redundant violet provenance cue; explicit text remains required |
| Connection support | `#276F68` | `#79B9AB` | Teal philosophical support relationship |
| Connection incompatible | `#6F4D83` | `#C29CCF` | Plum philosophical incompatibility relationship |

Native code resolves every role through dynamic `NSColor` and `Color`; both
palettes and their reviewed stronger variants respond to SwiftUI's Increase
Contrast environment. Teal support and plum incompatibility remain specialized
relationships so they cannot be mistaken for green success or red failure.
Agent authorship remains explicit text with violet as a redundant cue. WebKit
uses matching `prefers-color-scheme` and `prefers-contrast` variants and the
same kebab-case vocabulary, for example
`--scholium-color-primary-text`, in
`Scholium/Resources/Editor/editor.css`. `SafeMarkdownReadWebView` consumes the
same contract. `FrontendArchitectureTests` fail if the native and editor
vocabularies diverge, either reviewed palette drifts, foreground contrast falls
below the handbook threshold, or normal and increased-contrast relationship
values drift.

Stable geometry is named by meaning rather than number:

- `ScholiumMetrics.Triptych` owns the exact interface measures;
- `ScholiumMetrics.Document` owns the readable document measure; and
- `ScholiumMetrics.ContextSurface` owns the shared document-control geometry.

`ScholiumMotion` exposes purpose-named animations and returns no animation
when Reduce Motion is active. It does not install a global animation policy.
The existing `ScholiumInterfaceTypography` namespace remains the sole
interface typography namespace.

## Component rule

Extract a value or component only when it encodes a stable handbook rule, a
recurring semantic role, or meaningful reuse. Local geometry stays local.
Native controls remain direct when Scholium adds no domain semantics. Review,
Critique, Dialogue, Comments, and evidence remain distinct surfaces rather
than variants of a generic card.

## Tests and verification

`ScholiumContractsTests` covers exact BOM/CRLF bytes, YAML/source fidelity,
Codable compatibility, stable identifiers, requests, and structured errors.

`ScholiumApplicationTests` covers live-runtime identity reuse, snapshot mode
without watchers, initial snapshot delivery, event ordering and generation
gating, runtime replacement, cancellation, deterministic shutdown, capability
operations, and GUI/CLI result parity.

`ScholiumAppTests` depends on the executable target. Its architecture and
composition suites cover:

- sheet-route exclusivity, route-aware dismissal, alerts, and file import;
- document identity retention and per-window independence;
- retained conflict state;
- Search stale-result rejection and Quick Open cancellation;
- mutually exclusive Research Inspector and Note History state;
- Scholia presentation identity, action/state transitions, and stale-dismissal
  rejection;
- document-session work retention across view reconstruction; and
- two real windows sharing runtime services while retaining independent
  document, search, presentation, focus, and cancellation state;
- clean-peer convergence, exact dirty-buffer conflict retention, stable-identity
  rename migration, one-window teardown, and final runtime shutdown;
- Settings construction without a `WindowModel`;
- Contracts Property-contract to app-presentation one-to-one resolution; and
- rejection of direct repository, index, watcher, research-store, or Zotero
  MCP/server-authority construction in the App and CLI targets;
- native/WebKit semantic color parity and increased-contrast variants.

Contracts remains the authority for exact-source values, conflict vocabulary,
identity, and deterministic semantics. Core remains the internal repository,
search-index, watcher, and persistence implementation. Package-graph, source,
I/O, and public-symbol-graph gates prevent those boundaries from regressing.

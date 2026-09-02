# Architecture: Source Layout and Presentation

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Source layout,
native presentation, interface composition, and localization.

## Source layout

- `Scholium/UI/Foundation` contains semantic color roles, metrics, shapes,
  motion, and accessibility-aware surface modifiers.
- `Scholium/UI/Components` contains stateless Scholium building blocks plus
  the bounded native window-shell adapters described below.
- `Scholium/UI/PreviewCatalog` contains deterministic Debug-only presentation
  proofs. It resolves or mutates no production state and does not enter the
  released interface.
- `ScholiumContracts` contains boundary values, capability protocols,
  deterministic source transformations, immutable snapshots, events, and
  delivery-safe errors. It has no filesystem, database, network, UI, watcher,
  store, or global mutable authority.
  `LinkResolutionCatalog` reuses fail-closed Note, heading, and block lookup
  without building a Graph edge.
- `ScholiumCore` contains internal I/O and persistence implementations plus the
  app-default method resource bundle; it is not a public SwiftPM product.
- `ScholiumApplication` contains runtime configuration and pooling, capability
  actors, the typed event stream, CSS/App Support I/O, Obsidian appearance
  projection, and Zotero transport.
- `Scholium/Features` contains the Discovery, Document, Research, Properties,
  and Settings delivery controllers and per-window editor sessions.
- `Scholium/App/Window` contains `WindowShellState`,
  `WindowCommandObservation`, `WindowEditorFlushCoordinator`, mutually
  exclusive window presentation
  routing, and the document-transition,
  presentation-persistence, workspace-session, and immutable-projection
  coordinators. These coordinators do not duplicate a feature controller or
  writable document owner.
- Feature-root view files remain inside `Scholium/Views`. The application and
  window roots may receive the complete `WindowModel`; feature roots receive
  their one controller, and reusable leaves receive immutable values and
  closures.
- `Scholium/Resources/Artwork` contains approved product illustrations rather
  than identity or state authority. One Bootstrap artwork owner combines the
  fixed Point, Offer, Unlock Straight, and Lift hand assets with SwiftUI-drawn
  Flow or Converge geometry. All compositions are decorative, noninteractive,
  and absent from accessibility.

## Presentation

`WindowPresentationRouter` owns four typed channels:

- one mutually exclusive `WindowSheetRoute`;
- composable `WindowOverlayRoute` values for loading and Search;
- one `WindowAlertRoute`; and
- one typed `WindowFileImportRequest`.

Replacing a sheet route replaces its complete payload atomically. Conditional
dismissal uses the route identity, so a stale callback cannot dismiss a newer
sheet. Route payloads carry note paths only as navigation projections; they do
not own document sessions. Note creation is not a sheet route; file-operation
sheets remain only for operations that require a destination, name, or bounded
destructive confirmation. An immutable `NoteMutationTarget` carries exact path,
stable identity, and revision into system-Trash preparation. A committed
native move removes the absent Note's document page; if it was selected, the
Document controller clears selection and the native tab container presents its
existing no-document host without implicitly activating another page. The
native Outline cell retains ordinary selection, context-menu, drag, and
accessibility behavior; SwiftUI supplies one semantic command projection. The
system-Trash command opens the single typed confirmation route and does not
mutate source from row presentation.

`ContentView` has one `.sheet(item:)`, one typed alert presentation, and one
persistent `ScholiumWorkspaceSplitView` root for each configured workspace
window. Its bounded AppKit bridge creates the three-item split described above;
role-owned backgrounds fill each container while Library, Document, and
Apparatus content stays foreground in the live safe area. Bootstrap never
constructs this split. Loading and document states replace hosted content, not
the shell. Only the selected Triptych workspace's tab group enters the one
central `NSTabViewController`; inactive groups stay in the window-local
`DocumentTabController` and receive no native host or accessibility projection.
The composition root passes the complete `WindowModel` explicitly;
`ContentView` observes the presentation, Search, Research, Document, tab,
projection, CSS, and workspace-session owners it actually
reads, while reusable feature leaves remain on narrow values/controllers.
`WorkspaceWindowCoordinator` receives the exact window and split,
installs toolbar/delegate state, and registers readiness/flushing. Search,
notification, polling, delayed correction, and width calculation do not
participate in constructing that workspace split.

Research Records use a separate value-keyed `WindowGroup`, one scene identity
per Triptych. `ResearchRecordsWindowCoordinator` routes an exact Record/step
selection to the existing scene but retains no research data. The window uses
an AppKit-owned resizable split: a quiet scanning collection, centered
scholarly reading plane, and optional evidence rail. Its only text input is the
Record-provider Search field; step content is a read-only bounded Markdown
projection. Paragraphs, emphasis, strong text, inline code, lists, blockquotes,
and ordinary links render semantically. Headings and unsupported constructs
remain visible literal source.

Bootstrap, configured Workspace, and Settings scene roots each own one
`ScholiumFileSelectionPresenter`. A bounded native attachment supplies that
presenter with the exact scene window; it serializes one `NSOpenPanel` sheet at
a time and never searches application windows or presents app-modal UI. Feature
views provide typed file-or-directory intent and retain all workflow policy,
error presentation, bookmarks, imports, registration, and writes. The shared
request configures the native panel and validates its returned item kind; an
exact-directory constraint also canonicalizes aliases and rejects every sibling
path before the feature may treat access as renewed or authorized.

The Bootstrap root uses a transparent hidden-title titlebar over one full-size
content view. Its Welcome, Triptych, and Ready stages share one
adaptive full-bleed illustration field beside a linear native task pane and
fixed footer; narrow windows move the field above the task. Triptych folder
selection and bounded authorization remain the registration owner's native
controls behind the specified path cards and review pages. An
Application-owned structure preparer exclusively creates a confirmed new root
and its four fixed children; it refuses an existing destination. The setup view
returns a registration failure to the retained Triptych review and keeps
workspace routing closed until registration completes. Ready explicitly opens
the configured workspace.

Agent conversation and tool selection live in the configured external host.
Scholium has no chat, Agent lifecycle, Run, or portable result browser. The
Settings **Agent Integration** destination shows exact Codex and Claude Code MCP
registration commands and reveals the bundled Core Protocol Skill. It does not
store credentials or choose an Agent application.

Each workspace window may present machine-local **Agent Changes**. The view
reads `AgentChangeSummary` values recorded by successful MCP mutations and
compares exact before and after source where both revisions remain available.
Direct Update is available only after Application revalidates the target and
performs the exact write. Undo is bounded to the recorded after fingerprint and
becomes unavailable as soon as authoritative source diverges. Agent Changes
owns no portable research history and is not a source of truth.

Notifications is one native transient SwiftUI popover owned by each exact
`WindowModel`, not an app-wide Scene, sheet, inline Library destination,
utility panel, or always-on-top surface. Per-workspace
`AttentionPresentationState` projects structural and Settlement attention from
current immutable state. The machine-local dismissal ledger changes
presentation only. No queue item authorizes a source mutation, and the
Document toolbar consumes no notification state.

Ordinary workspace navigation uses a workspace-keyed
`DiscoveryLibraryRequest(.stagedReplacement)`. `DiscoveryController` retains
one Library state and one in-flight request per Triptych workspace, so a later
request supersedes only the same workspace. `WindowModel` first flushes the
active editor, stages the destination vault and Library projection, validates
its retained selected tab, and only then commits Shell selection, the
destination tab group, Document mode, and Inspector mode. Rapid requests
converge on the last requested workspace.

The Research Inspector receives immutable Overview and Connect presentation
values composed at the window root. It owns no workspace refresh, Agent
conversation, mutation, or lifecycle state. Its modes share the one native
trailing split item and one mode value per Triptych workspace; changing modes,
notes, or tabs never reconstructs the retained Document host. Overview contains
resolved About configuration, current Settlement state, and any portable Zotero
binding for the selected Analysis. Field-local edits delegate to the portable
Metadata revision owner or, after editor flush and target revalidation, to the
exact-source writer. File timestamps remain read-only snapshot facts.

`ConnectionsInspectorView` owns one nonpersistent link direction. The shared
segmented component projects the same immutable directed occurrence graph into
Incoming or Outgoing rows. Each authored occurrence appears once in the chosen
projection with its exact annotation, context, and source locator; no endpoint
pair is collapsed or classified. Peer-role headings and occurrence rows use one
flat scan hierarchy. Direction changes retain major-group
disclosure and return the sole Connect scroll owner to its beginning.

When the split item remains visible without a selected Document, the
composition root installs a read-only Apparatus content-state projection rather
than an empty host or stale Inspector leaf; the split controller remains the
sole visibility owner.
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
translation surface. App-default and researcher-owned Skill names
render verbatim; surrounding application labels and explanations
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

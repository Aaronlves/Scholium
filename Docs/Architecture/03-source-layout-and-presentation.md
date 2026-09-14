# Architecture: Source Layout, Presentation, and Shared Boundaries

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Source layout,
native presentation, interface composition, integrations, and shared boundaries.

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
  app-default Skill resource bundle; it is not a public SwiftPM product.
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
- `WindowOverlayRoute` for loading;
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
role-owned backgrounds fill each container while Library and Apparatus content
stays foreground in the live safe area. The Document reading and writing scroll
plane may continue beneath the integrated native toolbar; its initial readable
content stays clear through the existing Document content inset. Bootstrap never
constructs this split. Loading and document states replace hosted content, not
the shell. The window-wide document collection enters one central
`NSTabViewController`; its native content tabs render selection while the
window-local `DocumentTabController` retains membership and guarded selection.
The composition root passes the complete `WindowModel` explicitly;
`ContentView` observes the presentation, Search, Research, Document, tab,
projection, CSS, and workspace-session owners it actually
reads, while reusable feature leaves remain on narrow values/controllers.
`WorkspaceWindowCoordinator` receives the exact window and split,
installs toolbar/delegate state, and registers readiness/flushing. Search,
notification, polling, delayed correction, and width calculation do not
participate in constructing that workspace split.

`WindowSearchController` owns the inactive/sidebar/advanced presentation and
explicit focus requests as well as execution and saved-query lifecycle.
`ResearchSearchSurface` observes its existing controllers in both presentations.
`ResearchSearchView` keeps the Library mounted while showing quick results;
`ResearchSearchField` gives composition and responder behavior to `NSSearchField`.
`WorkspaceWindowCoordinator` owns one `AdvancedSearchWindowController`, which
owns only its native auxiliary window and closes with the source workspace.
Both surfaces project the same query, scope, and results; there is no centered
Search overlay or second query engine.

`ScholiumTriptychWorkspaceNavigator` wraps `WorkspaceSegmentedControl`, an
`NSSegmentedControl` that projects the three role destinations. Native layout
adapts complete labels to symbols; the coordinator publishes only selection
intents. It is not a vertical workspace table or a custom selection plate.

`ContextSearchField` lets AppKit own search text entry and its magnifying-glass
options menu; query/scope values and commands come from the feature model.
Notification consumers reuse that native presentation.

`NativeResearchTable` presents destination Notes and Agent Change collections.
Feature models retain rows and selected identity. AppKit owns single selection,
row reuse and column allocation: the first column autoresizes, secondary columns
retain their supplied widths, and header dragging is disabled. SwiftUI owns the
containing sheet lifecycle; the table never reads or resizes its window.

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

Agent execution and tool selection remain in the external runtime. Optional
Triptych-level Chat uses the official Codex App Server client described in the
Agent architecture chapter; it adds no Run or portable result browser. The
Chat presentation uses standard `GroupBox` content groups and macOS grouped
`TabView` navigation for Agent activity/details and context/account usage.
Tab selection belongs only to the containing view; the child composer remains
outside the tab subtree. Cards borrow existing request, material and execution
values and add no transport, storage, policy or animation coordinator. Native
symbol replacement is scoped to the delivery indicator; reduced motion keeps
its textual state without an animated replacement.
Chat's progressive reply reveal uses CSS Highlights over appended prose. The
reader compares its previous sanitized HTML in an inert template and advances
complete grapheme ranges without changing text nodes or queueing runtime output.
Native Chat owns eligibility and cancellation through the generation-bound reader
bridge. Selection, adaptation and teardown immediately expose the complete text.
The
Settings **Agents & Chat** destination shows exact Codex and Claude Code MCP
registration commands and reveals the bundled Core Protocol Skill. It does not
store credentials or choose an Agent application.

Each workspace window may present machine-local **Agent Changes**. The view
reads the window `ResearchController`'s borrowed `AgentChangeSummary` values
recorded by successful MCP mutations and
compares exact before and after source where both revisions remain available.
Direct Undo is available only after Application revalidates the target and
performs the exact write. Undo is bounded to the recorded after fingerprint and
becomes unavailable as soon as authoritative source diverges. Agent Changes
owns no portable research history and is not a source of truth.

Notifications is one native transient SwiftUI popover owned by each exact `WindowModel`,
not an app-wide Scene, sheet, inline Library destination, utility panel, or
always-on-top surface. Per-workspace `AttentionPresentationState` projects structural
and Settlement attention from current immutable state. The machine-local dismissal
ledger changes presentation only. No queue item authorizes a source mutation, and the
Document editing controls consume no notification state. Its bell anchor is a stable
native toolbar item; the nonzero dot is only a presentation of the existing exact queue.

`SystemNotificationService` owns App-level macOS delivery. The mutation router
submits confirmed results; Chat submits live terminal/input events with a
conversation-owned validity check through its injected notification sink. The
service does not infer events from per-window refresh or retained history.
`UNUserNotificationCenter` is attached at launch, with authorization
requested on the first eligible background event. Coalescing, activation
cancellation and delegate suppression govern delivery. `SystemNotificationRoute`
contains an exact Agent Change route or a Chat route with only opaque local IDs
and event category. One transport, authorization task and coalescing owner serve
both. Chat validity is checked before prompting and again before delivery. The
receiving window revalidates the receipt or loads/selects the exact retained
conversation; cold-window handoff is memory-only and consumed once. Chat opening
requests Sidebar visibility through the existing native window action, without
moving the document or toggling an already visible Chat closed.
`WindowShellState` retains persistent operation issues without expiry;
`ScholiumOperationIssueView` renders them in the Document region. Settings errors
remain with their field/save owner. No delivery result changes source authority.

Ordinary workspace navigation uses a workspace-keyed
`DiscoveryLibraryRequest(.stagedReplacement)`. `DiscoveryController` retains
one Library state and one in-flight request per Triptych workspace, so a later
request supersedes only the same workspace. `WindowModel` first flushes the
active editor, stages the destination vault and Library projection, validates
the request identity, and only then commits Library and Shell selection.
The current Document, tabs, and document mode remain unchanged. Rapid requests
converge on the last requested workspace.

`ResearchInspectorView` composes Links and Related Material in one trailing
split item. It owns no source or mutation state. Zotero occurrences are a
read-only Markdown projection, refreshed with the selected Note fingerprint.
File links and image embeds stay in the Document; Quick Look uses an explicit
bounded access lease. `SettlementPresentation` supports the existing toolbar
judgment command independently of the Inspector. There is no About field session
or Metadata departure flush; the ordinary editor owns all source drafts.

`WindowShellState` owns Links/Related Material selection. Its icon-only toolbar
control uses AppKit segments; `InspectorLinkDirectionControl` uses native
capsule segments with system-owned selection. `ResearchInspectorLayout` owns
the common content edge and top spacing for these panes; `ResearchListStyle`
owns the native list-row insets.
`LinksInspectorSession`, retained by the window's ResearchController, owns the
link direction and per-Note/direction query, collapsed Note groups and scroll
position. `ConnectionsInspectorView` filters an immutable occurrence projection;
each link keeps its exact source locator and context. It never creates another
graph or source owner. Native buttons and fields keep system presentation on the
Paper content background; feature code paints no competing control theme.

`RelatedMaterialsSession`, retained by ResearchController, owns one disposable
selection or paragraph context, debounced selection/idle-paragraph scheduling, request generation,
loading/error state, ranked passages grouped by Note and a revocable insertion receipt per window. Both Inspector panes share ResearchListStyle for native List and row geometry.
The Related pane uses native List rows and trailing swipe actions with full-swipe
execution disabled; SwiftUI owns their transient reveal lifecycle. The visible pane subscribes to the retained
editor's context events, revokes insertion on change and cancels work when hidden.
Readable cards retain their original context within the same Note until a replacement query succeeds.
During retrieval, ResearchSkeletonPulse animates initial skeletons or redacted retained
rows; those rows expose no actions until retrieval ends. Reduce Motion stops the pulse.
ResearchController synchronously observes DocumentController's incoming editing target;
a changed or absent target resets the complete recommendation session, even while hidden.
Publication checks the selected document and workspace runtime; automatic publication
also checks editor focus and mode. Pointer interaction cancels pending
updates; editor activity resumes following even with a stationary pointer. A stale
response triggers one index refresh and retry. Equal cards are retained and unchanged seeds refresh only the caret receipt.
`WindowRelatedMaterialsActions` captures the retained editor context and calls
`DiscoveryOperations.relatedContent` through the active workspace. WorkspaceHandle
uses `relatedMaterialSourceCandidates` to enumerate every eligible lexical source,
reads fingerprint-matched exact Notes without a Note-result cutoff, and delegates
Note ordering, paragraph selection and bounded match-centered excerpts with checked
readable-text highlight ranges to Core Search over the shared semantic parser.
`RelatedContentBM25F` owns the common field weights, per-field length normalization
and saturating term scoring for both stages. `SearchTextSegment` persists the
semantic projection's mutually attributed ranking text with the disposable index;
ordinary Search clauses and exact offset maps remain unchanged. Each comparison
set owns its statistics. Full-Note metadata affects Note ordering; local paragraph
scores select excerpts within each eligible Note. One passage per Note is emitted
before additional passages. YAML never becomes a material result.
Each result carries exact Markdown, its source range and a separate readable-text
projection. `ResearchExcerptPresentation` is shared with Links and Chat excerpts;
it hides syntax without changing authoritative source. The session preserves
paragraph identity and backend order. Opening or staging checks revisions again
and rejects a dirty retained destination. `AgentChatContextReceiving` receives
provider-neutral attachments with optional exact source ranges. Chat material chips
open native popovers; the research views own no runtime transport or durable record.

When the split item remains visible without a selected Document, the
composition root installs a read-only Apparatus content-state projection rather
than an empty host or stale Inspector leaf; the split controller remains the
sole visibility owner.
Library and Chat use `ScholiumSidebarLayout` for container edges, content insets
and header action slots. Search and the workspace navigator use the container
edge; headings, dates, conversation text and empty states use the content inset.
The Inspector's editorial metrics do not own sidebar geometry. The native
segmented navigator uses `fillEqually`; it does not add manual segment widths
to AppKit's own control chrome.

`ScholiumSidebarHeader`, `ScholiumSidebarHeaderActions` and
`ScholiumSidebarHeaderIcon` provide structure and complete label hit areas.
Header Buttons and Menus use native plain presentation and the existing native
secondary-label color role, with inherited tint reset. There is no additional
pointer reader, hover/press paint or color recipe. The shared symbol leaf applies
a body-scaled optical correction to the compose symbol's visible strokes;
this drawing-only offset does not change action frames, spacing or hit areas.
Native controls retain activation, keyboard focus, menu tracking and disabled
state. Chat's temporary selection set belongs to its list presentation; archive
persistence remains with `AgentChatController`.

`ScholiumSidebarAction` and `ScholiumSidebarItem` own Library/Chat action and
object glyph choices, reusing `ScholiumSystemSymbol` for native/WebKit identities.
`ScholiumSidebarIcon` and its action label style separate accessory alignment from
custom control targets. Copy feedback and custom disclosure arrows consume the
caller's state; activity, delivery and list-state models retain their existing
state and symbol authority. Native Source List disclosure remains AppKit-owned.

`ScholiumContentPreview` owns the parented AppKit panel for Chat rich objects and
operation output: one per originating window, screen-bounded geometry, focus return,
outside-click/Escape dismissal and observer teardown. The initiating native view
and rect anchor AppKit window animations; the child remains attached through closing. SwiftUI supplies read-only
content and the shared Close/Copy header; exact object projection and live activity
state remain caller-owned. Inline readers retain their selection and scroll owners.

`AgentChatComposerInput` embeds one native scroll view and `NSTextView` across the
whole message input slot. AppKit owns hit testing, caret placement, selection, Undo
and marked text. The host grows to seven lines before scrolling; Return dispatches
the existing send action, while modified Return inserts a newline. Draft callbacks
capture their conversation identity; switching or dismantling commits only changed
text through that binding, then releases delegates and closures. The controller
remains the only durable draft owner.

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

## Settings integrations

The Settings **Integrations** pane is navigation, not an Agent runtime. It
contains **Agents & Chat** and **Zotero**; those children preserve their
separate feature owners, storage boundaries and connection semantics.

### Agents & Chat

`AgentIntegrationSettingsView` receives delivery-neutral availability values
from `WorkspaceSettingsModel`. Application resolves the bundled helper and
release-bundled Core Protocol locations. The App reports its own availability;
the authenticated bridge status comes from the live App bridge owner.

Host setup actions write one generated command through the shared native
pasteboard boundary. The command contains the verified absolute helper path and
`mcp serve`; Codex and Claude labels and scope are presentation choices only.
Scholium does not execute the command, edit host configuration, install a Skill,
or record a configuration-success claim.

The Core Protocol reveal route is a Finder action over a release resource.
The selected runtime owns researcher Skills; the Chat capability owner
provides discovery and management under the Agent Collaboration chapter.

### Zotero

Zotero remains an optional integration with one Application-owned capability.
Its settings, exact library/item identity, attachment containment, and
source-derived reference navigation remain separate from MCP Agent collaboration.
The first-party Zotero MCP transport follows Specification §15 and does not
expand Scholium's knowledge-base MCP surface. `ZoteroMCPAccess` binds one helper
session to read-only delivery. Core uses one predicate for discovery and
dispatch, so hidden import tools cannot execute in read-only mode.
Application reads and MCP share Core's bounded URLSession client and redirect
policy. Foundation request injection stays inside Application composition;
delivery and boundary tests never construct Core services. The client cancels
oversized or cancelled responses.

`ZoteroMCPAnnotations` uses that server's request factory and API validation for
exact PDF/annotation reads, paginated snapshot pointers, record fingerprints
and attachment revalidation; it owns no material store. `ZoteroMCPOriginals`
resolves only an exact attachment's API file URL, checks its metadata and
supported type, then reuses `VaultAttachmentStore` bounded, descriptor-relative
coordinated reads. It rechecks metadata, URL and bytes before passing the
snapshot to the same Core `AgentAttachmentContentReader` used by Note
attachments. Only selected text/page/image coverage enters the tool response;
originals have no second archive or writable projection.

`ZoteroReference` owns library/item/PDF-page/annotation URL validation and
serialization. Source-link presentation, MCP results, Chat links/Sources and
native external navigation use it; a locator does not create source-read
evidence.

### Settings authority

Workspace, Document and Notifications settings retain their existing owners;
the Integrations and Interaction panes only compose those owners.
`WorkspaceSettingsModel` presents immutable snapshots and delegates writes to
Application capabilities. Portable Triptych settings contain Attention timing;
source properties need no settings catalog. Unsupported pre-production state
remains subject to the specification's non-migration and byte-preservation
boundaries; architecture adds no compatibility policy.

Settings search indexes static interface metadata only. It never searches
research content, reads external Skill files, or supplies Agent permission.

`SettingsToolbarAttachment` projects the five selected destinations to a native
preference `NSToolbar`. Its coordinator owns only exact-window attachment and
frame adjustment from the current top-left corner, constrained to the visible
screen and immediate under Reduce Motion. SwiftUI retains destination and
child-category state; feature owners retain configuration persistence. Native
search filters static page/control metadata and restores the browsing context.
`ScholiumHotkeyCommand` owns fixed and customizable menu bindings.
`ScholiumHotkeyPreferences` validates recording, writes and persisted overrides
against that catalog and native reservations. `ScholiumMenuShortcutModifier`
projects current preferences into menus; only customizable commands appear in
Settings. Fixed bindings have no second conflict-list definition.

`DocumentWebViewContainer` gives the focused document's registered shortcuts
to the native menu before WebKit, excluding hidden documents, other windows and
composition; disabled commands cannot fall through. Formatting and Find use
the existing editor bridge, while CodeMirror owns local text/navigation,
history and Save. Task-owned menu content receives the window command revision
explicitly. File, Edit, Format, Insert, View, Research and Window retain
separate command views. Research's Settlement route reuses the window toolbar's
exact-target availability and popover; it adds no mutation owner.

`SettingsInteractionView` composes Keyboard Shortcuts and Selection Actions
with a native segmented child selector. `SettingsIntegrationsView` composes
Agents & Chat and Zotero in the same way; it does not copy either feature's
state. Their scope notice is explanatory only and does not grant a broader
write authority.

The selected Triptych's Chat controller supplies connection settings through
the [Agent client](02-agent-collaboration.md#native-chat-client), not a second
runtime owned by the preferences window. `SelectionActionPreferences` owns the
ordered, enabled action definitions in machine-local UserDefaults. The Settings
pane retains editable drafts, validates count, native label width and prompt
size, and commits through that single owner. The native selection menu reads
those definitions; it owns no settings copy or installed-Skill inventory.

## Shared presentation and boundary enforcement

### Design-system implementation

[Design](../../Design.md) owns global intent and identity; §18 owns feature
presentation and state wording; §20 owns accessibility. This chapter maps shared
presentation responsibilities to code. It does not require a wrapper around a
standard system control or copy a feature's layout recipe.

| Responsibility | Current implementation owner |
| --- | --- |
| Paper input and adapted document colors; system Accent role | `ScholiumColorVariables`, `ScholiumColorResolver`, `ScholiumColorRole` and `ScholiumNativeColorRole` in `Scholium/UI/Foundation/ScholiumDesignSystem.swift`. |
| Native semantic colors | `ScholiumNativeColorRole`; AppKit/SwiftUI owns actual control rendering. |
| Native-to-document style transport | `ScholiumWebDesignTokens`; generated CSS consumes resolved values, not another palette or settings store. |
| Shared custom geometry | `ScholiumGrid`, `ScholiumMetrics`, `ScholiumShape`, surface/boundary/elevation roles; exact defaults remain in code. |
| App-owned typography | `ScholiumTypography` in `Scholium/Styling`; standard controls retain system type. |
| Chat message typography and ink | `ScholiumChatAppearance` in `ScholiumDesignSystem`; user and Agent bodies share adaptive system type and primary text, while authorship layout remains with Chat. |
| Document typography | `DocumentAppearanceSettings` and the rendering pipeline in [Documents and Editor](06-documents-and-editor.md#shared-document-rendering). |
| Shared symbols | `ScholiumSystemSymbol`; `ScholiumWebSymbolAssets` transports those symbols into WebKit. |
| Purpose-specific custom motion | `ScholiumMotion`; native controls retain their system lifecycle. |
| Page/pane state presentation | `ScholiumContentStateView`; compact Apparatus, field validation and recovery use their own bounded presentations. |

Shared values need repeated semantic or adaptation responsibility. Equal numbers
alone do not create a common owner. Native geometry stays with the platform;
local values remain with their feature. No JSON palette, geometry mirror or
second appearance configuration is authoritative.

Buttons and menus use SwiftUI/AppKit styles directly. No shared wrapper rewrites
command tint or destructive colors. `scholiumIconControl` in `ScholiumButtons`
provides bounded native glass icon composition; it does not impose an app-owned
palette. Native controls retain role, enabled, focus and appearance behavior.
Remaining custom feedback paths are tracked in [Open Work](../Status/03-open-work.md).

Custom link-equivalent cursors use `scholiumActivationPointer` and
`ScholiumPointingHandButton` where the host does not already own the cursor.
Standard native controls and list rows do not consume these adapters. Document
CSS provides the corresponding link behavior in its renderer.

### Component boundaries

Reusable presentation leaves receive values and typed actions. They own no
Document, workflow, permission, navigation or operation lifecycle. A shared
component is justified by a repeated task, one presentation responsibility and
an adaptation contract; feature-local views need no catalog promotion.

Concrete feature ownership is recorded only in its chapter:

- [Runtime and Ownership](01-runtime-and-ownership.md#document-tabs-and-native-shell):
  native split, tabs, toolbar validation and window teardown.
- [Source Layout and Presentation](03-source-layout-and-presentation.md#presentation):
  window routes, Search, Inspector, Sidebar headers and notifications.
- [Settings integrations](03-source-layout-and-presentation.md#settings-authority):
  Settings composition and native preference-window geometry.
- [Documents and Editor](06-documents-and-editor.md#editor-boundary-contract):
  retained editor, native previews, completion, Find and cross-runtime input.
- [Agent Collaboration](02-agent-collaboration.md#native-chat-client):
  Chat runtime, conversation state and receipt projections.

Native container adapters are bounded infrastructure: they own native attachment
and teardown, delegate/target lifetime and geometry, translating typed intents
without acquiring a competing domain state. A presentation reuse decision never
moves a feature's authoritative state into a style or component.

The selected Xcode also bundles `AppKit-Implementing-Liquid-Glass-Design.md`
under `IDEIntelligenceChat.framework/Resources/AdditionalDocumentation`.
It is an implementation reference, not a product design owner; sample custom
controls do not override Design's native presentation boundary.

### Boundary enforcement

Contracts, Application and App suites exercise their own module, runtime,
document and presentation responsibilities. Design checks cover semantic input
ownership, native/WebKit transport, contrast and actual shared consumers; they
must not freeze local implementation defaults or require obsolete custom skins.
`Tools/Scripts/verify.sh` also checks package dependencies, imports, I/O and
public symbols so delivery targets cannot acquire Core authority.

Debug presentation proofs consume production components and values; they are
not a second design system. [Verification Evidence](../Status/04-verification.md)
owns dated outcomes. A structural check or compiled preview does not establish
runtime interaction or human acceptance.

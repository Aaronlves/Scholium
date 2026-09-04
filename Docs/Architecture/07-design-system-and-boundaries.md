# Architecture: Design System and Boundary Enforcement

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Design-system
implementation, component boundaries, and executable enforcement.

## Design-system implementation

[Design §19](../../Design.md#19-scholarly-editorialism-and-design-variables)
owns palette meanings, typography, continuous content-plane and native-control
material language, motion, the
adaptive editorial grid, component and pattern presentation, and the shared
cross-functional state language. Section 20 remains the complete accessibility
and adaptation authority. The app implements the design contract in
`Scholium/UI/Foundation` through `ScholiumColorVariables`,
`ScholiumColorResolver`, derived `ScholiumColorRole`s, `ScholiumGrid`,
`ScholiumMetrics`, `ScholiumMotion`, and `ScholiumTypography`.
These shared types are current reusable implementation inventories, not a
permission list for every bounded feature-local layout value.

Accent and Paper are the only configurable inputs. Section 19.2's Paper is the exact
Light Document anchor; one resolver derives every other appearance role for
native and generated WebKit CSS. The Workspace `NSSplitViewItem` supplies the
complete native Sidebar material while the adjacent Document surface extends
its Paper background beneath that glass. Sidebar SwiftUI and source-list
content stays transparent. Inspector uses a distinct Apparatus role whose tone
is deliberately much closer to Document than Navigation. Sticky Inspector headers and
sticky-header occlusion and link-annotation disclosure reuse that exact Apparatus role rather than a
floating-control surface. `ScholiumWebDesignTokens` injects the resolved role
declarations and fixed Markup syntax exception into every document HTML
surface; authored Editor styles only consume those properties and contain no
fallback palette. Functional/status anchors stay private. Tests enforce the
input boundary, mappings, parity, and contrast; no
static appearance palette or JSON mirror exists.
`ScholiumSystemSymbol` centralizes native symbol names, while
`ScholiumWebSymbolAssets` transports the same SF Symbols into WebKit as CSS
masks without introducing a second path catalog.

`scholiumForeground` is the adaptive SwiftUI foreground boundary for
Scholium-owned copy and glyphs. Feature views select a `ScholiumColorRole`
rather than system primary/secondary styles or a resolved `Color`; the single
`TextField` prompt that must remain a `Text` value consumes the same semantic
role directly. `ScholiumNativeColorRole` names the only AppKit-owned effect
colors used by custom rendering: search-match highlight and structural shadow.
Bootstrap's closed narrative-art palette and the fixed Markup highlight remain
the two nonconfigurable authored exceptions declared by Design §19.2.
Repository inventory tests reject raw Swift inputs outside those owners,
direct AppKit palette access, leaf semantic-color opacity recipes, and authored
WebKit color declarations or literals.

`ScholiumSurfaceRole` maps a Scholium-owned content surface to its default
semantic boundary and, where applicable, one purpose-named
`ScholiumElevationRole`. The current shared custom transient roles are
`floatingControl`, `boundedPanel`, and `searchOverlay`; ordinary structural
surfaces resolve to none. Sidebar elevation has no Scholium renderer: AppKit's
Sidebar split-item behavior owns its glass edge and shadow, while the Document
item's `automaticallyAdjustsSafeAreaInsets` extends Paper beneath it and keeps
readable content in the unobscured safe area. `ScholiumWebDesignTokens` exports
only the transient role names as CSS shadow declarations without converting
points to CSS pixels.
Selection bars and the shared segmented selection plate consume
`floatingControl`; custom selection menus, the shared
link preview, and Edit input-suggestion lists consume `boundedPanel`; Search
consumes `searchOverlay`. The shared preview uses the complete opaque bounded-
panel surface, separator, semantic text, and elevation roles; it owns no Canvas
fallback, backdrop blur, or local transparency recipe. Increase
Contrast resolves custom shadows to none while the semantic boundary
strengthens. Reduce Transparency or an inactive native window reduces opacity;
Dark appearance applies the same quiet structural-depth opacity without
compounding these adaptations. Native menus, popovers, sheets, panels, alerts,
and windows retain their system-owned elevation and are never double-shadowed.

Repository ownership tests treat authored shadow syntax as a closed inventory.
The shared native elevation modifier is the only `.shadow` owner; generated WebKit
elevation consumes only the three purpose-named CSS variables. The remaining
inset `box-shadow` declarations are classified as editor boundaries or focus
rings rather than elevation. Adding a raw shadow, a direct SwiftUI hover site
outside the design-system owner, a WebKit `:hover` site, or another AppKit
pointer tracker fails the inventory until its semantic owner and exception
class are made explicit. The bounded WebKit hover inventory may shrink during
later simplification but must not grow.

`ScholiumContentInteractionSurface` is the shared SwiftUI, AppKit, and WebKit
mapping for content-control selection, hover, keyboard-focus, and press
emphasis. Hover resolves to a low-opacity semantic `primaryText` veil,
preserving the native toolbar's relative light/dark response over every content
plane without copying its dynamic AppKit pixels; keyboard focus retains the
stronger raised blend, while selection remains an explicit persistent input.
Its generated CSS declarations transport those same mixes and the Accent focus
ring into both retained document surfaces. The overloaded
`scholiumActivationFocus` modifier keeps matching custom button-like controls
in the complete keyboard chain, clears pointer-generated keyboard-only focus,
and locally replaces the native focus effect with that shared surface without
inspecting AppKit events or changing window-wide focus behavior.
Native Buttons, sheets, and alerts do not consume this adapter: AppKit owns
their modality-sensitive focus return. `ScholiumSegmentedControl` is the one
custom group that consumes the adapter; feature views do
not add unconditional `FocusState` assignments after native presentation
dismissal, which prevents pointer interactions from manufacturing keyboard
focus rings while retaining native keyboard traversal and return behavior.

Custom link-equivalent cursors have one cross-runtime boundary.
`scholiumActivationPointer` and `ScholiumPointingHandButton` are adapters for
bounded custom targets whose semantics require the link pointer and whose host
does not already own cursor behavior; generated document CSS provides the
corresponding WebKit link behavior. Standard SwiftUI/AppKit controls and native
table or outline rows do not consume these adapters. The Library outline adds
no cursor rectangles or pointer tracker. Text, drag, divider, resize, disabled,
and passive surfaces retain their task-specific cursors.

`ScholiumContentControlButtonFeedbackModifier` is the single transient-state
owner for custom SwiftUI Buttons. The generic
`ScholiumContentControlButtonStyle` and geometry-owning quiet-row style both
delegate to it. It normally owns one lightweight SwiftUI hover state, consumes
`ButtonStyle.Configuration.isPressed`, and resolves semantic ink, one
continuous surface, and immediate press dimming. Native Source List rows do not
consume this custom Button path. Borderless native Menus
instead use `scholiumContentControlPointerFeedback`: a zero-hit-test AppKit
adapter observes the complete Menu frame because the host does not reliably
forward pointer state into its label. The enclosing Button or Menu retains
activation, focus, menu tracking, and accessibility; no leaf or compound
wrapper adds another transient-state owner.
WebKit selection controls use the quiet hover mix for pointer hover and press,
the stronger mix for keyboard focus, and an Accent focus ring. CodeMirror
suggestions keep their current listbox item on the persistent raised surface
while pointer hover remains transient. The protected Callout stylesheet owns
only its disclosure geometry and selectors; its fold mark consumes the shared
hover/focus values instead of declaring another opacity or focus color.
Review preview delegation resolves one footnote, link-annotation marker, or link
anchor for both pointer and focus entry, ignores movement inside that anchor,
and closes on matching pointer or focus exit as well as scroll, resize, source
activation, or window blur. Edit's corresponding controller additionally owns
Command-armed link feedback, the same annotation-template presentation, and a
current-buffer one-definition footnote projection. Neither creates another
source, selection, or focus owner.
`ScholiumTriptychWorkspaceNavigator` is a thin `NSTableView` adapter for the
three vertical workspace rows and neutral Note totals. AppKit owns source-list
geometry, color, hover, focus, active/inactive selection, and Up/Down traversal
without a Scholium input-modality override. The coordinator only projects
availability and publishes a selected workspace intent. Scholium semantic text
colors adapt to AppKit's emphasized selected-row background without adding an
Accent mark, underline, border, shadow, custom corner, or parallel transition.
`ScholiumSegmentedControl` owns the current bounded text-only horizontal
single-choice groups that match its contract. It receives only a binding and
finite option labels, then owns equal layout, the Paper-derived track, adaptive
raised selection plate, continuous corners, pointer and press feedback,
Left/Right traversal, and accessibility state. A future group may remain native
or feature-owned when its semantics or interaction genuinely differ.
The Research Inspector's icon-only projection group remains a native AppKit
toolbar control because its placement and icon semantics differ from bounded
text choices in content.
`ScholiumEditorialIconControl` is the single presentation owner for matching
compact icon actions in content-owned headers. It gives each one an exact 28pt
target and semantic ink while a regular circular Glass Button or Menu owns
hover, focus, press, active-window, and accessibility adaptation. The 20pt label
inside the native regular control preserves the established 28pt outer size;
callers add no padding or second hover enclosure. The visible symbol remains
available to the native control so an icon-only Menu stays in the accessibility
tree; each callsite replaces its inferred symbol name with the complete action
label and value. The presentation adds no raw radius, animation, scale, or
shadow. The Debug Editorial
Parchment acceptance board consumes these production components and resolved
roles; it is not a second design-system source.

Workspace toolbar observations update standard bordered `NSToolbarItem`
instances and one `NSMenuToolbarItem`; no custom button view or fixed-size host
intervenes. AppKit therefore owns regular Glass, edge highlight, shadow, hover,
press, focus, geometry, and adaptive appearance. The Inspector projection
uses automatic native segmented-control styling and retains its 70 × 20 fitting
size. AppKit owns hover, press, focus, active-window, Reduce Transparency, menu
tracking, and disabled rendering; SwiftUI does not reconstruct those states or
paint a toolbar band.

The Sidebar Search and Notifications Glass controls locally clear
the workspace Accent tint. Their system material therefore remains
monochrome; Scholium color stays limited to the explicit nonzero Notifications
dot and other semantic states rather than staining ordinary control
backgrounds. Triptych opening and creation stay in the native File menu,
registration management stays in Settings, and open-window switching stays in
the Window menu, so the Sidebar adds no persistent context selector.
`ScholiumWindowLifecycleRegistry` publishes only exact registered
window-to-Triptych membership, allowing SwiftUI's native window subtitle to
appear when those windows span more than one distinct Triptych and disappear
again when they do not.
The Library header contains separate borderless SwiftUI Menus for Organize and
Add; global Folder disclosure moves into Organize beside Filter and Order. Each
Menu retains its own label, disabled state, focus target, activation, and menu
presentation while hiding the redundant indicator and persistent container.
The shared zero-hit-test pointer reader supplies only the shallow circular
hover and press surface. Their symbols and the Library section title use Muted
Text. The Scholium wordmark owns the Sidebar's brand-title role while Library
begins the subordinate section; the current Triptych name adds no persistent
competing title. Library Folder
rows supply a decorative monochrome Folder glyph in the same semantic icon slot
as Note symbols, while AppKit's unmodified outline disclosure remains the sole
owner of collapsed and expanded state indication. The source list does not
override `frameOfOutlineCell(atRow:)` or replace the native disclosure button.
Its 16pt grid-owned hierarchy step is supplied through
`NSOutlineView.indentationPerLevel`; AppKit continues to position disclosure,
cell, and selection.

`MCPAgentChangesView` uses one continuous semantic Document surface and a flat
machine-local change list. Each row distinguishes operation, stable Note
identity, source path, exact revision state, and available recovery without
treating the entry as a research result. Exact comparison reuses the shared
comparison components; Update Undo uses a native confirmation and remains
visibly unavailable when Application reports revision drift. The view adds no
second history, acceptance, or source-authority visual language.

Inspector and Agent Changes controls route hover, keyboard focus, and press
through shared component owners. System confirmation actions remain
native-owned. Technical fingerprints use `ScholiumApparatusFactGrid`, the same
adaptive label/value owner as Inspector About. Consumers provide semantic
values only; the grid chooses aligned or stacked structure and its exact-value
style distinguishes scholarly prose from revision identity.
`ScholiumTypography` is the sole native text resolver for Scholium-owned
surfaces. It exposes only `InterfaceRole`, `ScholarlyRole`, and `ExactRole`;
feature modules publish no Library, Apparatus, Agent Changes, or Chrome font
aliases. Every custom top-level view shares the 17pt Semibold Interface primary
title, while research-object titles share the 20pt Bold Scholarly title.
Emphasis and tabular figures are resolver inputs rather than cross-product
roles. Brand and Bootstrap retain the approved identity/hero exceptions.
Alegreya and Victor Mono resolution remains private. `ScholiumSymbolStyle`
separately maps purpose-named component scale to SF Symbols.
Repository tests reject fixed SwiftUI point sizes, raw SwiftUI text styles,
leaf-owned font weight, direct SwiftUI system-font construction, and low-level
typeface access outside the owner. Scholium-owned explanatory copy selects an
explicit semantic role; standard control labels, menus, alerts, and toolbar
identity retain platform typography. A runtime test registers every bundled
Alegreya and Victor Mono face and resolves it through AppKit. Document
typography remains in the Appearance/CSS pipeline. No recommendation-specific
color, spacing, radius, footer, badge, or elevation Variable exists.

`ScholiumGrid.Peripheral.contentInset` is the one 28pt outer page-edge source
for Library and Inspector. `ScholiumMetrics.Library` and
`ScholiumMetrics.Apparatus` map to it; their internal row, hierarchy, and section
variables remain separate.

`ScholiumLibrarySourceState` owns the Library empty, loading, and error page
inset. It maps horizontal content to the peripheral
edge and vertical entry to `sourceStateVerticalInset`; it does not wrap
populated OutlineRows or alter their denser row-surface inset.

`ScholiumGrid` owns the shared 4pt rhythm, bounded 2pt optical exception,
reusable semantic spacing, and component anchors. `ScholiumMetrics` maps
genuinely shared responsibilities to those roles without copying values; no
geometry JSON mirror exists. The shared 4pt label/accessory, 8pt inline-control,
12pt nested-content, 16pt section, and 20pt region values remain preferred at
matching call sites. A bounded component may keep a clear local cadence when it
is not reused, accessibility-critical, or an adaptation rule; equal numbers do
not create shared ownership. Tests exercise promoted roles and representative
consumers rather than scanning every production spacing, padding, line spacing,
or spacer value. Native control geometry, scene/window dimensions, Document CSS
units, the Debug proof catalog, and coordinate-driven Bootstrap art remain
separate classifications.

`ScholiumMetrics.ResearchGuidance` owns the categorized Settings surface's
native list-detail containment thresholds and the explanatory collection-row
rhythm. `researchSettingsCollectionRow` applies that one content/action layout
to Skill and Academic Profile rows while each caller
retains its domain values, operations, accessibility identifiers, and state.
The shared presentation component performs no persistence, routing, or
authorization work and does not style native controls themselves.

The Settings root uses one native sidebar List with Application, This Triptych,
and Research Guidance sections. Its native search field filters only a static
destination metadata catalog, while Triptych selection remains in the
Triptychs detail and continues to route the existing Settings model. Hotkey rows use native menus, and their
AppKit recorder is a focusable `NSButton` adapter that translates one key event
into `ScholiumHotkeyPreferences`, the versioned UserDefaults owner shared with
`ScholiumCommands`; it owns no command execution, and Hotkeys never enter
portable Triptych settings.

Settings uses a unified, title-free toolbar style.
`SettingsWindowAttachment` installs `fullSizeContentView` and retains the
transparent native titlebar, traffic lights, and drag behavior. The Settings
root is a two-column `NavigationSplitView`; its Navigation and detail columns
own their actual full-height semantic surfaces and the native divider beneath
that chrome. No window-level two-color background or SwiftUI divider duplicates
those planes.

The This Triptych Metadata detail consumes one candidate
`NoteMetadataCatalog` derived from its settings draft. Its field-definition and
About always-shown sections mutate separate subvalues and save only through the
existing exact-revision Settings transaction. Present values remain visible in
About independently of that empty-field preference. The inline Add
Field form owns only a key and supported simple value kind; it has no source,
About, Agent, Zotero, or body mutation authority.

Agent Integration is informational and operational: it presents host-specific
MCP setup commands and the bundled Core Protocol path. It persists no Agent
preference, credentials, sessions, or execution state. Help and accessibility
hints appear only when they supply otherwise missing action, exact value,
disabled-state, consequence, or recovery context; errors and recovery
instructions stay visible at their owning surface.

`ScholiumCornerRole` is the current shared responsibility vocabulary for custom
corner geometry. `ScholiumShape` exposes Native aliases and generates the
WebKit custom properties needed by shared or WebKit-specific constructs; it
does not define a numbered radius scale. Feature-local geometry may remain with
one bounded surface when it has no cross-runtime or adaptation contract.
`scholiumEditorialSurface` accepts a
`RoundedRectangularShape` and publishes it with `containerShape`, so a genuinely
nested custom surface such as the Search availability banner can resolve
`ConcentricRectangle` from its container. Independent Native controls consume a
purpose-named role, while Review/Edit styles consume generated
`--scholium-corner-*` properties. Tests preserve shared Native/WebKit parity and
representative adoption without treating every numeric corner as a catalog
violation.

- AppKit owns window, toolbar, split, divider, collapse, fullscreen, and frame
  geometry. The Library's 300pt content minimum is native split-item state, not
  grid spacing or persisted divider state;
- `ScholiumMetrics.Onboarding` owns the separate Bootstrap window and setup-form
  measures;
- `ScholiumMetrics.Workspace` owns the configured-workspace initial size, not a
  minimum;
- `ScholiumMetrics.Document` names the explicit CSS-pixel top inset and
  per-window text-scale range; and
- `DocumentAppearanceSettings.defaultSettings` is the sole built-in owner of
  Review/Edit Body, heading, Callout, and line-width values. The generated
  `ScholiumWebDesignTokens` transport derives those values rather than keeping
  a second typography table. `ScholiumDocumentRhythm` retains only
  renderer-specific Source and layout values; the unit-explicit
  `ScholiumDocumentPresentationConfiguration` supplies scale and minimum
  insets without overriding Appearance semantics. The normalized **48–96ch**
  line width has a **66ch** default; generated CSS exports it as
  `--scholium-document-line-width` together with an internal derived half-width
  length so the supported WebKit runtime does not depend on CSS division.
  Read/Live resolve it against Body type and Source against retained
  exact-source type. Dynamic presentation updates reuse the existing
  CodeMirror remeasure path rather than reconstructing editor state.

`ScholiumMotion` exposes purpose-named animations and returns no animation
when Reduce Motion is active. It does not install a global animation policy.

## Component boundaries

`Scholium/UI/Components` implements the component distinctions established by
the specification. Reusable feature components remain stateless leaves
receiving immutable values and typed closures; feature roots retain state and
action routing. The bounded AppKit window-shell adapters are infrastructure
exceptions: they own native controller and split-item lifetimes, weak
exact-window attachment, toolbar/delegate installation, explicit split
intents, and native visibility mirroring, but no
Triptych, document, or researcher-visible semantic state. `WindowShellState`,
`WindowWorkspaceController`, and the feature controllers own their bounded
state; `WindowModel` composes them and routes focused commands. This document records that
dependency direction, while the specification owns the stable rule for when
Scholium-specific components or distinct research surfaces are appropriate.
`ScholiumContentStateView` is the single presentation leaf for page- and
pane-level state copy. It accepts only visible content, indicator treatment,
region placement, density, and an action view; Document, Library, Search,
Agent Changes, Attention, Recovery, and Settings owners continue
to derive their own states and transitions. `ScholiumApparatusStateView`,
inline field feedback, and `ScholiumRecoveryNotice` remain separate owners for
their distinct compact, validation, and persistent-recovery responsibilities.
Window and Settings operation feedback share `ScholiumOperationFeedback`,
`ScholiumFeedbackKind`, and `ScholiumFeedbackPolicy`. Confirmation and
Information use one content-fitting bottom-centred window overlay; Warning
and Error use one top-centred window overlay until explicit dismissal. Neither
changes Document geometry. Settings
shows the same queue one item at a time in a top-centred window overlay, outside
pane layout and one compact inset from the top window edge, where it may cover
transparent native titlebar space. Main-window overlays use the same compact
outer-edge inset and their top variants may cover native toolbar space.
`ScholiumDocumentStatusNotice` remains an operation-state
projection, not a queue member, and occupies inline Document layout.

## Boundary enforcement

`ScholiumContractsTests`, `ScholiumApplicationTests`, and the architecture and
composition suites in `ScholiumAppTests` exercise their respective module,
runtime, window, document, presentation, and design-system boundaries.
`Tools/Scripts/verify.sh` adds package-graph, source-import, I/O, and public
symbol-graph guards so delivery targets cannot reacquire Core-owned authority.

See [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) for dated evidence,
reachable behavior, and remaining acceptance work. This document intentionally
does not duplicate test counts or claim that a dated pass proves the
current checkout.

# Architecture: Design System and Boundary Enforcement

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Design-system
implementation, component boundaries, and executable enforcement.

## Design-system implementation

[Design §19](../../Design.md#19-scholarly-editorialism-and-design-variables)
owns palette meanings, typography, opaque surface language, motion, the
adaptive editorial grid, component and pattern presentation, and the shared
cross-functional state language. Section 20 remains the complete accessibility
and adaptation authority. The app implements the design contract in
`Scholium/UI/Foundation` through `ScholiumColorVariables`,
`ScholiumColorResolver`, derived `ScholiumColorRole`s, `ScholiumGrid`,
`ScholiumMetrics`, `ScholiumMotion`, and `ScholiumTypography`.

Accent and Paper are the only configurable inputs. Section 19.2's Paper is the exact
Light Document anchor; one resolver derives every other appearance role for
native and generated WebKit CSS. The complete Sidebar uses the Navigation
surface; Inspector uses a distinct Apparatus role whose tone is deliberately
much closer to Document than Navigation. Sticky Inspector headers and
relationship-symbol occlusion reuse that exact Apparatus role rather than a
floating-control surface. `ScholiumWebDesignTokens` injects the resolved role
declarations and fixed Markup syntax exception into every document HTML
surface; authored Editor styles only consume those properties and contain no
fallback palette. Functional/status anchors stay private. Tests enforce the
input boundary, mappings, parity, contrast, and relationship variants; no
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

`ScholiumSurfaceRole` maps a Scholium-owned surface to its default semantic
boundary and, where applicable, one purpose-named `ScholiumElevationRole`.
`floatingControl`, `boundedPanel`, and `searchOverlay` are the complete custom
transient elevation set; ordinary structural surfaces resolve to none. The
native-only `ScholiumStructuralDepthRole` instead owns exactly the
`documentNavigationBoundary` and `readingEvidenceBoundary` plane relationships
and is not exported to WebKit. The Workspace Library host clips a Document-
color caster just outside the logical edge, leaving only the shadow inside
Library while AppKit's thin divider stays visible and interactive. The Record
detail host uses the same full-height split grammar to cast from the dominant
reading plane into the Evidence rail. Each host covers the complete receiving
split-item bounds beneath the native toolbar, is excluded from hit testing and
accessibility, and mirrors in right-to-left presentation. The native modifiers
consume the named structural-shadow exception, while
`ScholiumWebDesignTokens` exports only the transient role names as CSS shadow
declarations without converting points to CSS pixels.
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
The two native renderers are the only `.shadow` owners; generated WebKit
elevation consumes only the three purpose-named CSS variables. The remaining
inset `box-shadow` declarations are classified as editor boundaries or focus
rings rather than elevation. Adding a raw shadow, a direct SwiftUI hover site
outside the design-system owner, a WebKit `:hover` site, or another AppKit
pointer tracker fails the inventory until its semantic owner and exception
class are made explicit. The bounded WebKit hover inventory may shrink during
later simplification but must not grow.

`ScholiumLibraryLocationPicker` owns the borderless native Location menu and
its single native indicator and shared interaction surface without owning
Location state or applying a persistent Accent tint. Its plain button
presentation prevents the native Menu host from adding a second hover shape;
the title resolves from Regular secondary ink to primary ink through the same
hover/focus emphasis environment as adjacent commands.
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
`ScholiumContentControlButtonFeedbackModifier` is the single transient-state
owner for custom SwiftUI Buttons. The generic
`ScholiumContentControlButtonStyle` and geometry-owning quiet-row style both
delegate to it. It normally owns one lightweight SwiftUI hover state, consumes
`ButtonStyle.Configuration.isPressed`, and resolves semantic ink, one
continuous surface, and immediate press dimming. A Button hosted inside the
native Source List suppresses that SwiftUI hover tracker while retaining the
shared press path, so the AppKit row remains the sole hover and selection
owner. Borderless native Menus
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
Review preview delegation resolves one footnote-or-link anchor for both pointer
and focus entry, ignores movement inside that anchor, and closes on matching
pointer or focus exit as well as scroll, resize, or window blur. It does not
create another source, selection, or focus owner.
`ScholiumTriptychWorkspaceNavigator` owns
the three vertical workspace rows, neutral Note totals, selection/hover
surfaces, focus, and Up/Down traversal without owning the selected workspace. Its continuous
surface consumes the purpose-named workspace-navigation corner recipe and has
no Accent mark, underline, border, or shadow.
`ScholiumSegmentedControl` owns every horizontal local single-choice group. It
receives only a binding and finite option labels, then owns equal layout, the
Paper-derived track, adaptive raised selection plate, continuous corners,
pointer and press feedback, Left/Right traversal, and accessibility state.
`ScholiumInspectorModeIndex` is now a semantic adapter into that component.
`ScholiumEditorialIconControl` is the single presentation owner for Filter,
disclosure, and Add in LocationHeader. It gives all three one exact 28pt target,
semantic ink, and one rounded-rectangle hover, focus, and press surface. Its Button or
Menu child retains only activation, focus, accessibility, and menu tracking;
the component applies one plain button presentation so Menu hosts cannot add a
second circular hover enclosure. The visible symbol remains available to the
native control so an icon-only Menu stays in the accessibility tree; each
callsite replaces its inferred symbol name with the complete action label and
value. The presentation adds no raw radius, animation, scale, or shadow. The Debug Editorial
Parchment acceptance board consumes these production components and resolved
roles; it is not a second design-system source.

Workspace toolbar hosts bridge live window observations into native AppKit
toolbar-bezel buttons and pull-downs. `NSButton` and `NSPopUpButton` own their
small control-size geometry, hover, press, focus, menu tracking, and disabled
rendering. The same semantic recipe pairs that geometry with the system body
font and body-medium SF Symbol scale that the original SwiftUI toolbar used;
SwiftUI does not reconstruct a
toolbar interaction surface or persistent active state.

Research Records uses one continuous semantic Document surface, collection-
first routing, native TextField/Menu/Toggle/sheet behavior, structural rules,
and two independent detail scroll owners. Its toolbar View index consumes the
shared compact segmented component and hides macOS shared background material,
so the quiet track and raised selection plate receive no automatic Liquid Glass
enclosure. Scope and Filters
remain borderless native Menus. The View index and detail navigation are native-
toolbar content; the adaptive
collection header owns identity, search, Scope, Filters, and count. The selected
Record allocates the remaining width to reading while its default-visible
Evidence rail stays between 260pt and 304pt. One native toolbar control removes
or restores the rail. One adaptive divider and the full-height
`readingEvidenceBoundary`, never color or shadow alone, distinguish the visible
planes; Increase Contrast removes the depth cue while retaining the divider and
surface relationship.
The Records scene applies `fullSizeContentView` once for the complete window
lifetime. AppKit's safe area remains the content boundary for collection and
detail scroll owners, while the selected Record's Document and Apparatus plane
backgrounds and their structural boundary continue behind the transparent
toolbar. The root hides the native toolbar background, and macOS 26+ toolbar
content hides its automatic shared background, so those semantic planes remain
continuous without Liquid Glass or a painted masking layer.

Every custom Records Button routes hover, keyboard focus, and press through
the shared Button feedback owner; Scope and Filters use the bounded Menu
adapter and plain presentation. Inspector ModeIndex and the toolbar View index
both resolve selection, focus, and traversal through the same segmented owner;
neither adds an Accent underline or fill. View items, menu labels, search clear,
ordinary actions, evidence links, and continuity links use the editorial-
control continuous shape; native toolbar Back and Evidence controls retain
system interaction geometry. Collection destinations and their leading Handled
control share one purpose-owned 8pt row surface with no icon well or
detached background. Press changes ink/surface immediately without geometry
animation; no leaf supplies a raw hover color or radius. Record groups and
Reading Lead occurrences retain fixed scanning rhythm and flat textual
hierarchy without elevation or nested card families. The provider-bounded
Record ledger and rebuildable Reading Leads index publish exact totals and
stable 100-row slices to flat native lazy containers; later slices append at
the collection boundary without replacing loaded rows. Both
ledgers align through one fixed shared header and row rhythm; their whole-row
destination needs no trailing glyph. Triptych Record rows own an unlabeled 28pt
Attention gutter, a flexible two-line frozen-title/focal-Note Record track, a
fixed Action track, and a fixed Date track; This Note omits the focal-Note line. Attention
projects only explicit frozen exceptions and otherwise stays empty. Completed
adds no repeated status. Action is a centered text-only neutral capsule with no
icon, category tint, or independent control semantics. The visually unlabeled
32pt Handled track keeps an accessible label and independent native-control
semantics.
System confirmation actions remain native-owned.
Evidence rows reuse one prototype-derived ledger component with an aligned
symbol column and no trailing action button. Academic evidence remains visible
when the rail is shown; the evaluation editor and technical identity use
separate disclosure controls, and permanent deletion remains in the Record
header.
Bibliography and both Record and Reading Lead technical identity reuse
`ScholiumApparatusFactGrid`, the same adaptive label/value owner as Inspector
About. Consumers provide semantic values only; the grid alone chooses aligned
or stacked structure and its value-style token distinguishes scholarly prose
from exact revision identity.
The window observes `WindowColorSchemeChoice.defaultsKey` and resolves it
through the same `swiftUIColorScheme` mapping used by Workspace content and
toolbar hosts; it owns no second appearance preference.
`ScholiumTypography` is the sole native text resolver for Scholium-owned
surfaces. It exposes only `InterfaceRole`, `ScholarlyRole`, and `ExactRole`;
feature modules publish no Library, Apparatus, Research Records, or Chrome font
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

`ScholiumLibrarySourceState` owns the common Library/Set Aside/Trash empty,
loading, and error page inset. It maps horizontal content to the peripheral
edge and vertical entry to `sourceStateVerticalInset`; it does not wrap
populated OutlineRows or alter their denser row-surface inset.

`ScholiumGrid` is the single native authority for the 4pt rhythm, bounded 2pt
optical exception, semantic spacing, and component anchors. `ScholiumMetrics`
maps responsibilities to those roles without copying values; no geometry JSON
mirror exists.

The shared foundation values are closed at their call sites: 4pt
label/accessory, 8pt inline-control, 12pt nested-content, 16pt section, and
20pt region spacing are always expressed through `ScholiumGrid.Spacing` rather
than repeated by leaf Views. Every other nonzero user-interface cadence is
purpose-owned through `ScholiumMetrics`, including stack gaps, content insets,
line spacing, and nonzero minimum separation. The architecture inventory
rejects raw forms of those calls across production Swift. Structural zero
spacing, native control geometry, scene/window dimensions, and Document CSS
units remain separate classifications. The Debug component catalog is a proof
surface, and the coordinate-driven Bootstrap narrative artwork is an art
composition; neither is treated as production interface cadence.

`ScholiumMetrics.ResearchGuidance` owns the categorized Settings surface's
native list-detail containment thresholds and the explanatory collection-row
rhythm. `researchSettingsCollectionRow` applies that one content/action layout
to Method, Academic Profile, and Philosophical Practice rows while each caller
retains its domain values, operations, accessibility identifiers, and state.
The shared presentation component performs no persistence, routing, or
authorization work and does not style native controls themselves.

`ScholiumGrid.ResearchSheet` owns the common editorial rhythm for research-
facing sheet content: a 4pt title/detail gap, 16pt body-section cadence, 8pt
footer-control gap, and a bounded status inset. `ScholiumMetrics.ResearchSheet`
maps those roles plus the existing purpose-specific Action, Reading Lead note,
and Record evaluation size constraints. The three views retain separate Run,
note-save, evaluation-draft, dismissal, focus, and recovery owners; the shared
metrics do not create a generic sheet lifecycle or move native sheet chrome out
of AppKit. Each sheet presents a fixed title region, independently scrolling
body, and fixed action region separated by structural rules.

Default Research Actions present their stable title without repeating an
ordinary summary in hover help. Help and accessibility hints remain only when
they supply otherwise missing action, exact value, disabled-state, consequence,
or recovery context; errors and recovery instructions stay visible at their
owning surface. Relationship rows likewise do not repeat their already visible
section title as tooltip text.

The populated Records and Reading Leads ledgers own
`scholium.researchRecords.collection`; the Records empty-content leaf owns
`scholium.researchRecords.empty`. Their common outer container owns neither, so
an ancestor cannot replace the state-specific identity in the accessibility
tree.

`ScholiumCornerRole` is the closed responsibility vocabulary for custom corner
geometry. `ScholiumShape` exposes the Native aliases and generates only the
WebKit custom properties needed by the same or WebKit-specific constructs; it
does not define a numbered radius scale. `scholiumEditorialSurface` accepts a
`RoundedRectangularShape` and publishes it with `containerShape`, so a genuinely
nested custom surface such as the Search availability banner can resolve
`ConcentricRectangle` from its container. Independent Native controls consume a
purpose-named role, while Review/Edit styles consume generated
`--scholium-corner-*` properties. The architecture inventory rejects numeric
Swift corner arguments and numeric CSS corner declarations outside this owner.

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
  line width has a **72ch** default; generated CSS exports it as
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
Research Records, Attention, Checkpoint, Recovery, and Settings owners continue
to derive their own states and transitions. `ScholiumApparatusStateView`,
inline field feedback, and `ScholiumRecoveryNotice` remain separate owners for
their distinct compact, validation, and persistent-recovery responsibilities.

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

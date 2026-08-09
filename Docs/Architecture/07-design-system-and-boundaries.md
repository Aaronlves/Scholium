# Architecture: Design System and Boundary Enforcement

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns design-system implementation, component boundaries, and executable enforcement; sibling chapters do not restate it.

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
floating-control surface. Matching `editor.css`
fallbacks preserve deterministic first paint. Functional/status anchors stay
private. Tests enforce the input boundary, mappings, parity, contrast, and
relationship variants; no static appearance palette or JSON mirror exists.
`ScholiumSystemSymbol` centralizes native symbol names, while
`ScholiumWebSymbolAssets` transports the same SF Symbols into WebKit as CSS
masks without introducing a second path catalog.

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
use AppKit's semantic shadow color, while `ScholiumWebDesignTokens` exports only
the transient role names as CSS shadow declarations without converting points
to CSS pixels.
Selection bars consume `floatingControl`; custom selection menus, the shared
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
rings rather than elevation. Adding a raw shadow, a direct SwiftUI hover site,
a WebKit `:hover` site, or another AppKit pointer tracker fails the inventory
until its semantic owner and exception class are made explicit. The bounded
hover inventory may shrink during the current ownership cutover but must not
grow.

`ScholiumLibraryLocationPicker` owns the borderless native Location menu and
its single native indicator and shared interaction surface without owning
Location state or applying a persistent Accent tint. Its plain button
presentation prevents the native Menu host from adding a second hover shape;
the title resolves from Regular secondary ink to primary ink through the same
hover/focus emphasis environment as adjacent commands.
`ScholiumContentInteractionSurface` is the pure SwiftUI/AppKit mapping for
content-control hover and keyboard-focus surface emphasis. Hover resolves to a
low-opacity semantic `primaryText` veil, preserving the native toolbar's
relative light/dark response over every content plane without copying its
dynamic AppKit pixels; keyboard focus retains the stronger raised blend and
selection remains with its owning component. The overloaded
`scholiumActivationFocus` modifier keeps matching custom button-like controls
in the complete keyboard chain, clears pointer-generated keyboard-only focus,
and locally replaces the native focus effect with that shared surface without
inspecting AppKit events or changing window-wide focus behavior.
`scholiumContentControlPointerFeedback` is the single transient-presentation
owner for matching content controls. A zero-hit-test AppKit tracking adapter observes the
complete SwiftUI Button or Menu frame because the native Menu host does not
reliably forward pointer state into its label. The adapter translates hover and
press; the enclosing native control retains activation, focus, menu tracking,
and accessibility, while the shared resolver consumes its focus state and owns
semantic ink, one continuous surface, and immediate press dimming.
`ScholiumTriptychWorkspaceNavigator` owns
the three vertical workspace rows, neutral Note totals, selection/hover
surfaces, focus, and Up/Down traversal without owning the selected workspace. Its continuous
surface consumes the purpose-named workspace-navigation corner recipe and has
no Accent mark, underline, border, or shadow.
`ScholiumInspectorModeIndex` instead owns one selected shallow raised surface
and a quieter same-shape hover surface using the semantic editorial-control
corner recipe and a 4pt gap between adjacent state surfaces.
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
and two independent detail scroll owners. Its View index uses the shared
shallow interaction surface without an underline; Scope and Filters remain
borderless native Menus. The View index and detail navigation are native-
toolbar content; the adaptive
collection header owns identity, search, Scope, Filters, and count. The selected
Record allocates the remaining width to reading while its default-visible
Evidence rail stays between 260pt and 304pt. One native toolbar control removes
or restores the rail. One adaptive divider and the full-height
`readingEvidenceBoundary`, never color or shadow alone, distinguish the visible
planes; Increase Contrast removes the depth cue while retaining the divider and
surface relationship.
The Records scene uses a standard content view rather than
`fullSizeContentView`; AppKit's content-layout rectangle is therefore the one
titlebar boundary for every collection and detail scroll owner. The root hides
the native toolbar background, and macOS 26+ toolbar content hides its automatic
shared background, so Document color remains continuous without Liquid Glass or
a painted masking layer.

Every custom Records target routes hover, keyboard focus, and press through
`ScholiumContentInteractionSurface`. The toolbar View index and Inspector
ModeIndex also resolve persistent selection through that same shallow surface,
without an Accent underline or a filled segmented band. View items, menu labels, search clear,
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

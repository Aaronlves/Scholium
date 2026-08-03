# Architecture: Design System and Boundary Enforcement

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns design-system implementation, component boundaries, and executable enforcement; sibling chapters do not restate it.

## Design-system implementation

[Specification §19](../Specification/08-design-system.md#19-scholarly-editorialism-and-design-variables)
owns palette meanings, typography, opaque surface language, motion, the
adaptive editorial grid, and accessibility rules. The app implements that
contract in `Scholium/UI/Foundation` through `ScholiumColorVariables`,
`ScholiumColorResolver`, derived `ScholiumColorRole`s, `ScholiumGrid`,
`ScholiumMetrics`, `ScholiumMotion`, and `ScholiumInterfaceTypography`.

Accent and Paper are the only configurable inputs. Section 19.2's Paper is the exact
Light Document anchor; one resolver derives every other appearance role for
native and generated WebKit CSS. The complete Sidebar uses the Navigation
surface; Inspector uses a distinct Apparatus role whose tone is deliberately
much closer to Document than Navigation. Sticky Inspector headers and
relationship-glyph occlusion reuse that exact Apparatus role rather than a
floating-control surface. Matching `editor.css`
fallbacks preserve deterministic first paint. Functional/status anchors stay
private. Tests enforce the input boundary, mappings, parity, contrast, and
relationship variants; no static appearance palette or JSON mirror exists.

`ScholiumLibraryLocationPicker` owns the borderless native Location menu and
its single indicator without owning Location state. ScopeIndex and ModeIndex
pass their independent dimensions to `ScholiumEditorialIndexUnderline`, which
owns only the shared semantic color and visibility recipe. The Debug Editorial
Parchment acceptance board consumes these production components and resolved
roles; it is not a second design-system source.

The compact Recommended Bibliography component retains no explanatory subcopy
or horizontal candidate list. Its one native Button owns the full fixed band,
shows at most the first static citation preview, and opens the existing complete
surface. `ScholiumQuietRowButtonStyle` supplies the same raised hover/press
grammar used by Inspector summary/action rows without taking over each
consumer's purpose-owned height or insets.
`ScholiumMetrics.Library.bibliographyTopInset` and
`bibliographyBottomInset` map its asymmetric vertical rhythm to the shared grid;
the heading and accessibility group continue to carry Triptych-wide identity.
`ScholiumInterfaceTypography` owns the Folder, unselected Note, selected Note,
compact toolbar identity, bibliography preview, and bibliography empty-state
roles; leaf views no longer restate their sizes or weights.

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
- `ScholiumDocumentRhythm`, the unit-explicit
  `ScholiumDocumentPresentationConfiguration`, and `ScholiumWebDesignTokens`
  supply one responsive `rem`/CSS-pixel typography and minimum-inset contract
  to Read, Live Preview, and Source. `DocumentAppearanceSettings` owns one
  normalized **48–96ch** line-width value with a **72ch** default; generated
  presentation CSS exports it as `--scholium-document-line-width` together
  with an internal derived half-width length so the supported WebKit runtime
  does not depend on CSS division. Read/Live resolve it against Body type and
  Source against retained exact-source type. The shared CSS centers that
  measure subject to the mode-specific minimum inline inset, while dynamic
  presentation updates reuse the existing CodeMirror remeasure path rather
  than reconstructing editor state.

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
exact-window attachment, toolbar/delegate installation, explicit split
intents, and native visibility mirroring, but no
Triptych, document, or researcher-visible semantic state. `WindowShellState`,
`WindowWorkspaceController`, and the feature controllers own their bounded
state; `WindowModel` composes them and routes focused commands. This document records that
dependency direction, while the specification owns the stable rule for when
Scholium-specific components or distinct research surfaces are appropriate.

## Boundary enforcement

`ScholiumContractsTests`, `ScholiumApplicationTests`, and the architecture and
composition suites in `ScholiumAppTests` exercise their respective module,
runtime, window, document, presentation, and design-system boundaries.
`Tools/Scripts/verify.sh` adds package-graph, source-import, I/O, and public
symbol-graph guards so delivery targets cannot reacquire Core-owned authority.

See [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) for dated evidence,
reachable behavior, and remaining acceptance work. This document intentionally
does not duplicate test counts or claim that a historical pass proves the
current checkout.

# Scholium Design

Part of the canonical document set rooted at
[SCHOLIUM_SPEC.md](Docs/SCHOLIUM_SPEC.md). This document owns Section 19:
Scholarly Editorialism, visual language, design Variables, reusable component
and pattern presentation, layout, icon, motion, and interface writing. Sibling
chapters do not restate those rules.

Product and workflow chapters continue to own research meaning, domain-specific
state transitions, action semantics, authorization, conflict, recovery, and
interface information architecture. This document owns the cross-functional
state language and presentation contract in §19.9. [Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md)
owns modules and state ownership; [Implementation Status](Docs/IMPLEMENTATION_STATUS.md)
owns current reachability and evidence. This document may link to those owners
but never reconstructs their rules or treats target design as implementation
proof.

## 19. Scholarly Editorialism and design variables

**Scholarly Editorialism** combines humanist type, editorial hierarchy, warm
opaque surfaces, fine rules, marginal organization, deliberate whitespace, and
restrained color in a contemporary macOS environment—neither antique-book
imitation nor decorative minimalism.

Until sustained Usable Core acceptance, this is semantic direction, not a
pixel gate. Except accessibility, readability, source safety, and native
boundaries, Sections 18–20 metrics remain provisional and cannot override
native behavior, add state owners, or delay the core.

Canonical design system in brief:

- Document remains primary; Sidebar, Document, and Apparatus are distinct,
  opaque structural planes derived from one Paper resolver. The complete
  Sidebar shares one Navigation surface; Apparatus remains a document-adjacent
  margin whose tone is much closer to Document than Navigation. One continuous
  document-navigation boundary depth cue lets the Document/Apparatus work field
  advance subtly over Sidebar without turning any plane into a card.
- System sans organizes interface structure, Alegreya carries readable
  research content, and Victor Mono identifies exact source and revisions.
- Typography, the purpose-named 4pt grid, whitespace, alignment, and semantic
  color establish hierarchy before rules, containers, or elevation.
- Native macOS controls own geometry, focus, selection, menus, sheets, and
  transient presentation. Scholium adds no parallel window or control skin.
- Inspector uses one ModeIndex with one selected editorial-control surface,
  section/fact/reading grammar, a native local
  Connection Direction Control, relationship clusters, Action rows, and local
  state views; ordinary rows and sections are borderless by default. Library's
  canonical target uses one TriptychWorkspaceNavigator, stable Triptych
  Attention entry, LocationPicker, and Source List under §18.3.
- Interface copy follows §19.6; cross-functional state presentation follows
  §19.9; and every component carries the applicable keyboard, accessibility,
  localization, appearance, and recovery requirements from §20.

Exploratory documents retain only unresolved proposals. Once a visual recipe
enters this specification and becomes reachable, its implementation evidence
belongs in [Implementation Status](Docs/IMPLEMENTATION_STATUS.md), not in a
parallel design guide.

### 19.1 Liquid Glass and material boundary

Liquid Glass is not part of Scholium's interface language. Do not use
`glassEffect`, `GlassEffectContainer`, glass button styles, refractive morphing
chrome, or another Liquid Glass treatment to define Scholium surfaces or
controls.

Transparency, blur, vibrancy, and native or custom glass/material effects are
not categorically prohibited. They may be used for a named local task when
they preserve readability, contrast, focus, hit testing, adaptation, and the
surrounding native ownership boundary. Native material is preferred when it
fully serves the task; a custom effect still requires a concrete remaining
gap. A local effect does not automatically become a design Variable, brand
token, card recipe, or permission to glassify another surface.

The structural Sidebar, Document, and Apparatus planes remain opaque under
§18.2. Their one approved Workspace depth cue is the opaque-surface
document-navigation boundary in §19.3; it adds no material or transparency to
the planes. The §18.3 Put Back veil is an explicitly approved bounded native
Sidebar material: it transiently covers the untruncated title beneath the
trailing control, owns no geometry or action state, and creates no card or
additional plane.

System chrome, menus, presentations, controls, focus, selection, semantic
Sidebar/Inspector, and tracking separators stay native. Document tabs are
ordinary Document controls, not simulated window tabs.

Research Guidance, Actions, permission sheets, and Research Record use
continuous native planes, textual list/detail structure, editorial hierarchy,
fine rules, alignment, and deliberate whitespace. They do not use per-Skill
cards, colorful category tiles, score badges, agent avatars, chat bubbles,
nested rounded containers, or decorative workflow diagrams. Selection and
consequence remain clear through native state, typography, symbols, and text.

Library Locations retain one opaque navigation plane. Location content neither
dims retained content nor floats above it, and adds no material, reflection,
grabber, rounded panel, accessory row, separately measured bar, local shadow,
or sheet motion. It neither owns nor alters the Workspace boundary depth cue.
The LocationPicker's transient menu remains system-owned rather than becoming
a Scholium popover. Pane-local content hosts consume the native safe area once;
the titlebar and its single native toolbar own visibility-control alignment.

Research Records reuses the existing native list/detail structure, search and
empty/error states, structural rules, semantic surfaces, typography, native
menu, checkbox, sheet, and focus behavior. Its native titlebar remains ordinary
window chrome. View uses the existing restrained editorial-index underline at
the top of the Navigation plane; Scope uses one borderless native menu in the
list-context row. Neither becomes a filled segment, full-width control band,
feature toolbar, or Liquid Glass container. The leading List reveals the
Navigation surface instead of a default scroll background, and reading-plane
actions share one borderless ink-and-hover treatment. The auxiliary window
consumes the same persisted System/Light/Dark choice and resolved semantic roles
as Workspace rather than inventing a local appearance state. Recommendations
adds no palette, card recipe, badge, bespoke split, Sidebar treatment, or new
visual Variable.

### 19.2 Typography and color

- System sans is interface structure: navigation names, chrome, menus,
  controls, Settings, alerts, section headings, field labels, action names,
  dates, compact scanning cues, and every Connect relationship heading and Note
  row. The fixed **Scholium** Alegreya wordmark remains the identity exception.
- Library Folder and unselected Note titles use the same 12pt Regular system
  role; only the selected Note uses Semibold. The compact Document-toolbar
  identity uses the 13pt system body role with secondary ink.
- **Alegreya** is for Review/Edit prose and may identify content-derived
  titles, linked research objects, researcher judgments, field values,
  explanations, Scope, Limitations, and other research content when density,
  scaling, and mixed-script fallback remain legible.
- Apparatus text never exceeds the adjacent Document Body at the default
  Appearance. Its interface labels and headings use the quieter semantic text
  roles; its 12pt content values and explanations may use Alegreya, but small
  text still meets §20 contrast and mixed-script legibility requirements.
  Connect remains a flat operational scan surface and therefore uses Sans for
  its complete visible language even when a row names a research Note.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, paths, stable identifiers, and diffs.
- The default Appearance uses a **72ch** Line width plus **Alegreya 12pt**,
  **2.0** line spacing, **1em** paragraph spacing, **0.02em** tracking,
  zero first-line indent, zero word spacing, justified text, no hyphenation,
  kerning, and common ligatures. Line width is configurable from **48–96ch**
  in **1ch** steps and is shared by Review, Edit, and Source.
- Default headings use the Body family, upright style, **500** weight,
  **1.8** line spacing, and zero tracking. H1 is **200%**, centered, with
  **0em** before and **2em** after; its fine separator sits **0.5em** below the
  final title line inside that after-space rather than at the space's outer
  edge. H2 is **150%**, start-aligned, with
  **0.6em** before and after; H3–H6 are **115%**, start-aligned, with **0.5em**
  before and after. A long or mixed-script title wraps inside the same measure.
  The first paragraph after a heading retains ordinary Body rules. Scholium
  introduces no Abstract-specific hierarchy; an authored Abstract label is an
  ordinary heading.
- These document typography values are user-configurable. The eight protected
  Callout roles inherit Body typography and expose independent role
  spacing/composition parameters without acquiring a separate palette.
  Ordinary Markdown quotation remains selectable prose, uses the semantic
  Accent boundary in Review and Edit, and never becomes a Callout or card.
  Lists retain ordinary Body line height inside each contiguous list: list
  items and nested lists add no paragraph gap or semantic block gap between
  rows. Review and Edit share one marker track, marker-to-prose gap, nesting
  step, and task-control size; bullet shape, order width, task state, and exact
  prefix exposure never shift the prose column. Only the complete top-level
  list participates in surrounding document block spacing. Edit keeps every
  Markdown paragraph-separator blank line as a
  real, keyboard-addressable exact source line. Its measured line box supplies
  the corresponding Review paragraph gap; Edit does not collapse it or add the
  same gap again to the preceding paragraph. Consecutive authored blank lines
  remain distinct source lines. When Edit exposes an active fenced code block,
  its block surface ends with the exact closing fence and adds no blank-looking
  inset below that delimiter; any following authored separator remains a
  separate keyboard-addressable line and owns the surrounding rhythm.
  Tables, code, and mathematics keep object-local horizontal overflow; the page
  itself never gains horizontal reading scroll. Display mathematics remains
  centered and italic with its number on a separate physical-right track.
  Footnote references retain Review-owned preview/navigation; Edit uses the
  reference only to locate the one directly editable definition under §5.1;
  the definition marker stays exact while its body uses ordinary
  construct-scoped Edit projection at that same source position.
- Native document selection remains authoritative in Review, Edit, and Source,
  while its visible paint uses the same resolved Accent mix on every surface;
  Review never falls back to a system-blue block selection. Layout-only block
  boundaries, padding, and paragraph gaps do not receive selection paint.
  Markdown `==text==` uses one fixed, nonconfigurable **Markup highlight**
  background `#FF9A00` with contrast-safe dark ink in Review and Edit. It is a
  syntax role, not Accent, status, authorship, Connection meaning, or a third
  researcher-configurable color input.
- Provide intentional CJK serif fallback and test mixed Chinese/Latin lines.
- Color exposes exactly two approved sRGB inputs: **Accent** `#A94C22` and
  **Paper** `#FEF8ED`. In Light appearance Paper is the illuminated Document
  plane; one resolver derives every other Light output and every Dark and
  Increase Contrast semantic output. The complete Sidebar uses one recessive
  and neutral `navigationSurface`. Inspector's
  `apparatusSurface` is a document-adjacent Paper role: it remains subtly
  distinct across the native split while staying perceptually much closer to
  `documentBackground` than to Navigation. These roles are not additional
  author inputs or palettes; their exact separation is provisional and must
  retain text/state contrast under every appearance. No derived output or
  functional/status hue is independently configurable.
- Native and WebKit surfaces consume the same derived semantic color outputs.
  Feature views name no raw value, and generated WebKit properties are
  transport, not a second palette. Private functional/status anchors adapt to
  appearance and contrast.
- Status, authorship, and Connection colors remain distinct with text/symbol
  redundancy. Color never encodes philosophical value, truth, support, or
  authority.
- Bootstrap fields use `#99815A`, `#5C7180`, `#728B80`, and `#805B57`;
  parchment, ink, and accent use `#E8D2AC`, `#19303D`, and `#9B4A2B`.
  This closed palette is not an input or state.

### 19.3 Variable boundary

Keep eight families: Color, Typography, Surfaces, Elevation, Boundaries,
feature Metrics, Motion, and provisional Document Rhythm. Promote only stable
cross-component decisions or critical thresholds. The adaptive grid uses a
bounded **4pt** foundation with a **2pt** optical exception; APIs expose
purpose-named roles, never numbered positions. Invent no numbered opacity,
radius, shadow, border, gradient, or paper scales.

#### Corner geometry

Corner geometry follows component responsibility and containment rather than
one application-wide numeric scale.

- System windows, toolbars, menus, sheets, popovers, and native controls retain
  their platform-owned shapes. Scholium neither copies their current numeric
  radii nor adds a parallel control skin.
- Matching instances of the same component responsibility and size use one
  shape recipe. A leaf View never names a raw radius; a fixed radius belongs
  only to the owning component, surface role, or purpose-named feature metric.
- A custom surface adjacent to or nested inside a rounded container uses
  container-concentric geometry. When the supported platform cannot resolve
  that geometry, one purpose-owned fixed fallback preserves the same visual
  relationship rather than creating a second appearance.
- A border does not imply rounding. Ordinary lists, structural separators,
  toolbar symbols, and unbounded content do not acquire a custom rounded
  enclosure merely to make geometry appear uniform. Capsules remain
  native-owned or require a named full-height enclosure; they do not create
  tag walls, card families, or decoration.
- Native and WebKit presentations share a corner recipe only when they express
  the same semantic construct. Distinct constructs may use distinct fixed
  geometry.

Corner shape never carries state or authority by itself; boundary and focus
adaptation continue to follow §20.

- Interface type roles: identity, section title, row title, metadata, and
  narrowly approved editorial hierarchy. Library exposes purpose-named Folder,
  Note, selected-Note, and Attention-alert roles; the toolbar exposes the
  compact-identity role.
  These roles may resolve to a shared point
  size but leaf views do not recreate their weights or sizes. Document Body
  and heading roles are owned by `DocumentAppearanceSettings`; native helpers
  cover Exact Source, Code, Diff, and Revision Identity only.
- Document Appearance exposes one machine-local Line width input with the
  default, range, unit, and shared-mode ownership in §18.4. Document Rhythm
  adds no second built-in typography or measure path.
- The Color family exposes only the two approved Accent and Paper inputs.
  Semantic roles are resolver outputs, not additional Variables; components
  consume those roles without owning a palette value.
- Structural Sidebar, Document, and Apparatus surfaces are opaque semantic
  planes; bounded local glass or material follows §19.1. Their sole structural
  depth exception is the Workspace-owned document-navigation boundary below.
  Dense evidence is quietest and most legible.
- The Sidebar's Triptych Attention entry is one stable presentation component,
  not an owner of diagnostics or counts. It shares the Triptych identity row
  and uses one direct warning symbol. At rest it has no background: zero uses
  secondary ink without a number, while nonzero places the exact aggregate
  Triptych total beside, never over, the symbol and uses Attention ink for both.
  Hover, keyboard focus, press, and an open popover place one shared shallow
  interaction surface behind the complete symbol-and-count target; the symbol
  never owns a separate circle and the count never becomes a badge. Checking
  and unavailable retain the same identity and expose complete state and Retry.
  No Attention count, aggregate, or anchor is projected into the Document
  toolbar or individual workspace rows.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones. Apparatus sections, ordinary rows, and Action rows default to no
  boundary; a consumer must explicitly request a boundary for a named semantic
  distinction.
- Elevation is a purpose mapping, never a numbered depth or shadow scale.
  System-owned windows, panels, menus, popovers, sheets, and alerts retain
  their native elevation and receive no Scholium shadow wrapper. The sole
  structural role is **document-navigation boundary**. Workspace owns it at the
  Document's logical leading edge and casts it only into Sidebar, continuously
  from the window top through the titlebar/toolbar background to the bottom.
  The native toolbar and 1pt tracking separator remain in front, interactive,
  and geometrically authoritative. The cue is noninteractive, has no motion,
  mirrors in right-to-left presentation, disappears with Sidebar, and never
  appears between Document and Apparatus. Its provisional active-Light recipe
  uses AppKit's semantic shadow color at **0.04** opacity, **8pt** blur radius,
  **2pt** logical offset toward Sidebar, zero vertical offset, and no spread.
  Dark appearance, an inactive window, or Reduce Transparency resolves opacity
  to **0.02** without compounding; Increase Contrast resolves it to zero and
  relies on the native separator plus semantic surface difference.
  A Scholium-owned transient surface separately uses exactly one of three
  roles: **floating control** for compact selection, status, and loading
  controls; **bounded panel** for a larger custom menu, preview, or locally
  bounded presentation above content; and **search overlay** for the centered
  Search command surface. No other structural or ordinary content surface has
  elevation. A child does not accumulate its parent's shadow, and a leaf view
  never supplies shadow color, opacity, blur, or offset. Surface, boundary,
  text, and position must communicate ownership when any shadow is absent.
- Native controls own interaction states. Custom targets prefer **28pt** and
  never fall below **20pt**; this does not redefine native sizes. Custom
  button-like controls share one pointer-neutral focus policy: each stays in
  the complete native keyboard focus chain, while a pointer press clears the
  keyboard-only focus state before activation settles. Matching controls
  locally replace the system focus effect with the shared content-focus
  surface; a caller never samples the current AppKit event or suppresses focus
  effects for the window or application.
- Toolbar symbols use system-owned geometry, hover, focus, and press behavior;
  they receive no Scholium underline or custom active enclosure. A custom
  content control uses an immediate state change with no geometry animation:
  secondary ink at rest, primary ink on hover or focus, and a purpose-owned
  surface only when its component responsibility requires one. Every
  Scholium-owned content control consumes one shared adaptive hover-surface
  resolver; no SwiftUI or AppKit caller supplies a local hover color or opacity.
  That resolver uses one translucent semantic-ink veil whose relative contrast
  follows the native toolbar's system hover on every underlying content plane;
  it does not sample, copy, or freeze the toolbar's current AppKit pixel value.
  Keyboard focus remains a stronger raised treatment, while Navigation
  selection keeps its purpose-owned persistent surface.
  Matching LocationHeader icon controls reuse one exact **28 × 28pt** outer
  target and the editorial-control shape recipe; LocationPicker and Triptych
  Attention instead fit their complete text or count content at the same
  preferred height. LocationPicker uses 13pt Regular secondary ink at rest and
  promotes to primary ink on hover or keyboard focus without changing weight;
  its hover, focus, and press states use the same editorial-control shape
  rather than stacking a native enclosure. Triptych workspace rows own one continuous Navigation
  selection shape, while ModeIndex selected and hover surfaces use the
  editorial-control recipe. No leaf supplies a raw radius, and no capsule is
  inferred from selection or a count.
- Standard actions and Vector Link relationship marks use direct SF Symbols.
  Text remains primary; Scholium owns no parallel custom Vector Link glyph
  family.
- Grid roles are optical alignment **2pt**, label/accessory **4pt**, inline
  control **8pt**, nested content **12pt**, section separation **16pt**, and
  region content **20pt**. The two peripheral planes share a separate **28pt**
  page-edge inset; their internal rhythms remain purpose-owned. Fixed
  component anchors remain purpose-owned:
  preferred/minimum custom targets **28/20pt**, Document tab strip **40pt**,
  Action target **44pt**, and region header **48pt**. A general compact
  **24pt** row role does not size Library rows, and Library has no fixed
  lifecycle-footer anchor.
- The Library's **300pt minimum readable thickness** is a component-specific
  containment threshold outside the grid, not a spacing role, preferred width,
  or scene minimum.
- Peripheral metrics own the shared **28pt** outer page edge for Library and
  Inspector. Library metrics independently own the
  Library's **12pt** row-surface inset, **28pt** minimum row rhythm, **16pt**
  hierarchy indentation step, **12–14pt** semantic leading slot, **8pt**
  leading-to-title gap, and the Triptych workspace-row selection recipe.
  Ordinary row content begins at the 12pt inset while a selected or pressed
  navigation feedback surface may span the Source List width; the surface does
  not change the content axis. Content headings and principal controls align to
  the shared 28pt page edge. BrandHeader and LocationHeader retain
  intrinsic content-driven height rather than copying a toolbar or
  footer height. BrandHeader-to-workspace spacing uses the **12pt**
  nested-content role rather than another local value. Workspace rows retain
  the preferred **28pt** target, grow rather than clip, and align their
  noninteractive Note total at the logical trailing edge. That total uses
  system Sans, monospaced digits, and `mutedText` without a background or
  hover promotion. These values remain provisional until they pass the 300pt,
  localization, scaling, contrast, and human visual-acceptance matrix.
- Apparatus metrics map the outer inset to the shared peripheral edge and
  independently own the Inspector ModeIndex's shallow editorial-control state
  surface, **4pt** separation between adjacent local states, **78pt** minimum fact
  label column, **14pt** fact-column gap, **204pt** horizontal FactGrid
  threshold, and **44pt** Action-row rhythm. Connect uses a four-level
  Inspector cadence rather than copying the Library: **16pt** separates its
  direction control, freshness line, and complete role groups; **8pt** leads
  from a nonempty role heading to its first relationship cluster; **12pt**
  separates relationship clusters; and Note rows use a **28pt** minimum rhythm
  with **4pt** between each relationship heading and its rows. Its native
  direction control is centered on the Inspector content axis and grows only
  to a **240pt** maximum before narrower Inspectors compress it. Absent
  freshness, empty groups, and the scroll anchor add no hidden spacing. These
  names may reuse a general value only when the purpose is genuinely the same;
  Inspector-specific rhythm is not expressed by borrowing a peripheral or
  Library metric.
- Research Records independently retains its existing **18pt × 1pt** View
  selection underline; it does not borrow the removed Inspector-mode metric.
- The one-time **320pt** first-reveal request is a native-container initial
  condition outside the grid. It is not a design Variable, persisted setting,
  minimum, maximum, or continuously enforced preference.
- Set Aside and Trash reuse the Library metrics and common OutlineRow
  and LocationHeader components. They create no parallel lifecycle spacing
  namespace, destination header, or footer role.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, decorative motion, or repeating
  Attention pulse. Conditional Attention count and emphasis remain
  understandable with motion entirely absent. Native controls retain their
  system feedback; custom controls use an immediate semantic state change for
  hover, focus, press, and
  disabled feedback rather than adding geometry animation to frequent actions.
  Motion is reserved for a named content or structure transition: disclosure,
  document reveal, search presentation/expansion, transient status, Triptych
  workspace change, and the bounded Bootstrap step transition. A Triptych
  workspace change keeps the selected-workspace control, LocationHeader,
  native titlebar, toolbar, split surfaces, dividers, Document, and Apparatus
  stationary. Only the safely committed destination Source List content uses
  one shallow top-origin settle: it begins **6pt** above its final position,
  remains clipped to the source region, and moves downward while fading in over
  **0.18s ease-out**. The complete tree or Location state moves as one object;
  rows never cascade, a long tree receives no sweep or delayed tail, and the
  origin tree does not remain as a second interactive or accessibility
  subtree. Repeated input interrupts and retargets the latest safely committed
  destination rather than queueing animations. Reduce Motion installs the
  destination without offset, opacity transition, or delay. Workspace identity,
  selection, and destination content remain fully legible when motion is
  absent.
- Document rhythm is renderer-aware and uses the approved default and adaptive
  behavior in §18.4 and §19.2.

### 19.4 Provisional layout defaults

Layout defaults support testing, not independent gates. Native containers own
chrome and split geometry; Scholium owns semantic order and necessary content
insets.
Scenes have no Scholium numeric minimum unless the complete adaptation matrix
proves one. Independently, the Library content threshold in §18.2 adds no
preferred/maximum width or persisted divider position. The first-reveal
**320pt** Apparatus request is applied at most once per newly created native
split controller and is skipped or clamped when Document space cannot
accommodate it; later hiding, showing, restoration, and direct resizing never
replay it.

Initial sizes are Workspace **1180 × 760**, Bootstrap **760 × 740**, Research
Record **760 × 680**, and fixed Settings content **700 × 560**. Regions scroll
independently; Document takes remaining space without a fixed size. Native
geometry stays outside the grid. WebKit uses `rem`, `ch`, CSS px, and viewport
units without point conversion. The selected **48–96ch** Line width is centered
inside the available Document width while `max(...)` retains the **20/32/40 CSS
px** minimum border separations. Wide rendered tables, code, and mathematics
may scroll inside that measure; rendered prose reflows without page-level
horizontal reading scroll. Source mode instead soft-wraps every exact logical
line within its measure without changing source line breaks or line numbers.
The 72ch default and typographic rhythm apply at ordinary, narrow,
mixed-script, and 100%/200% text presentations. Screenshots and prototype
coordinates remain evidence only and never define native/CSS unit conversion.

### 19.5 Icons and symbols

#### Interface symbols

Standard actions, navigation, toolbar commands, and relationship marks use the
direct SF Symbol that names the action or concept. Interface symbols default to
one restrained monochrome rendering mode and match the optical weight and scale
of their adjacent interface text. A symbol is decorative only when its visible
label already carries the meaning; otherwise its control or status has a complete
accessible name. Scholium owns no parallel action-glyph family.

Icon color is a semantic role, not a local tint:

| Use | Role | Constraint |
| --- | --- | --- |
| Passive leading or ordinary command icon | `secondaryText` | The resting icon does not compete with its label. |
| Hovered, focused, or selected command icon | `primaryText` | State change is also expressed by native focus, selection, label, or surface. |
| Disclosure, chevron, or auxiliary trailing glyph | `mutedText` | It never carries the only state or navigation meaning. |
| Active selection mark or bounded primary action | `accent` | Accent is not the default color for every actionable symbol. |
| Attention, destructive, confirmed, agent-authored, and Connection marks | Their existing semantic role | Text, shape, or accessible state must repeat the meaning; hue never declares truth, value, authority, or correctness. |

Native control tint, disabled rendering, focus indication, and selected-state
painting remain system-owned where a native control already supplies them. A
custom interface glyph consumes the resolved `ScholiumColorRole` in both native
and WebKit surfaces; it does not name `.tint`, `.primary`, `.secondary`, a raw
system hue, or a second local palette. SF Symbol palette, multicolor, gradient,
and variable-color rendering are not used to encode Scholium workflow state.
Hierarchical rendering is limited to bounded Bootstrap concept illustrations
when the single semantic source color and the accompanying text remain clear.

#### Bootstrap narrative illustration

Fixed compositions:

| Stage | Hand / pattern / field | Tuning |
| --- | --- | --- |
| Welcome | Point / Flow / Golden Ochre | `0, 0`; `1.00`; `0°` |
| Triptych | Offer / Flow / Mineral Blue | `-115, -180`; `1.18`; `78°` |
| Agent | Unlock Straight / Converge / Verdigris | `+60, 0`; `1.00`; `0°` |
| Ready | Lift / Converge / Oxblood | `+24, +57`; `0.96`; `0°` |

Fields are decorative and absent from accessibility. No tuner, guide, or
inferred readiness ships.

#### Application icon

The canonical Scholium application icon is the exact researcher-approved
parchment-and-ink composition: a cuffed hand points right toward one vertical
marginal rule and six short manuscript strokes. Its composition, orientation,
paper grain, ink character, and rounded parchment field are application
identity, not Appearance settings or design Variables.

Use this artwork only as the application icon. Do not recolor it through the
Accent/Paper resolver, mirror it for right-to-left interfaces, substitute an SF
Symbol, reuse it as a state or action glyph, or add text, badges, shadows, or
other Scholium-owned effects. Debug, QA, and release bundles derive their icon
representations from the same approved artwork. The platform may scale or mask
those representations; Scholium does not crop, recompose, or maintain a second
icon lineage. Replacing the artwork requires explicit researcher approval and
an update to this canonical rule.

### 19.6 Interface writing and explanatory copy

Interface words earn their space. A control or Action begins with the shortest
accurate label that lets a researcher predict its immediate result. Prefer a
direct verb or established research term; do not add explanatory copy merely
to restate the label, nearby heading, standard component, or visible state.

Visible supporting copy is optional. Add it only when the label and immediate
context cannot communicate a necessary research boundary, unfamiliar result,
or first executable repair. Use one short sentence or fragment authored to fit
within two lines at the component's ordinary supported width and default text
size. Localization, mixed scripts, and 200% text may reflow rather than
truncate, but the source wording does not expand to compensate. An unavailable
Action replaces its ordinary explanation with only the first executable
repair; it does not show both.

One meaning has one presentation:

- A visible explanation is never repeated as a tooltip or accessibility hint.
- A macOS tooltip describes only the indicated control, begins with the action,
  repeats no visible name, and stays within 60–75 Latin characters or an
  equivalently terse localized phrase.
- An accessibility hint adds only a result, consequence, or context missing
  from the current label, role, value, and visible copy. Brevity never removes
  the names, values, state, or consequences needed to complete the task.
- Permission, provenance, destructive consequence, conflict, failure, and
  recovery detail belongs in the relevant body, alert, comparison, or sheet.
  It is neither hidden nor truncated to make a button annotation appear short.

Default Actions prefer title-only rows when their group and title already
identify the task. Researcher-defined Actions may use one terse explanation
when the title cannot faithfully distinguish their declared boundary. No
control accumulates a label, subtitle, tooltip, and adjacent paragraph that all
explain the same action.

Compact Freshness, checking, stale, and Settled state lines obey the same
nonduplication rule and do not become independent sections or cards. Error,
conflict, permission, cancellation recovery, and source-protection detail is
complete even when it exceeds two lines.

### 19.7 Component catalog

This is the canonical catalog of Scholium-specific reusable presentation
responsibilities. An entry names the researcher task, structure, states,
accessibility and adaptation contract, semantic owner, and evidence route. A
component owns no document, workflow, authorization, navigation, or operation
lifecycle. Native controls remain the component owner when they already carry
the required meaning.

| Component | Scholium task and presentation contract | Do not turn it into | Semantic owner |
| --- | --- | --- | --- |
| `Sidebar / Document / Apparatus` | Keep Document primary across three opaque planes; one full-height Sidebar-edge cue advances the Document/Apparatus work field without replacing the native divider. | Cards, a floating Inspector, a parallel divider, or a dashboard. | §18.2 |
| `Triptych Workspace Navigator` | Presents Analyses, Topics, and Works as full-width destinations with one persistent Navigation selection and quiet, exact Note totals. | A Scope filter, pipeline, project selector, segmented band, or Attention counter. | §§3.2, 18.2–18.3 |
| `ModeIndex` | Selects one local Inspector mode through a shallow editorial-control surface while retaining focus, pointer, keyboard, and RTL behavior without an Accent underline. | A workspace navigator, filled segmented band, or Document tab strip. | §18.5 |
| `Source List` | Organize Locations and Notes as a quiet, hierarchical source navigation surface with explicit selected, empty, loading, and error states. | A tile grid, lifecycle badge wall, or content preview card. | §18.3 |
| `Connection Direction Control` | Switch Connect between Incoming and Outgoing through one native two-segment control. Undirected relations appear in both with source anchors preserved. | A Combined/All segment, an index replacement, or a second graph owner. | §§12, 18.5 |
| `Action Row` | Expose one bounded Research Action with its declared intent, scope, current state, consequence, and first repair. | An agent avatar, chat bubble, score badge, or generic command card. | §§8–11, 18.5 |
| `Triptych Attention Entry` | Keeps one stable Sidebar route to the complete Triptych queue and adds the exact nonzero aggregate beside its warning symbol without imitating a notification badge. | Per-Vault counters, a bell, pulse, diagnostic owner, or Document-toolbar item. | §14, §18.3 |
| `Recovery Notice` | Present a persistent workflow-supplied condition, consequence, and repair or inspection action as a Document notice or Workspace banner. | A generic error or Search banner, runtime state owner, or recovery coordinator. | §§5.3, 14, 18.2, 18.6 |
| `Content State` | Presents page or pane state with one restrained indicator, title, optional explanation, and adjacent repair action. | A runtime state owner, card, or compact inline feedback. | §§18.2–18.5, §19.9 |
| `Bootstrap Narrative Illustration` | Frames each fixed onboarding stage while adjacent text remains complete. | A state indicator, selector, interactive diagram, tuner, or icon variant. | §16, §§19.2, 19.5 |

The catalog is presentation authority, not a replacement for the owning
workflow rule. New entries require a distinct task, a single state owner, a
reusable adaptation boundary, and a proof that can reject the component.

### 19.8 Pattern catalog

Patterns combine components around one Scholium research task. Their entries
describe entry context, information order, primary action, feedback,
cancellation, failure, recovery, focus return, and concurrent participants;
the owning workflow chapter remains authoritative for meaning and permission.

| Pattern | Scholium task | Presentation boundary | Semantic owner |
| --- | --- | --- | --- |
| `Workspace Shell` | Move among three retained Triptych workspaces without losing their Library, tabs, Document, or Apparatus context. | One native window and fixed split geometry; only role-partitioned content changes inside the three planes. | §§3.2, 18.1–18.3 |
| `New Note` | Start writing immediately while source bytes stay authoritative and derived work remains off the hot path. | Direct-to-Edit readiness, retained focus, and non-blocking derived refresh. | §§5–7, 18.3–18.4 |
| `Review / Edit / Source` | Read, edit, and inspect one source through reversible projections. | One live mode per retained Triptych workspace session rather than a history keyed by Note or tab, shared measure, and distinct source and rendered typography. | §§5–7, 18.4 |
| `Search` | Retrieve bounded research material with explicit provider, scope, explanation, and freshness. | Stable command surface, retained context, and distinct empty/stale/error results. | §§12–14, 18.3 |
| `Connect` | Inspect direct relations from the current Note through an Incoming/Outgoing view switch, typed relationship subheadings, and source-located rows. | A file hierarchy, inferred graph, evidence verdict, or multi-hop exploration surface. | §§12, 18.5 |
| `Attention` | Enter the complete Triptych queue from one stable Sidebar control or add an exact current-Note subset from Inspector without interruption. | One native transient presentation; zero removes emphasis and count but not the Triptych route. | §14, §§18.2–18.3 |
| `Research Action` | Prepare, run, inspect, settle, and optionally write a bounded Agent result. | Intent-first Action row, visible state transitions, cancellation, and recovery. | §§8–11, 18.5 |
| `Conflict / Recovery` | Preserve authored bytes when an external participant changes the source. | Retained buffer, exact revision comparison, selective choice, and reversible restore. | §§12–14, 18.4–18.6 |
| `Research Records` | Review portable records without reconstructing writable research Markdown. | Native list/detail reading structure with source and derived evidence distinct. | §14, §18.5 |
| `Bootstrap Agent Preparation` | Installs the CLI, copies one prompt, and accepts confirmation without granting research access. | An Agent launcher, provider picker, readiness manager, Session, or Run handoff. | §16 |

Patterns may reference multiple components, but they must not introduce a
second state owner or copy a workflow's authorization and recovery rules.

### 19.9 Cross-functional state language

This section is the shared design vocabulary for states that recur across
components and patterns. It standardizes what a researcher sees and what the
interface must communicate; the owning workflow still defines the underlying
meaning, transition, authorization, source revision, and recovery operation.
Do not implement this table as a universal runtime state enum or presentation
store. A component receives a typed state from its existing owner and maps it
to this language plus its domain-specific label.

| State | Shared presentation meaning | Required Scholium treatment | Not equivalent to |
| --- | --- | --- | --- |
| `Ready` | A trustworthy committed representation is available and relevant actions may be offered. | Preserve the normal context and expose the next valid action without extra status decoration. | `Saved`, `Settled`, or merely “the view loaded”. |
| `Loading` | No trustworthy committed projection is available yet, or an explicit refresh owns the wait. | Retain identity and context; name the work; never use an empty layout as a loading disguise. | Empty, unavailable, or stale content. |
| `Empty` | The requested valid scope contains no authored or derived items. | Explain what is empty and provide the first relevant next step; keep the scope and destination visible. | Missing source, failed read, or unresolved result. |
| `Unavailable` | A required source, provider, permission, or capability cannot currently serve the task. | State what is unavailable and expose the first executable repair or a safe alternative. | Disabled styling with no explanation. |
| `Stale` | A visible derived or remote projection represents an older committed revision. | Identify freshness and preserve the last trustworthy content while refresh/retry remains explicit. | Conflict or a failed operation. |
| `Error` | A read, render, query, or operation failed. | Preserve useful context, name the impact, and expose Retry or the smallest safe alternative. | Empty, unavailable, or silent disappearance. |
| `Conflict` | Two authoritative or active source participants no longer agree on the expected revision. | Retain the authored buffer, identify the competing revision, and route to comparison or an explicit choice. | Stale derived data, Undo, or ordinary Save Failed. |
| `Recovery` | The interface offers a reversible or explicitly consequential path after failure or interruption. | State the candidate source, consequence, reversibility, and final verification condition before action. | A generic toast, ordinary Undo, or automatic overwrite. |
| `Disabled` | An otherwise known action cannot be invoked under the current prerequisite or policy. | Keep the control discoverable when it is part of the core task and expose the missing condition without relying on low contrast. | Unavailable content or an omitted non-core control. |
| `Running` | A researcher-started Research Action is executing within its declared scope. | Keep the Action identity, current state, cancellation/end route, and focus path visible; motion is supplementary. | Loading a passive projection or background refresh. |
| `Settle` | A Research Action result is ready for the researcher to inspect and decide. | Keep result, provenance, uncertainty, and write boundary distinct; do not imply adoption. | Settled or an authorized write. |
| `Settled` | The researcher has explicitly recorded the Action result's disposition. | Show the disposition and durable record route without implying that source Markdown was rewritten. | Successful execution or automatic acceptance. |

Every state presentation follows five invariants:

1. Retain the researcher's visible context and the state owner's identity.
2. Communicate state, consequence, and first repair through at least two suitable
   channels, consistent with §20.
3. Keep domain-specific labels and exact source/revision details in the owning
   workflow rather than replacing them with a generic status word.
4. Do not use color, motion, hover, position, or a transient timeout as the sole
   state channel.
5. A state transition must preserve cancellation, focus return, source safety,
   and recovery semantics owned by the underlying workflow.

Page- and pane-level state copy uses the `Content State` component. Its symbol
or progress indicator remains restrained at the approved interface scale; the
title uses primary interface ink and the explanation uses secondary ink within
one readable measure. An Attention-colored symbol supplements, but never
replaces, explicit Unavailable or Error language. The component keeps repair
actions in the same content flow so they cannot overlap explanatory text at a
narrow width. Compact Inspector rows, field-level validation, transient status,
and persistent recovery notices keep their purpose-owned components and apply
the same vocabulary without adopting the page layout.

The component catalog and pattern catalog must reference this vocabulary when
describing normal, degraded, loading, empty, error, conflict, and recovery
presentations. They must not invent synonyms for the same cross-functional
state without documenting a distinct product meaning.

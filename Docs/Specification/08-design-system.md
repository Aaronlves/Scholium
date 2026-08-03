# Specification: Scholarly Editorialism and Design System

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Section 19: visual language, Variables, layout, icon, and interface writing; sibling chapters do not restate it.

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
  margin whose tone is much closer to Document than Navigation.
- System sans organizes interface structure, Alegreya carries readable
  research content, and Victor Mono identifies exact source and revisions.
- Typography, the purpose-named 4pt grid, whitespace, alignment, and semantic
  color establish hierarchy before rules, containers, or elevation.
- Native macOS controls own geometry, focus, selection, menus, sheets, and
  transient presentation. Scholium adds no parallel window or control skin.
- Inspector uses one ModeIndex, section/fact/reading grammar, relationship
  clusters, Action rows, and local state views; ordinary rows and sections are
  borderless by default. Library's canonical target uses one ScopeIndex,
  LocationPicker, and Source List under §18.3.
- Interface copy follows §19.6, and every component carries the applicable
  keyboard, accessibility, localization, appearance, and recovery states from
  §20.

Exploratory documents retain only unresolved proposals. Once a visual recipe
enters this specification and becomes reachable, its implementation evidence
belongs in [Implementation Status](../IMPLEMENTATION_STATUS.md), not in a
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
§18.2. The §18.3 Put Back veil is an explicitly approved bounded native Sidebar
material: it transiently covers the untruncated title beneath the trailing
control, owns no geometry or action state, and creates no card or additional
plane.

System chrome, menus, presentations, controls, focus, selection, semantic
Sidebar/Inspector, and tracking separators stay native. Document tabs are
ordinary Document controls, not simulated window tabs.

Research Guidance, Actions, permission sheets, and Research Record use
continuous native planes, textual list/detail structure, editorial hierarchy,
fine rules, alignment, and deliberate whitespace. They do not use per-Skill
cards, colorful category tiles, score badges, agent avatars, chat bubbles,
nested rounded containers, or decorative workflow diagrams. Selection and
consequence remain clear through native state, typography, symbols, and text.

Library Locations retain one opaque navigation plane. Location content neither dims retained content nor floats
above it, and adds no material, reflection, grabber, rounded panel, accessory
row, separately measured bar, shadow, or sheet motion. The LocationPicker's
transient menu remains system-owned rather than becoming a Scholium popover.
Pane-local content hosts consume the native safe area once; the titlebar and
its single native toolbar own visibility-control alignment.

The fixed Recommended Bibliography band is a sibling Sidebar utility, not a
Library Location or Source List footer. It shares the complete Sidebar's
Paper-derived Navigation surface; one structural top boundary, fixed position,
heading, and accessible Triptych-scoped group express its ownership without
explanatory subcopy, a card, blur, material, decorative elevation, or an
independent palette. Its named top and bottom insets place the content slightly
above visual centre and preserve a calm bottom edge.

### 19.2 Typography and color

- System sans is interface structure: navigation names, chrome, menus,
  controls, Settings, alerts, section headings, field labels, action names,
  dates, and compact scanning cues. The fixed **Scholium** Alegreya wordmark
  remains the identity exception.
- Library Folder and unselected Note titles use the same 12pt Regular system
  role; only the selected Note uses Semibold. The compact Document-toolbar
  identity uses the 13pt system body role with secondary ink. Recommended
  Bibliography's empty state uses the purpose-named 10pt metadata role with
  secondary ink; a populated compact preview uses the editorial citation role.
- **Alegreya** is for Review/Edit prose and may identify content-derived
  titles, linked research objects, researcher judgments, field values,
  explanations, Scope, Limitations, and other research content when density,
  scaling, and mixed-script fallback remain legible.
- Apparatus text never exceeds the adjacent Document Body at the default
  Appearance. Its interface labels and headings use the quieter semantic text
  roles; its 12pt content values and explanations may use Alegreya, but small
  text still meets §20 contrast and mixed-script legibility requirements.
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
  Increase Contrast semantic output. The complete Sidebar, including Recommended
  Bibliography, uses one recessive and neutral `navigationSurface`. Inspector's
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

### 19.3 Variable boundary

Keep eight families: Color, Typography, Surfaces, Elevation, Boundaries,
feature Metrics, Motion, and provisional Document Rhythm. Promote only stable
cross-component decisions or critical thresholds. The adaptive grid uses a
bounded **4pt** foundation with a **2pt** optical exception; APIs expose
purpose-named roles, never numbered positions. Invent no numbered opacity,
radius, shadow, border, gradient, or paper scales.

- Interface type roles: identity, section title, row title, metadata, and
  narrowly approved editorial hierarchy. Library exposes purpose-named Folder,
  Note, selected-Note, Attention-alert, bibliography-empty, and
  bibliography-preview roles; the toolbar exposes the compact-identity role.
  These roles may resolve to a shared point
  size but leaf views do not recreate their weights or sizes. Document roles:
  Body,
  `heading(level:)`, Exact Source, Code, Diff, Revision Identity.
- Document Rhythm exposes one machine-local Line width input with the default,
  range, unit, and shared-mode ownership in §18.4. It creates no second
  built-in measure path.
- The Color family exposes only the two approved Accent and Paper inputs.
  Semantic roles are resolver outputs, not additional Variables; components
  consume those roles without owning a palette value.
- Structural Sidebar, Document, and Apparatus surfaces are opaque semantic
  planes; bounded local glass or material follows §19.1. Dense evidence is
  quietest and most legible.
- The Sidebar Attention alert is one state-derived presentation component, not
  an owner of diagnostics or counts. Zero produces no component. Nonzero combines
  the existing raised Navigation surface, warning symbol, label, and exact
  count; unavailable substitutes complete diagnostic text and Retry. No
  Attention count, aggregate, or anchor is projected into the Document toolbar.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones. Apparatus sections, ordinary rows, and Action rows default to no
  boundary; a consumer must explicitly request a boundary for a named semantic
  distinction.
- Elevation is a purpose mapping, never a numbered depth or shadow scale.
  System-owned windows, panels, menus, popovers, sheets, and alerts retain
  their native elevation and receive no Scholium shadow wrapper. A
  Scholium-owned transient surface uses exactly one of three roles:
  **floating control** for compact selection, status, and loading controls;
  **bounded panel** for a larger custom menu, preview, or locally bounded
  presentation above content; and **search overlay** for the centered Search
  command surface. Structural Sidebar, Document, Apparatus, and ordinary
  content surfaces have no elevation. A child does not accumulate its parent's
  shadow, and a leaf view never supplies shadow color, opacity, blur, or offset.
  The role resolver may weaken elevation for inactive windows or Reduce
  Transparency and removes the soft shadow under Increase Contrast, where the
  strengthened semantic boundary preserves separation. Surface, boundary,
  text, and position must communicate ownership when shadow is absent.
- Native controls own interaction states. Custom targets prefer **28pt** and
  never fall below **20pt**; this does not redefine native sizes.
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
  lifecycle-footer anchor. Recommended Bibliography's fixed position uses its
  intrinsic content height rather than a footer-height Variable.
- The Library's **300pt minimum readable thickness** is a component-specific
  containment threshold outside the grid, not a spacing role, preferred width,
  or scene minimum.
- Peripheral metrics own the shared **28pt** outer page edge for Library and
  Inspector. Library metrics independently own the
  Library's **12pt** row-surface inset, **28pt** minimum row rhythm, **16pt**
  hierarchy indentation step, **12–14pt** semantic leading slot, **8pt**
  leading-to-title gap, and **18pt × 1pt** ScopeIndex selection underline.
  Ordinary row content begins at the 12pt inset while a selected or pressed
  navigation feedback surface may span the Source List width; the surface does
  not change the content axis. Content headings and principal controls align to
  the shared 28pt page edge. BrandHeader and LocationHeader retain
  intrinsic content-driven height rather than copying a toolbar or
  footer height. These values remain provisional until they pass the 300pt,
  localization, scaling, contrast, and human visual-acceptance matrix.
- Apparatus metrics map the outer inset to the shared peripheral edge and
  independently own the Inspector's **18pt** selected-mode underline,
  **78pt** minimum fact
  label column, **14pt** fact-column gap, **204pt** horizontal FactGrid
  threshold, and **44pt** Action-row rhythm. These names may reuse a general
  value only when the purpose is genuinely the same; Inspector-specific rhythm
  is not expressed by borrowing a peripheral or Library metric.
- The one-time **320pt** first-reveal request is a native-container initial
  condition outside the grid. It is not a design Variable, persisted setting,
  minimum, maximum, or continuously enforced preference.
- Set Aside and Trash reuse the Library metrics and common OutlineRow
  and LocationHeader components. They create no parallel lifecycle spacing
  namespace, destination header, or footer role.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, decorative motion, or repeating
  Attention pulse. Conditional Attention presence remains understandable with
  motion entirely absent.
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

Initial sizes are Workspace **1180 × 760**, Bootstrap **720 × 720**, Research
Record **760 × 680**, and fixed Settings content **700 × 560**. Regions scroll
independently; Document takes remaining space without a fixed size. Native
geometry stays outside the grid. WebKit uses `rem`, `ch`, CSS px, and viewport
units without point conversion. The selected **48–96ch** Line width is centered
inside the available Document width while `max(...)` retains the **20/32/40 CSS
px** minimum border separations. Wide rendered tables, code, and mathematics
may scroll inside that measure; rendered prose reflows without page-level
horizontal reading scroll. Source mode instead soft-wraps every exact logical
line within its measure without changing source line breaks or line numbers.
The 72ch default and typographic rhythm have passed ordinary, narrow,
mixed-script, and 100%/200% visual acceptance. Screenshots and prototype
coordinates remain evidence only and never define native/CSS unit conversion.

### 19.5 Application icon

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

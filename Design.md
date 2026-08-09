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

Document remains primary across the opaque Sidebar, Document, and Apparatus
planes. System sans, Alegreya, and Victor Mono distinguish interface,
scholarly, and exact content; purpose-named typography, spacing, alignment, and
semantic color establish hierarchy before boundaries or elevation. Native
controls retain platform behavior. Library and Inspector use the components in
§19.7, copy follows §19.6, state presentation follows §19.9, and every
surface carries §20 adaptation requirements.

Exploratory documents retain only unresolved proposals. Once a visual recipe
enters this specification and becomes reachable, its implementation evidence
belongs in [Implementation Status](Docs/IMPLEMENTATION_STATUS.md), not in a
parallel design guide.

### 19.1 Liquid Glass and material boundary

Liquid Glass is not Scholium's interface language: `glassEffect`,
`GlassEffectContainer`, glass button styles, and refractive chrome do not define
surfaces or controls. A named local task may use native, or when necessary
custom, transparency, blur, vibrancy, or material only while preserving
readability, contrast, focus, hit testing, adaptation, and native ownership.
That bounded use creates no reusable Variable or permission elsewhere.

The structural Sidebar, Document, and Apparatus planes remain opaque under
§18.2. Their one approved Workspace depth cue is the opaque-surface
document-navigation boundary in §19.3; it adds no material or transparency to
the planes. The §18.3 Put Back veil is an explicitly approved bounded native
Sidebar material: it transiently covers the untruncated title beneath the
trailing control, owns no geometry or action state, and creates no card or
additional plane.

Chrome, menus, presentations, controls, focus, selection, separators, and
Document tabs stay native. Research Guidance, Actions, permission sheets, and
Research Record use continuous planes, textual collection/detail structure,
editorial hierarchy, rules, alignment, and whitespace—not cards, tiles, badges,
avatars, chat bubbles, nested rounded containers, or decorative diagrams.
Finite ledger fields may use the quiet semantic capsules defined below; they
are compact value presentations, not decorative badges or status collections.

Library Locations remain in the opaque Navigation plane, never alter Workspace
depth, and add no floating layer, local elevation, accessory bar, or sheet
motion. LocationPicker stays system-owned; pane hosts consume native safe area
once and the titlebar/toolbar own visibility-control alignment.

Research Records is collection-first. Toolbar owns one shallow-surface View
index without an underline; its labels are always Records and Reading Leads,
with no appended count. One adaptive row owns search and Scope/Filters; the
search field receives available width and the toolbar index is the visible
collection identity. Records and Leads are
rule-separated ledgers, never cards, and share one compact 48pt row, column
header, separator, and interaction rhythm. Rows need no navigation glyph.
The Triptych Record columns are an unlabeled 28pt Attention gutter, a two-line
Record cell, Action, and Date. The frozen Record Title is collection interface
language and uses the regular 12pt Default interface role;
the focal Note is a second 10pt muted Sans line. This Note omits that redundant
line. Attention, Action, and Date center against the complete Record cell.
Source, Method, and complete results remain in detail. Completed
is implicit. Attention stays empty normally and uses one icon-only exception
mark for Blocked or limited, unavailable, or missing Analyze
Reliability/Coverage; Help and accessibility preserve exact values. Action is
a quiet, text-only, neutral capsule with no category tint or symbol. It is a
finite ledger value, not a control. Records default to finished date descending
and expose provider-owned Record, Action, and Date sorting. The collection has
no visible content title, subtitle, Pin, date grouping, generated
Research Result synopsis, source line, or note-count projection. Leads visually omit the
Handled header, place its 32pt checkbox track 8pt from Title, then show
Author(s), Year, and Publication. Reading Lead Title uses the regular 12pt
Default interface role; Author(s), Year, Publication, and unavailable-field
state use the 11pt Compact interface role. Changing a long-list value to Sans
does not promote supporting information to 12pt. Action uses medium weight and
capsules use 10pt. Record detail is 64/36:
Document is the dominant reading plane and Apparatus is the quieter evidence
rail. Their adaptive divider and semantic reading-evidence depth run behind the
toolbar while both scroll contents remain below it.
Lead detail keeps one centered reading flow: its header places an independently
operable Handled disposition button beside the title. Unprocessed is an
accented **Mark as handled** action with a clock; the immediate optimistic
result becomes a neutral bordered **Handled** state with a checkmark and can be
reversed. The full citation follows as selectable Scholarly body in muted
ink, above one adaptive Bibliography/Discovery information band. Bibliography
keeps Authors, Year, Publication, DOI, and Zotero item key together in the
shared About FactGrid grammar. DOI, Zotero item key, and Discovery Locators are
academic values and use the Scholarly body role; exact Record and revision
identity retains the Exact family.
Record and Reading Lead detail academic prose and content-derived values use
the Scholarly body role. Long scrolling ledgers are navigation and scanning
surfaces, so their complete visible language uses Sans: primary values use the
12pt Default interface role, supporting values use the 11pt Compact interface
role, and annotations or metadata use the 10pt Small role. Supporting
explanations and explicit content-state descriptions outside a ledger use
Compact interface; Small remains limited to labels, annotations, and metadata.
Empty or unavailable content remains explicit even when its explanatory
treatment is visually secondary.
At regular reading widths,
Bibliography owns the wider left column and Discovery Locators the bounded
right column; a genuinely narrow window stacks the same complete groups in
that order without changing their semantics. Recommendation reason and
uncertainty, researcher note, source and parent, and closed Technical Details
follow the band.

Both ledgers load exact 100-row slices. A muted 10pt tabular total sits beside
Record or Title in the first content-column header, never in the toolbar or
controls and never with parentheses or “results”. Reaching the loaded boundary
requests the next slice; later-page failure keeps loaded content and offers
Retry at the same boundary.

Header states Action/date/title once, then distinct metadata. Completion is not
repeated; empty sections state status. Reading shares Apparatus headings. Fixed
authorship/Serif tracks label Researcher Accent/`person`
and Agent `agentAuthorship`/`sparkle`.

Evidence section headings align through the Apparatus heading role. Each
evidence item identity uses the 12pt Medium interface Row Title role rather than
the Semibold Section Title role; its provenance uses un-emphasized 10pt Small
Sans in `mutedText`. Sans owns names/provenance, Alegreya testimony/judgment;
Context alone uses `text.quote`.
Participants/Context preview three; chevrons show all. Effects/judgment remain;
Technical Details closes; `trash` deletes. Dense facts use Inspector About's
label/value grid. Metadata omits middots.

### 19.2 Typography and color

Family communicates content kind; size communicates hierarchy. The two axes are
independent:

| Role outside Document | Family | Base size | Constraint |
| --- | --- | --- | --- |
| Default interface | System sans | **12pt** Regular | Includes Library Folder and Note titles; selection changes only weight. |
| Compact interface | System sans | **11pt** | Dense ledgers and scanning rows. |
| Small | Same family as its content | **10pt** | Labels, annotations, and metadata; ordinary floor, never a way to hide important state. |
| Scholarly body | Alegreya | **13pt** | Optically compensates for Alegreya's lower x-height; research prose, judgments, and content-derived values. |
| Exact body | Victor Mono | **12pt** | Source, code, paths, identifiers, revisions, and diffs. |

Native text resolves through only three families: Interface, Scholarly, and
Exact. Interface has one **17pt Semibold primary title**, then section, row,
body, compact, and small roles; every custom window, sheet, Settings page, and
top-level route shares that primary title. Scholarly has one **20pt Bold title**,
one **17pt Bold section title**, body, and emphasis. Exact has body, strong, and
small. Tabular figures are an option on a role, never another role. Feature
areas publish no font aliases. Brand and Bootstrap hero typography are the only
exceptions; symbols remain a component concern. Native controls retain platform
typography. Apparatus may pair compact Sans labels with scholarly values;
Connect remains entirely Sans. `DocumentAppearanceSettings` and generated
Appearance CSS own all Document typography and renderer adaptations.

A long, repeated, scrolling list is an interface index even when it names
academic objects. Its visible rows therefore remain Sans for comfortable
scanning. Family does not flatten hierarchy: the primary row value uses Default
interface, supporting values use Compact interface, and annotations or metadata
use Small. Selecting an item returns its academic prose and content-derived
values to Scholarly typography in the detail or reading surface. Bounded
evidence previews and detail sections do not become long-list interface merely
because they repeat entries.

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

- Native windows, toolbars, menus, sheets, popovers, and controls retain their
  platform shapes; Scholium copies no system radius or control skin.
- Matching component responsibilities and sizes use one recipe. Leaf Views name
  no raw radius. Nested custom surfaces use container-concentric geometry or one
  purpose-owned fallback when the platform cannot resolve it.
- Borders do not imply rounding. Lists, separators, symbols, and unbounded
  content remain unenclosed; capsules are native-owned or named full-height
  enclosures, never decoration or tag walls.
- Native and WebKit share geometry only for the same semantic construct.

Corner shape never carries state or authority by itself; boundary and focus
adaptation continue to follow §20.

- Interface roles map default, compact, and small text to 12pt, 11pt, and 10pt;
  purpose-named identity, section, row, metadata, Library, and toolbar roles
  derive from them without leaf-owned values. Document typography remains
  CSS-owned; native exact-content helpers serve only non-Document presentations.
- Document Appearance exposes one machine-local Line width input with the
  default, range, unit, and shared-mode ownership in §18.4. Document Rhythm
  adds no second built-in typography or measure path.
- The Color family exposes only the two approved Accent and Paper inputs.
  Semantic roles are resolver outputs, not additional Variables; components
  consume those roles without owning a palette value.
- Structural Sidebar, Document, and Apparatus surfaces are opaque semantic
  planes; bounded local glass or material follows §19.1. Their structural depth
  exceptions are the Workspace-owned document-navigation boundary and the
  single-Record reading-evidence boundary below.
  Dense evidence is quietest and most legible.
- Triptych Attention is one stable Sidebar presentation, not a diagnostics or
  count owner. At rest, zero has secondary ink and no number; nonzero places the
  exact aggregate beside its direct warning symbol and uses Attention ink for
  both. Hover, focus, press, and open-popover states raise the complete target,
  never a symbol circle or count badge. Checking and unavailable retain identity,
  complete state, and Retry. Document toolbar and workspace rows expose no
  Attention projection.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones. Apparatus sections, ordinary rows, and Action rows default to no
  boundary; a consumer must explicitly request a boundary for a named semantic
  distinction.
- Elevation is purpose-named, never a depth scale; system presentations retain
  native elevation. Workspace owns the structural **document-navigation
  boundary** at Document's logical leading edge, cast into Sidebar from window
  top to bottom behind the native toolbar and 1pt separator. Single-Record
  detail owns the corresponding **reading-evidence boundary**, cast from the
  dominant Document reading plane into the Apparatus evidence rail through the
  same full-height native split grammar. Each is noninteractive, motionless,
  RTL-aware, and absent with its receiving plane. Active Light uses AppKit
  semantic shadow at
  **0.04** opacity, **8pt** blur, **2pt** logical Sidebar offset, zero vertical
  offset, and no spread. Dark, inactive, or Reduce Transparency uses **0.02**;
  values never compound. Increase Contrast removes it and relies on separator
  and surface difference.
  Transient custom surfaces use only **floating control**, **bounded panel**, or
  **search overlay**. No other content elevation, inherited child shadow, or
  leaf-owned shadow value exists; ownership remains legible without shadow.
- Native controls own interaction states. Custom targets prefer **28pt**, never
  fall below **20pt**, and remain in the keyboard focus chain. Pointer press
  clears keyboard-only focus before activation; matching controls use the shared
  content-focus surface without sampling events or suppressing app/window focus.
  A transient evidence popover gives default focus to its effect-free scroll
  owner rather than its first row. Pointer opening therefore paints neither a
  keyboard focus frame nor a false hover surface; Tab advances to a row, whose
  native focus effect remains visible, while actual hover and press still use
  the shared content feedback.
- Toolbar symbols retain one native small-control recipe, system body symbol
  geometry, and platform hover, press, focus, and disabled feedback across the
  main Workspace and auxiliary windows, without Scholium underline or custom
  enclosure. Custom content controls change immediately: secondary ink at
  rest, primary ink on hover/focus, and a purpose-owned surface only when needed.
  One adaptive semantic-ink resolver supplies hover surfaces across content
  planes without copying toolbar pixels; keyboard focus is stronger and
  Navigation selection remains persistent.
  LocationHeader icons share one **28 × 28pt** target and editorial-control
  shape. LocationPicker and Triptych Attention fit complete content at that
  height and reuse that hover/focus/press shape; LocationPicker uses 12pt Regular
  secondary ink, promoted to primary without weight change. Triptych rows own
  continuous Navigation selection; ModeIndex owns editorial-control selection
  and hover.
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
- Library and Inspector share a **28pt** outer page edge. Library owns a
  **12pt** row inset, **28pt** minimum row rhythm, **16pt** hierarchy step,
  **12–14pt** leading slot, **8pt** title gap, and Triptych selection recipe.
  Full-width feedback never shifts the 12pt content axis. Headings align to the
  outer edge; BrandHeader and LocationHeader remain intrinsic, with **12pt** to
  workspace content. Workspace rows grow rather than clip and align a trailing,
  noninteractive Sans monospaced `mutedText` total without background or hover
  promotion. The 300pt, localization, scaling, contrast, and human-acceptance
  matrix remains the gate.
- Apparatus owns the ModeIndex surface, **4pt** local-state gap, **78pt** fact
  label minimum, **14pt** fact gap, **204pt** horizontal FactGrid threshold, and
  **44pt** Action rhythm. Connect cadence is **16pt** between direction,
  freshness, and role groups; **8pt** heading-to-first-cluster; **12pt** between
  clusters; and **28pt** Note rows with a **4pt** relationship-heading gap. Its
  centered native direction control caps at **240pt**. Absent content adds no
  spacing; Inspector roles never borrow Library metrics merely by equal value.
- Records: **240pt** shallow-surface View index, **28pt** page-edge/column
  header, **24pt** section header, **8pt** corners, **48pt** Record/Lead rows,
  a **28pt** Attention gutter, **96pt** Action, **104pt** Date,
  **32pt** collection Handled track with an **8pt** Title gap, and
  **116/48/184pt** author/year/publication. The detail owns a **260–304pt** context rail,
  **three-row** preview, **328 × 384pt** popover, **680pt** reading measure,
  **92pt** authorship track, **20pt** statement gap, and **28pt** Evidence heading.
- The one-time **320pt** first-reveal request is a native-container initial
  condition outside the grid. It is not a design Variable, persisted setting,
  minimum, maximum, or continuously enforced preference.
- Set Aside and Trash reuse the Library metrics and common OutlineRow
  and LocationHeader components. They create no parallel lifecycle spacing
  namespace, destination header, or footer role.
- Motion is purpose-named, interruptible, and absent under Reduce Motion: no
  duration scale, parallax, grain, decoration, or repeating Attention pulse.
  Native feedback stays system-owned; custom hover, focus, press, and disabled
  states change immediately without geometry animation. Named transitions are
  disclosure, document reveal, search presentation/expansion, transient status,
  Handled disposition feedback, Triptych workspace change, and bounded Bootstrap
  steps. Handled disposition feedback applies the shared **0.12s**
  symbol-replacement easing to the collection checkbox or detail button label
  only after the model publishes an immediate optimistic value. The detail
  button reserves its longer label width, moves no surrounding geometry, rolls
  back on write failure, and becomes immediate under Reduce Motion.
  During Triptych change, controls, chrome, splits, Document, and Apparatus stay
  fixed. Only committed destination Source List content settles as one clipped
  object from **6pt** above while fading over **0.18s ease-out**; rows never
  cascade and the origin leaves no interactive/accessibility subtree. Repeated
  input retargets the latest committed destination. Reduce Motion installs it
  immediately; identity, selection, and content remain complete without motion.
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
| `ModeIndex` | Selects one local Inspector mode or auxiliary-window view through a shallow editorial-control surface while retaining focus, pointer, keyboard, and RTL behavior without an Accent underline. | A workspace navigator, filled segmented band, or Document tab strip. | §18.5 |
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
| `Research Records` | Review portable records without reconstructing writable research Markdown. | Collection-first navigation into one reading-first Record or Reading Lead detail, with source and derived evidence distinct. | §14, §18.5 |
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

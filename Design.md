# Scholium Design

Part of the canonical document set rooted at
[SCHOLIUM_SPEC.md](Docs/SCHOLIUM_SPEC.md). This document owns Section 19:
Scholarly Editorialism, visual language, design Variables, reusable component
and pattern presentation, layout, icon, motion, and interface writing. Sibling
chapters do not restate those rules.

Product and workflow chapters own research meaning, domain-specific
state transitions, action semantics, authorization, conflict, recovery, and
interface information architecture. Section 19.9 owns only the shared
presentation vocabulary for states supplied by those workflow owners.

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
the planes. Library rows use native selection, hover, focus, context-menu, and
accessibility presentation without a trailing restore veil or a second plane.

Chrome, menus, presentations, controls, focus, selection, separators, and
Document tabs stay native. Research Guidance, Actions, permission sheets, and
Research Record use continuous planes, textual collection/detail structure,
editorial hierarchy, rules, alignment, and whitespace—not cards, tiles, badges,
avatars, chat bubbles, nested rounded containers, or decorative diagrams.
Finite ledger fields may use the quiet semantic capsules defined below; they
are compact value presentations, not decorative badges or status collections.

Library remains in the opaque Navigation plane and adds no floating layer,
local elevation, accessory bar, or sheet motion. Research Records
follows the collection and detail structure in §18.5: its collections are flat,
rule-separated ledgers on one continuous Document surface; Record detail pairs
the dominant Document reading plane with a quieter Apparatus evidence rail;
Reading Lead detail remains one centered reading flow. These surfaces use the
typography, spacing, boundaries, and elevation roles below without creating a
feature-local material language. Finite Action values use 10pt medium Sans in
the neutral capsule. Record authorship pairs Researcher Accent with `person`
and `agentAuthorship` with `sparkle`; Context uses `text.quote` so it cannot be
confused with a Participant document.

Record academic prose uses the 13pt Scholarly body role. Its limited read-only
markup adds no Document-style heading scale: every authored heading is the same
body-sized Bold section lead. Strong and emphasis select the matching Alegreya
face, inline code and literal unsupported syntax use 12pt Exact, lists retain
quiet textual markers, and block quotations use one 2pt Accent leading rule.
All resolved links use Accent plus an underline. Wikilinks additionally use
the quiet raised-surface inline field; unresolved or
ambiguous links show exact source in secondary Exact text. These inline fields
do not become capsules, badges, cards, relation colors, hover-only controls, or
Evidence semantics.

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
Connect remains entirely Sans. Document Appearance owns all Document
typography and renderer adaptations.

A long, repeated, scrolling list is an interface index even when it names
academic objects. Its visible rows therefore remain Sans for comfortable
scanning. Family does not flatten hierarchy: the primary row value uses Default
interface, supporting values use Compact interface, and annotations or metadata
use Small. Selecting an item returns its academic prose and content-derived
values to Scholarly typography in the detail or reading surface. Bounded
evidence previews and detail sections do not become long-list interface merely
because they repeat entries.

- The default Appearance uses §18.4's shared Line width plus **Alegreya 12pt**,
  **2.0** line spacing, **1em** paragraph spacing, **0.02em** tracking,
  zero first-line indent, zero word spacing, justified text, no hyphenation,
  kerning, and common ligatures. Line-width values, range, stepping, and
  cross-mode behavior remain owned by §18.4.
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
  same gap again to the preceding paragraph. A separator line containing the
  collapsed caret preflights the prose line box its first character will use,
  so empty-to-nonempty input moves neither the caret baseline nor surrounding
  source lines. Consecutive authored blank lines
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
- A current-revision active Comment uses a derived **Review Comment Anchor**:
  a quiet 6% Accent wash across the source-located block, a 2px leading Accent
  boundary, and one 28px circular `text.bubble` margin button. Hover or keyboard
  focus strengthens the wash to 12% and the boundary to 3px. Multiple Comments
  in one active Discussion at the same line range add a compact count to that
  marker. Increase Contrast removes the wash and retains a 3px Accent boundary
  plus a stronger button edge. It is not a chat card, authored highlight,
  persistent composer, or comments-pane substitute; stale and finished
  Discussions paint no current prose.
- A finished Record shows a Comment's bounded selected passage as at most three
  tail-truncated Scholarly lines in `mutedText`, without a line number,
  surrounding context, source-jump control, border, or card surface. The
  attributed Comment remains primary; the passage is quiet focal context.
- Standard Markdown hyperlinks use Accent with an underline. Wikilinks and
  Vector Links use that same Accent without an underline and place one small,
  optically equal trailing upper-corner SF Symbol badge after the linked text:
  `link`, `plus`, `minus`, or `xmark` for Related, Supports, Opposes, or
  Incompatible respectively. No relationship symbol precedes linked text, no
  relationship receives a separate hue, and the visible text plus accessible
  name retains the complete meaning. Review and inactive Edit use the same
  recipe and visual dimensions. An embedded Note's header title is the named
  route to open that Note and carries no corner badge.
- Callout surfaces, Markup highlight, inline code, and embedded Notes consume
  their purpose-owned Document corner recipes. The large bounded content
  surfaces remain visibly softer than the compact inline marks; feature CSS
  names no raw radius and Review/Edit share each semantic recipe. An embedded
  Note is a finite-height Document-within-Document surface, not an inline chip,
  card collection, writable projection, or second renderer. A link preview
  likewise reuses protected Document typography and components, displays its
  title once, omits relationship type copy, and adds only the bounded panel's
  structural scrolling and presentation chrome.
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
bounded **4pt** foundation with a **2pt** optical exception; published roles are
purpose-named, never numbered positions. Invent no numbered opacity,
radius, shadow, border, gradient, or paper scales.

#### Corner geometry

Corner geometry follows component responsibility and containment rather than
one application-wide numeric scale.

- Native windows, toolbars, menus, sheets, popovers, and ordinary controls
  retain their platform shapes. The shared segmented control alone uses the
  approved continuous track and selection corners; no feature copies its skin.
- Matching component responsibilities and sizes use one recipe. Feature
  components name no raw radius. Nested custom surfaces use container-concentric geometry or one
  purpose-owned fallback when the platform cannot resolve it.
- Borders do not imply rounding. Lists, separators, symbols, and unbounded
  content remain unenclosed; capsules are native-owned or named full-height
  enclosures, never decoration or tag walls.
- Native and WebKit share geometry only for the same semantic construct.

Corner shape never carries state or authority by itself; boundary and focus
adaptation continue to follow §20.

#### Variable ownership

- **Typography:** Interface roles derive from the 12pt Default, 11pt Compact,
  and 10pt Small roles in §19.2. Document typography remains owned by Document
  Appearance and its renderer; native exact-content helpers serve only
  non-Document presentations.
- **Color:** Accent and Paper are the only inputs. Every surface, text, state,
  and interaction color is a semantic output consumed without a feature-local
  palette.
- **Surfaces and boundaries:** Sidebar, Document, and Apparatus are opaque
  semantic planes. The only boundary roles are **structural divider**, **subtle
  boundary**, and **floating boundary**. Ordinary Apparatus sections and rows
  are unbounded unless a named ownership, consequence, or recovery distinction
  requires one.
- **Elevation:** Elevation is purpose-named, never a depth scale. Native
  presentations keep system elevation. Custom transient surfaces use only
  **floating control**, **bounded panel**, or **search overlay**. The shared
  segmented selection plate reuses floating-control depth. Structural
  depth is limited to the Workspace **document-navigation boundary** and Record
  detail **reading-evidence boundary**. Each is noninteractive, motionless,
  defined with logical edges, structurally mirrorable for §17's deferred
  right-to-left interface scope, absent with its receiving plane, and secondary
  to the semantic surface and 1pt divider. Active Light uses **0.04** opacity,
  **8pt** blur, **2pt** logical offset into the receiving plane, zero vertical
  offset, and no spread; Dark, inactive, or Reduce Transparency uses **0.02**
  without compounding. Increase Contrast removes the shadow and strengthens
  the divider and surface difference. No child or ordinary content surface
  adds another shadow.
- **Document Rhythm:** Document Appearance exposes the one machine-local Line
  width input defined in §18.4. The typography and adaptive behavior in §19.2
  are the only built-in Document rhythm.

#### Interaction presentation

Native controls own their platform states and shapes. The shared segmented
control is the one custom horizontal-choice owner. Custom targets prefer
**28pt**, never fall below **20pt**, and remain keyboard reachable. Resting
content controls use secondary ink; hover or focus promotes primary ink and
adds the purpose-owned surface only when needed. Keyboard focus remains stronger
than hover, persistent selection remains stronger than both, and pointer
activation does not leave a keyboard-only focus effect. Matching controls use
one recipe without copying toolbar pixels or adding geometry animation. Native
Buttons and sheets receive no feature-local focus state or unconditional focus
restoration. Segmented focus and Left/Right traversal live only in the shared
component; no feature recreates them.

Toolbar controls retain native small-control geometry and feedback without a
Scholium underline or enclosure. Library-header icons share one **28 × 28pt**
target and editorial-control shape; Library commands and Triptych Attention
entry fit their complete content at that height. Triptych navigation rows use
continuous Navigation selection; local mode indexes use editorial-control
selection. Standard actions and Vector Link relationships use direct SF
Symbols with text as the primary meaning.

The window-local Back/Forward pair uses direct borderless `arrow.left` and
`arrow.right` SF Symbols with native disabled, hover, press, and focus behavior.
It adds no enclosing capsule, Scholium color, custom animation, or persistent
history surface.

Document Mode is one native borderless toolbar button, not a segmented control.
Its direct monochrome SF Symbol reports the current Review, Edit, or Source
state; concise pointer help names that state and the accessible value agrees.
Behavior follows §18.4. AppKit owns hover, press, disabled, and focus feedback;
Scholium adds no capsule, tint, shadow, or custom animation.

#### Metrics

Equal values do not merge responsibilities: each feature consumes its named
metrics, and absent content contributes no spacing.

| Scope | Canonical metrics |
| --- | --- |
| Shared grid | **2pt** optical alignment; **4pt** label/accessory; **8pt** inline control; **12pt** nested content; **16pt** section; **20pt** region content; **28pt** peripheral page edge. |
| Shared anchors | Preferred/minimum custom target **28/20pt**; Document tab strip **40pt**; Action target **44pt**; region header **48pt**. There is no general 24pt row role. |
| Activity notification stack | **520pt** maximum width; at most **3** visible layers; **4/8pt** collapsed/preview offsets; **2.5%** horizontal inset per rear layer. |
| Library | **300pt** minimum readable thickness; **12pt** row inset; **28pt** minimum row; **16pt** hierarchy step; **12–14pt** leading slot; **8pt** title gap; **12pt** header-to-workspace gap. |
| Apparatus | **270pt** system Inspector minimum with no application-defined maximum; **4pt** local-state gap; **78pt** fact-label minimum; **14pt** fact gap; **204pt** horizontal-grid threshold; **44pt** Action row. |
| Connect | **16pt** between major groups; **8pt** heading-to-first-cluster; **12pt** between clusters; **28pt** Note rows; **4pt** relationship-heading gap; **240pt** direction-control cap. |
| Records collection | **240pt** View index; **28pt** page edge and column header; **24pt** section header; **8pt** row corners; **48pt** ledger rows. |
| Records columns | **28pt** Attention gutter; **96pt** Action; **104pt** Date; **32pt** Handled track with **8pt** Title gap; **116/48/184pt** author/year/publication. |
| Record detail | **260–304pt** evidence rail; three-row preview; **328 × 384pt** popover; **680pt** reading measure; **92pt** authorship track; **20pt** statement gap; **28pt** Evidence heading. |

The one-time **320pt** first Apparatus reveal request is a container initial
condition, not a Variable, persisted setting, minimum, maximum, or later-reveal
preference.

#### Motion

Motion is purpose-named, interruptible, and absent under Reduce Motion. There
is no duration scale, parallax, grain, decorative loop, or repeating Attention
pulse. Native feedback stays system-owned; custom hover, focus, press, and
disabled states change immediately. The Activity Notification Stack alone may
move two decorative rear surfaces from 4pt to 8pt over **0.16s ease-out** on
hover or keyboard focus; content and extent stay fixed. Reduce Motion leaves it
collapsed. Named transitions are disclosure, document reveal, search
presentation/expansion, transient status, Activity Notification Stack preview,
Handled disposition feedback, Triptych workspace change, and bounded Bootstrap
steps.

Handled feedback applies **0.12s** symbol-replacement easing to the collection
checkbox or detail-button label after the immediate optimistic value appears.
The detail button reserves its longer label width, moves no surrounding
geometry, rolls back on write failure, and changes immediately under Reduce
Motion. During a Triptych change, chrome and planes stay fixed; committed
destination Source List content settles as one clipped object from **6pt** above
while fading over **0.18s ease-out**. Rows never cascade, the origin leaves no
interactive or accessibility subtree, and repeated input retargets the latest
committed destination. Reduce Motion installs the destination immediately.

### 19.4 Provisional layout defaults

Layout defaults support testing, not independent gates. Native containers own
chrome and split geometry; Scholium owns semantic order and content insets.
Scenes have no Scholium numeric minimum unless the complete adaptation matrix
proves one. The Library's 300pt threshold adds no preferred or maximum width,
persisted divider position, or scene minimum.

| Surface | Initial content size |
| --- | --- |
| Workspace | **1180 × 760pt** |
| Bootstrap | **760 × 740pt** |
| Research Records | **760 × 680pt** |
| Settings | fixed **700 × 560pt** content |

Regions scroll independently and Document takes remaining space without a
fixed size. Native geometry stays outside the grid. Document layout uses
`rem`, `ch`, CSS px, and viewport units without point conversion. Its selected
measure and adaptive minimum insets remain owned by §18.4. Prose reflows without page-level horizontal reading
scroll; intrinsically wide objects keep object-local overflow; Source
soft-wraps exact logical lines without changing source line breaks or line
numbers. The configured measure and typography remain valid at narrow widths, with
mixed scripts, and at 100%/200% text. Screenshots and prototype coordinates are
evidence only and never define native/CSS unit conversion.

Settings uses one opaque Navigation sidebar and one continuous detail plane.
Its native titlebar keeps the traffic lights and drag region but hides the
redundant window-title label. The sidebar begins with native Settings search,
not another visible Settings heading.
The sidebar orders Application, This Triptych, and Research Guidance as
succinct native list sections. Settings adds no
toolbar of peer icons, card grid, bottom action strip, or unrelated General or
Advanced collection. Every destination retains the shared 17pt primary title;
scope is visible in navigation and repeated inside a mixed-scope detail only
where a consequential action needs the explicit **This Triptych** or **This
Mac** boundary.

The This Triptych **Metadata** destination keeps three explicit sections in
one role-selected detail: global field definitions first, optional Agent
preferences for Analysis second, and About order last. Adding a definition is
an inline bounded form with labelled key, display-name, optional-description,
finite value-kind and controlled-choice inputs, Cancel, and Add Field. Existing
custom definitions expose editable semantic copy, type, lifecycle, use count,
and named Archive or Restore; stable key and kind remain static. Built-ins are
not repeated as a 52-row schema inventory. Adding or archiving a definition
neither checks an About/Agent option nor writes or deletes a Note value.

Document Appearance presents Configuration, Line width, Body Typeface, Font
size, and Line spacing before one **Advanced Appearance** disclosure. Body
details, Headings, and Callouts live inside that disclosure; Advanced CSS has
its own disclosure. Save and **Revert to Saved** remain visible beside the
selected profile. Switching profiles protects an unsaved draft, and restoring
the built-in appearance changes the draft only until Save.

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
custom interface glyph consumes the same resolved semantic role in native and
Document surfaces; it introduces no raw system hue or second local palette. SF
Symbol palette, multicolor, gradient, and variable-color rendering are not used
to encode Scholium workflow state.
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
size. English and Simplified Chinese localization, mixed scripts, and 200% text
may reflow rather than truncate, but the source wording does not expand to compensate. An unavailable
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
identify the task. Researcher-configured Action names may use one terse explanation
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
| `Segmented Control` | Equal text segments use a quiet Paper track, one adaptive raised selection, continuous corners, and no Accent fill. Inspector, Connect, Search, Properties, and Records share input and accessibility. | Workspace navigation, tab strips, or mixed actions. | §§18.4–18.5 |
| `Source List` | Organize Notes as a quiet, hierarchical source navigation surface with explicit selected, empty, loading, and error states. | A tile grid, status badge wall, or content preview card. | §18.3 |
| `Connection Direction Control` | Switch Connect between Incoming and Outgoing through one native two-segment control. Undirected relations appear in both with source anchors preserved. | A Combined/All segment, an index replacement, or a second graph owner. | §12, §18.5 |
| `Action Row` | Expose one bounded Research Action with its declared intent, scope, current state, consequence, and first repair. | An agent avatar, chat bubble, score badge, or generic command card. | §8.1, §18.5 |
| `Triptych Notifications Entry` | Opens persistent Action activities and structural Attention; shows the exact nonzero total beside a bell. | Per-Vault counters, task manager, unread/adoption matrix, pulse, diagnostic owner, or Document-toolbar item. | §13, §§18.2–18.3 |
| `Activity Notification Stack` | One exact-count Document control summarizes attention-required Action activities, previews two rear layers, opens the queue, and waits behind Note Review. | A second queue, full expansion, card deck, timeout, unread model, or Dismiss owner. | §18.3, §18.5 |
| `Recovery Notice` | Present a persistent workflow-supplied condition, consequence, and repair or inspection action as a Document notice or Workspace banner. | A generic error or Search banner, runtime state owner, or recovery coordinator. | §§5.3, 14, 18.2, 18.6 |
| `Document Find Bar` | Find and, in writable modes, replace literal text in the current unsaved buffer while retaining editor selection, Undo, and focus. | Research Search, a modal panel, a second text owner, or saved query history. | §13, §18.4 |
| `Review Comment Anchor` | Shows a current Comment at its source line and opens its Discussion through one counted margin marker with keyboard and contrast states. | An authored highlight, chat card, comments pane, guessed reattachment, or annotation store. | §7.2, §18.4 |
| `Property Group` | Uses 24pt between groups and 16pt between fields in Properties/About; names stay accessible. Help owns definitions. The fixed action slot reveals on hover/focus without reflow. Save stays emphasized. | Heading, explanation, card, rule, permission, or schema. | §§5.2, 18.4–18.5 |
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
| `New Note` | Start writing immediately while source bytes stay authoritative and derived work remains off the hot path. | Direct-to-Edit readiness, retained focus, and non-blocking derived refresh. | §5.3, §§18.3–18.4 |
| `Review / Edit / Source` | Read, edit, and inspect one source through reversible projections. | One Edit-default live mode per retained Triptych workspace session; the toolbar prioritizes Review/Edit while Source remains menu-accessible, without a history keyed by Note or tab. | §5.1, §18.4 |
| `Document Find / Replace` | Locate literal text in the current unsaved buffer and replace it only in writable modes. | One inline Document bar; standard menu and keyboard routes; no Search provider, index, or persistent history. | §13, §18.4 |
| `Search` | Retrieve bounded research material with explicit provider, scope, explanation, and freshness. | Stable command surface, retained context, and distinct empty/stale/error results. | §13, §18.3 |
| `Connect` | Inspect direct relations from the current Note through an Incoming/Outgoing view switch, typed relationship subheadings, and source-located rows. | A file hierarchy, inferred graph, evidence verdict, or multi-hop exploration surface. | §12, §18.5 |
| `Notifications` | One queue holds Action activities and structural Attention; Sidebar, current-Note Inspector, and temporary Document stack anchor it within the exact window. | A task manager or unread model; closing an anchor never Dismisses an Action. | §§8.4, 13, §§18.2–18.3 |
| `Research Action` | Prepare one bounded Research Action, then track, open, end, review, follow up, dismiss, or recover it. | Intent-first launcher plus one persistent Action-level activity whose state transitions and controls remain separate from Note Review. | §§8–11, 18.5 |
| `Conflict / Recovery` | Preserve authored bytes when an external participant changes the source. | Retained buffer, exact revision comparison, selective choice, and reversible restore. | §14, §§18.4–18.6 |
| `Research Records` | Review portable records without reconstructing writable research Markdown. | Collection-first navigation into one reading-first Record or Reading Lead detail, with source and derived evidence distinct. | §8.4, §18.5 |
| `Note Review` | Inspects Agent activity and marks the current saved Note reviewed. | Task bar has Document-top priority; close suppresses the set, Overview reopens, and a new set presents. The Action stack waits and returns. Raised surface and rule, never a card or focus transfer. | §§8.4, 18.5 |
| `Bootstrap Agent Preparation` | Copies one independent-CLI setup prompt and accepts confirmation without granting research access. | App-owned CLI status or install, Agent launcher, provider picker, readiness manager, Session, or Run handoff. | §16 |

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
| `Conflict` | Two authoritative or active source participants no longer agree on the expected revision. | Retain the authored buffer, identify the competing revision, and route to comparison or an explicit choice. | Stale derived data, Undo, or Autosave Failed. |
| `Recovery` | The interface offers a reversible or explicitly consequential path after failure or interruption. | State the candidate source, consequence, reversibility, and final verification condition before action. | A generic toast, ordinary Undo, or automatic overwrite. |
| `Disabled` | An otherwise known action cannot be invoked under the current prerequisite or policy. | Keep the control discoverable when it is part of the core task and expose the missing condition without relying on low contrast. | Unavailable content or an omitted non-core control. |
| `Running` | A researcher-started Research Action is executing within its declared scope. | Keep the Action identity, current state, cancellation/end route, and focus path visible; motion is supplementary. | Loading a passive projection or background refresh. |

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

Note Settle/Settled semantics remain owned by §7.1. Result arrival, Action
notification Dismissal, researcher Follow-up, Method Feedback, and Note Review
remain separately owned by §8.4; none is a generic
cross-functional state or a synonym for another.

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

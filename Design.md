# Scholium Design

Part of the canonical set rooted at
[SCHOLIUM_SPEC.md](Docs/SCHOLIUM_SPEC.md). This document owns Section 19:
Scholarly Editorialism, visual identity, semantic presentation roles, adaptive
layout principles, reuse boundaries, icons, motion, interface writing, and
cross-functional state language. Workflow chapters own research meaning,
commands, navigation, authorization, focus transitions, and recovery.

## 19. Scholarly Editorialism and design variables

**Scholarly Editorialism** combines humanist typography, editorial hierarchy,
warm Paper and ink, native macOS navigation and controls, fine rules, marginal
organization, deliberate whitespace, and restrained color. It is neither an
antique-book imitation, a productivity dashboard, nor decorative minimalism.

The research Document remains primary across Sidebar, Document, and Apparatus.
Hierarchy begins with type, spacing, alignment, and semantic color; structural
boundaries are secondary and decorative elevation is last. Native controls keep
platform behavior, and every presentation follows §20.

This section specifies durable visual meaning, not the current implementation
inventory. Framework types, source symbols, exact dimensions, ratios, opacity,
animation timing, window defaults, and component names are implementation or
acceptance evidence unless this section explicitly gives them stable semantic
force.

### 19.1 Native material and content-plane boundary

Academic and research views directly related to the Document use Scholium's
opaque Paper-derived backgrounds throughout their content area. This includes
document reading and editing, bibliographic information, link context and
annotations, research questions, discussion, and cited passages. Human and Agent
contributions share this content plane; attribution uses text and structure.

Software operations use native macOS presentation: navigation, toolbars, menus,
Settings, notifications, operation history and file-difference inspection,
connection management, confirmation, and recovery. Native does not mean glass everywhere;
the platform owns the appropriate background, material, controls, and behavior.

The distinction is primarily the background plane, never a second control
skin. Buttons, fields, menus, selection, focus, and segmented controls on Paper
retain native macOS appearance and behavior. Do not paint custom hover fills, focus effects, or rounded button backgrounds.
Research links use the existing adaptive Accent; persistent navigation uses
neutral native selection rather than introducing a competing system accent.
Borderless native controls may keep direct research editing quiet; native input
and Undo remain intact. Inspector navigation uses icon-only controls with named
Help, and native rounded segments rather than Liquid Glass artwork.

Each complete content view uses one coherent visual language, chosen by its
primary research or software-operation purpose. Do not mix native operation
panels and Paper content blocks within that view. An operational view remains
native when it includes source excerpts or file differences; a route into
research reading opens the corresponding Paper view. Native window chrome and
input behavior remain platform-owned without introducing contrasting interior
panels. Direct research editing retains Paper; field validation stays inline
on the same surface with visible, accessible feedback and repair.

The Sidebar is a recessive native navigation plane above the warm Document
underlay. Document and the Inspector's research content are continuous opaque
content planes; Apparatus stays visually closer to Document than to navigation. Inspector
fields use native Interface type, trailing-aligned labels and a consistent
value axis. The editable list has no category headings or per-group rules;
quiet spacing and order provide hierarchy. Compact creator rows preserve the same rhythm while their controls retain
native hover and focus semantics. Read-only facts share the same field sequence, value axis and row rhythm. Native safe
areas keep content unobscured when system chrome or materials overlap it.

Research prose, Metadata, link context, discussion, and source excerpts do not
acquire glass, cards, tiles, chat bubbles, badges, or nested
decorative containers merely to manufacture hierarchy. Use type, alignment,
whitespace, semantic surfaces, and fine structural rules first. A bounded panel
is appropriate only when its task is genuinely transient or spatially anchored.

Floating operational surfaces, including Find, query explanations, and
suggestions, use native presentation and the supported system's Liquid Glass
where appropriate. Research previews use one opaque Paper surface. Both remain
above their origin without reflowing it; neither nests the other visual language
inside its content area. Editor assistance controls and candidates retain system
presentation. Clickability alone does not grant a control a glass surface.
Settings uses native macOS window backgrounds, preference toolbars, typography,
and controls. Right-aligned group labels share one column; related controls
start on one content axis, with necessary supporting copy directly below its
control. Fine rules separate groups; field and shortcut collections use native
tables with adjacent collection actions. Settings stays on one visual level:
Appearance directly exposes body font and size, line width and spacing, Source
font and size. Fine typography,
headings, and Callout geometry are edited in the documented Appearance
configuration file rather than additional controls or nested advanced pages.
A Finder route, explicit Reload, and Restore Defaults retain access and recovery. Pane changes resize from the current top-left corner with interruptible native
animation and an immediate Reduce Motion result. Screen edges constrain the
final frame. Toolbar labels stay concise; tooltips retain full category names.
System-owned navigation, toolbars, menus, and popovers keep native treatment.
There is no separate feature-authored frosted-glass style. The system owns
transparency and contrast adaptation; do not simulate Liquid Glass in WebKit.

The exact system material variant and framework host belong to the selected SDK
and implementation architecture. Feature code does not reproduce native
material, shadow, hover, focus, inactive-window, contrast, or transparency
behavior. A custom material host is justified only by a documented framework
boundary that preserves native geometry, input, menus, and accessibility.

Structural shadows never carry interaction or meaning. They use logical edges,
remain subordinate to a semantic surface and boundary, do not compound through
children, and may disappear under Increase Contrast, Reduce Transparency, or an
inactive window.

### 19.2 Typography and color

Family communicates content kind; size and weight communicate hierarchy.

| Role | Stable requirement | Presentation freedom |
| --- | --- | --- |
| **Interface** | Native macOS typography for windows, navigation, controls, indexes, and labels. | System-owned; Scholium does not replace it with a brand face. |
| **Scholarly** | A highly legible humanist reading face for research prose and judgments. | Document Appearance may choose the face, size, measure, and rhythm; the shipped default expresses Scholium's editorial character. |
| **Exact** | Source, paths, identifiers, revisions, and diffs remain visibly distinct from ordinary prose. | The researcher may choose any installed face and size. The shipped default is monospaced; the choice changes presentation only. |

Native controls retain platform typography. Long scanning lists use Interface
type even when they name scholarly objects. Scholarly detail uses one primary
title hierarchy plus restrained section and body roles. Scholium does not audit
or reject a researcher-selected Exact face; source bytes and operations remain
independent of that presentation choice.

The research Inspector uses system typography with language-aware fallback.
About field labels and values use the same 13-point regular type and baseline;
right-aligned labels use the secondary text role and left-aligned values use
the primary role. Links lists use 13-point regular text; supporting context uses
12-point secondary text. Editing preserves the resting field's type and position.
Primary text retains the system label role. Inspector controls use their native hover, selection, text-selection and
keyboard-focus treatment. Persistent navigation remains neutral; actionable
research references share the Document's adaptive Accent. Transient native text
selection and focus remain system-owned. This does not flatten text hierarchy
or recolor prose.

The app-owned Note title is the strongest element at the top of Review and Edit.
Authored H1 remains a first-level body section rather than a second document
title. Review and Edit share a recognizable manuscript hierarchy and reading
measure, while editing requirements may create bounded geometric differences.
The target is continuity of place and hierarchy, not pixel identity between a
reader and an active editor.

Ordinary prose uses language-aware editorial line breaking. English,
Simplified Chinese, mixed scripts, preserved spaces, lists, code, tables,
mathematics, footnotes, Callouts, and source markers retain legible local rhythm.
An implementation may de-emphasize inactive syntax only when entering it exposes
the exact source without losing the caret location, selection, composition, or
nearby reading context.

Hyperlinks and Wikilinks use Accent plus a non-color affordance. Authored
highlight uses a protected Markup role rather than Accent or status color.
Footnote and link-annotation markers remain subordinate to prose, keyboard
reachable, and visually stable within the line. §18 owns their activation,
dismissal, and source-navigation behavior.

Scholium content color has exactly two researcher inputs:

- **Accent** `#A94C22`
- **Paper** `#FEF8ED`

One resolver derives Light, Dark, Increase Contrast, text, surface, selection,
authorship, status, and interaction outputs. Native and embedded-document
presentations consume the same semantic meanings. Feature code introduces no
parallel palette, and color alone never encodes truth, support, authority,
acceptance, completion, or philosophical value.

Software-operation surfaces and editing auxiliaries use native semantic colors,
including the system control accent. System typography
and standard button/menu styles need no product wrapper in these boundaries.

Onboarding illustrations use a closed parchment, ink, and Accent palette. That
palette is illustration identity, not a general interface palette.

### 19.3 Variable boundary

A design Variable is justified only when several consumers share its meaning,
adaptation, and proof. Similar numbers or repeated styling do not create a
semantic role. Bounded single-owner values remain local, and implementation
inventories belong to the architecture set.

#### Variable ownership

- **Typography:** Interface, Scholarly, and Exact roles; Document Appearance owns
  researcher-selected document presentation.
- **Color:** Accent and Paper inputs; every other interface color is a semantic
  output.
- **Surfaces:** recessive native navigation, continuous Document, adjacent
  Apparatus, and purpose-bounded transient presentation.
- **Boundaries and elevation:** structural separation, focus, selection, and
  transient presentation without decorative depth systems.
- **Metrics:** only reused or adaptation-critical relationships, never a global
  numeric scale adopted for convenience.
- **Motion:** purpose-named feedback for an already-defined state change, with an
  immediate Reduce Motion outcome.
- **Document rhythm:** the active Appearance's measure, type, and spacing.

Native windows, titlebars, toolbars, menus, sheets, popovers, controls, and
focus effects retain platform geometry. Shared custom components may own reused
corner or inset relationships; borders do not imply rounding, unbounded content
remains unenclosed, and shape never carries state or authority alone.

#### Interaction presentation

Feedback names a present interaction fact, never merely that something was
clicked. Selection, hover, press, input focus, disclosure and arrival are distinct
meanings; they do not accumulate as independent highlights on one target.

| Feedback | Meaning and lifetime | Presentation boundary |
| --- | --- | --- |
| Selection | Current navigation destination, active choice, or explicitly selected object; persists only while that state holds. | Quiet native gray for persistent workspace navigation. A past activation, successful save, opened menu or followed link creates no selection. |
| Hover | This target is operable and this is its hit area; ends when the pointer leaves. | Recessive native feedback on the actual target, without moving text, changing layout or selecting anything. Passive labels and reading prose receive none. |
| Press | A native command control is being activated; ends with the gesture. | Use the control's native treatment. It does not prove an asynchronous operation succeeded; add no custom flash, scale or lingering clicked state. |
| Input focus | The current keyboard/input recipient; follows the responder. | Native focus, caret and text-selection treatment. Metadata exposes its edit frame without selecting the whole row or shifting its value. |
| Disclosure | Whether grouped content is visible. | Arrow orientation and accessible expanded/collapsed state. An expanded heading is not a selected Note. |
| Arrival | Navigation has revealed the requested passage in the Document. | One brief destination highlight, then ordinary reading. No persistent selected/checked/visited state on the initiating Links passage. §18.5 owns the navigation behavior. |
| Operation state | Actual loading, failure, conflict or recovery supplied by the operation owner. | Use §19.9 and the owning workflow. Ordinary success stays silent when the resulting content or state is already apparent; necessary failures remain inspectable. |

Native controls own rendering and adaptation; these meanings do not authorize a
custom control skin or a second state owner. The Library and input candidates
retain their purpose-specific selection/focus behavior below. Keyboard focus and
text selection are not additional product navigation accents. Hover is never
the only way to discover or operate a core command.

The application of these meanings is bounded by the object being presented:

| Surface | Persistent state | Local interaction and information |
| --- | --- | --- |
| Library, document tabs, workspace and Inspector selectors | Current Note, tab, workspace or pane. | Native navigation feedback; titles/icons identify destinations. |
| Incoming/Outgoing | Current direction. | Native neutral selection; the two labels supply scope without another explanation. |
| About fields | No row selection; only active input focus. | Labels and values share the grid. Editable values have a native input affordance; a field error supplies its necessary repair. Creator columns stay in place. |
| Links Note heading | Expanded/collapsed only. | The entire heading toggles disclosure; title and occurrence count identify the group. |
| Links passage | No persistent selection or toggle state. | Hover identifies the passage target. Context, source location and authored annotation remain readable; arrival feedback belongs in the Document. |
| Attachment preview | Which file is displayed when several exist. | Filename, preview and necessary switching controls; opening one preview adds no selected frame or completion badge. |
| Notifications and command menus | Only real open/busy/error state, never a history of clicks. | Native activation and applicable actions; counts and actual problems carry their existing workflow meanings. |

Information stays visible when it identifies the object, carries research
content, supports a current decision or repairs a real problem. Familiar
interaction is expressed through affordances rather than standing instructions.
Icon-only actions retain localized Help and accessible names. Repeated headings,
normal-success captions and internal bookkeeping do not fill research space;
full paths, exact revisions and technical details appear only where the owning
inspection/recovery task requires them. Necessary error and provenance text is
not removed in the name of quietness.

The persistent Outline follows Sidebar material and native tree presentation,
with no floating container or candidate-menu treatment. Its current section and
transient hover have distinct meanings. The Triptych/Outline toolbar selector and Analyses/Topics/Works workspace
selector use native neutral navigation feedback,
without an Accent-filled selected segment. Toolbar document identity uses Muted
Text; the in-document filename title retains its primary heading role.

Native containers and controls own hover, press, disabled, selected, focused,
active, inactive, and cursor presentation. Section 18.3 alone defines the
Library tree's quiet pointer selection and keyboard-navigation emphasis; it does not
create a general modality-styling system. The selected row remains the sole
visible list-focus indicator without a duplicate perimeter effect. Caret
completion uses compact 28-point single-line rows and 40-point rows with a
secondary description, with native control feedback. The
selected row adds no shadow or second glass layer; the floating container owns
system material and elevation. Liquid Glass is rendered only by native framework
components; candidate lists use native selection rendering without custom
drawing. Pointer movement and keyboard navigation update one current candidate;
click or Return accepts it. There is no separate hover fill or activated row.
The editor owns source-facing candidate state. Editing assistance follows the input-method
candidate-window pattern: compact, anchored, nonmodal, and outside document
layout. Completion keeps the editor as keyboard owner; Find takes query focus
and restores document focus on dismissal. During marked-text composition,
application suggestions and previews yield to the input method; Find fields
retain uncommitted text without issuing partial queries. System typography,
selection, control tint, and accessibility adaptation govern these auxiliary
controls; they do not inherit product navigation's quiet gray treatment.

Revealed editable Markdown delimiters use Muted Text; authored content retains
its semantic text color and formatting. Syntax color never changes source.

Color reinforces these meanings without becoming another feedback system.
Persistent workspace navigation and hover use native neutral grays; hover stays
subordinate to selection. Ordinary actions, disclosure arrows, More and relation
management use native neutral ink rather than Accent merely because they are
clickable. Document hyperlinks and attachment opening links
share the existing adaptive Scholium Accent. Warning/error colors keep their
own semantic role and readable wording; they are not brand emphasis.

Software-operation windows and transient native text editing retain system
semantic colors, default/destructive/cancel roles and keyboard behavior. Paper
changes the content background, not the platform's control anatomy. Native
focus and text selection may retain their system accent. A destination arrival
highlight is a temporary presentation of navigation, not authored Markup,
text selection, an error, or a research judgement; it adds no color input or
feature-local palette. Feature views do not paint a competing control skin.

Custom targets remain comfortably clickable and keyboard reachable. Focus is
stronger than hover, persistent selection is distinguishable from both, and a
pointer action does not manufacture a lasting keyboard-only effect. Standard
controls retain their platform cursor. The pointing hand is reserved for links
and genuinely link-equivalent custom targets when the platform supplies no
better cursor.

Settlement is a research milestone, not task completion. Its resting presentation
may receive restrained Confirmed reinforcement after an explicit successful
Settle, while Changed Since Settle combines the milestone identity with
Attention. Wording, shape, accessibility value, and the owning detail
presentation carry the state without color or motion. A brief non-celebratory
transition may acknowledge the researcher's explicit act; its choreography is
an implementation choice and never replays merely because the state is shown.
The toolbar uses unmodified native symbol rendering for every component,
including Settlement. State-specific symbol shapes and accessible wording
remain; custom tint, painted selection, and feature-owned toolbar animations
are excluded. AppKit owns enabled, disabled, selected, pressed, inactive-window,
and accessibility-adapted control appearance.

#### Metrics

Exact spacing, target, row, radius, window, split, readable-width, and animation
values are implementation defaults unless §20 supplies an accessibility
threshold or this document assigns the value stable semantic meaning. Native
geometry and system metrics are never copied into Scholium Variables.

Promoting a metric to the product specification requires a repeated semantic or
adaptation need, evidence that native behavior and a local value are
insufficient, and a proof capable of rejecting the threshold. Visual preference
or equality across two call sites is insufficient.

#### Motion

Motion communicates continuity or feedback for a real state change. It remains
interruptible where the action is, preserves object identity and focus, and has
a non-motion cue. Reduce Motion produces the final state immediately.

Frequent navigation, list selection, disclosure, window changes, and research
maturity judgments receive no parallel decorative transition. Pulsing, looping,
bounce, wobble, parallax, blur animation, press scaling, row cascades, and
celebratory confirmation remain excluded from the research workspace.

### 19.4 Adaptive layout

Native containers own window resizing, fullscreen, divider behavior, toolbar
overflow, and split collapse. Scholium owns semantic region order, readable
peripheral thresholds, content insets, and the rule that Document receives the
remaining usable space.

Every multi-region surface defines an ordinary-width composition and a narrower
fallback. A fixed-width or permanently expanded secondary region is not a
product requirement. Collapse, disclosure, reflow, or a transient navigator may
preserve access, but the adaptation must retain selection, focus, context, and a
named keyboard or menu route.

Prose reflows without page-level horizontal scrolling. Ordinary controls and
text wrap or recompose before requiring horizontal navigation. A deliberately
single-line identity strip may instead cap and truncate each item, expose its
complete identity accessibly, and scroll locally when its small expected set
overflows. Intrinsically wide technical objects may retain bounded local
overflow. Source may soft-wrap visual rows without changing logical lines.

Default window sizes and divider positions are implementation conveniences, not
minimums or acceptance gates. A window must remain usable at its supported
minimum size, enlarged interface text, and 200% document text.

### 19.5 Icons and illustrations

Standard actions use familiar system symbols matched optically to adjacent
Interface type. The semantic action and accessible name are normative; an
individual symbol name or configuration is an implementation choice unless its
shape is required to distinguish a state. Decorative or duplicate symbols stay
out of the accessibility tree.

Passive symbols use secondary or muted ink; ordinary active actions use primary
Ink. Attention, destructive, confirmation, authorship, and link direction use
their named semantic output together with text or shape redundancy. Multicolor,
gradient, or variable rendering never carries workflow state alone.

Onboarding illustrations combine the canonical hand, one simple directional
pattern, and one solid field to support Welcome, Triptych, and Ready. They are
decorative; adjacent text and controls communicate the complete task.

The canonical application icon is the approved parchment-and-ink composition:
a cuffed hand points right toward one marginal rule and manuscript strokes. Its
orientation, Paper field, ink character, and composition are application
identity, not Appearance Variables. Do not recolor, mirror, badge, label,
recompose, or reuse it as a control or state glyph. Replacement requires explicit
researcher approval.

### 19.6 Interface writing and explanatory copy

Use the shortest accurate label that lets a researcher predict the immediate
result. Prefer a direct verb or established research term. Supporting copy
appears only for a necessary boundary, unfamiliar consequence, or first
executable repair and remains one short sentence or fragment.

One meaning has one presentation:

- visible explanation is not repeated in Help or accessibility hints;
- Help describes only the control and begins with the action;
- accessibility hints add only missing consequence or context; and
- permission, provenance, destructive consequence, conflict, failure, and
  recovery remain complete in the owning body, alert, comparison, or sheet.

Status copy names only what Scholium can verify. Brevity never hides essential
state, identity, consequence, uncertainty, or recovery.

### 19.7 Component and pattern boundary

The product specification names researcher tasks, semantic regions, state
distinctions, and presentation responsibilities. It does not canonize the
current component tree, framework types, source symbols, or one composition's
private layout recipe. The architecture set maps the target onto current
components and framework owners.

A reusable component owns presentation and adaptation, never Document,
workflow, authorization, navigation, or operation lifecycle. Promotion requires
a distinct repeated task, one semantic owner, a shared adaptation contract, and
rejectable proof. A bounded feature-local view needs no catalog entry.

A reusable pattern combines components around one task without copying the
workflow authority. Pattern names do not become new modes, statuses, research
objects, or state stores. §§18.1–18.6 own the actual Workspace, Document,
Search, Connect, Notifications, Agent Changes, Settlement, and Recovery
contracts.

### 19.8 Normative boundary and defaults

| Kind | Status in the product specification |
| --- | --- |
| Research meaning, authority, state distinctions, required routes, source/provenance separation | Normative in the owning workflow chapter. |
| Document primacy, semantic type/color/surface roles, application icon identity, non-color meaning, adaptation principles | Normative in §§19–20. |
| Accessibility minimums and release acceptance | Normative only where §§20–21 define them. |
| Framework/API/type names, current component catalogs, exact SF Symbol names, generated CSS, rendering recipes | Architecture or implementation evidence, not product norms. |
| Exact dimensions, spacing, ratios, opacity, timing, default window frames, divider positions, and local alignment corrections | Implementation defaults unless explicitly promoted through the metric rule above. |
| Human judgments such as quietness, balance, manuscript character, motion feel, or optical alignment | Design intent until accepted against a named artifact and representative task. |

A default may change without a product decision when it preserves every
normative meaning and passes the affected proof. A target change still updates
its owning canonical chapter and removes the replaced rule in one patch.

### 19.9 Cross-functional state language

Workflow owners supply typed state; presentation maps it to this vocabulary.
This is not a universal runtime enum or second state store.

| State | Shared presentation | Not equivalent to |
| --- | --- | --- |
| **Ready** | Trustworthy committed representation and valid next action. | Saved, Settled, or merely loaded |
| **Loading** | No trustworthy projection yet or an explicit refresh wait. | Empty, unavailable, stale |
| **Empty** | Valid scope contains no items; retain scope and first next step. | Missing or failed source |
| **Unavailable** | Required source or capability cannot serve; name repair or alternative. | Disabled styling |
| **Stale** | Older trustworthy projection retained with explicit refresh. | Conflict or failed operation |
| **Error** | Operation failed; preserve context and expose safe retry or alternative. | Empty or silent disappearance |
| **Conflict** | Expected authoritative revision diverged; retain buffer and compare. | Stale derived data |
| **Recovery** | Consequential repair after failure or interruption with verification. | Generic toast or overwrite |
| **Disabled** | Known action lacks a prerequisite; keep discoverable when core. | Unavailable content |

Every state retains owner and visible context; communicates state, consequence,
and first repair through redundant channels; preserves focus, cancellation,
source, and recovery; and never relies solely on color, motion, hover, position,
or timeout.

Settle and Dismiss retain their workflow meanings. Page and pane states may use
a shared Content State presentation; field validation, compact rows, operation
feedback, and recovery notices keep purpose-owned presentations while reusing
this vocabulary.

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

Navigation and chrome use the supported macOS version's native materials and
controls. The Sidebar is a recessive navigation plane above the warm Document
underlay. Document and Apparatus are continuous, opaque semantic content planes;
Apparatus stays visually closer to Document than to navigation. Native safe
areas keep content unobscured when system chrome or materials overlap it.

Research prose, Metadata groups, Lists, Records, Agent Changes, and recovery
content do not acquire glass, cards, tiles, chat bubbles, badges, or nested
decorative containers merely to manufacture hierarchy. Use type, alignment,
whitespace, semantic surfaces, and fine structural rules first. A bounded panel
is appropriate only when its task is genuinely transient or spatially anchored.

Semantic floating containers use native Liquid Glass: contextual Find, query explanations,
previews, and suggestions sit above their originating
content without reflowing it. Reading, editing, document forms, and persistent
operation or recovery regions,
use Scholium's opaque semantic colors. Glass
belongs to the floating container. Embedded document previews retain document
semantics; editor assistance controls and candidates use system presentation. Clickability alone does not grant a control a glass surface.
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

Settings and editing auxiliaries use native semantic colors, including the
system control accent, rather than Scholium's content palette. System typography
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

Ordinary command buttons use neutral Ink and native surfaces. Default-action
status retains native keyboard behavior without introducing brand Accent.
Destructive and cancel actions retain their native semantic roles. Shared
presentation owns ordinary command styling, icon-control chrome, and custom
row/selection feedback outside Settings and editing assistance. These native boundaries explicitly
restores native control defaults, including system accent behavior; feature
views do not author button colors or selection fills. Native menus, groups, and toolbar controls retain their distinct
platform forms. Accent remains available for meaningful state and authored
links, not as a general indication that a control is clickable.

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
Search, Connect, Notifications, Agent Changes, Records, Settlement, and Recovery
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

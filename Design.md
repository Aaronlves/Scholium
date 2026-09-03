# Scholium Design

Part of the canonical set rooted at
[SCHOLIUM_SPEC.md](Docs/SCHOLIUM_SPEC.md). This document owns Section 19:
Scholarly Editorialism, visual language, design Variables, reusable components
and patterns, layout, icons, motion, and interface writing. Workflow chapters
own research meaning, authorization, and state transitions.

## 19. Scholarly Editorialism and design variables

**Scholarly Editorialism** combines humanist type, editorial hierarchy, warm
opaque surfaces, fine rules, marginal organization, deliberate whitespace, and
restrained color in a contemporary macOS environment. It is neither
antique-book imitation nor decorative minimalism.

Document remains primary across opaque Sidebar, Document, and Apparatus planes.
System Sans, Alegreya, and Victor Mono distinguish interface, scholarly, and
exact content. Hierarchy begins with type, spacing, alignment, and semantic
color; boundaries and elevation are secondary. Native controls retain platform
behavior and every surface follows §20.

Visual values that remain provisional cannot override native behavior, create
state owners, weaken accessibility/source safety, or block a usable core.

### 19.1 Liquid Glass and material boundary

Liquid Glass is not Scholium's interface language. Structural planes and
research content remain opaque. A bounded native material may be used only for
a platform-owned presentation whose readability, contrast, focus, hit testing,
and adaptation remain intact; it creates no reusable permission elsewhere.

Chrome, menus, controls, focus, selection, separators, tabs, sheets, and
popovers stay native. Research Guidance, Agent Integration, Agent Changes, and
Records use continuous planes, editorial hierarchy, rules, and whitespace
rather than cards, tiles, badges, avatars, chat bubbles, or nested decorative
containers. Small capsules are reserved for finite semantic values, never
general decoration or status walls.

The separate Records window uses a quiet collection-to-reading transition. A
fixed, non-collapsible index keeps Record navigation continuously available;
the detail retains the proven centered scholarly reading measure and pins the
current question above the independently scrolling step sequence. Each step
presents its own Note references immediately after the prose as one quiet,
single-line attachment strip that grows to the right and scrolls horizontally
when necessary. The question/step/Note-reference contract alone supplies
content: no superseded Action ledger, Result, participant workflow, or
bibliographic lead survives as presentation semantics. The question is the one
primary title; step time and Agent attribution use compact Interface type,
step prose uses Scholarly type, and identifiers or fingerprints use Exact type.
Continuous navigation/document planes, structural rules, and whitespace carry
hierarchy without a card timeline or detached evidence inspector.

Records uses semantic color only where it changes interpretation or action:
Agent attribution uses Agent Authorship, Note navigation uses Accent, an
earlier referenced revision uses Attention, and an unavailable Note uses Muted
text. The visible state word remains present whenever color varies. A current
Note is the unmarked default. Each Note reference is one compact native bordered
button containing only its document name and `Basis` or `Modified`; native
hover, focus, and press feedback make the affordance visible without a resting
card. It adds
`Earlier` or `Unavailable` only for those exceptional states. It has no
reference count, `.md` suffix, repeated current-state label, underline, trailing
chevron, resting card, or second visual button system.

Records has no toolbar or separate white chrome band. Its hidden title-bar style
lets the navigation and document planes fill the window while preserving native
close, minimize, zoom, drag, and resize behavior. Search remains at the top of
the collection because it changes that collection rather than the current
reading; visible Records refresh automatically while the window is open. The
compact default window preserves the index and reading measure. Escape or the
close control dismisses it; opening a Note attachment transfers focus to that
Note in the exact originating Workspace window and dismisses Records, while
ordinary focus loss does not. Attachment navigation never creates a second
Workspace window or falls back to an unrelated one. No disabled write,
evidence, share, refresh, or technical-identity action is added merely to fill
space.

### 19.2 Typography and color

Family communicates content kind; size/weight communicates hierarchy.

| Role | Family | Use |
| --- | --- | --- |
| Interface | System Sans | windows, navigation, controls, indexes, labels |
| Scholarly | Alegreya | research prose, judgments, content-derived values |
| Exact | Victor Mono | source, code, paths, identifiers, revisions, diffs |

Interface provides one primary title hierarchy plus section, row, compact, and
small roles. Scholarly provides title, section, body, strong, and emphasis.
Exact provides body, strong, and small. Long scanning lists remain Sans even
when they name scholarly objects; selection opens Scholarly detail. Native
controls keep platform typography. Brand and onboarding hero type are bounded
exceptions. Feature areas publish no font aliases.

Document Appearance owns document measure, Body, headings, and Callout
typography. The default is a readable Alegreya body with a compact scholarly
line and paragraph rhythm, natural start alignment, a start-aligned first-level
body heading, quieter lower headings, and deliberate CJK fallback. The
app-owned Note title is the strongest typographic element at the top of the
Review/Edit document plane. Review keeps it inert; Edit uses the same typography
as a borderless filename field whose whole visible region, including trailing
space, accepts focus. No separate edit affordance or title card is added.
Authored H1 is never styled as a second document title. Native window title
identifies the window without competing with that in-document title. Review
and Edit share one measure and typographic hierarchy, but Edit may reserve the
additional physical-line space required for stable authoring. Moving the
caret, entering or leaving an authored blank line, typing its first character,
and deleting it back to empty do not move the insertion baseline or neighboring
content. Inactive ATX headings spend no horizontal measure on hidden opening
syntax; entering one reveals the exact marker within that active line without
moving neighboring blocks. Preserved spaces remain measurable, ordinary prose
uses language-aware editorial breaking rather than terminal-style arbitrary
breaking, and an interactive inline locator remains attached to immediately
following closing punctuation. Lists, blank lines, code fences, tables,
mathematics, footnotes, and Callouts preserve their source-owned rhythm and
object-local overflow.

Native selection is authoritative in every mode and uses the resolved Accent
consistently. Authored `==highlight==` uses one protected high-contrast Markup
highlight, not Accent or status color. Current Comment anchoring uses a quiet
Accent boundary/field plus a counted margin control; stale Comment groups do
not paint current prose.

Hyperlinks and Wikilinks use Accent plus underline. Hover or keyboard focus
strengthens the underline and adds only the shared quiet interaction surface;
Edit applies that feedback while Command arms a projected link for preview or
opening. An annotated Wikilink adds one small trailing superscript
`text.bubble` disclosure marker at the link's upper inline end. The marker uses
footnote-like zero-line-height geometry, reserves only its compact inline width,
and reveals the annotation in the shared bounded preview surface rather than in
document flow. Its text and accessibility name say that a source-owned
annotation is present. The marker never classifies argumentative force, truth,
evidence, or value.

Named and inline footnotes use one print-like treatment. Their prose locator is
a medium-weight Scholarly superscript ordinal with zero-line-height geometry,
Accent ink, and the shared quiet hover/focus surface. The generated end section
has no injected heading, card, or enclosing fill: one short leading rule,
hanging Accent ordinals, compact secondary Scholarly prose, and a quiet return
control at the content end carry the hierarchy. Footnote previews retain the
shared bounded-panel surface, show one concise footnote title and rendered
definition, and add no redundant metadata line. Edit adds no second end-section
projection.

Color has exactly two researcher inputs:

- **Accent** `#A94C22`
- **Paper** `#FEF8ED`

One resolver derives every Light, Dark, Increase Contrast, text, surface,
selection, authorship, status, and interaction output. Sidebar is a recessive
navigation surface; Apparatus is a document-adjacent surface closer to Paper.
Native and WebKit consume the same semantic outputs. Feature code introduces no
raw palette, and no color alone encodes truth, support, authority, acceptance,
or philosophical value.

Onboarding illustrations use a closed parchment/ink/accent palette independent
of Appearance. It is not a general component palette.

### 19.3 Variable boundary

The current shared Variables cover Color, Typography, Surfaces, Elevation,
Boundaries, reusable Metrics, Motion, and provisional Document Rhythm. This is
an extensible implementation inventory, not a closed taxonomy or a requirement
that every local value become a Variable. Promote stable cross-component
decisions and accessibility-critical thresholds. A bounded single-owner layout
value may remain local when it carries no state, authority, or adaptation rule.
Shared roles are purpose-named; do not create a numbered global scale merely to
avoid a clear local constant.

#### Corner geometry

Native windows, toolbars, menus, sheets, popovers, and controls retain platform
shapes. Shared custom components own reused or cross-runtime corner recipes.
A bounded feature-local surface may own its local geometry; promote it only
when responsibility or adaptation is genuinely shared. Borders do not imply
rounding, and unbounded content remains unenclosed. Shape never carries state
or authority alone.

#### Variable ownership

- **Typography:** §19.2 roles; Document typography remains owned by Appearance.
- **Color:** Accent and Paper inputs; every other color is a semantic output.
- **Surfaces:** opaque Navigation, Document, and Apparatus planes.
- **Boundaries:** structural divider, subtle boundary, and floating boundary.
- **Elevation:** native presentation elevation plus the current shared custom
  floating-control, bounded-panel, and Search-overlay recipes. Current
  structural depth covers the Sidebar–Document navigation cue and Record
  reading–evidence cue.
- **Metrics:** reused or adaptation-critical spacing, target, row, region, and
  readable-width roles owned by their reusable component.
- **Motion:** shared transitions are purpose-named and always define immediate
  Reduce Motion behavior.
- **Document Rhythm:** the selected Appearance's measure and typography.

Structural shadows are noninteractive, logical-edge-based, removed under
Increase Contrast, weakened with reduced transparency/inactive windows, and
secondary to a semantic surface plus divider. Children do not compound them.

#### Interaction presentation

Native controls own hover, press, disabled, selection, and focus. Custom
targets remain comfortably clickable and keyboard reachable. Resting controls
are quiet; focus is stronger than hover and persistent selection stronger than
both. Pointer activation does not leave a keyboard-only focus effect.

The shared segmented control is the default custom owner when a bounded
text-only horizontal single-choice group matches its interaction contract.
Native controls and feature-owned alternatives remain valid when their
semantics or interaction differ. Toolbar controls remain native and borderless.
Library icons share one editorial-control recipe. The Document Mode button
reports current Review, Edit, or Source through symbol, Help, and accessibility
value without becoming a segmented control.

#### Metrics

Metrics express responsibility rather than an application-wide numeric grid:

| Scope | Owned metrics |
| --- | --- |
| Shared | optical alignment, inline/section/region spacing, custom target minimums |
| Library | readable width, row height/inset, hierarchy step, header spacing |
| Apparatus | readable width, fact grid, section and row rhythm |
| Connect | group/cluster spacing, row height, direction-control bound |
| Records | collection columns/rows, reading measure, Note-reference rows, previews |
| Document | Appearance measure, adaptive insets, top/trailing scrolling space |

Native geometry, divider position, toolbar height, and window chrome are not
design Variables. Equal values across features do not merge ownership, and a
single-owner value does not need a catalog entry merely because it is numeric.

#### Motion

Motion is purposeful, interruptible, and absent under Reduce Motion. Native
feedback remains system-owned. Current shared motion covers disclosure, search,
document/workspace reveal, transient feedback, the Agent Change notification
stack, and onboarding steps. A bounded feature-local transition
may remain local when it communicates continuity or feedback and supplies the
same Reduce Motion behavior. Motion never changes authority or becomes the sole
state signal; decorative pulsing, looping, parallax scrolling, and row cascades
remain excluded.

### 19.4 Provisional layout defaults

Native containers own chrome, window resizing, and split geometry. Scholium
owns semantic region order, readable peripheral boundaries, content insets, and
the rule that Document receives remaining space. Initial window sizes are
implementation defaults, not minimums or acceptance gates.

Document uses CSS-native units without point conversion. Prose reflows without
page-level horizontal scrolling; wide technical objects retain local overflow;
Source wraps visual rows without altering logical lines. Layout remains usable
at narrow widths, enlarged text, and mixed scripts.

Settings uses one full-height native list/detail split beneath native titlebar
geometry. Search leads its navigation; Application, This Triptych, and Research
Guidance form concise groups. It has no card grid, icon toolbar, bottom action
strip, or catch-all General/Advanced page.

Metadata settings present field definitions and the order of fields always
shown in About without repeating the complete built-in schema. Document Appearance
presents the selected configuration and common controls first; detailed Body,
Heading, Callout, and CSS controls remain progressively disclosed. Unsaved
configuration changes require Save or explicit Revert.

### 19.5 Icons and symbols

#### Interface symbols

Standard actions and annotation disclosures use direct monochrome SF Symbols matched to
adjacent interface text. Visible labels own meaning; otherwise controls expose a
complete accessibility name. Native tint, disabled, focus, and selection remain
system-owned.

Passive/auxiliary glyphs use secondary or muted semantic ink; active bounded
actions may use Accent; Attention, destructive, confirmation, authorship, and
link direction use their named semantic output with textual/shape redundancy.
Multicolor, gradient, or variable symbol rendering never encodes workflow
state.

#### Bootstrap narrative illustration

Onboarding illustrations combine the canonical hand, one simple directional
pattern, and one solid field to support Welcome, Triptych, and Ready.
They are decorative and absent from accessibility. Adjacent text and controls
must fully communicate the task. No tuner or inferred readiness ships.

#### Application icon

The canonical application icon is the approved parchment-and-ink composition:
a cuffed hand points right toward one marginal rule and manuscript strokes. Its
orientation, paper field, ink character, and composition are application
identity, not Appearance Variables.

Use it only as the application icon. Do not recolor, mirror, badge, label,
recompose, or reuse it as a control/state glyph. Debug, QA, and release derive
from the same artwork. Replacement requires explicit researcher approval.

### 19.6 Interface writing and explanatory copy

Use the shortest accurate label that lets a researcher predict the immediate
result. Prefer a direct verb or established research term. Supporting copy
appears only for a necessary boundary, unfamiliar consequence, or first
executable repair and should remain one short sentence or fragment.

One meaning has one presentation:

- visible explanation is not repeated in Help or accessibility hints;
- Help describes only the control and begins with the action;
- accessibility hints add only missing consequence or context; and
- permission, provenance, destructive consequence, conflict, failure, and
  recovery remain complete in the owning body, alert, comparison, or sheet.

Agent Integration uses practical verb labels: **Copy Codex Setup Command**,
**Copy Claude Setup Command**, and **Show Core Protocol in Finder…**. Status
copy names only what Scholium can verify. Brevity never hides essential state,
names, consequences, or recovery.

### 19.7 Component catalog

A component owns presentation and adaptation, never document, workflow,
authorization, navigation, or operation lifecycle.
This catalog records current shared responsibilities; it is not an exhaustive
permission list. A feature may use a bounded local view without first creating
a reusable component or catalog entry.

| Component | Presentation responsibility | Semantic owner |
| --- | --- | --- |
| `Sidebar / Document / Apparatus` | Keep Document primary across three opaque native planes. | §18.2 |
| `Triptych Workspace Navigator` | Present Analyses, Topics, Works as peers with one selection and Note totals. | §§3.2, 18.2–18.3 |
| `Segmented Control` | Shared bounded text-only single-choice input with native-equivalent focus/traversal. | §§18.4–18.5 |
| `Source List` | Quiet hierarchical Note navigation with complete content states. | §18.3 |
| `Connection Direction Control` | Switch Incoming/Outgoing without changing graph authority. | §§12, 18.5 |
| `Document Rail` | Keep Settle at the Document edge without an Agent launcher or review milestone. | §§7.1, 18.5 |
| `Triptych Notifications Entry` | Open the complete Agent Change/Settlement/Attention queue with exact nonzero total. | §§13, 18.2–18.3 |
| `Top Notification Banner` | Give Agent Change, Settlement, permission, and persistent operation notices one concise adaptive grammar. | §§18.3–18.5, 20 |
| `Activity Notification Stack` | Present Agent Changes and Changed Since Settle reminders without becoming the queue or changing Settlement. | §§7.1, 18.3, 18.5 |
| `Operation Feedback` | Present transient information or persistent consequence/repair. | §§18.2–18.5, 20 |
| `Agent Changes` | Present one temporary exact `(change_id, Note)` mutation at a time without creating review state or completing Settlement. | §§7.1, 8.4, 18.5 |
| `Recovery Notice` | Present candidate, consequence, and safe repair from the workflow owner. | §§14, 18.6 |
| `Document Find Bar` | Find/replace in the current unsaved buffer while preserving editor state. | §§13, 18.4 |
| `Review Comment Anchor` | Locate current Comment groups without becoming authored Markdown. | §§7.2, 18.4 |
| `Property Group` | Group Metadata/About fields through a concise visible heading, spacing, and stable action slots. | §§5.2, 18.4–18.5 |
| `Content State` | Present page/pane state, explanation, and first repair. | §§18.2–18.5, 19.9 |
| `Bootstrap Illustration` | Support onboarding narrative without carrying task meaning. | §§16, 19.5 |

Promotion into this shared catalog requires a distinct repeated task, one
semantic owner, an adaptation contract, and rejectable proof.

### 19.8 Pattern catalog

Patterns combine components around one task without copying workflow authority.
The table records current shared patterns and does not prohibit a bounded
feature-local composition.

| Pattern | Boundary | Owner |
| --- | --- | --- |
| `Workspace Shell` | Switch retained Triptych workspaces inside one native split. | §§3.2, 18.1–18.3 |
| `New Note` | Commit exact source and enter Edit before derived refresh completes. | §§5.3, 18.3–18.4 |
| `Review / Edit / Source` | Reversible projections over one buffer and workspace-owned mode. | §§5.1, 18.4 |
| `Document Find` | Inline literal Find/Replace, distinct from Research Search. | §§13, 18.4 |
| `Search` | Explicit provider/scope, explanation, freshness, and bounded results. | §§13, 18.3 |
| `Connect` | Direct authored link occurrences with direction, source anchors, local context, and source-owned annotations. | §§12, 18.5 |
| `Notifications` | Complete queue in Sidebar/Inspector; Agent Change/Settlement subset in Document. | §§8.4, 13, 18.2–18.3 |
| `Agent Integration` | Present verifiable local status and copy user-scope host setup without editing external configuration. | §§8.2, 16, 18.2 |
| `Conflict / Recovery` | Retain bytes, compare exact revisions, and expose safe repair. | §§14, 18.4–18.6 |
| `Research Records` | Present the dedicated read-only collection, centered question/step reading plane, and step-local Note-reference attachments without inheriting chat or superseded workflow semantics. | §§8.6, 13, 18.5 |
| `Settlement Reminder` | Invite explicit Settle Again, Mark Unsettled, or no status change; dismissal changes no judgment, and exact Agent Changes open one comparison at a time. | §§7.1, 8.4, 18.3–18.5 |

### 19.9 Cross-functional state language

Workflow owners supply typed state; components map it to this vocabulary. This
is not a universal runtime enum or second state store.

| State | Shared presentation | Not equivalent to |
| --- | --- | --- |
| **Ready** | Trustworthy committed representation and valid next action. | Saved, Settled, or merely loaded |
| **Loading** | No trustworthy projection yet or an explicit refresh wait. | Empty, unavailable, stale |
| **Empty** | Valid scope contains no items; retain scope and first next step. | Missing or failed source |
| **Unavailable** | Required source/capability cannot serve; name repair/alternative. | Disabled styling |
| **Stale** | Older trustworthy projection retained with explicit refresh. | Conflict or failed operation |
| **Error** | Operation failed; preserve context and expose safe retry/alternative. | Empty or silent disappearance |
| **Conflict** | Expected authoritative revision diverged; retain buffer and compare. | Stale derived data |
| **Recovery** | Consequential repair after failure/interruption with verification. | Generic toast or overwrite |
| **Disabled** | Known action lacks a prerequisite; keep discoverable when core. | Unavailable content |

Every state retains owner and visible context; communicates state, consequence,
and first repair through redundant channels; keeps exact domain meaning with
the workflow owner; preserves focus/cancellation/source/recovery; and never
relies solely on color, motion, hover, position, or timeout.

Settle and Dismiss remain their own workflow meanings. Page/pane states use `Content State`;
field validation, compact rows, operation feedback, and recovery notices keep
their purpose-owned presentations while using this vocabulary.

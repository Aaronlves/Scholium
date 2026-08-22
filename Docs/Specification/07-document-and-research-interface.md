# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7. Shared
state presentation belongs to [Scholium Design](../../Design.md#199-cross-functional-state-language).

## 18.4 Document modes, context, and Metadata

Review, Edit, and Source are modes, not tabs, and follow Section 5.1. Their
chooser retains exactly one current selection for each live Triptych workspace
session, owned by the Document presentation rather than by a Note or Document
tab. Each workspace starts in Edit and carries that mode across Note
and tab changes. Switching workspace retains the origin selection and restores
the destination workspace's live selection with its tab group; it does not
create a per-Note mode history or reconstruct an editor. Window-session
persistence may restore the three workspace selections as presentation state
but never writes them to Markdown or a vault. Ordinary scrolling space clears
initial editor content from chrome. Review owns a
transient Comment bar and its in-place field; Edit owns a separate formatting
bar; Source owns neither. Each disappears when the selection clears, focus
leaves its task, or the document mode changes. The Comment field also
disappears when the researcher cancels or a save is acknowledged. Neither bar
appears during a pointer-selection gesture: it is evaluated only after
primary-button release, while a completed keyboard selection remains immediate.
At ordinary widths, each compact bar is horizontally centered above its
completed selection and clamped to the viewport, moving below only when there
is insufficient space above. While visible, the bar and an expanded Comment
field retain the same document-coordinate anchor as the document scrolls
instead of remaining fixed at an obsolete viewport coordinate. Cancelling an
empty Review Comment releases its input focus and retained action anchor, so
the next pointer or keyboard selection is immediately available without
erasing the current visible selection.

Managed New Note selects Edit and focuses the exact body start after commit.
Editor failure retains the Note with **Retry Edit** and **Source**.

An exact empty body presents **Empty Note** and **This note has no body
content.** without starting a renderer. Malformed frontmatter, whitespace,
unavailable source, unresolved reads, and render failures remain distinct.

The two selection surfaces share one restrained component style: an opaque
document-adjacent semantic surface, a neutral semantic separator boundary,
semantic text, and the same Accent focus treatment. Accent does not outline the
resting bar or its menus. They consume only resolved roles derived from
Variables. Both bars use the shallow **floating control** Elevation role;
Edit's custom menus and submenu use the **bounded panel** role. Each visible
container paints at most one role-owned shadow, and shadow remains secondary to
its surface and boundary. These surfaces introduce no independent colors,
blur, glass, or shadow recipes.

Edit's formatting bar keeps the frequent commands visible in this order:
**Text Style** (Paragraph and Heading 1–6), **Bold**, **Italic**,
**Strikethrough**, **Highlight**, **Link**, a **Wiki** split control, and
**More**. Wiki applies a Wikilink directly; its adjacent, undivided chevron
opens **Supports**, **Opposes**, and **Incompatible** Vector Link actions.
More contains **Inline Code**, **Code Block**, one **Lists** submenu for bullet,
numbered, and checkbox lists, **Blockquote**, **Comment** (the Markdown Comment
wrapper), **Import Image…**, and **Index Image…**. Both image routes also appear
in Format and Insert. A
constrained-width presentation may also move Strikethrough and Highlight into
More without changing command availability. Familiar formatting actions and
all Vector Link relationship actions use direct monochrome SF Symbols with one
quiet optical weight; Scholium does not redraw equivalent marks. Wiki remains
a short text label. Menu rows show action names, never syntax examples; only
Lists nests.

Edit's Wikilink and slash-command suggestions use one caret-anchored bounded
panel rather than a window, sheet, toolbar, or second text field. It follows the
editor caret as the document scrolls and flips above only when space below
is insufficient. The neutral boundary, opaque Document-adjacent surface,
**bounded panel** Elevation role, 12 CSS px interface labels, direct 14 CSS px
monochrome SF Symbols, 28 CSS px minimum rows, and Accent-free resting boundary
match the selection-menu grammar. Note rows may add one quiet, ellipsized path;
command and Callout-role rows show only names, never delimiters or syntax
previews. A bare block-safe slash shows four frequent entries; subsequent input
searches the complete command set while rendering at most seven visible
matches. The list remains content-fitting and viewport-bounded rather than
reserving width for absent detail.

All modes use one adaptive editorial-grid configuration for insets, responsive
threshold, trailing space, text scale, and semantic typography. The selected
Appearance supplies exactly one **Line width** value: default **72ch**, range
**48–96ch**, step **1ch**. Scholium provides no built-in preset, full-width
switch, percentage mode, or per-mode override. Remaining inline space is split
symmetrically with `max(mode minimum inset, (available width - line width) / 2)`.
The regular minimum inset is **32 CSS px** in Review/Edit and **40 CSS px** in
Source; all three reduce to **20 CSS px** below **44rem**. The **32 CSS px** top
inset and existing trailing scrolling space remain separate. CSS lengths never
convert to macOS points. `ch` resolves against Review/Edit Body type or Source's
exact-source type and therefore does not promise an exact character count.
At ordinary, narrow, mixed-script, and 100%/200% text presentations, all three
modes retain the shared measure and minimum insets. Edit and Source reconfigure
one retained editor state; window, split, theme,
line-width, or text-size changes never replace it or create an Editor window.

Each researcher-authored semantic text block preserves its exact Unicode source
independently of interface language. Beta and 1.0 interactive writing support
covers English, Simplified Chinese, and mixed English/Chinese content. Other
scripts remain byte-preserved and available in Source, but complete
bidirectional rendering, visual cursor and selection behavior, and installed
RTL input-method behavior are deferred under §17. Scholium never normalizes,
reconstructs, or silently replaces unsupported source. Code, mathematics, and
inert raw-HTML source remain left-to-right isolated technical regions. Interface
language never forces the direction of document prose, all Scholium-owned
spacing and boundaries use logical start/end edges so later RTL support requires
no second layout system, and user-authored raw HTML remains inert rather than
becoming an alternate direction-control or rendering path.

Appearance is machine-local configuration and never Markdown or vault state.
It stores multiple named configurations, keeps exactly one selected, and
supports save, rename, duplicate, and deletion while retaining at least one.
Structured controls configure the shared Line width plus Body, headings, and
each semantic Callout. Line width applies to Review, Edit, and Source; Body,
heading, and Callout presentation applies only to Review and Edit.
The default configuration uses the values in §19.2; Callout controls map
presentation parameters without changing protected role structure, generated
accessible role names, or source-controlled fold state. Mathematics remains
centered and italic, with automatic numbering on the physical right scoped per
document; code and tables retain their shared app-owned styles.
Advanced sanitized CSS snippets are an additive extension inside Appearance,
but Appearance displays no generated CSS preview. Source typography and the
application interface are not changed by a document configuration; only the
shared Line width changes Source layout.

### 18.4.1 Advanced CSS boundary

Imported snippets are copied into managed Application Support storage;
Scholium never loads them directly from a research vault and never modifies the
imported original. They style document content in Review and Edit only. Exact
visual parity is not required where Edit must preserve editable geometry.

The supported selector surface is bounded to the document root and ordinary
prose, heading, list, quotation, table, code, link, emphasis, mark, and rule
elements. Supported declarations are ordinary visual properties such as color,
background color, font family, font size, font style, font weight, line height,
letter spacing, text decoration, borders, border radius, padding, and margins.

Sanitization rejects imports, `!important`, scripts or executable HTML,
external URLs, selectors escaping the document root, and declarations that
hide, remove, reposition, or cover protected research information. Callouts,
footnotes, Review annotations, provenance warnings, diagnostics, conflict and
recovery controls, and application chrome remain app-owned protected
components. Their semantic structure and source-controlled state cannot be
restyled by a snippet.

An invalid snippet is disabled with an adjacent validation error. A rendering
failure enters persistent CSS Safe Mode and disables enabled snippets until the
researcher uses **Disable All Snippets** and re-enables selected managed copies.
Import, duplicate, rename, reorder, edit, reload, remove, and reveal act only on
those managed copies.

Toolbar: Sidebar and Back/Forward; Library separator; Heading Outline
and identity; flexible space; Search, Document Mode, and **Records** at
§19.3's inline-control spacing; Apparatus separator; trailing Inspector.
Records opens **This Note** with a selection, otherwise **Triptych**. Mode icon/help
report Review, Edit, or Source. Activation switches Review/Edit and returns
Source to Review.
Source remains selectable only under **View > Document Mode**; `Command-R`
performs the same switch. Controls remain borderless.
No second identity row, Document Metadata, or More; complete
Metadata remains in Research. Compact identity stays secondary and static;
H1 stays primary without handoff or scroll animation.
Document Text Size is per-window and source-neutral.

The shared sheet edits role-valid Metadata at the record revision.
Labels and values remain; definitions use Help. Its action slot reveals on
hover/focus without reflow and stays accessible. Whitespace groups fields.
Contributors retain numbered subfields and the neutral segmented kind selector.
Save stays emphasized. The sheet never changes YAML; authored `summary` and
`keywords` route to Source, and unknown YAML is not a managed field. About
reuses the configured cross-authority order without merging ownership.

## 18.5 Contextual research and Actions

Apparatus contains Research Inspector only; active Discussion and Research
Records keep distinct ownership. Active Discussion opens as an
Action sheet. Research Records is an independent, nonrestored native auxiliary
window keyed to one Triptych. It reads that Triptych rather than following
unrelated window focus, uses §19.4's initial size, and is resizable down to
**700 × 520pt**. It has no Workspace Sidebar control or alternate primary-
interface mode and never appears inside Inspector.

The ordinary entry is a full-window collection on one continuous semantic
Document surface. The native toolbar hosts the shared **Records / Reading
Leads** segmented index: equal text segments, a quiet track, and one raised
selection plate without Accent fill or shared Liquid Glass. Below it, one adaptive header places search and the borderless native
Scope and filter menus on one scanning row at wide widths and stacks them only
when space requires it. The toolbar index is the visible collection identity
without a count; search fills the header. Ready, empty, filtered-empty,
partial-load, unavailable, and error states retain this compact hierarchy and
accessible custom targets. The titlebar,
toolbar, collection header, and content resolve the same Document background
and use adaptive 1pt rules rather than contrasting bars, materials, or shadows.
Native traffic lights, dragging, resizing, full screen, key-window appearance,
and the window menu remain system-owned. Collection and Reading Lead content
stay below system chrome while Record detail's reading/evidence boundary remains
visually continuous through the toolbar band. No scroll owner may pass through
the titlebar.

Records form one flat rule-separated ledger, not cards or date groups. One
compact 48pt Triptych row owns an unlabeled 28pt Attention gutter, a two-line
**Record** cell, **Action**, and **Date**. Record is the frozen one-line Record
Title in the regular 12pt Default interface role; its second line is the focal Note in
muted 10pt Sans. This Note omits the redundant second line. Attention, Action, and Date
center against the complete Record cell. Method, source, and complete results
remain in detail. Attention stays empty
normally and uses one icon-only exception mark for Blocked or limited,
unavailable, or missing Analyze Reliability/Coverage. Help and accessibility
preserve exact values. Action is a centered, text-only neutral capsule with no
category color or symbol and no independent action semantics. Records default
to finished time descending and stable identity. Record, Action, and Date
headers request provider-owned ordering before pagination. The collection has
no visible content title, explanatory subtitle, Pin, Research Result synopsis,
source line, or note count. Reading Leads apply the same compact row, column-header, separator,
and interaction rhythm. The visible header begins with Title: the leading 32pt
checkbox track retains the accessible Handled label and sits 8pt from Title,
followed by Author(s), Year, and Publication. Academic row values use the
interface family throughout: Title uses the regular 12pt Default interface
role, while Author(s), Year, Publication, and unavailable-field state use the
11pt Compact interface role. Switching family does not promote supporting
values to 12pt; capsules remain 10pt Sans. The checkbox remains independent;
the four academic columns open detail
without another glyph. Missing bibliographic facts read **Not recorded**.
Reason, uncertainty, locators, note, and parent context
stay in detail. Neither collection introduces an icon well, nested card, badge,
or trailing detached action region.

Both collections load exact 100-row slices. The first content-column header
shows the exact filtered total beside Record or Title in muted 10pt tabular
figures, without parentheses or a “results” suffix. Reaching the loaded boundary
requests the next slice while preserving collection state. Later-page failure
retains loaded rows and exposes Retry at that boundary.

Selecting a row enters one route-owned detail and removes the collection from
the active accessibility tree. The native toolbar owns Back, omits the generic
Record title, and retains only meaningful destination titles. Back restores the
collection state.
A Record detail contains one dominant reading plane and one narrower
**Evidence** rail at an approximately **64/36** working proportion;
additional width accrues to reading first. The panes use the Document and
Apparatus semantic backgrounds respectively. One 1pt adaptive divider and one
purpose-named reading-evidence structural shadow distinguish the quieter rail
from the dominant reading plane; both continue to the top of the native
full-height split. Increase Contrast removes the shadow and relies on the
strengthened divider and semantic surface difference. Evidence is expanded by default. A
native trailing-toolbar control hides or shows the whole rail; hiding it gives
the available width to reading and does not alter Record, route, or Response
state. Reading Leads use a corresponding single-occurrence detail route. Focus
changes in other windows never retarget Scope, View, route, filters, or the
current detail.

A Reading Lead detail uses one centered reading flow rather than the Record's
split workspace. Its header places one independently operable disposition
button beside the scholarly title. Unprocessed presents the accented
**Mark as handled** action with a clock; the immediate optimistic state becomes
a neutral bordered **Handled** button with a checkmark and remains reversible.
The control retains an accessible action label and current value; concise Help
and an accessibility hint preserve that Handled means processed only, never
read, accepted, cited, verified, or endorsed. The selectable full citation
follows in muted Scholarly body above the information band. Bibliography
keeps authors, year, publication, DOI, and Zotero item key together. At regular reading widths Bibliography occupies the wider left side
of one information band and Discovery Locators occupies its bounded right side;
at genuinely narrow widths the two complete groups stack in the same order.
Recommendation reason, uncertainty, researcher note, source and parent
destinations, then closed Technical Details follow the band.
Bibliography, Record identity, and Technical Details reuse the
Inspector About label/value grid, with Sans labels and Note names, Scholarly
body values. DOI, Zotero item key, and Discovery Locators are scholarly
content and use that same Scholarly value treatment rather than technical
identity typography. Exact Record and revision identity remains monospaced.
Missing bibliography or locator facts remain explicit.
Across both Record and Reading Lead detail routes, academic prose and
content-derived values use Scholarly body. Their long collection ledgers are
interface indexes and therefore remain Sans: primary row values use Default
interface, supporting values use Compact interface, and annotations or metadata
use Small. Supporting explanations and explicit empty or unavailable-state
descriptions outside a ledger use Compact interface. Visual subordination never
permits an empty, unavailable, or error state to disappear.

The Record header shows Action and finished time once, one scholarly title, and
only distinct role, Method, or source metadata. Completed is not repeated there;
Blocked remains visible. **Research Result** remains present when its Result
Contract has no academic fields and states that exact condition. It and
every other reading-plane section share the Apparatus heading token. Attributed
rows align one fixed authorship track with one Serif academic-prose track.
Researcher and Agent use distinct semantic
colors and symbols with visible role labels; generic response-kind labels do not
repeat the author. Records metadata uses spacing and alignment, never middots.
The auxiliary window's Scope remains **This Note / Triptych**. A Record result
found through global **This Vault** Search still opens this existing Triptych-
keyed window, reapplies its **Triptych** Scope, selects Records View and the
exact Record detail, and locates its matched attributed statement when one was
returned. The window does not add a This Vault control, reconstruct cached
result prose, or create a second Record-query owner. A continuation child
Record remains searchable but appears beneath its parent Action/Record rather
than as another peer row in the ordinary Records collection.

The reading plane owns **Researcher Response**: empty offers **Add Response...**;
saved content offers **Edit Response...**. Evaluation comes first; absent Method
Feedback stays behind **+ Add Method Feedback...**. Saved feedback reveals
**Improve Current Method...**. **Save Response** atomically writes both. Its
heading uses the reading baseline, never the Evidence inset.

The fixed Evidence rail presents **Changes**, **Effects**, **Context Used**,
**Participants**, and **Technical Details**. It owns no Review or Response.
Every section title shares one height, inset, baseline, and Apparatus heading
style. Each fact uses one aligned monochrome symbol, title, and short provenance
text. A fact title uses the 12pt Medium interface Row Title role, never the
Semibold Section Title role; its provenance uses un-emphasized 10pt Small Sans
in `mutedText`. Note and Record names, roles, dates, state, and provenance use
Sans; attributed testimony and academic result prose use Serif. Context Used
uses a quotation symbol distinct from every Participant document symbol.
A Participants or Context Used preview contains at most three rows; the focal
Note and other safely actionable entries lead, while deleted or unresolved
provenance remains available. When the complete set exceeds three, the title is
one rounded, keyboard-operable disclosure showing the total and a right
chevron, then opens a native transient popover with every entry. The popover
closes through native outside-click,
Escape, or source navigation and introduces no custom close button, material,
shadow, or persistent state. Its initial focus belongs to the effect-free scroll
owner rather than the first evidence row, so pointer opening paints neither a
keyboard focus frame nor a false hover surface. Tab advances to a row and then
uses its visible native focus effect; the shared rounded hover surface appears
only under an actual pointer or press.
A safely resolved Note or Record destination makes the complete rounded row
interactive without adding an **Open** glyph or button. An unresolved source
retains its exact locator and testimony as selectable, copyable,
noninteractive text. Agent-reported Material use is a fallback only when a
verified Context Use report is absent. **Changes** alone owns source-change
state, comparison, and recovery. **Effects** states completion, Fidelity, and
discrepancies without repeating Changes, scores, badges, or color-only meaning.

The current researcher judgment remains directly readable in the reading
plane. Its Add/Edit control opens the combined native
Response sheet; an unsaved draft blocks implicit dismissal and requires
explicit discard confirmation, while a save or reload blocks all dismissal.
One
default-closed **Technical Details** group contains only Record kind, schema,
integrity, identifier, Method/source identity, and exact participant revisions.
It uses the same adaptive Inspector About label/value grid rather than a local
field layout; a narrow region stacks the complete group as one unit.
The single confirmed permanent-delete route is a named `trash` icon in the
single-Record header, never on collection rows or inside
Technical Details. Changes offers read-only **View Changes...** or **Compare
Changes...** for confirmed Agent changes and only the recovery operations whose
exact prerequisites remain valid. Method improvement begins only from the
saved Method Feedback in this Record and remains a separate authenticated Run.

Compare Changes is one shared attached single-column diff, never a left/right
pair. Each document shows path, state, and revisions and can fold; the sole or
first document opens initially, with **Expand All** and **Collapse All**. Three
context lines surround changes; longer equal ranges become **N unchanged
lines**. Record mode selects whole documents only and offers **Return to
Record** / **Undo Selected Documents...**; Conflict mode offers **Return to
Editing** / **Reload from Disk**. Full success returns; partial results remain
visible per document.

Direct Undo is available from that exact Record only while each selected Note
still equals its final Agent revision and its Run-bound starting evidence is
intact. Closing and reopening the Records window does not change this factual
eligibility. Undo never grants authority for another revision and never means
Note Review.
There is exactly one native trailing Inspector per window, with **Overview,
Connect, Actions** in that order. These are
mutually exclusive modes inside the Inspector, not split columns, Document
tabs, panels, or windows. The index uses the shared segmented control with
three equal centered labels, its quiet track, and one raised selection plate.
It has no underline, Accent fill, or full-width bottom rule. The selected mode uses
the shared continuous selection corner;
its label uses Semibold primary ink. An unselected label uses Regular secondary
ink. Hover gives an unselected item the same-shaped but quieter local surface
and primary ink without changing its weight; press and native focus remain
distinct immediate states with no geometry animation. Labels remain
horizontally reachable rather than truncating. The selected mode is exposed
accessibly, Left/Right Arrow changes mode, Tab enters its content, and every
mode owns at most one vertical scroll.

A new window begins each Triptych workspace in Overview and stores one last
Inspector mode for each workspace. Restoring a window restores those modes;
switching notes, Document tabs, or Review/Edit/Source never changes the
selected workspace's Inspector mode. Switching workspace restores its mode
without creating another Inspector or changing native split geometry. Hiding
the Inspector transfers only its Show route under §18.2; no Inspector content
moves into Document. The Research menu opens an Action without revealing or
changing the Inspector.

An Inspector without a Document shows **No Document Selected**, never stale
content or automatic collapse. Selecting a Note restores its retained mode.

Overview presents only compact current-note projections, in this order:

1. **Needs Attention:** current-note count and distinct actionable kinds form
   one full-row native button that opens the Workspace Attention popover filtered
   to that exact Note. It has no nested **Show All** row. At zero it retains the
   heading and `0` but no reassurance sentence or decorative verdict.
2. **Review:** distinct from Attention. It states **No Agent changes to review**,
   **Needs Review · N Agent activities** as one full-row route, or
   **No Agent changes awaiting Review** with **Last reviewed [date]**.
3. **About:** nonempty fields use spacing-only groups with accessible names.
   Research fields use reading blocks and Keywords use neutral capsules. Its **Edit
   Metadata** heading opens the shared sheet; values remain static and
   selectable. Analysis adds **Link Zotero
   Item…** or **Manage Zotero Link…**; a bound Analysis also adds **Open in
   Zotero**. The sheet owns selection, Rebind, and confirmed
   Clear without exposing identity or metadata in Inspector. Research Status, Key Metadata,
   Provenance, Derived State, and a Zotero section remain absent.

A pending activity set automatically presents a once-announced, focus-neutral
Document task bar with **View Changes** and **Mark Current Note Reviewed**. Its
raised surface and bottom rule never form a floating card or shadow. Close
suppresses that exact set only in the retained session; Overview reopens it,
and a new Agent set presents again, unlike researcher-only revision changes.
Commit requires clean, available, conflict-free exact Note and Record revisions;
every mismatch fails closed. No toolbar, Record/change action, or result
notification substitutes.

Freshness appears only as a compact actionable line when Refresh is pending,
stale, failed, or unavailable. It preserves last-known-good projections and
offers Retry where applicable; it never claims reading, truth, or evidence.
In Overview it follows the About projection and its Edit Metadata route; it
is not promoted to a separate section or card.

Connect begins with the shared two-segment single-choice control labelled
**Incoming Links** and **Outgoing Links**, immediately after its freshness
state and before the relationship groups. It is centered on the Inspector
content axis rather than aligned as a leading list row. This is a local Connect view switch,
not a TriptychWorkspaceNavigator, ModeIndex, Document mode, or Search filter. Every new
Connect presentation starts at **Outgoing Links**. The live Connect
presentation owns exactly one current direction selection, not a history keyed
by window, Note, or prior destination, and writes nothing to window-session
persistence. Switching direction changes only the visible projection and never
mutates the graph, source, or Note selection. The control has no Combined or All
segment. It remains visible when the selected direction is empty so the
researcher can move directly to the other direction.

Outgoing shows relations authored by the current Note; Incoming shows
relations authored by another Note toward the current Note. Neutral Related
and Incompatible relations are undirected and therefore appear in both
segments, with their same source anchors and an accessible explanation that
they are shown in both directions. Switching direction retains the three group
expansion states and returns the scroll position to the beginning of Connect so
the selected direction's context is immediately visible.

Connect then presents three expanded, independently collapsible groups:

| Target | Groups |
| --- | --- |
| Analysis | Neighbor Analyses, Related Topics, Related Works |
| Topic | Related Sources, Neighbor Topics, Related Works |
| Work | Related Sources, Related Topics, Neighbor Works |

Within a group, the selected direction orders relationship clusters as
applicable: Supports, Supports This Note, Opposes, Opposes This Note,
Incompatible, then neutral Related. Each major group heading shows its total
for the selected direction. Each relationship cluster begins with a visible,
non-card subheading containing one direct monochrome SF Symbol, its complete
relationship name, and a quiet monospaced cluster count. A long cluster's
subheading may pin immediately below its parent group heading while it scrolls,
but it is not a disclosure control and does not own expansion state. Individual
Note rows repeat neither symbol, relationship label, nor count.
All visible Connect interface language, including Note-row titles, uses the
system Sans interface family rather than the editorial Serif. Default headings
and rows use existing secondary or muted text roles; hover and keyboard focus
may raise the active row to primary text. Connect adds no local gray or color
Variable, and every default text role continues to meet the §20 contrast floor.

Supports and Supports This Note use `plus.circle`; Opposes and Opposes This
Note use `minus.circle`; Incompatible uses `xmark.circle`; neutral Related uses
`link`. Text owns relationship direction and meaning, so inverse forms reuse the
same decorative symbol. These symbols share one restrained semantic text color
and never encode truth, force, or value by hue. Titles wrap. Do not open a
second panel merely to show a title. Preserve source anchors. An empty group
retains its heading and `0` without **None**. Connect shows the same freshness
state before its direction control and groups. Stale or failed state keeps the
last complete graph readable and offers a full-row Retry action.

Relation rows remain single full-row native buttons using the Connect Note-row
metric owned by §19.3, with no default separators or trailing diagonal-open glyph.
Their concise pointer help and accessible name state the relationship from the
current Note's perspective. Primary activation opens the connected Note,
using the source line when that peer owns the relation occurrence. When the
distinct source-return route remains applicable, it stays available as an
explicitly named context and accessibility action without adding a second
detail panel. Each original group heading is a sticky section header inside
Connect's sole scroll owner. A relationship subheading may pin only within its
parent group and hands off to the next subheading; it is never a glyph-only rail
fixed to a window coordinate. The symbol is decorative and hidden from
accessibility, but the visible relationship name and count remain in the
heading. Each Note row is one primary full-row button whose accessible name
still states the relationship from the current Note's perspective; a distinct
source anchor remains a named accessibility action after the visual symbol is
removed.

Actions has no generic **Actions** section heading. The role-valid defaults in
Section 8.1 retain their canonical order while appearing in two quiet semantic
groups: **Research** contains Discuss and the applicable Analyze, Synthesize,
or Write Action; **Review** contains Critique where applicable and Check
Fidelity. Completed work is accessed through Research Records, and Agent
handoff remains inside the selected Action. Discuss reopens the current Note's
resumable active Discussion and automatically includes its existing line
Comments from that one row.

Profiles configure only the closed Platform Actions and do not create a third
custom-Action group or another visual branch. Availability fails closed while
checking; an unavailable Action states
only its first executable repair. Settle remains a quiet direct current-note
action under one **Judgment** group, and Attention remains in Overview/Library
rather than becoming completed history.

Each Action is one native full-row button with a direct symbol, the shortest
accurate title, explanation only under §19.6, and only when useful a trailing
chevron. Action launchers have no assigned shortcuts; the menu and Inspector
remain keyboard-accessible. Its modular sheet shows the necessary scholarly inputs
and app-owned authority or recovery facts without exposing assembled prompts,
registration keys, Session secrets, or technical mode names. The active Action and its sheet
retain keyboard, menu, pointer, focus, cancellation, and VoiceOver parity.
All Action launchers use one shared visual row recipe with the Action target
metric owned by §19.3 and no default row or group separator. Availability checking,
ready, unavailable, running, error, cancellation recovery, Settle, and Settled
remain distinct states without changing Action routing or ownership. A default
Action whose title already identifies the task shows no ordinary explanation.
An unavailable Action shows only its first executable repair. Error and
recovery information may use the complete required text and is never truncated
to the ordinary two-line explanation budget.

A running Action retains that ordinary row structure and minimum rhythm rather
than becoming a taller state block. Its leading Action symbol yields to one
small indeterminate progress indicator; the Action title remains on the shared
title axis; trailing text states **Running**; and a separately named direct
**End Action** control replaces the ready-state chevron. It adds no ordinary
second line. Larger interface text or localization may grow the row rather
than clip its title, state, or ending route.

An Action sheet ends at successful handoff: request/focal context, academic
inputs or repair, then **Copy Handoff**. The copied instructions contain only
Run locator, one-time Pairing Code, local route, and CLI steps; the code is
never a separate field. Copy freezes when needed but never selects or opens an
Agent app. Success closes and restores focus to the Action row; failure keeps
the sheet and inputs. A prepared Run's compact status sheet offers Run status,
**Copy New Handoff**, **End Action**, and recovery only. Recopy invalidates the
prior pairing without replacing the Run.
Closing the sheet leaves an unfinished Action active; the explicit **End
Action** route revokes Agent access and closes a cancellable no-write Run.
Confirmed changes instead require Result finalization; conflicts, unknown
writes, and recovery duties retain their owning repair path. **Finish Discussion** preserves the
current exchange as a finished Research Record, even when the Agent has not
replied. Pairing,
re-pairing, Session expiry or revocation, missing local Skill-folder path,
conflict, write result unknown, and recovery each use complete text and an
executable next route without displaying the real Session secret or internal
fingerprints as tasks for the researcher.

The Action row states **Waiting for Agent**, **Running**, or **Needs Attention**
from the privacy-bounded projection. A Record ends the row. Arrival never opens,
retargets, activates, focuses, or reviews; only notification action opens it.

Foreground completion sends one actionable in-app notification to the origin
window. Authorized background delivery says only **An Agent result is ready to
review.** Record ID plus finalized-result fingerprint deduplicates it. Clicking
opens the exact Triptych/Record. Delivery is one-shot and independent of Note
Review. No
notification contains research content, credentials, change evidence, or traces;
denial is not repeatedly requested and never weakens the Action row.

Functional text is never a generic blue link or a separate **Open** button.
Body and secondary colors, hover surface, focus ring, button semantics, and
the full hit region make interaction recognizable without depending on color,
hover, or pointer use.

All section headings across Overview, Connect, and Actions
use one Apparatus heading token. Its provisional starting point is 10pt system
semibold, 0.7pt tracking, and secondary text color. English localization
supplies uppercase strings; runtime code never forces case, so Chinese and
other languages retain natural writing.

Inspector layout uses the purpose-named Apparatus content-inset and fact-grid
metrics owned by §19.3 rather than leaf-view literals. Short facts form one
section-level two-column grid with a shared, trailing-aligned label column, one
common leading axis for values, and first-baseline alignment. Ordinary canonical labels therefore remain
horizontal in **300pt** and **278pt** Inspector scenarios after the content
insets. If available width, 200% readability, or localized labels cannot fit,
one container-level adaptation stacks the complete grid; individual rows never
switch independently. Empty values do not create rows. Summary, Source Basis,
Limitations, and other long researcher prose always use a reading block: label
on its own line and Alegreya content on the next line with a 12pt leading
indent. Labels, diagnostic/state names, and action names remain system sans semibold; field values,
explanations, and research prose use Alegreya; exact paths and revisions remain
monospaced. Counts use monospaced digits without changing the surrounding
face.

Provisional rhythm uses the Apparatus scanning and Action-row metrics owned by
§19.3, the Scholarly body
role with approximately 17–18pt reading leading, 4pt label-to-copy gap, 8pt between
reading blocks, and 16pt between sections. Apparatus sections, ordinary Action
rows, and relation rows draw no boundary by default. A local boundary must be
enabled explicitly for a named ownership, consequence, or recovery distinction.
The native comparison catalog and human review may revise typography, grid,
indent, and spacing while preserving semantics, interaction, researcher
control, and accessibility.

Document has no bottom Research Strip or hidden-Inspector duplicate. Action
handoff remains keyboard/VoiceOver reachable; its sheet survives launch and
restores focus on reactivation. Inspector visibility, mode changes, and
projection refresh never replace the retained Editor host or its buffer,
selection, Undo, IME, scroll, or focus state. Report handoff, never agent
execution.

## 18.6 Document-owned state and action meanings

The shared cross-functional presentation vocabulary is canonical in
[Scholium Design §19.9](../../Design.md#199-cross-functional-state-language).
The table below retains the Document-specific meanings, source-revision
transitions, and recovery actions that cannot be reduced to a presentation
state. Its terms are not a second cross-functional state dictionary.

| State | Meaning |
| --- | --- |
| **Edited** | Active buffer differs from committed source. |
| **Saving** | Revision-checked commit is running. |
| **Saved** | Exact canonical Markdown readback matches the validated candidate; derived consumers may still refresh. |
| **Autosave Failed** | Source commit cannot be proven; retain the buffer and offer Retry or recovery. |
| **Conflict** | Expected revision differs from disk; retain buffer and compare before destructive reload. |
| **Refreshing** | Derived consumers are catching up to committed source. |
| **Derived State Stale** | A consumer represents an older committed revision. |
| **Fully Up to Date** | Source and named consumers share one committed revision. |

Conflict actions are **Compare Changes**, **Reload from Disk**, and **Keep
Editing**. Comparison supplies the Document-conflict inputs and actions to the
same single-column exact comparison used by Research Records; it offers
**Return to Editing** or **Reload from Disk** and no source-change selection.
Each exact comparison row retains one logical source line while soft-wrapping
its visible text within the comparison width; wrapping never mutates either
revision or creates a source line. Editor Undo and Research Record direct Undo
are never interchangeable; editor `Command-Z` affects only the active editor
session.

Autosave and conflict presentation belong to Document, never Actions or
Research Inspector. After Saving, autosave has exactly three
terminal Document outcomes: silent **Saved**, persistent **Autosave Failed**,
or persistent **Conflict**. Ordinary autosave creates no Save button, success
toast, or saved-with-warning state. Autosave Failed states that the editor
buffer remains available and retains the existing Retry or recovery route. An
unresolved Conflict uses the same Document-owned position, states that
autosave is paused because the file changed outside Scholium, preserves the
editor buffer, and exposes **Compare Changes**. These failure states remain
until the state changes or the researcher chooses the applicable recovery
path; they do not time out as if the failure were resolved.

Filesystem metadata and redundant machine-local housekeeping are not Document
states. Once exact canonical readback proves the candidate, the Document is
Saved without a technical warning or another write request. If that readback
cannot prove the candidate, Scholium reports Autosave Failed rather than
softening uncertainty into success.

Retained interrupted-save candidates share the existing native Recovery sheet
with durable file-operation recovery; they do not create a version browser,
Document mode, or Research Action. Each candidate row
states its current source relationship in text and symbol, exposes a selectable
read-only exact-source disclosure plus **Copy Candidate** and **Reveal Candidate
in Finder**, and enables **Restore Candidate…** only for an observed expected or
already-candidate revision. The confirmation states the editor-flush and final
revision check. A later mismatch fails as Conflict, keeps the candidate, and
updates the row on Refresh. Recovery errors remain visible without hiding valid
entries from the other recovery class.

System-Trash recovery rows are visually and semantically distinct from save
candidates. They name original source items, known Finder-owned destinations,
affected Discussions and finished Records, current receipt state, and whether
the only safe route is forward cleanup or researcher inspection followed by
**Retain Records and Resolve**. The latter never claims to restore or erase a
file. File deletion actions use exactly **Move to Trash…** and **Cancel**.
Standalone Research Record deletion retains its separately named permanent
confirmation and never presents itself as Finder-restorable.

## 18.7 Simplified Chinese terminology and translation boundary

Beta and 1.0 localize the researcher-facing interface only in English and
Simplified Chinese; §17 defers additional languages and RTL chrome, while §18.4
preserves exact Unicode source.

Translate researcher-facing language contextually, not by mechanical token
replacement. Stable identifiers, enum values, command IDs, paths, exact source,
researcher prose, and internal vocabulary remain unchanged. Skill names and
package-authored descriptions stay verbatim. Chinese prose uses full-width
punctuation.

| English | Approved Simplified Chinese |
| --- | --- |
| Scholium | Scholium |
| Triptych | 脉络 |
| Vault | 研究库 |
| Library | 研究文档 |
| Analyses / Topics / Works | 分析 / 议题 / 写作 |
| Discuss / Analyze / Synthesize / Write | 讨论 / 分析 / 综合 / 写入 |
| Critique / Check Fidelity / Manuscript | 评析 / 核查 / 稿件 |
| Research / Review / Judgment (Actions groups) | 研究 / 审查 / 判断 |
| Settle / Settled | 暂定 / 已暂定 |
| Attention / Connect | 关注 / 连接 |
| Incoming Links / Outgoing Links | 传入连接 / 传出连接 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| Comment / Discussion / Response | 评论 / 讨论 / 回应 |
| Research Record | 研究记录 |
| No Document Selected | 未选择文档 |
| Expand All Folders / Collapse All Folders | 展开所有文件夹 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

System-owned Finder names, paths, stable identifiers, enum/raw values, and
researcher-authored titles remain verbatim and are never translated.

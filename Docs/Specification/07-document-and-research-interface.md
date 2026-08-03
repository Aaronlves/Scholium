# Specification: Document and Research Interface

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 18.4–18.7: Document modes, research interface, state meanings, and terminology; sibling chapters do not restate it.

## 18.4 Document modes, context, and Properties

Review, Edit, and Source are modes, not tabs, and follow Section 5.1. Ordinary
scrolling space clears initial editor content from chrome. Review owns a
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

When the selected note's exact Markdown source is zero bytes, Review presents
one centered read-only group: decorative document symbol, **Empty Note**, and
**This note has no content.** This is a completed source state, not Loading,
and it starts no empty WebKit render. Whitespace, an unavailable File Provider
source, an unresolved read, and a rendering failure are not empty notes and
retain their distinct states.

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
numbered, and checkbox lists, **Blockquote**, and **Comment** (the Markdown
Comment wrapper). A
constrained-width presentation may also move Strikethrough and Highlight into
More without changing command availability. Familiar formatting actions and
all Vector Link relationship actions use direct monochrome SF Symbols with one
quiet optical weight; Scholium does not redraw equivalent marks. Wiki remains
a short text label. Menu rows show action names, never Markdown delimiters or
syntax examples, and no submenu nests beyond the single Lists level.

Edit's Wikilink and slash-command suggestions use one caret-anchored bounded
panel rather than a window, sheet, toolbar, or second text field. It follows the
CodeMirror caret as the document scrolls and flips above only when space below
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
Shared ownership, units, and the 72ch default have passed ordinary, narrow,
mixed-script, and 100%/200% researcher comparison. Edit and Source
reconfigure one retained editor state; window, split, theme,
line-width, or text-size changes never replace it or create an Editor window.

Each researcher-authored semantic text block owns its base writing direction.
Review determines that direction from the block's first strong directional
character and directionally isolates the block from adjacent content. Edit
applies the same automatic direction to semantic lines and projected fragment
components; Source applies automatic direction independently to each visible
exact source line. Code, mathematics, and inert raw-HTML source remain
left-to-right isolated technical regions. CodeMirror's visual cursor and
selection model must consume the same per-line direction and syntactic bidi
isolates that produce the visible order. Automatic direction never replaces,
locks, or reconstructs text: pointer, keyboard, selection, deletion, insertion,
Undo, and installed input methods edit RTL content through the same exact
CodeMirror source in Edit and Source. Interface language never forces the
direction of document prose, all Scholium-owned spacing and boundaries use
logical start/end edges, and user-authored raw HTML remains inert rather than
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
Advanced sanitized CSS snippets remain an additive compatibility path inside
Appearance, but Appearance displays no generated CSS preview. Source typography
and the application interface are not changed by a document configuration;
only the shared Line width changes Source layout.

Document toolbar order is Sidebar visibility; Heading Outline and compact
identity; mode and Search; Research Record; Inspector visibility. Scholium
controls are borderless ink. No second identity row,
Document Properties button, or More control exists.
Complete Properties is in Research; direct controls retain menu/keyboard
routes. The compact identity uses secondary text while the in-document H1
remains primary. It is static during Beta scrolling; no custom H1-to-toolbar
identity handoff or scroll-linked title animation is included. Document Text
Size is per-window and source-neutral.

Properties performs targeted frontmatter edits and distinguishes absent,
empty, invalid, derived, and not-applicable. Exact YAML stays available in
Source. About follows the role-specific catalog in Appendix A; absence is
quiet, and `zotero_item_key` and Analysis title are never selectable there.

## 18.5 Contextual research and Actions

Apparatus contains Research Inspector only; active Discussion, Research Record,
and checkpoint recovery keep distinct ownership. Active Discussion opens as an
Action sheet. Research Record is an independent, nonrestored native utility
window, reads the focused Triptych directly, and keeps a fixed **760 × 680** content
size chosen for readable temporary inspection. It uses one native list/detail
layout, has no Workspace Sidebar control or alternate wide/narrow presentation,
does not adapt into another primary interface, and never appears inside
Inspector. Its leading record list remains compact and top-aligned in ready,
empty, and filtered-empty states; controls and rows use compact native macOS
density while every custom target retains the minimum accessible hit region.
Normal Action Material-use and Fidelity facts remain in the existing collapsed
**Record Details**. An `unverified` Fidelity state instead appears once in the
evidence area as a complete textual statement; it is not duplicated in Details
and does not acquire a badge, score, color-only meaning, tooltip, filter, or
new disclosure. Discussions show neither inapplicable row.
There is
exactly one native trailing Inspector per
Workspace, with **Overview, Connect, Actions** in that order. These are
mutually exclusive modes inside the Inspector, not split columns, Document
tabs, panels, or windows. Their text labels use a restrained ink underline,
not a filled/capsule segment. The index uses three equal columns with each
label centered, no Scholium-drawn full-width bottom rule, and a provisional
**18pt** Accent underline for the selected item. Labels remain horizontally
reachable rather than truncating. The selected mode is exposed accessibly,
Left/Right Arrow changes mode, Tab enters its content, and every mode owns at
most one vertical scroll.

A new window begins in Overview and stores its last mode per window. Restoring
a window restores that mode; switching notes, Document tabs, or
Review/Edit/Source never changes it. Hiding the Inspector transfers only its Show
route under §18.2; no Inspector content moves into Document. Research menu and
keyboard commands may open an Action without revealing the Inspector or
changing its mode.

Overview presents only compact current-note projections, in this order:

1. **Needs Attention:** current-note count and distinct actionable kinds form
   one full-row native button that opens the Workspace Attention popover filtered
   to that exact Note. It has no nested **Show All** row. At zero it retains the
   heading and `0` but no reassurance sentence or decorative verdict.
2. **About:** only non-empty role-specific fields in Appendix A. Scope and each
   Limitation use reading blocks. The complete About heading row is the direct
   **Edit Properties** button; the values and reading blocks remain static and
   selectable rather than becoming button content. There is no bottom Edit
   row and About has no Customize route. A current Analysis with a valid
   protected Zotero item key appends one quiet full-row **Open in Zotero**
   action inside About; it exposes neither the key nor fetched metadata and is
   absent for every other target. There is no Research Status, Key Properties,
   Provenance, Derived State, or separate Zotero section.

Freshness appears only as a compact actionable line when Refresh is pending,
stale, failed, or unavailable. It preserves last-known-good projections and
offers Retry where applicable; it never claims reading, truth, or evidence.
In Overview it follows the About projection and its Edit Properties route; it
is not promoted to a separate section or card.

Connect begins with three expanded, independently collapsible groups:

| Target | Groups |
| --- | --- |
| Analysis | Neighbor Analyses, Related Topics, Related Works |
| Topic | Related Sources, Neighbor Topics, Related Works |
| Work | Related Sources, Related Topics, Neighbor Works |

Within a group, links form ordered relationship clusters: Supports, Supports
This Note, Opposes, Opposes This Note, Incompatible, then neutral Related.
Counts appear only on the three major group headings. A cluster shows one
direct monochrome SF Symbol at 14pt in a 24pt leading track with a 4pt gap to
the shared title axis; individual Note rows repeat neither symbol, relationship
label, nor count. Supports and Supports This Note use `plus.circle`; Opposes
and Opposes This Note use `minus.circle`; Incompatible uses `xmark.circle`;
neutral Related uses `link`. Text owns relationship direction and meaning, so
inverse forms reuse the same decorative symbol. These symbols share one
restrained semantic text color and never encode truth, force, or value by hue.
Titles wrap. Do not open a second panel merely to show a title. Preserve source
anchors. An empty group retains its heading and `0` without **None**. Connect
shows the same freshness state before its groups. Stale or failed state keeps
the last complete graph readable and offers a full-row Retry action.

Relation rows remain single full-row native buttons with a provisional 36pt
minimum rhythm, no default separators, and no trailing diagonal-open glyph.
Their concise pointer help and accessible name state the relationship from the
current Note's perspective. Primary activation opens the connected Note,
using the source line when that peer owns the relation occurrence. When the
distinct source-return route remains applicable, it stays available as an
explicitly named context and accessibility action without adding a second
detail panel. Each original group heading is a sticky section header inside
Connect's sole scroll owner. While one relationship cluster scrolls, its one
decorative glyph pins immediately below that heading, remains bounded by its
own cluster, and hands off to the next glyph. Neither heading nor glyph is
fixed to a window coordinate, copied into a second state owner, or exposed
twice accessibly.

Actions has no generic **Actions** section heading. The role-valid defaults in
Section 8.1 retain their canonical order while appearing in two quiet semantic
groups: **Research** contains Discuss and the applicable Analyze, Synthesize,
or Write Action; **Review** contains Critique where applicable and Check
Fidelity. There is no horizontal Research Activity HUD, completed chronology,
generic **Open Research Record** row, **Work with Agent** wrapper, or mode picker. The
Discuss Action itself reopens the current Note's resumable active Discussion
and automatically includes its existing line Comments. It has no second
active-Discussion row or parallel destination.

Researcher-enabled custom Actions follow under one **Researcher Skills** group
in the researcher-chosen order. Only Profiles with **Show in Actions** enabled
appear. This is an open ordered collection using the same generic row and
direct per-window Action route; adding a Skill never requires a new Inspector
component or case-specific visual branch. Availability fails closed while checking; an unavailable Action states
only its first executable repair. Settle remains a quiet direct current-note
action under one **Judgment** group, and Attention remains in Overview/Library
rather than becoming completed history.

Each Action is one native full-row button with a direct symbol, the shortest
accurate title, explanation only under §19.6, and only when useful a trailing
chevron or shortcut. Its modular sheet shows the necessary scholarly inputs
and app-owned authority or recovery facts without exposing assembled prompts,
package internals, or technical mode names. The active Action and its sheet
retain keyboard, menu, pointer, focus, cancellation, and VoiceOver parity.
All Action launchers use one shared visual row recipe with a **44pt** minimum
operation rhythm and no default row or group separator. Availability checking,
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
Cancel control replaces the ready-state chevron. It adds no ordinary second
line. Larger interface text or localization may grow the row rather than clip
its title, state, or cancellation route.

Functional text is never a generic blue link or a separate **Open** button.
Body and secondary colors, hover surface, focus ring, button semantics, and
the full hit region make interaction recognizable without depending on color,
hover, or pointer use.

All section headings across Overview, Connect, and Actions
use one Apparatus heading token. Its provisional starting point is 10pt system
semibold, 0.7pt tracking, and secondary text color. English localization
supplies uppercase strings; runtime code never forces case, so Chinese and
other languages retain natural writing.

Inspector layout uses purpose-named Apparatus metrics rather than leaf-view
literals. Its provisional native content inset is **28pt**. Short
facts form one section-level two-column grid with a shared, trailing-aligned
label column of at least **78pt**, a **14pt** column gap, one common leading
axis for values, and first-baseline alignment. The horizontal candidate keeps
at least **204pt** of content width; ordinary canonical labels therefore remain
horizontal in **300pt** and **278pt** Inspector scenarios after the content
insets. If available width, 200% readability, or localized labels cannot fit,
one container-level adaptation stacks the complete grid; individual rows never
switch independently. Empty values do not create rows. Scope, Research Scope,
Limitations, and other long researcher prose always use a reading block: label
on its own line and Alegreya content on the next line with a 12pt leading
indent. Labels, diagnostic/state names, and action names remain system sans semibold; field values,
explanations, and research prose use Alegreya; exact paths and revisions remain
monospaced. Counts use monospaced digits without changing the surrounding
face.

Provisional rhythm is a 28pt minimum scanning/action row, 12pt Alegreya with
approximately 17–18pt reading leading, 4pt label-to-copy gap, 8pt between
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

## 18.6 Canonical state and action meanings

| State | Meaning |
| --- | --- |
| **Edited** | Active buffer differs from committed source. |
| **Saving** | Revision-checked commit is running. |
| **Saved** | Authoritative source committed; derived consumers may still refresh. |
| **Save Failed** | Source did not commit; retain buffer and offer Retry/comparison. |
| **Conflict** | Expected revision differs from disk; retain buffer and compare before destructive reload. |
| **Refreshing** | Derived consumers are catching up to committed source. |
| **Derived State Stale** | A consumer represents an older committed revision. |
| **Fully Up to Date** | Source and named consumers share one committed revision. |

Conflict actions are **Compare Changes**, **Reload from Disk**, and **Keep
Editing**. Comparison shows exact editor/disk revisions and offers **Return to
Editing** or **Reload from Disk**. Each exact comparison row retains one logical
source line while soft-wrapping its visible text within the comparison width;
wrapping never mutates either revision or creates a source line. Checkpoint restore, editor Undo, and Research
Record are never interchangeable; editor `Command-Z` never means checkpoint
restoration.

Autosave, conflict, and checkpoint-result presentation belongs to Document,
never Actions or Research Inspector. Ordinary autosave creates no Save button
and no success toast. **Save Failed** appears there as a persistent
**Autosave Failed** bottom status toast that states the editor buffer remains
available; the existing Retry/comparison recovery routes remain Document-owned
and never become Research Actions. An unresolved **Conflict** uses the same
Document-owned position, states that autosave is paused because the file
changed outside Scholium, preserves the editor buffer, and exposes **Compare
Changes**. These failure toasts remain until the state changes or the
researcher chooses the applicable recovery path; they do not time out as if
the failure were resolved.

Checkpoint availability is not a document state, toast, or Action row; its
entry remains under File. A successful restore alone produces one transient
Document confirmation, **Checkpoint Restored**, and states that Scholium
created the Before Restore checkpoint. This completion feedback never implies
that editor Undo became checkpoint restoration.

Retained interrupted-save candidates share the existing native Recovery sheet
with durable file-operation recovery; they do not create a version browser,
Document mode, Research Action, or checkpoint manager. Each candidate row
states its current source relationship in text and symbol, exposes a selectable
read-only exact-source disclosure plus **Copy Candidate** and **Reveal Candidate
in Finder**, and enables **Restore Candidate…** only for an observed expected or
already-candidate revision. The confirmation states the editor-flush and final
revision check. A later mismatch fails as Conflict, keeps the candidate, and
updates the row on Refresh. Recovery errors remain visible without hiding valid
entries from the other recovery class.

Lifecycle and destructive actions use exactly **Set Aside**, **Move to Trash**,
**Put Back**, **Delete Permanently**, and **Cancel** when applicable. Put Back
remains the direct reversible exception and is never styled as destructive.

## 18.7 Simplified Chinese terminology and translation boundary

Translate researcher-facing language contextually, not by mechanical token
replacement. Stable identifiers, enum values, command IDs, paths, exact source,
researcher prose, and internal vocabulary remain unchanged. Skill names and
package-authored descriptions stay verbatim unless a later decision creates a
Scholium-owned translated field. Chinese prose uses full-width punctuation.

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
| Completion / Research Scope / Limitation | 完成度 / 研究范围 / 局限 |
| Checkpoint / Snapshot | 恢复点 / 快照 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| Comment / Discussion / Response | 评论 / 讨论 / 回应 |
| Research Record | 研究记录 |
| Set Aside / SET ASIDE | 搁置 |
| Trash / TRASH | 纸篓 |
| No Document Selected | 未选择文档 |
| Expand All Folders / Collapse All Folders | 展开所有文件夹 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |
| Put Back | 放回 |

The literal `Trash/` directory, paths, stable identifiers, enum/raw values,
and researcher-authored titles remain verbatim and are never translated.

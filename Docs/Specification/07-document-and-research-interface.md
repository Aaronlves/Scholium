# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7: Document,
Inspector, shared state presentation, and translation. Global design belongs
to [Scholium Design](../../Design.md).

## 18.4 Document modes, context, and Metadata

Review, Edit, and Source are modes over one Document, not tabs. Each live
Triptych workspace session owns one current mode, starting in Edit and retained
across its Note/tab changes. Activating a Note applies its role's mode; merely
browsing another Library role does not change the active Document mode. Mode state never becomes a Note, vault, or Markdown fact.

Review owns read selection; Edit owns formatting. Selection remains source-local without creating a separate annotation or
collaboration object.

Managed New Note opens Edit at the exact body start after durable commit.
Editor failure retains the Note and offers **Retry Edit** and **Source**. An
exact empty body has a distinct quiet state; malformed YAML, whitespace,
unavailable source, and render failure are not Empty.

Edit keeps text selection unobscured, without a floating formatting toolbar.
A nonempty body selection offers one compact native selection surface beside the
passage in Review, Edit and Source: Explain, Polish and More Actions. The native
More Actions menu contains Ask Agent and enabled custom operations. Freeform
instructions belong to the ordinary Chat composer; this surface has no duplicate
input field or horizontally expanding action pages. The existing native glass
container and standard AppKit controls remain the presentation foundation.
Peer action labels and symbols share the native primary text color; native
controls retain disabled and menu-selection treatment.
Native layout and menu presentation own alignment and transitions; no custom
refraction, control skin or independent animation engine is introduced. The
surface retains its selection anchor and never adds document padding. A result
opens in a bounded native popover under §8.7, without dimming content.
Selection changes, scrolling, Escape, composition, mode changes and document
departure dismiss the surface. Settings supplies the ordered custom operations
and visible validation. Ask Agent, its Research-menu action and shortcut retain the
draft-only handoff to Chat under §8.7. A source range that cannot be verified
remains unavailable.

Formatting and insertion remain available through native Format/Insert menus,
keyboard shortcuts, and exact Markdown input. These routes preserve the current
selection and share the existing source transaction and Undo behavior.

Document Find is one compact nonmodal floating panel at the document's logical
upper trailing corner. Native material, colors and control treatment follow
§19.1. There is no full-width band, backdrop dimming or blocked document input.
Opening, closing, and disclosure preserve prose geometry and scroll position; the panel
never adds document padding or reserves layout space. Find shows the query, match count,
Previous/Next, and Close; empty input has no no-match message. The native search-field
menu owns case and whole-word options, with active options also visible in quiet text.
Replace expands downward inside the same panel with aligned input fields; Find and
Replace opens it directly. Review has no replacement controls. Opening/closing uses a
short trailing-edge translation and fade, while replacement disclosure changes panel
height. Both remain reversible; Reduce Motion presents final states immediately.
Return/Shift-Return navigate matches through normal document scrolling. Escape or Close
returns native and embedded document focus without changing the current exact selection.
Clicking the document keeps Find open. Reopening Find focuses its query even when
already open. Drafts/options remain local to the retained document; narrow reflow
retains the native fields and never changes source. Query and replacement use native
field editors. Marked text remains local until committed; incoming results cannot
overwrite composition or consume its Return/Escape commands.

Caret suggestions use one bounded panel attached to the editor caret. Autosave
does not dismiss it; acceptance, explicit dismissal, loss of the editing context,
or completion-state invalidation does. Selection changes update the retained
list without reconstructing its container. Pointer movement and keyboard
navigation update the same current candidate, shown with native emphasized
selection; click or Return accepts it. There is no independent hovered choice. They keep
document focus, show only useful identity/path context, fit the viewport, and
never introduce another text owner. These editing auxiliaries follow the
input-method candidate-window pattern: native system text, colors, controls, selection,
and elevation above the document; they do not inherit the main Document palette. During composition, application suggestions
and previews yield to the input method immediately; candidate navigation and
acceptance resume only outside composition. §19 governs the material boundary.

Insert presents Footnote and Inline Footnote as neighboring commands. Their
default shortcuts are Option-Command-N and Option-Shift-Command-N respectively;
the existing Keyboard Shortcuts owner may replace or clear either binding.

Internal-link preview preserves each mode's interaction meaning. Review reveals
the cached destination on ordinary pointer hover or link focus. Edit follows the
macOS editing convention: holding Command while pointing at an inactive
projected link reveals the same cached destination, and Command-click opens it;
pressing Command after the pointer is already over the link works without
requiring pointer re-entry. The armed link gives visible pointer feedback.
Unmodified Edit interaction continues to place the caret and reveal exact
source. Preview never mutates source, moves selection, or takes editor focus.

Review and inactive Edit present an annotated Wikilink through one small
trailing superscript disclosure marker. Pointer hover or keyboard focus reveals
its source-owned Markdown in the same bounded anchored surface as a footnote
preview; primary activation keeps that surface open for reading. Escape,
outside activation, scrolling, resizing, source activation, or a document
change dismisses it. Annotation prose never enters document flow or changes
neighboring line geometry.

Review and inactive Edit present every named or inline footnote occurrence as
the same superscript ordinal. Pointer hover or keyboard focus reveals one
bounded rendered definition without adding prose to document flow. Review
activation navigates to the generated end note and its return route; Edit
activation reveals the exact source-owned definition or inline range in the
same Editor state.

All modes use one adaptive editorial grid and one Appearance **Line width**
value. Review/Edit use scholarly type; Source uses exact-source type. The
measure remains centered with readable logical insets and adapts at narrow
widths and enlarged text. Source soft-wraps visual rows without changing
logical lines. Layout changes reconfigure the retained editor rather than
replace its buffer, selection, Undo, composition, scroll, or focus.

Beta/1.0 interactive writing supports English, Simplified Chinese, and mixed
content. Every Unicode byte remains preserved and Source-visible. Code,
mathematics, and inert raw HTML are isolated technical regions. Complete RTL
chrome/input behavior remains deferred under §17, but all Scholium-owned layout
uses logical start/end edges.

Document Appearance is machine-local. It manages named configurations for line
width, Body, headings, semantic Callouts, and Exact-source face and size while
preserving protected structure and accessibility. Body and heading roles each
have independent optional Bold and Italic font choices. The Settings surface
uses only these general role labels; it does not ask the researcher to manage
language-specific variants. By default, Latin glyphs use the selected role's
native weight/style variants, the built-in mixed-script body face is FangSong,
and the built-in italic face is KaiTi. An explicit researcher choice remains
authoritative until it is changed or reset. The researcher may choose any
installed Exact-source font; Scholium does not audit the choice. The shipped
default is monospaced. Changing presentation never changes source bytes or
logical lines. Native app chrome is not themeable. Advanced CSS is additive and
optional.

Appearance exposes one settings pane for body font/size, line width/spacing,
Source font/size, alignment, paragraph spacing, first-line indentation,
body/heading Bold and Italic fonts, heading type, and heading-level values
against the same appearance draft. Body and heading controls remain grouped as
named sections in one scrollable page, with aligned property matrices that
collapse before the form becomes cramped. Bold and Italic choices are
independent for Body and Headings and remain stable when the base role font
changes. Heading hierarchy settings address H1 through H6 independently; the
main page shows their compact scale and alignment summary, while a native child
sheet reveals each level's spacing controls on demand.
Low-frequency letter spacing, word spacing, hyphenation, kerning, and ligatures
are not structured appearance fields or native controls. Advanced CSS is their
single explicit configuration surface and is applied after generated appearance
CSS in both Review and Edit. Frontmatter remains at its authored beginning in
the source, while the shared scrolling document plane projects the app-owned
filename title first, then the quiet source-located YAML, then the authored
body (including its first H1). Review and Edit use the same YAML presentation;
Source retains the exact text. It is never replaced by a field editor or
reordered in the source, and no disclosure or timed collapse exists. Outside
an active YAML selection, its fence lines are visually suppressed; entering or
selecting YAML restores the exact delimiters at their source locations.
Opening and switching use the ordinary document scroll position or an explicit
retained/locator target; saving does not reset the viewport. Document switching
presents only the requested mode after readiness, without showing a temporary
layout from another mode.
A View-menu action may navigate to Frontmatter without creating an empty
envelope or changing its document order.
Source always displays the full original text. The documented `appearances.json`
file owns the structured appearance profile; the separately managed Advanced
CSS snippets own fine typography and other ordinary-content overrides. The
native Appearance settings pane edits structured body typography and headings
without creating a second appearance owner; Callout geometry remains
file-managed. Finder, configuration guidance, explicit Reload, and Restore
Defaults remain available. An external edit prevents stale GUI overwrite;
invalid reload preserves the loaded appearance and draft and identifies the
invalid field. Saving the profile does not rewrite or reset CSS snippets. CSS
snippets remain separately managed under §18.4.1.

The app-owned filename title is the primary document title. Review and Edit
place it at the top of the shared document plane, inside the document's
scrolling reading and writing context but outside authoritative Markdown.
Review presents it as a read-only identity projection. Edit presents the same
title as a borderless inline filename control: Return or leaving the field
requests the existing revision-aware Rename file operation, while Escape
cancels. Its visible trailing space belongs to the control and focuses it when
clicked; it is never an unresponsive surface. A rejected rename preserves the
draft and explains the failure beside the title. Native window title continues
to identify the window without becoming the visual title. Authored Markdown
headings belong to the body: H1 through H6 are presented as six relative
semantic levels beneath the Note title, with H1 remaining the first-level
section and lower levels becoming progressively quieter. Review and Edit
preserve those relative visual and accessible levels; Source exposes only the
exact authored hierarchy and no projected title.

The Note's document attachments belong to Overview, below metadata and the
separate Zotero relation. The filename precedes one large preview using the
available width and the document's aspect ratio. Multiple attachments expose a
separate compact position/selection menu; the filename and thumbnail always
open Quick Look regardless of attachment count. Count appears once, and a single
file omits the selection menu. Complete names and unavailable
states remain inspectable. Activating an attachment first opens a temporary
system Quick Look window with its standard toolbar, opening actions, and
Escape/close behavior. The system offers the associated application (normally
Preview for PDFs and images); Scholium does not replace this window, add its own
opening toolbar, or override file associations. Overview and File retain **Attach a
Copy…** and **Reference Original…** for this Note. Scholium has no global
attachment manager or persistent attachment reader. No attachment
strip or timed Add control appears in Review, Edit, or Source.

Ordinary Edit entry restores retained, fingerprint-valid title/body focus and
selection when available. Otherwise it uses an exactly mapped Review selection,
or places a collapsed insertion point at the first authored body position after
YAML. Direct title activation and Rename remain explicit title-focus routes.
An explicit source locator and Managed New Note's body-start insertion take
precedence. Window restoration retains this state only for still-open tabs;
closing a tab ends it, without permanent vault-wide cursor history.

Quick Look and external opening preserve the initiating Note, mode, source selection,
and attachment selection. Preparation failure retains an actionable error in Overview;
returning from the external application reveals the same Document. Inline thumbnail
loading never takes editor focus or recreates the reader/editor.

Edit treats all visible document rhythm as addressable. Clicking an authored
heading's visual padding places the caret in that heading; clicking a visible
Markdown blank line places it on that exact source line; and source-less
spacing between projected objects resolves to the nearest explicit source
boundary. Typography cannot create a region that merely ignores editing input.
Review and inactive Edit retain the same recognizable manuscript hierarchy,
measure, wrapping intent, and visible semantic-block order. Editing may create
bounded geometric differences needed for caret placement, marked text, exact
spaces, blank source rows, and active syntax. Every authored blank line remains
addressable and cannot collapse, overlap adjacent content, or jump when its
first visible character is entered.

Recognized Markdown syntax remains visible while a caret is inside its editable
construct or immediately at either boundary; moving outside hides it. A range selection
reveals constructs it actually overlaps. Revealed delimiters use readable secondary text
while authored content keeps its semantic styling; Increase Contrast may strengthen the
syntax ink. Unrecognized or incomplete inline punctuation remains ordinary source,
without inferred styling.

A valid heading keeps its semantic size while typing and when the caret leaves
or re-enters it. Editing its prefix immediately updates the level or returns
it to prose; while editing, an empty ATX heading keeps a visible marker line.
An inactive heading or quotation may de-emphasize its structural prefix.
Entering it reveals the exact prefix at the same source location without moving
the researcher to another block or losing selection, composition, or scroll
context. The product contract does not prescribe a particular prefix track,
line-box recipe, or pixel-identical Review/Edit geometry. Preserved spaces keep
their exact width without acquiring visible whitespace markers in ordinary
Edit prose. Ordinary prose follows language-aware line-breaking rules, and
closing punctuation is not left alone at a visual-line start merely because it
follows an interactive inline projection.

Review and Edit Callouts share role-specific title colors, typography, quiet surfaces,
and a single-column header/body order. Examples do not acquire a Review-only
column layout, and quotation titles retain their authored position above the
passage. Untitled Callouts share a default role title while inactive; activating
the Edit header replaces that projection with exact source. Active syntax and
addressable source rows remain the bounded editing exceptions described above.

Edit Callouts retain their exact authored markers when active, but do not repeat
generated role names such as `Caution`, `Statement`, or `Quotation` as visible
prose beside the authored title. Semantic title colors and typography distinguish research roles without
using warning or success meanings. Orientation, literature and connection
body prose uses accessible secondary text; claims, examples, quotations and
qualifications retain primary reading ink. Callouts do not accumulate
decorative rules or full frames. Open indents distinguish orientation and
connections; literature uses compact grouping; statements gain typographic
weight; examples use an inset; quotations retain italic prose and a quiet
attribution; qualifications use restrained grouping. Color is supplementary.
The role name remains available to assistive
technology, and Source always exposes the complete authored text.

Outline and document statistics currently have no interface entry, including
Inspector, toolbar, menus and popovers.
Toolbar placement and available commands belong to §18.2. Document Text Size
is per-window and source-neutral.

About edits Metadata directly through a quiet, ordered list without category
headings, an alternate editor, or Save/Cancel controls. Labels align to one trailing edge, values to one leading edge. The label column
adapts to localized labels and available width; long labels wrap, preserving
space for values. Configured empty fields remain visible with meaningful hints.
Editable text fields have no permanent filled bezel; their values remain the
visual subject. Direct editing retains native input, selection and focus treatment
without replacing controls. Read-only values remain selectable text. Short fields stay on one row; longer text grows within its value column.
Choices use native pop-up controls and Boolean values use native checkboxes;
hover, selection and disabled appearance remain system-owned.

Native controls remain mounted during editing. Tab and Shift-Tab use the native
key loop across text, choices, creator/list actions and the next field; rapid
input cannot wait for a declarative render or a save to move focus. Leaving a
field submits its captured draft. Return finishes short input; multiline input
uses Command-Return. Escape cancels uncommitted input. Native text Undo remains
available while typing, and committed Metadata changes have revision-checked
Undo/Redo. No success toast or confirmation button is added.

Creators use compact ordered name rows with one label for the collection,
a visible Add Author/Creator action after its rows, and persistent per-row
options for removal and ordering. A name can use family/given fields or one literal field; conversion is
explicit and never guesses how to split a name. Options expose secondary name
parts and keyboard-accessible ordering. Empty placeholders create no value;
incomplete nonempty names retain their draft and explain the error. Contributor
identity and position are included in accessible names.

Settings owns field definitions, visibility, and order. About exposes no Add Field or
per-row Remove Field command. Configured empty fields remain editable; present archived
or unsupported values remain visible, with unsupported shapes read-only rather than
reconstructed. §18.5 owns the separate Zotero, attachment and collapsed File Information
positions; they do not become editable Metadata fields.

One Note-local session serializes exact Metadata revision commits. Acknowledged
writes advance only that session's revision and never replace newer typing.
Marked text remains owned by AppKit, retains its candidate commands, and blocks
departure that would discard it. Note/workspace/window departure drains pending
Metadata; a failure retains the Note, draft and recovery. Inspector projection
changes preserve the same session. Persistent field errors identify the affected
field and expose Retry or explicit Reload Metadata through its options; reload
replaces the local Metadata drafts with the current authoritative record. YAML
has no About edit route.

Short syntax markers may borrow available outer whitespace if revealing them
would otherwise wrap the prose. The placement stays stable during activation;
long technical destinations wrap locally. Reveal never clips source, overlaps
navigation or introduces page-level horizontal scrolling. Input, selection,
composition and source updates never wait for a transition.

### 18.4.1 Advanced CSS boundary

Advanced CSS is an explicit, machine-local folder surface at the app-owned
Styles/Snippets location. Settings provides **Open CSS Folder**, **Reload**, and
import as equivalent entry points. Direct `.css` files are discovered into the
snippet list; the folder owns their bytes, while the adjacent manifest retains
only snippet identity, display name, order, and enablement. A newly discovered
file is enabled by default. An external edit is re-read and projected without
rewriting the file; a missing or invalid file remains visible with an actionable
error until it is repaired or explicitly removed.

CSS applies only to document content in Review/Edit, after generated appearance
CSS, and never to Source, app chrome, or research source. It is scoped to
ordinary prose, headings, lists, quotations, tables, code, links, emphasis,
marks, rules, and the public Callout selectors `.callout`, `.callout-title`,
`.callout-body`, `.callout-content`, and `.callout-<role>`. These Callout names
are a stable user-facing API projected to the protected Review and Edit
representations; internal WebKit or CodeMirror selectors are not accepted.

Sanitization rejects imports, executable content, external URLs, escaping
selectors, `!important`, and declarations that hide, reposition, or cover
protected information. Callout semantics, folding, footnotes, provenance,
diagnostics, conflicts, recovery, and chrome remain app-owned. Invalid snippets
stay disabled with errors. Rendering failure enters persistent CSS Safe Mode
until the researcher disables or selectively re-enables managed copies.

## 18.5 Contextual research and Agent Changes

Apparatus contains one trailing Inspector with **About**, **Links**, and **Related Material**.
Research questions and continuing discussion are ordinary Works Notes (§4 and
§8.6), read and edited in the main Document. They have no dedicated Inspector,
window, search category, or management commands.

**Agent Changes** opens on explicit request and lists the most recent operation
per Note, independent of Notifications dismissal. Older receipts remain retained
and individually addressable. Chat's Conversation Changes opens the same interface
scoped to all retained receipt IDs from that conversation, including earlier
changes to the same Note. Runtime-only reports never fabricate exact receipts. Its collection
and exact comparison remain native software-operation views throughout. The
collection fits short lists and uses bounded scrolling for longer histories;
it does not reserve the comparison canvas. Shared logical insets align title,
rows and actions. Each row leads with Note identity, then concise operation,
time and viewed state, with one explicit comparison action. The comparison
uses a larger reading area, a Note-first summary and a separate stable footer
for navigation, viewed marking and eligible Undo. Empty and unavailable states
retain the same compact collection frame; no decorative empty canvas is added. It is
not a fourth Document mode, durable review state, or
research history. An Agent Change notification opens one exact
`(change_id, Note ID)` result. An updated Note shows only the exact preimage and
confirmed readback revision. A created Note shows **Created by External Agent**
and current content without a fabricated empty baseline. A system-Trash change
shows the original Note identity and location plus the Finder-owned recovery
boundary; it is not rendered as an editable deletion diff.

Several Agent Changes never become one cumulative diff. The current collection uses
exact position and **Previous**/**Next** routes. A direct receipt link opens only that
change, without unrelated history navigation. The compact header names Note, operation,
time, and current-revision state; `change_id`, complete path, and exact fingerprints use
progressive detail. Ordinary Review continues to show the current complete Note. If
current saved source differs from the ending fingerprint, comparison is **Earlier
Revision** and is never overlaid on current prose.

Closing returns to the originating context, records no viewed/unread progress,
and never changes Settlement. Direct Undo remains per eligible update and uses
§8.4's revision requirement; creation and system Trash have no fabricated
source preimage or Undo.

An icon-only native single-choice group in the Inspector's toolbar selects
About, Links, or Related Material; each icon retains its complete Help and accessibility
name. These panes share content-edge insets and top spacing, use system semantic
control colors, and leave selection and interaction feedback to native controls.
Pane content never repeats that selector. Each
workspace retains its selection across Note and tab changes. Hiding Inspector
moves no content elsewhere. Without a Document it presents No Document Selected.

Related Material starts from an explicit selection in Edit or Source, including
unsaved writing. Find from Selection and its Research-menu route capture one fixed
passage; moving the caret or opening a source does not replace it. A new request
replaces that context; cancellation and Triptych departure prevent late publication.
The pane uses §13's local paragraph retrieval over Analyses and Topics. Each quiet
card leads with a readable paragraph, followed by its Note identity, role and actual
wording-match reason. A Note may contribute several distinct paragraphs; metadata,
a title or another paragraph matching cannot substitute for a matching paragraph.
Raw Markdown, full paths and internal offsets are not standing card content.
Matches are discovery leads, never support, objection, or correctness verdicts.
Open Source locates the checked paragraph revision. Add to Chat stages the captured
writing passage and that paragraph, retaining each identity, revision and locator,
without sending or replacing the draft. Chat owns provider selection and transport;
this handoff has no provider-specific configuration. Context attachments appear as
compact material cards; activation reveals a read-only excerpt preview and source
opening, while removal remains visible and keyboard-accessible. Preview uses readable
text, while handoff preserves exact source. An earlier snapshot can open its current
Note but never claims that an old offset still locates the same passage.
Changed or unavailable sources cannot be passed as current excerpts. Empty,
loading, cancelled, unavailable and omitted-source states retain their distinct
meaning and an explicit retry route. Results and selection are disposable window
state, with no new index, research record, or automatically inserted citation syntax.

About contains, in order:

1. a conditional current-Note notification summary and route into its existing
   Notifications queue. It includes Agent Changes, Settlement reminders, and
   visible diagnostics, independently of the popover's previous filters.
   Ordinary Agent Change history uses a quiet Note Notifications label and
   total item count, without implying unread or required action. Current issues
   and Settlement reminders show their actual description;
   no notifications occupy no space. Opening the summary shows all categories
   for that Note; it never acknowledges, dismisses, or accepts them;
2. ordered, ungrouped metadata with configured core fields even when empty,
   every other present managed value, and direct editing. Prefer title, authors,
   publication date, publication, then type and other bibliographic details.
   Labels and values share type size and baseline; secondary, right-aligned
   labels and primary, left-aligned values establish the two columns. Long
   titles wrap without becoming display headings. Creators retain fixed
   Last Name then First Name columns in both resting and editing states;
   leaving a field never joins, reverses, or replaces them with a display name.
   Literal names occupy one field only after an explicit name-mode choice.
   Empty names retain field placeholders. Native Tab moves through the retained
   controls; focus departure commits without moving their positions. Validation
   errors and composition retain the fields and draft;
3. an applicable Zotero relation/action row separated from metadata by spacing
   and a divider, with a quiet native Link Item/options control; no duplicated
   Zotero metadata form;
4. document attachments with a large preview and explicit external opening; and
5. collapsed File Information, with read-only Created/Modified dates and
   exact-revision Settlement facts using the same field/value typography.
   Changed-revision reminders remain visible through Notifications and the
   existing Settlement command even while this section is collapsed.

It has no generic Research Status, Provenance, or Derived State section.
Freshness appears only when pending, stale, failed, or unavailable and retains
last trustworthy content plus Retry. Native editing feedback, keyboard input,
Undo and recovery remain intact; no field-removal or confirmation buttons are
introduced.

Links contains one native capsule Incoming/Outgoing segmented choice and a local search
field. The system owns selector artwork and feedback. Search scope and options live in
the search-field magnifying-glass menu, with no separate filter row. Direction,
grouping, and distinct activation targets carry the interaction; no standing explanatory
caption repeats the controls. Each direction groups authored occurrences by linked Note
identity, with a Note title and occurrence count. Incoming expands to passages in that
source Note; Outgoing expands to passages in the current Note that link to the named
destination. The entire group heading, including its Note title and disclosure arrow,
expands or collapses the passages without navigating. Its contextual Open Linked Note
action opens the peer when needed. Links passages have a quiet hover affordance and
retain keyboard activation, but no persistent selected, checked, visited or clicked
appearance. Passage activation locates its original source in the current Document mode.
Once the target has been revealed, the Document briefly highlights the corresponding
visible line in Review or source line in Edit/Source, then returns to ordinary reading;
it does not wash an entire long paragraph or enclosing section with color. The marker
fades in briefly, holds, then fades out without moving or scaling the text. Reduce
Motion keeps the same brief marker static. Repeated activation locates and briefly
highlights the target again. Only one arrival highlight appears in a Document at a time;
another navigation replaces it, and passive refresh never replays it. It is a transient
presentation, not a source edit or a substitute for the researcher's text selection. If
the target cannot be resolved, use the existing unavailable/recovery path rather than
highlighting an unrelated paragraph or claiming arrival. No toast or explanatory success
caption accompanies the jump. Readable context precedes its secondary source line; the
existing dialect parser projects link labels without exposing link syntax or changing
source anchors. Explicit outgoing fragments retain Open Linked Passage in the secondary
menu. Repeated links remain separate occurrences. No inferred relation, predicate, or
Combined direction is introduced. Each row retains its exact source anchor, complete
local context, and optional annotation; repeated links remain repeated occurrences.
Outgoing annotation editing changes only the current source Note. Incoming annotations
are read-only and expose a separately named **Edit at Source** route that navigates to
the source occurrence. Row titles, annotation text, and context wrap and use full-row
native destination activation. Ordinary incoming, outgoing, and in-document link
navigation retains the current Document mode and reveals the corresponding rendered
paragraph in Review or exact line in Edit/Source. Outgoing fragment links use the
resolved destination anchor. Each Note and direction retains its query, group
disclosure, and reading position in window-local state. Returning restores that context
without creating another graph or source owner.

Document owns one **Settlement** command with a default native toolbar item and
complete Research-menu route. It is presented as a research milestone, not task
completion. Unsettled, Settled, and Changed Since Settle have distinct wording,
symbol shape, Help, and state-bearing accessibility value. Toolbar rendering
uses native state feedback without a feature-owned tint or animation;
Changed Since Settle does not imply failure.

Activating Settle or Settle Again opens one compact popover with optional
rationale rather than changing the judgment directly. Successful exact-revision
Settlement updates the control and Inspector facts without a parallel overlay,
Agent launcher or Skill button. Agent setup and conversation behavior
belong to §§8.2 and 8.7.

External-host MCP retrieval creates no persistent activity UI. Confirmed
mutations add their Agent Change to Notifications without activating the App
or moving focus. External hosts add no App approval sheet; in-app Chat activity
and permission follow §8.7. Dismissal hides the notification
but does not delete exact recovery evidence or imply reading, acceptance,
adoption, Undo, or Settlement. The Inspector, Document mode, projection
refresh, and pane visibility never replace the retained editor host or state.

## 18.6 Document-owned state and action meanings

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

Every state retains its feature owner and visible context. Accessibility,
announcement and persistent-repair requirements are owned by §20.

Settle and Dismiss retain their workflow meanings. Page and pane states may use
a shared Content State presentation; field validation, compact rows, operation
feedback, and recovery notices keep purpose-owned presentations while reusing
this vocabulary.

These Document states retain their source-specific meanings:

| State | Meaning |
| --- | --- |
| **Edited** | Buffer differs from committed source. |
| **Saving** | Revision-checked commit is running. |
| **Saved** | Canonical Markdown readback exactly matches the validated candidate. |
| **Autosave Failed** | Commit cannot be proven; retain buffer and recovery. |
| **Conflict** | Expected revision differs from disk; retain buffer and compare. |
| **Refreshing** | Derived consumers are catching up to committed source. |
| **Derived State Stale** | A consumer reflects an older committed revision. |
| **Fully Up to Date** | Source and named consumers share one committed revision. |

Conflict offers **Compare Changes**, **Reload from Disk**, and **Keep Editing**.
Comparison shows exact soft-wrapped source lines without altering either
revision and returns to Editing or explicit Reload. Editor Undo affects only
the live editor; Agent direct Undo follows the selected Agent Change's
fingerprint-bound recovery contract.

§14 owns save outcomes and interrupted-save recovery. Failed saves and conflicts
remain persistent above Document content with the applicable repair.

Recovery candidates use one native Recovery surface with exact source,
relationship to canonical source, Copy, Reveal, and Restore only when the
recorded revision permits it. System-Trash recovery is visibly distinct and
offers only safe forward cleanup or **Resolve** after an unknown native
outcome. Research discussion in Works follows the same Note Trash contract.

## 18.7 Simplified Chinese terminology and translation boundary

Beta/1.0 localizes researcher-facing interface text in English and Simplified
Chinese. Translate contextually; stable identifiers, enum values, command IDs,
paths, source, researcher prose, and Skill names remain verbatim.

| English | Approved Simplified Chinese |
| --- | --- |
| Scholium | Scholium |
| Triptych | 脉络 |
| Vault | 研究库 |
| Library | 研究文档 |
| Analyses / Topics / Works | 分析 / 议题 / 写作 |
| Agents & Chat / Agent Changes | 智能体与聊天 / Agent 修改 |
| Research / Review / Judgment | 研究 / 审查 / 判断 |
| Settle / Settled | 暂定 / 已暂定 |
| Attention / Connect | 关注 / 连接 |
| Incoming Links / Outgoing Links | 传入连接 / 传出连接 |
| Annotated Wikilink / Link Annotation | 带注释双链 / 链接注释 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| No Document Selected | 未选择文档 |
| Expand / Collapse All Folders | 展开 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

Chinese uses full-width punctuation. System-owned Finder names, exact paths,
stable identifiers, raw values, and researcher-authored titles are never
translated.

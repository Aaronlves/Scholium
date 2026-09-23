# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7: Document,
Inspector, shared state presentation, and translation. Global design belongs
to [Scholium Design](../../Design.md).

## 18.4 Document modes, context, and source properties

Read and Edit are modes over one Document, not tabs. Each live
Triptych workspace session owns one current mode, starting in Edit and retained
across its Note/tab changes. Activating a Note applies its role's mode; merely
browsing another Library role does not change the active Document mode. Mode state never becomes a Note, vault, or Markdown fact.

Read owns read selection; Edit owns formatting. Selection remains source-local without creating a separate annotation or
collaboration object.

Managed New Note opens Edit at the exact body start after durable commit.
Editor failure retains the Note and its recoverable exact source and offers **Retry Edit**. An
exact empty body has a distinct quiet state; malformed YAML, whitespace,
unavailable source, and render failure are not Empty.

The system toolbar keeps scrolling Document text out of its controls; initial
content remains unobscured. System background, selection, focus, Undo,
composition and restoration remain unchanged.

Edit keeps text selection unobscured, without a floating formatting toolbar.
A nonempty body selection offers Explain, Polish and More Actions in
Read and Edit. More Actions contains Ask Agent and enabled custom
operations; instructions stay in Chat. Native controls own layout, transitions,
hover, pressed, disabled, focus and menu feedback. Peer labels use primary text;
hover uses system Accent with minimal gaps. No custom skin or animation engine.
Explain and Polish replace the toolbar with one bounded native popover anchored
to the passage, preferably below. Progress, Stop, completed content and errors
share it. Replace Selection stays trailing; Regenerate becomes Stop.
Copy, Chat handoff and version navigation remain. Results scroll.
Custom operations dismiss the toolbar and open Chat under §8.7. No document
padding, dimming or stacked toolbar is added. Selection changes, scrolling,
Escape, composition, mode changes and departure dismiss presentation; native
focus restoration preserves the passage. Settings owns custom operations.
Ask Agent's menu and shortcut share §8.7's draft-only handoff. Unverifiable
source ranges remain unavailable.

Body context menus and Research commands expose §5.4. Body mutations require
verified source and Edit. Reorganization sheets use native search and a striped
Name/Folder table sharing its visible width, then exact preview in the same resizable sheet, with Change,
Cancel and operation-specific confirmation. Merge property conflicts show both
authored entries and a named, initially unselected source/destination choice for
each key. All choices precede the exact preview; changing destination clears them.

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
Replace opens it directly. Read has no replacement controls. Opening/closing uses a
short trailing-edge translation and fade, while replacement disclosure changes panel
height. Both remain reversible; Reduce Motion presents final states immediately.
Return/Shift-Return navigate matches through normal document scrolling. Escape or Close
returns native and embedded document focus without changing the current exact selection.
Clicking the document keeps Find open. Reopening Find focuses its query even when
already open. Drafts/options remain local to the retained document; narrow reflow
retains the native fields and never changes source. Query and replacement use native
field editors. Marked text remains local until committed; incoming results cannot
overwrite composition or consume its Return/Escape commands.

After `/` in a supported Edit context, insertion commands filter as text is
typed. Acceptance replaces the slash and query in one Undo transaction;
Escape preserves the text. Deletion remains ordinary editor input.

Slash commands, Wikilink, analysis-reference and Callout candidates retain one bounded native
list beside the caret, keeping editor focus. Filtering updates the retained
list with stable width and opening direction; overflow scrolls. Autosave does
not dismiss it; acceptance, dismissal or invalidated editing context does.
Pointer and keyboard update one native secondary selection; click or Return
accepts. Useful identity/path context fits the viewport without another text
owner. All editing auxiliaries use system text, colors, controls and elevation
under §19. During composition, menus, candidates and previews yield immediately
to the input method; application navigation and acceptance resume afterward.

Edit has an inline preview with dotted underline and ⇥, never a panel.
Local completion offers authored alias/keyword suffixes, excluding complete terms
and undeclared titles. AI continuation defaults off. Writing Assistance selects
one runtime-inventory model shared by continuation, Explain and Polish, independent
of Chat, with low-cost default and low-or-lower supported effort.
Unavailable choices never silently switch. Enabling permits bounded writing/retrieved
context to reach the runtime; remote processing and usage are disclosed.
After a pause, AI is eligible at a focused caret in an unfinished sentence.
Completed/protected/structural contexts suppress AI; local completion remains. AI uses
current-sentence context; suffix cannot cross a sentence/paragraph. An admitted request
shows phases at the caret; Reduce Motion freezes it. Off stays quiet.
Connection/model/runtime failures and timeout show a reason;
cancellation/stale work stay quiet. Waiting shows no preview; late AI ignored.
Tab appends in one Undo; Return remains newline. Escape dismisses without fallback;
preview is not source. Typing/caret/focus/composition/configuration changes cancel
requests/previews. Literal/code/frontmatter/multiple selections suppress both. Statuses
never enter source/history. System spelling/grammar remains
separate from prediction.

**Find Writing References…** in Insert (default Shift-Command-J, configurable)
shares selection recommendations' pane/session. It captures selections,
otherwise the current logical source line, independent of soft wrapping. Blank
lines never borrow preceding prose. Silent Note preparation works with the pane
closed, changing no results, focus or errors. Source/index changes invalidate it;
composition, departure and foreground retrieval cancel it. Retrieval never requires
preparation. The visible pane queries on opening, after a short selection debounce,
or after about 1.2 seconds without typing at an empty caret.
Resuming editing restores following even if the pointer was left in the pane.
A stale index is refreshed once before showing a recoverable retrieval error.
Composition, focus outside the editor and pointer interaction in the pane suspend
automatic replacement. Only failed/incomplete retrieval offers Retry. Unchanged
results retain card identities/order; a fresh caret receipt restores insertion.
Each Note offers up to two passages, navigation
and Note/paragraph link insertion. Unavailable insertion never hides
readable material. No excerpts or generated prose are inserted. Waiting shows
the actual shortcut or unbound command's menu path. Typing never opens the pane.
Same-Note writing or failed retrieval retains results/context; §18.5 owns departure.
Text/selection changes invalidate insertion; retrieval renews it without
confirmation or a standing refresh indicator.
Paragraph insertion is explicit: it validates the complete current ordinary
paragraph, creates an authored anchor only when needed, saves and rechecks that
source, then inserts its live link. It neither navigates away from the draft nor
reuses an old range after revision drift. If anchor saving succeeds but insertion
fails, report both outcomes without reverting a later source edit.
Insertion checks session identity, document generation, caret and composition
again in the editor and forms one Undo transaction. New results replace the old
cards and context together. Loading, empty, cancelled, failed and stale outcomes
remain distinct. No query history is stored.

Insert presents Footnote and Inline Footnote as neighboring commands. Their
default shortcuts are Option-Command-N and Option-Shift-Command-N respectively;
the existing Keyboard Shortcuts owner may replace or clear either binding.

Read reveals cached internal-link destinations on ordinary hover or link
focus. Edit requires Command over an inactive projected link, including Command
pressed after pointer entry; Command-click opens it. The armed link gives visible
pointer feedback. Unmodified Edit interaction places the caret and reveals exact
source.

Read and inactive Edit show annotated Wikilinks with a small trailing
superscript disclosure marker. Hover or keyboard focus reveals its source-owned
Markdown; primary activation keeps it open. Escape, outside activation,
document scrolling, resizing, source activation or document change dismisses it.
Annotation prose never enters document flow or changes neighboring line geometry.

Read and inactive Edit show named and inline footnote occurrences as
superscript ordinals. Hover or keyboard focus reveals the rendered definition
without reflow. Read activation navigates to the generated end note and its
return route; Edit activation reveals the exact source-owned definition or
inline range in the same Editor state.

Link, footnote and link-annotation previews share one bounded native popover,
measured at its available reading width before display. Repeated disclosure
preserves position and reading context; long content scrolls internally. Moving
the pointer from trigger into preview permits continued reading. Disclosure
never mutates source, moves selection or takes document focus.

Read/Edit share Appearance **Reading line width** on one native text surface.
Quiet, contrast-safe syntax colors distinguish active headings, YAML, links and
markers without a separate source view. Soft wraps distinguish continuation rows. Layout changes
retain buffer, selection, Undo, composition, scroll and focus.

Beta/1.0 interactive writing supports English, Simplified Chinese, and mixed
content. Every Unicode byte remains preserved and accessible through exact editing. Code,
mathematics, and inert raw HTML are isolated technical regions. Complete RTL
chrome/input behavior remains deferred under §17, but all Scholium-owned layout
uses logical start/end edges.

Document Appearance is machine-local, with named configurations for line width,
Body, headings, semantic Callouts and technical-source face and size. Body and
headings have independent optional Bold and Italic choices, labelled by role
without language-specific controls. Defaults use the selected Latin face's
native variants, FangSong for mixed-script body text and KaiTi for italics.
Researchers may choose any installed font family for Body, headings and
technical source. Unavailable families remain selected and saved while rendering
uses fallbacks. Explicit choices remain authoritative until changed or reset;
Scholium does not audit them. Technical source defaults to a monospaced font.
Presentation preserves protected structure, accessibility, source bytes and
logical lines. Appearance uses native settings; document Advanced CSS is not offered.
Native app chrome is not themeable.

Appearance exposes one settings pane for body font/size, line width/spacing,
hyphenation, technical-source font/size, alignment, paragraph spacing, first-line indentation,
body/heading Bold and Italic fonts, heading type, and heading-level values
against the same appearance draft. Body and heading controls remain grouped as
named sections in one scrollable page, with aligned property matrices that
collapse before the form becomes cramped. Bold and Italic choices are
independent for Body and Headings and remain stable when the base role font
changes. Heading hierarchy settings address H1 through H6 independently; the
main page shows each level's scale, alignment and before/after spacing in
the appearance draft, adapting to rows at narrow widths.
Hyphenation is a Never/Automatic reading setting for supported prose; Chinese
and technical regions remain unhyphenated.
The shared scrolling document plane shows quiet source-located YAML, then
authored body (including its first H1); frontmatter retains its authored source
position. The filename title belongs to the toolbar. Read and Edit share quiet
reading type and neutral ink for YAML; Edit retains direct access to exact text.
YAML is never replaced by a field editor or
reordered in the source, and no disclosure or timed collapse exists. Outside
an active YAML selection, its fence lines are visually suppressed; entering or
selecting YAML restores the exact delimiters at their source locations.
Opening and switching use the ordinary document scroll position or an explicit
retained/locator target; saving does not reset the viewport. Document switching
presents only the requested mode after readiness, without showing a temporary
layout from another mode.
A View-menu action may navigate to Frontmatter without creating an empty
envelope or changing its document order.
Edit retains complete authored text; explicit folds remain visibly and
accessibly reversible. The documented `appearances.json` file owns structured
profiles. Finder, guidance, Reload and Restore Defaults remain available.
External edits prevent stale overwrite; invalid reload preserves loaded
appearance and drafts and identifies the invalid field. Scoped repair preserves
other configuration. Whole-file recovery preserves previous bytes and creates
a default profile without modifying research source.

The toolbar's filename title identifies the current Note in Read and Edit.
Activating it by pointer or keyboard opens one native popover with a **Name**
field and the Note's existing location context. Confirming the name requests the
existing identity-checked rename operation; cancellation preserves the filename.
A rejected change retains the draft and explains the failure in the popover.
Rename remains available in either mode when file-operation admission permits;
Read keeps the document body read-only. Dismissal restores focus without
changing source selection or scroll. The title is not repeated in the document
plane or inserted into Markdown.
Authored H1 through H6 retain their six relative visual and accessible levels;
H1 is the first-level heading in the body. Filename changes do not alter authored
headings.

Document modes may show a Document Outline over the Document's
logical trailing edge, without changing prose geometry. H1-H2 ticks share a
trailing endpoint; H1 extends inward. H3-H6 are omitted.
Disjoint rows retain complete accessible labels. The vertically centered rail
shrinks for few headings or a short window. Overflow scrolls
independently; system-background fades appear only at edges with hidden ticks. The resting
rail has no filled track or persistent labels. Pointer proximity lengthens
nearby ticks with reversible falloff. The current section has a stronger stroke.

Pointer proximity or keyboard focus immediately reveals the authored title
inward from the marker in a compact, noninteractive floating preview. It uses small
system text and the shared native floating-surface material, with tight insets
and a small rounded-rectangle shape instead of an arrowed capsule. The system
owns its highlights, elevation and adaptation. Scanning updates title and
position without waiting. The preview never takes focus or intercepts input;
leaving the rail, Escape, activation, document departure or heading replacement
removes it. Complete heading labels remain available to accessibility.

Activation directly uses the current mode's revision-bound source-location route;
preview is optional. Neither creates history, edits source nor substitutes for
selection. Pointer activation has no rectangular plate; keyboard traversal
retains system focus. A system haptic acknowledges pointer press while contact
remains; crossing markers offers alignment feedback with jitter and rapid
sweeps suppressed. Haptics follow system preferences and never claim arrival.
Hover changes no selection; press feedback stays on the marker. Successful
navigation uses a short smooth reveal and the existing transient arrival marker.
Reduce Motion uses immediate positioning and static feedback. The rail hides
before it would compress or cover readable Document content.

Attachments remain file links or image embeds. Read and inactive Edit
add quiet file-type symbols beside authored link labels without changing source
or activation. File-menu insertion uses the editor selection; system Quick Look
owns file opening/dismissal. No attachment sidebar, global manager or persistent
reader is added.

Ordinary Edit entry restores retained, fingerprint-valid body focus and
selection when available. Otherwise it uses an exactly mapped Read selection,
or places a collapsed insertion point at the first authored body position after
YAML. The explicit title-focus route opens the toolbar's rename popover; mode
entry alone never opens it.
An explicit source locator and Managed New Note's body-start insertion take
precedence. Window restoration retains this state only for still-open tabs;
closing a tab ends it, without permanent vault-wide cursor history.

Quick Look and external opening preserve the initiating Note, mode, source selection,
and document context. Preparation failure reports an actionable document error;
returning from the external application reveals the same Document. Inline thumbnail
loading never takes editor focus or recreates the reader/editor.

Edit treats all visible document rhythm as addressable. Clicking an authored
heading's visual padding places the caret in that heading; clicking a visible
Markdown blank line places it on that exact source line; and source-less
spacing between projected objects resolves to the nearest explicit source
boundary. Typography cannot create a region that merely ignores editing input.
Read and inactive Edit retain the same recognizable manuscript hierarchy,
measure, wrapping intent, and visible semantic-block order. Editing may create
bounded geometric differences needed for caret placement, marked text, exact
spaces, blank source rows, and active syntax. Every authored blank line remains
addressable and cannot collapse, overlap adjacent content, or jump when its
first visible character is entered.

Recognized Markdown syntax remains visible while a caret is inside its editable
construct or immediately at either boundary; moving outside hides it. A range selection
reveals constructs it actually overlaps. Recognized active delimiters use an accessible system-Accent-derived syntax
color while authored content keeps its semantic styling. Short inline delimiters
and short heading/quotation prefixes expand and retract with restrained motion.
Callout markers, code fences, long destinations and technical source never
animate their width or indentation; they remain quiet or fade. Activation color
may transition briefly. Typing, composition, selection dragging and Reduce
Motion finish motion immediately; source, caret and Undo remain authoritative. Unrecognized or incomplete inline punctuation remains ordinary source,
without inferred styling.

A heading retains its semantic size through focus changes; editing its prefix
updates its level or returns it to prose. Empty active ATX headings retain a
visible marker. Activation reveals exact syntax in place, preserving selection,
composition and scroll. Preserved spaces retain their width without visible
markers; language-aware wrapping keeps closing punctuation off visual-line starts.

Completing an Edit pointer selection over a whole visible heading includes its
original structural markers; complete-line selections include the final authored
newline. Partial text and explicit exact-source ranges never expand. The actual
selection and revealed syntax agree before copy, cut or drag. Complete lines
containing a heading drop at line boundaries; partial text at a caret. Feedback
and insertion share one location. Moves preserve Markdown and line endings,
adding only necessary missing boundary separators, and undo once. Source changes
invalidate local drags. Selecting a heading never implicitly selects its section.

Read and Edit Callouts share role-specific title colors, typography, quiet surfaces,
and a single-column header/body order. Examples do not acquire a Read-only
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
technology, and Edit always retains access to the complete authored text.

The compact Document Outline rail is the only outline surface. Document
statistics have no interface entry in Inspector, toolbar, menus or popovers.
Toolbar placement and available commands belong to §18.2. Document Text Size
is per-window and source-neutral.

Properties remain in the document's source-located YAML. There is no About,
Overview, Metadata form, or dedicated attachment Inspector. Native controls,
quiet hierarchy and system semantic colors follow Design; reference images do
not prescribe copied card geometry or decorative glass.

### 18.4.1 Native appearance boundary

Document Appearance configures the native Read/Edit surface through structured,
machine-local settings. It changes typography and layout without changing source,
selection, composition, Undo or document identity. Application chrome and semantic
state remain system-owned. No document CSS folder, snippet import or executable
styling surface is exposed. Invalid appearance data retains the last valid
presentation and the existing scoped repair routes.

## 18.5 Contextual research and Agent Changes

Apparatus contains one trailing Inspector with **Links** and **Related Material**.
Research questions and continuing discussion are ordinary Works Notes (§4 and
§8.6), read and edited in the main Document. They have no dedicated Inspector,
window, search category, or management commands.

**Agent Changes** opens on explicit request and lists the most recent operation
per Note, independent of Notifications dismissal. Older receipts remain retained
and individually addressable. Chat's Conversation Changes opens this interface
scoped to all retained receipt IDs from that conversation, including earlier
changes to the same Note. Runtime-only reports never fabricate exact receipts. The collection uses a native striped single-selection table. Columns share the
visible width using native autoresizing: identity absorbs spare space and
secondary columns stay compact. Header dragging is disabled; long histories
scroll vertically. Shared insets align title, rows and actions.
Note identity leads, followed by operation, time and viewed state; one explicit
action opens comparison. A single system-owned resizable sheet retains its geometry across list,
comparison and dismissal. The Note-first comparison has a stable navigation/Undo
footer. Empty and unavailable states use the same shell. It is
not another Document mode, durable review state, or
research history. An Agent Change notification opens one exact
`(change_id, Note ID)` result. An updated Note shows only the exact preimage and
confirmed readback revision. A created Note shows **Created by External Agent**
and current content without a fabricated empty baseline. A system-Trash change
shows the original Note identity and location plus the Finder-owned recovery
boundary; it is not rendered as an editable deletion diff.

Several Agent Changes never become one cumulative diff. The current collection uses
exact position and **Previous**/**Next** routes. A direct receipt link opens only that
change, without unrelated history navigation. The compact header names Note, operation,
time, and current-revision state. Hide receipt IDs, hashes and encoding details; Help exposes full Note paths. Ordinary Read continues to show the current complete Note. If
current saved source differs from the ending fingerprint, comparison is **Earlier
Revision** and is never overlaid on current prose.

Displayed confirmed changes become Viewed automatically.
Selection/loading/failure never marks Viewed; no confirmation button remains.
Closing returns to the originating context without changing Settlement. Direct Undo remains per eligible update and uses
§8.4's revision requirement; creation and system Trash have no fabricated
source preimage or Undo.

An icon-only native single-choice group in the Inspector's toolbar selects
Links or Related Material; each icon retains its complete Help and accessibility
name. These panes share content-edge insets and top spacing, use system semantic
control colors, and leave selection and interaction feedback to native controls.
Pane content never repeats that selector. Each
workspace retains its selection across Note and tab changes. Hiding Inspector
moves no content elsewhere. Without a Document it presents No Document Selected.

Related Material follows selected or paused Edit text, including unsaved
writing. Opening, switching editors and selection changes schedule debounced
retrieval; composition suspends it. New selections invalidate older responses;
closing cancels pending work. The Research menu retains its keyboard route.
Pane focus preserves context until a successful query. Note departure, including
opening a recommendation, synchronously clears results, context and insertion;
departed requests cannot publish after returning. Results lead without a standing
context summary, refresh command or caret-confirmation step.
§13 retrieves Analyses, Topics and other Works as researcher writing. Results show
the Note title, verified match excerpt, quiet role identity, Link to This Note and
Add to Chat. Headers share Links' disclosure pattern: role symbol, title, adjacent
chevron and trailing actions. The chevron appears on hover or focus without
reflow. Help and accessible headers, passages and actions identify role and
relative path. Duplicate titles add quiet vault/directory context; unique titles
remain compact. Identity context never changes ranking. Headers toggle expansion
without navigation; their link action inserts the Note link. Groups start
expanded with at most two retrieved passages. A shared native passage-card
container owns insets, type alignment and grouping in both
panes. Each excerpt opens its checked paragraph; its chat action stages that
paragraph and the captured writing context without sending. No action generates
philosophical prose. Note order follows retrieval's Note ranking and passages
retain their within-Note ranking. Trailing native row swipe actions reveal Link to This Note on the group header
and Add to Chat on a paragraph. Full-swipe execution is disabled: reveal alone
never inserts, attaches or sends. Native List owns gesture direction arbitration,
closing, scrolling and action feedback. Only one reveal remains open; reverse
swipe, outside interaction or Escape closes it. A group action menu revealed by pointer hover, keyboard focus or accessibility focus
provides named keyboard and pointer alternatives, including selection of a
paragraph for Chat or Insert Paragraph Link. Paragraph choices use an ordinal plus at most eight source
characters and an ellipsis; the attached source remains complete. Context menus and accessibility actions remain additional
routes. Actions take no width from the resting excerpt. Both panes share native List rows, identity headers, passage containers and
secondary heading color. Their copy rail and spacing follow Library Sidebar
layout roles; Links controls use that rail, without extra outer horizontal padding.
The action menu uses the same image-only label and native control treatment as
the Library Sidebar, with a reserved target to prevent reflow. Analysis, Topic and Work use the existing three workspace role symbols. There is no refresh header; shortcut guidance appears only before the first usable query. Empty results show
one concise empty state without repeating writing instructions. Waiting, empty
and failed retrieval use the shared Sidebar state presentation. Loading alone
shows pulsing skeletons, including replacement searches. Existing rows retain their
geometry and reading position while masked as inactive placeholders. New Note groups enter
as one visual unit: the identity header and every excerpt share a single upward
translation and opacity sample. Groups start in reading order with overlapping,
brief ease-out entrances; no blur, scaling, bounce, clipping reveal or separate
highlight animation is added. Existing Notes keep their position and do not
replay when excerpts change, scrolling resumes or a group is reopened. Native
rows retain their independent actions and final grid. Reduce Motion presents the
completed state immediately, including when enabled during playback. Links uses
the same static header and highlight treatment without the search entrance. Failed or
incomplete retrieval retains existing cards and exposes one recovery state.
Guidance belongs in Help rather than a standing footer. Authored link annotations remain readable
in the excerpt when they supply the match; they retain their containing Note as
source. Excerpts open the checked source paragraph. Excerpts use a shared restrained highlight with Links: a faint system-accent
background and medium word weight. Related Material highlights at most three
distinct complete words covered by Search-owned readable-text matches, excluding
common words; it never highlights YAML-only matches or displays keyword capsules.
Links highlights the authored link alias or target when it has one unambiguous
occurrence in the readable context. Ambiguous labels remain unhighlighted.
Initial loading uses pulsing skeleton cards matching the title, role, excerpt and
action-area geometry of real results; Reduce Motion keeps them static. Subsequent
retrieval masks retained cards with the same pulse, without adding loading rows or layout animation.
Loading exposes one accessible search status and no actionable placeholder results.
Completion, cancellation or failure restores retained same-Note cards.
Brief opacity transitions accompany action disclosure only. Ellipses identify omitted text; there is no generated summary, standing
keyword list, full-paragraph expansion, or repeated Open Source button.
A contextual Retry action recovers from failure or unavailable sources. Normal automatic replacement does not add a stack of disabled actions.
Content YAML contributes to Note ordering but is not displayed as a separate
result. Each recommended Note presents an actual matching paragraph; metadata,
a title or another paragraph matching cannot substitute for that paragraph.
Opening preserves Document mode and follows the destination's recommendation lifecycle.
Cards omit raw Markdown, full paths and internal offsets. Matches are discovery
leads, never evidential verdicts; Help/accessibility explains connection paths.
Open Source checks the paragraph revision when
queued navigation executes. Changed sources open without old positioning and
explain the mismatch; unverifiable or unsaved sources receive a distinct
explanation. Add to Chat stages the captured
writing passage and that paragraph, retaining each identity, revision and locator,
without sending or replacing the draft. Chat owns provider selection and transport;
this handoff has no provider-specific configuration. Context attachments appear as
compact material cards; activation reveals a read-only excerpt preview and source
opening, while removal remains visible and keyboard-accessible. Preview uses readable
text, while handoff preserves exact source. An earlier snapshot can open its current
Note but never claims that an old offset still locates the same passage.
Changed or unavailable sources cannot be passed as current excerpts. Distinct
empty, loading, cancelled, unavailable and omitted-source states retain retry.
Results and selection are disposable window state, never a new index or research record.

External contains authored destinations outside all registered vaults, including
web, Zotero, other application URLs and outside-file references; internal Note and
attachment destinations remain internal. Classification does not authorize opening. Show authored labels; exact destinations belong in Help and Copy Link.
Opening follows ordinary external navigation; no incoming external graph is inferred.
Links uses a native capsule Incoming/Outgoing/External selector: every segment has
an icon, only the selected segment shows its name, and all retain full accessible
names and Help. A local search field matches names and destinations. The system
owns selector artwork and feedback. Search scope and options live in
the search-field magnifying-glass menu, with no separate filter row. Direction,
grouping, and distinct activation targets carry the interaction; no standing explanatory
caption repeats the controls. Incoming and Outgoing group authored occurrences by linked Note
identity, with a Note title and occurrence count. Incoming expands to passages in that
source Note; Outgoing expands to passages in the current Note that link to the named
destination. The entire group heading, including its Note title and disclosure arrow,
expands or collapses the passages without navigating. Its contextual Open Linked Note
action opens the peer when needed. Links passages have a quiet hover affordance and
retain keyboard activation, but no persistent selected, checked, visited or clicked
appearance. Passage activation locates its original source in the current Document mode.
Show meaningful passages and annotations, never source line numbers as visible fields.
Once the target has been revealed, the Document briefly highlights the corresponding
visible line in Read or source line in Edit, then returns to ordinary reading;
it does not wash an entire long paragraph or enclosing section with color. The marker
fades in briefly, holds, then fades out without moving or scaling the text. Reduce
Motion keeps the same brief marker static. Repeated activation locates and briefly
highlights the target again. Only one arrival highlight appears in a Document at a time;
another navigation replaces it, and passive refresh never replays it. It is a transient
presentation, not a source edit or a substitute for the researcher's text selection. If
the target cannot be resolved, use the existing unavailable/recovery path rather than
highlighting an unrelated paragraph or claiming arrival. No toast or explanatory success
caption accompanies the jump. The existing dialect parser projects link labels without exposing link syntax or changing
source anchors. Explicit outgoing fragments retain a direct Open Linked Passage action. Repeated links remain separate occurrences. No inferred relation, predicate, or
Combined direction is introduced. Each row retains its exact source anchor, complete
local context, and optional annotation; repeated links remain repeated occurrences.
Links has no annotation editing, creation, draft, or save controls. Passage and
annotation form one activation target that reveals the exact source occurrence.
Note group headings use a document symbol and stronger type. Each occurrence has
one native grouped card: the directly related passage uses regular primary text;
its annotation follows a separator with an inset comment symbol and secondary text.
The card forms one source-navigation button; hierarchy uses grouping, spacing and
type as well as color. Titles, passages and annotations wrap; line numbers stay internal.
Ordinary incoming, outgoing, and in-document link
navigation retains the current Document mode and reveals the corresponding rendered
paragraph in Read or exact line in Edit. Outgoing fragment links use the
resolved destination anchor. Each Note and direction retains its query, group
disclosure, and reading position in window-local state. Returning restores that context
without creating another graph or source owner.

Document owns one **Settlement** command with a default native toolbar item and
complete Research-menu route. It is presented as a research milestone, not task
completion. Unsettled, Settled, and Changed Since Settle have distinct wording,
symbol shape, Help, and state-bearing accessibility value. Toolbar rendering
uses `checkmark.circle`, `checkmark.circle.fill`, and
`checkmark.arrow.trianglehead.clockwise` respectively, with native color and control
feedback. Changed Since Settle is static and does not imply failure or processing.

Activating Settle or Settle Again opens one compact popover with optional
rationale rather than changing the judgment directly. Successful exact-revision
Settlement updates the control and Inspector facts. The existing confirmation
popover briefly shows a filled checkmark with one native Bounce, a short
“Current revision settled” confirmation, and one system haptic before closing.
This feedback follows only a confirmed, explicitly requested commit, including
Settle Again; navigation, refresh, failure, and a departed document never replay it.
Reduce Motion uses the static confirmation. Dismissal remains immediate, restores
focus, and cancels pending presentation. A derived refresh failure never presents
the committed Settlement as a failed mutation. No parallel overlay, Agent launcher
or Skill button is added. Agent setup and conversation behavior
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

Document Loading, Empty and Unavailable share centered presentation.
Editor failure retains recoverable exact source and offers Retry Edit. Notices above
usable content share a bounded, centered measure with reflowing native actions.

Owners retain state and context; §20 owns accessibility and persistent
repair. Settle and Dismiss retain their meanings. Fields, rows and notices keep
purpose-specific presentations using this vocabulary.

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
| Research / Judgment | 研究 / 判断 |
| Settle / Settled | 暂定 / 已暂定 |
| Attention / Connect | 关注 / 连接 |
| Incoming Links / Outgoing Links | 传入连接 / 传出连接 |
| Annotated Wikilink / Link Annotation | 带注释双链 / 链接注释 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Read / Edit | 阅读 / 编辑 |
| No Document Selected | 未选择文档 |
| Expand / Collapse All Folders | 展开 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

Chinese uses full-width punctuation. System-owned Finder names, exact paths,
stable identifiers, raw values, and researcher-authored titles are never
translated.

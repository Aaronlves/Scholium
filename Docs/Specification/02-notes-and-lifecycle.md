# Specification: Notes and Lifecycle

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 5–7.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work notes support:

- Review, Edit, and Source over one exact Markdown buffer;
- autosaved editing without an ordinary Save button;
- create, duplicate, import, rename, move, Reveal in Finder, Set Aside, Trash,
  Put Back, and permanent deletion;
- exact-source preservation, conflict detection, atomic writes, and external
  coordination;
- source-located Connect relations, passage Comments inside Discussion, and
  authoritative Markdown annotation including semantic Callouts;
- role-aware Properties and the closed Platform Research Actions with
  researcher-configured academic Profiles;
- Search in **This Note**, **This Vault**, or **Triptych**, plus Attention; and
- Research Record and independent checkpoint recovery.

Critique bodies are read-only in Scholium but remain ordinary externally
editable Markdown; Scholium does not set filesystem read-only permissions.

### 5.1 Document modes and YAML

- **Review** renders committed content for reading, selection, navigation, and
  commenting.
- **Edit** edits the exact body through a visual projection, shares
  Review's semantic render components, typography, callout presentation,
  document measure, and theme variables, reveals syntax only around the active
  construct, and shows neither YAML nor line numbers. Inactive content should
  match Review; caret, selection, marked-text composition, and the active
  construct are the permitted editing differences.
- **Source** edits complete Markdown and YAML, shows logical source-line
  numbers, and retains the same document session, viewport, measure, and
  semantic colors while using exact-source typography. Exact text soft-wraps
  within the available measure: visual continuation rows never insert or
  remove source line breaks and never acquire independent line numbers. The
  active-line treatment belongs only to a collapsed caret; a nonempty
  selection never paints an unselected following logical line as active.

All three modes consume the selected Appearance's one shared line-width value.
It changes only layout in Source: Victor Mono and the exact-source typography
contract remain unchanged. The CSS `ch` unit resolves against each mode's
current font and is a character-width unit, not an exact characters-per-line
promise.

Edit activation remains construct-scoped. A plain pointer click on projected
inline syntax or projected block content places one collapsed editor caret
at its mapped source position during pointer-down; it never first paints a
caret at the projected range boundary or constructs a text range as a side
effect of revealing syntax. Pointer-drag selection updates the authoritative
selection continuously but holds the visual Markdown projection stable until
pointer release; a discrete triple-click paragraph selection may reveal its
selected constructs immediately. A direct click on a rendered link reveals
that link's source with the collapsed caret immediately after its exact closing
marker. The first keyboard move into an inactive rendered link lands at that
same trailing boundary; one further backward move enters the now-visible exact
syntax. Control-click and Command-click instead activate the target without
moving the caret.

Review and Edit use one stable marker track and nesting step for unordered,
ordered, and task lists. Edit keeps the semantic marker projected while the
caret edits list-item prose; it reveals the exact list prefix only when the
selection enters that prefix. Left Arrow from the first prose position enters
the prefix at its trailing edge. Neither projected versus exact presentation
nor checked versus unchecked task state may move the prose start or change its
indentation. Review task controls are read-only. Edit's task checkbox is a
redundant pointer action that changes only `[ ]` to `[x]` or back in one Undo
transaction without moving the document selection; the caret-line **Toggle
Task** command remains the keyboard/menu route. Source always exposes the exact
prefix and task bytes.

Edit alone owns two caret-triggered input suggestion lists. Typing `[[` opens
the current Workspace note catalog and filters it again as the researcher types;
each insertable result shows its resolved title and quiet path context. Accepting
one unique result completes exactly one Wikilink, reusing rather than duplicating
any auto-inserted closing brackets. Ambiguous cross-vault targets remain
nonauthorizing and are not offered as insertable results. Typing `/` at the
start of a line or after whitespace opens structured insertion. A bare slash on
a block-safe line shows only **Callout**, **Date**, **Inline Math**, and
**Mermaid**; further characters fuzzy-match the complete bounded set:
**Callout**, **Date**, **Inline Math**, **Display Math**, **Mermaid**, **Table**,
**Footnote**, **Code Block**, and **Divider**. In ordinary prose, the bare slash
offers only Date, Inline Math, and Footnote. Date inserts the local calendar date
as `YYYY-MM-DD`; Callout continues into the canonical role chooser. These lists
never run during marked-text composition or inside frontmatter, code, raw HTML,
comments, mathematics, or another protected construct. Source owns neither
input list. Each accepted suggestion is one editor transaction and one
Undo event; it never creates another buffer, selection, focus owner, or
writable projection.

Rendered callouts hide generated role names visually but retain them for
accessibility. A supplied title inherits the role heading style; an untitled
callout adds no heading. Ordinary Body prose uses the selected Appearance's
alignment; the canonical default is justified without hyphenation. Callout,
table, code, mathematics, footnote, and ordinary-quotation composition remains
owned by each protected object rule rather than inheriting Body alignment
indiscriminately.

A title-only Callout remains visibly rendered rather than disappearing when a
following line is created or the caret leaves it. Because **Orient** has no
visible role heading, an author-supplied Orient title becomes its Body prose
when no authored Body exists; it is neither duplicated nor replaced by the
generated role name. In Edit, an active Callout retains one quiet block surface.
Only the physical line containing a collapsed caret exposes its exact quote and
role markers; a nonempty selection exposes only the physical lines it intersects.
Every other line keeps its construct-scoped projection.

Return on a nonempty Callout line inserts a newline with that line's exact
quote prefix. When that line is a list item, the same transaction additionally
continues its current indentation, list kind, task form, and ordered-list
sequence inside the Callout. Return on an empty quoted list item removes only
its list prefix and leaves the empty quoted line; Return on that line containing
only `>` plus optional spacing then removes the quote prefix and exits the
Callout. Each operation is one editor transaction and one Undo event.
Source remains ordinary exact text and applies neither continuation rule nor
Edit projection.

An inactive Edit callout atomically projects one half-open source range, but
the insertion point immediately after its last content character remains
editable Callout content. Down Arrow or Right Arrow from above enters at the
range start; Up Arrow from below or a pointer press on its rendered title/body
enters at that content-end insertion point. One further horizontal move enters
the real authored separator line. Nested inline constructs inside an active
Callout retain the same construct-scoped projection rules as ordinary prose.
Only the disclosure mark changes fold state by pointer; the focused summary
retains keyboard disclosure.

Review and Edit support Obsidian-compatible inline `$…$` and display
`$$…$$` mathematics outside YAML, code, raw HTML, comments, and escaped
delimiters. The immutable editing dialect owns exact delimiter behavior.
Malformed or unsupported mathematics stays visible as exact source with a
diagnostic; rendering never rewrites it.

Review and Edit render a fenced code block whose case-insensitive info-string
token is exactly `mermaid` as an authored diagram. The exactly pinned, local
Mermaid runtime determines the supported built-in diagram families; Scholium
does not maintain a narrower diagram-type list. Review renders on document
load. In Edit, an inactive block renders once, a direct pointer or keyboard
entry reveals its complete exact fenced source in the same editor state, and
the opening delimiter and info string, complete body, and closing delimiter all
remain visible while any selection intersects the block. The latest source
renders again only after the selection leaves the complete block. Mermaid never
renders incrementally while the researcher is typing in that block. Source
always exposes the exact fence, info string, and content.

Rendered Mermaid retains its intrinsic size when it is narrower than the
document measure and scales down proportionally when it is wider or exceeds the
bounded diagram viewport height; it does not force a narrow diagram to fill the
measure or require document-level horizontal scrolling. Diagram fills, labels,
borders, and relationship lines derive only from Scholium's protected semantic
document palette rather than Mermaid's independent multicolor scales. Review
and inactive Edit use the same projection geometry and styling.

Mermaid is a static illustration projection, not evidence, a Connection, an
argument endorsement, or a second source authority. It uses no network or
remote resources and cannot activate links, callbacks, scripts, arbitrary
initialization directives, diagram-local executable behavior, or injectable
custom styles. Unsupported, malformed, over-limit, or prohibited input keeps
its source visible with a textual diagnostic and is never repaired or
rewritten. Authored `accTitle` and `accDescr` supply the diagram's nonvisual
account. Their absence is a visible accessibility diagnostic; Scholium retains
the exact source as an assistive alternative and never invents an
interpretation of the philosophical structure. Review retains ordinary
selection and copying for the diagram, but a selection intersecting either a
rendered Mermaid projection or its visible source fallback is not a passage
Comment target and exposes no Comment bar.
The projection does not broaden, replace, or remap a precise selection in
surrounding Review prose. In Edit, activating the block preserves ordinary
UTF-16 source selection over the exact fence and body rather than selecting the
generated SVG or a whole-block surrogate.

Review and Edit treat Obsidian-compatible `![[Target]]` embeds, including
aliases and heading or block fragments, as source-located neutral links.
Inactive embeds share protected presentation, navigation, and diagnostics; the
active construct reveals its exact syntax. Scholium neither reads nor
transcludes target content through an embed and creates no philosophical
relationship edge from one. Transclusion remains outside the current product
boundary.

Internal links and Vector Links provide bounded previews without becoming
evidence or another source authority. Review additionally previews footnote
references on ordinary hover; a footnote preview contains only the referenced
definition. Footnote preview and return controls belong to Review, with
keyboard and accessibility-equivalent routes. Edit projects an inactive
reference as a numbered locator; activating it moves the caret to that named
definition. Its definition marker remains exact and directly editable at that
one source position; its body uses the same construct-scoped Edit projection as
ordinary Markdown and reveals only the active construct's exact syntax. It is
never copied into a second rendered editable block. Inserting a
named footnote appends one definition without renumbering existing identifiers
and places the Edit selection in that definition. Undefined and duplicate
forms remain exact source rather than being silently repaired. Source exposes
and edits the same exact reference and definition text.

Review and Edit have a direct keyboard toggle. Source is entered through
the mode menu. It may alter protected or machine-facing YAML; the researcher
accepts responsibility, while Scholium still performs targeted, byte-preserving
validation and never reserializes the whole frontmatter.

Modes add no floating Metadata or Properties surface over the text. Initial
top clearance belongs to the scrolling document.

### 5.2 Properties

Properties keeps three independent contracts: canonical vocabulary and
ownership, the default About profile, and creation requirements. Visibility
does not imply recognition or editability. Analysis, Topic, and Work have no
required creation property; the interface uses no asterisk or required-looking
marker. Cross-field validation remains fail-closed for values that are supplied.

Each vault may configure visible About fields and order from its role-specific
About catalog; no folder/note layouts or default disclosure state exist.
Complete Properties is an explicit editing destination. Identity,
fingerprints, provenance, protected-machine fields, and app facts are not
ordinary Properties controls even when exact Source YAML contains them.

`research_unit` is role-aware:

- Analysis accepts `completion` and/or `limitations`;
- Topic and Work accept `scope` and/or `limitations`; Work labels `scope`
  **Research Scope**.

Empty mappings, unknown members, wrong member types, or members from another
role are invalid. Removing one member preserves the others; only removing the
last non-empty member removes the mapping. Limitations are material claim
boundaries, never identity, links, confidence, timestamps, derived facts, or a
generic workflow state. An authorized agent edit follows the Research Action
Grant, conflict, fingerprint, and exact-source preservation rules.

Analysis `completion` is `complete`, `incomplete`, or a quoted ratio such as
`"6/11"`. A ratio requires a positive total and `0 <= completed <= total`.
It states represented material only: it quietly reminds the researcher of
incompleteness but does not identify units, certify adequacy, create a ledger,
gate work, enter Search, or duplicate a Limitation. A single article in an
edited collection may use the binary form. The researcher or an authorized
agent chooses the form; Scholium never infers it from Zotero type, children,
or page count.

Analysis retains YAML `title` for source identity and agent indexing but About
does not show it. Analysis resolves display identity as YAML `title`, then the
first H1, then filename. Topic and Work do not recognize YAML `title`; both use
the first H1, then filename. One shared resolver supplies Workspace, Search,
Link Graph, and Research Actions.

Creation/modification times are app-owned Research Record facts, not
Properties; timestamp keys in Markdown remain exact custom source.

`summary` is one optional canonical researcher-owned string Property shared by
Analysis, Topic, and Work. It is a short human-readable navigation declaration
about the current Note as a whole: what it studies, its distinctive scope or
problem, and why a later researcher or Agent may need to open it. It is not a
Skill, instruction, source, unified position, completeness assertion,
Researcher State, or researcher acceptance. A substantive claim found through
it must be checked against the current exact Note body and actual sources.

Researcher and authorized Agent edits maintain the same YAML field through the
ordinary exact-revision, attribution, conflict, and recovery boundary. There
is no human/Agent pair, approval copy, pending summary, automatic backfill, or
summary lifecycle. Missing, not-yet-written, and not-applicable are valid.
Scholium never silently generates, overwrites, or claims freshness for it. A
Scholium-mediated write or Research Record retains its actual actor only in the
existing operation/Record owner that proves that act. The current Note revision
and `summary` value alone do not identify their writer: Research Context reports
that actor as unknown unless such an authoritative owner separately proves it.
Authorization, the last Run, file location, macOS user, or vault ownership may
not fill the gap. Agent authority does not turn the field into a
researcher-authored stance, and Scholium creates no writer-history database to
infer one. An uncommitted machine summary remains a disposable projection and
can never write source.
The field should preserve competing interpretations, historical differences,
open questions, and mixed epistemic identities rather than compressing them
into false consensus.

An Analysis may pair whole-number `debate_importance` (0–10) with
`debate_importance_scope`. Both are required together and comparable only
within the same named debate, domain, tradition, period, or reception context.
It is not project relevance, source quality, truth, prestige, or citation
impact. After choosing one exact scope, Library may sort rated Analyses high to
low with unrated notes afterward. No global cross-debate ranking exists;
Scholium neither generates nor presents Project Relevance. Existing
`relevance` and `relevance_rating` are preserved custom data with no Scholium
semantics.

About omits absent fields without explanatory empty copy. Its role-specific
order is defined in Appendix A. `status` has no Scholium semantics, query,
index, filter, ordering, or UI. Work `deadline`, Topic/Work YAML `title`,
required markers, and **Open Properties by Default** likewise do not exist.
Unknown source YAML remains byte-preserved but acquires no Scholium semantics.
Section 13 may address a literal top-level YAML key for presence or exact
string-value retrieval. That addressability is a source-faithful Search lead,
not admission to the canonical Property catalog, validation, display,
philosophical interpretation, or researcher judgment.

### 5.3 Create, duplicate, rename, and identity

**New Note** and **New Folder** are immediate, nonmodal actions. The
Library-header Add menu offers both actions at the current vault root. A
secondary click in unoccupied Library source-list space offers the same compact
pair; the header menu remains their primary pointer and accessibility route, so
secondary click is never required. **File → New Note** and its keyboard
shortcut directly create the same empty root note. A folder row's **New Note**
and **New Folder** context actions create inside that exact vault-relative
folder; the folder row also exposes equivalent accessibility actions.

An ordinary folder context menu is compact and ordered by semantic group:

1. **New Note**, **New Folder**, **Rename Folder…**, and **Move Folder…**;
2. **Expand All** or **Collapse All** when the folder has descendants;
3. **Copy Relative Path** and **Reveal in Finder**;
4. destructive **Move Folder and Notes to Trash…** at the bottom.

Expansion mutates only window-local disclosure state. Copy and Reveal expose
the exact existing vault-relative folder without changing research source.
An ordinary note row exposes **Rename…** rather than combining naming and
placement in one command. It is a direct one-item drag source: dropping it on
an ordinary Folder moves it into that exact folder, while dropping it on the
Library LocationHeader moves it to the current vault root. The drop target
highlights only while it can accept the note; a successful move keeps that note
selected at its destination. Collision, stale revision, unresolved identity,
cross-vault placement, managed Critique placement, or source mutation failure
changes nothing and reports the reason. **File → Move Note…** and the named
accessibility action remain the non-drag placement routes; drag is never the
only way to move a note. Copy Relative Path and Reveal in Finder remain beside
the existing open and lifecycle actions, while Open in New Tab, Rename, Move,
Copy, and Reveal remain available without secondary click.

An ordinary mutable Folder is likewise a direct one-item drag source. Dropping
it on another ordinary Folder moves the complete source folder inside that
destination; dropping it on the Library LocationHeader moves it to the current
vault root. The process-private payload contains only its exact vault and path,
and a target advertises Move only after rejecting cross-vault placement, the
current parent, the source itself, and every source descendant. Completion uses
the same flush-and-recheck folder Move transaction described below. A rejected
or failed drop changes no source or disclosure. **Move Folder…** and the named
accessibility action remain the non-drag route.

A folder is only a vault-relative filesystem location used for classification.
It has no UUID, Properties, Research Record, checkpoint identity, or independent
lifecycle record. Empty folders remain visible in Library. **New Folder**
immediately and atomically claims `Untitled Folder`, `Untitled Folder 2`, and so
on inside the clicked folder; it opens no sheet. Once that directory claim is
durable, the exact window installs it immediately and the Workspace completes
folder inventory and disposable derived projections in its owned background
refresh. Creation never waits for graph, Search, or research-state assembly.
Rename and Move use one scoped sheet only because the researcher must supply a
name or destination.

A confirmed folder rename or move flushes every open editor in the Triptych,
rechecks the complete descendant Markdown path-and-fingerprint inventory, and
then renames the directory entry once without replacement. Each descendant note
retains its stable identity; all identity paths are rebound in one portable
state write, app-owned path projections resume idempotently, and only exact
already-resolved incoming links are rewritten against one future graph.
Ambiguous links, a changed inventory, a symlink boundary, moving into the
source subtree, or any destination collision aborts the operation. A failed
link transaction rolls back or leaves durable recovery evidence. Non-Markdown
contents move with the same directory without being parsed or rewritten.

**Move Folder and Notes to Trash…** requires confirmation, moves the directory
once beneath `Trash/`, and gives each descendant note the ordinary Trash
location semantics while preserving its stable identity. The folder itself
still has no lifecycle identity. Managed Critiques and ambiguous folder
projections omit all source-mutating folder actions. Every contextual operation
has an equivalent accessibility action; secondary click is never the only path.

Scholium atomically claims the first available path in the sequence
`Untitled.md`, `Untitled 2.md`, `Untitled 3.md`, and so on. It never replaces an
existing or comparison-equivalent path. A concurrent collision advances to the
next name; another error stops without creating a substitute elsewhere.
Successful creation selects and opens the note. Creation never presents a
sheet, popover, naming form, or required-properties step; naming and Properties
remain later explicit edits.

Only after the source commit and latest authoritative Library projection are
available, successful creation clears active Library filters, expands only the
created note's folder ancestors, preserves every unrelated disclosure, and
reveals the selected row without moving keyboard focus into Library. Ordinary
sort order remains unchanged; **Debate Importance** falls back to **Recently
Modified** when clearing its required explicit debate scope. A failure before
this presentation transition preserves the prior filters, disclosure, sort,
selection, and visible source.

Paths are locations; notes have stable app-owned identities. Duplication creates
a new identity with no inherited Settlement or Research Records. Rename keeps
the current containing folder; Move changes placement by drag or the explicit
File/accessibility route. Confirmed moves and renames preserve records and
update resolved incoming links. Ambiguous
external rename keeps the note readable but blocks identity-dependent mutation,
Settle, record attachment, and Discussion anchor attachment until confirmation.

## 6. Note location, Set Aside, and Trash

There is no generic lifecycle status or advance control; location determines
active, Set Aside, or Trash state.

- **Set Aside** is direct and reversible. It records no reason or failure
  status. Set-aside notes remain readable but are excluded from ordinary
  Search, synthesis, Critique, and agent context unless explicitly included.
- **Move to Trash** excludes the note from ordinary Search, Connect, agent
  context, and workflows without immediately erasing it.
- **Put Back** is direct and reversible. It restores the exact original
  vault-relative path and reports a conflict rather than inventing another
  name or destination; it requires no confirmation or destination sheet.
- **Cancel** changes nothing.
- **Delete Permanently** purges the note, its active Discussion drafts,
  Settlements, associated Critique, and note-specific machine state from live
  storage and every checkpoint. A checkpoint that cannot be scrubbed is
  invalidated and removed. A finished shared Research Record survives with a
  participant tombstone until the researcher separately deletes that record.

Note-specific records follow stable identity into Set Aside and Trash while
recovery remains possible. Permanent note deletion advertises no checkpoint
recovery; a surviving record tombstone is provenance, not a way to restore the
deleted note.

Library, Set Aside, and Trash are category projections of one native file-tree
model, not distinct browsers. They share hierarchy, indentation, disclosure,
selection, hover, scrolling, keyboard and accessibility navigation, document
opening, and exact-path presentation. Each category filters the same vault
inventory and differs only where its lifecycle semantics require different
available actions or mutation policy. A committed category move updates the
exact window immediately and queues the complete disposable Workspace refresh;
it never waits for graph, Search, or research-state assembly before returning.
When Set Aside, Move to Trash, or Put Back moves the currently presented Note
out of its visible Location, that document page closes and the Document region
returns to the restrained no-document state. Other open pages remain available
without being activated implicitly. Selecting the moved Note in Set Aside,
Trash, or Library later opens its exact content normally; clearing the prior
presentation is not deletion and does not make lifecycle content unreadable.

## 7. Settlement, annotation, and Discussion

### 7.1 Settle

Settle is available for every active Analysis, Topic, and Work as a quiet
current-note action. It binds to the exact saved fingerprint, accepts an
optional rationale, records date and researcher identity, and never blocks on
an agent response or Fidelity warning. Repeating Settle for the current
fingerprint may update the rationale, date, or researcher judgment and may
backfill a missing machine-local pin; it does not create a second pin for
identical bytes.
Save failure, dirty conflict, unknown stable identity, or a revision mismatch
blocks Settle. A later saved fingerprint keeps the prior statement, offers
**Settle Again**, and may produce **Changed Since Settled** in Attention. Settle
is neither a Research Record list row nor an activity-history node. Repeating
Settle for the same fingerprint updates the portable judgment without creating
another recovery version. Settled versions are separate from temporary Action
recovery and are retained per stable Note identity according to the
machine-local Triptych policy: latest 10, 30, 50, or no automatic deletion; the
default is 30. Lowering a limit requires a preview and explicit confirmation of
the exact older versions to remove. Commit uncertainty keeps recovery bytes
rather than deleting them. Restore does not Settle the restored revision;
storage and pruning mechanics belong to
[Source Storage and Read Models](../Architecture/05-source-storage-and-read-models.md).

### 7.2 Discussion, Comment, and written annotation

Review exposes **Comment** for a nonempty passage selection; Edit and Source do
not. Review selection reveals one compact contextual Comment bar near the
text. Edit selection instead reveals only the common formatting commands valid
for that exact selection. A pointer-created Comment or formatting bar remains
hidden throughout selection and appears only after the primary-button gesture
finishes; a completed keyboard selection may reveal it immediately. The Format
menu and keyboard retain equivalent formatting routes. The editor's
secondary-click menu consumes that same finalized editor selection and
starts with **Cut**, **Copy**, **Paste**, and **Select All**; it then adds only
operations whose meaning depends on one collapsed clicked construct. It does
not duplicate common formatting, inherit generic Autofill or Services
hierarchies, or contain a Preview command or Preview submenu. Footnote hover,
focus, and navigation belong to Review only; Edit retains only the ordinary
cursor-placement needed to reach the underlying Markdown, and Source exposes
the exact text. Markdown has no bundled underline command.

A Review selection intersecting a protected Mermaid projection, including its
visible failure fallback, does not expose Comment or publish a passage target.
The selection and ordinary copying remain available; surrounding authored prose
remains commentable. Scholium never guesses a line anchor from generated SVG
text or converts a diagram-node selection into a whole-fence Comment.

Comment expands the contextual bar in place into a bounded multiline field.
Return saves and closes it, Shift-Return inserts a line break, and Escape
cancels. Return enters a brief saving state; the field closes only after
Scholium confirms the portable write. A failed write keeps the exact Comment
text in place for retry, while a committed write with stale derived views is
reported as saved rather than invited to duplicate. Saving creates or appends a researcher-authored line Comment inside
the current note's active Discussion without copying instructions, opening an
agent application, or presenting a sheet. A line Comment records only the
stable Note, the exact Note fingerprint, and its one-based inclusive starting
and ending lines; selection text, quotation, surrounding context, and exact
byte or UTF-16 offsets are neither stored in that Comment nor sent to an agent.
Review may use the current rendered selection transiently to resolve its actual
Markdown source lines before discarding the selection payload. The submission
remains bound to the original stable Note and exact fingerprint; changing the
Note, revision, mode, or editor generation cannot redirect it.
If the Note later changes, the original revision-bound line location remains
truthful and is not guessed or reattached.

**Discuss** is the deliberate agent-interaction boundary. It automatically
includes the current Note's existing line Comments, permits an optional
unanchored whole-note turn and focal notes, and opens the one active Discussion
when it already has a resolved Discuss Action. A Comment-only draft first opens
the ordinary Discuss Action. Every new Discuss Action begins with a concise,
editable request to discuss the Note including any existing Comments, so the
researcher need not restate this routine collection rule; preparation freezes
the registered primary Skill text, resolved Practices, optional folder-path
string, and Result Contract for that same Discussion and preserves every
Comment before any Agent handoff. Later handoffs reload those Run-frozen
contracts rather than constructing an application-owned substitute prompt.
Comments and Discuss remain one Discussion model, not
parallel archives, but adding a Comment never initiates Discuss or an agent
handoff.

Discussion begins without source mutation. It remains resumable through
researcher turns, attributed Agent replies, and any separately authorized
next Action. Closing its sheet retains the draft. **Finish Discussion** moves
the complete exchange into one portable Research Record; Finish means only
that the exchange is no longer active and implies no approval, rejection,
truth, failure, or settlement.

Scholium has no app-owned Annotation record, marginal-note store, Annotation
action, or overlay. A researcher annotates a document authoritatively by
editing its Markdown, including an ordinary semantic Callout when a visibly
separate note is useful.

# Scholium Specification

**Status:** Canonical product, interface, and release specification
**Applies to:** Scholium for macOS and its agent-facing CLI
**Canonicalized:** 2026-07-17
**Consolidated:** 2026-07-29

This is Scholium's sole target authority for product, interface, action
language, Scholarly Editorialism, accessibility, release, and stable decisions.
`IMPLEMENTATION_ARCHITECTURE.md` describes structure; `IMPLEMENTATION_STATUS.md`,
README, live construction, and tests establish reachability and evidence.
Implementation divergence is tracked outside this document and never defines
an alternative target.

In this specification:

- **Target** is required behavior, whether implemented or not.
- **Reachable** means exposed by the current build, not accepted for release.
- **Verified** means directly exercised by the stated evidence.
- **Deferred** is intentionally outside the stated release boundary.
- **Unresolved** means a decision or acceptance judgment remains open.

Apple HIG and the selected SDK own platform/API behavior; this specification
owns the Triptych, scholarly semantics, evidence, and research governance.

Scholium uses direct agent edits and has no Proposal or unapplied-Revision
workflow. Unsupported application state fails closed and remains unparsed and
untouched; unsupported data never authorizes behavior. Scholium never deletes
or normalizes researcher Markdown, custom YAML, or unrecognized Triptych files
merely because it does not interpret them.

## 1. Canonical terminology

- A **Scholium Triptych** (**Triptych**) is one configured workspace containing
  exactly three vaults: **Analyses**, **Topics**, and **Works**. Their ordinary
  documents are an **Analysis**, **Topic**, and **Work**.
- A **Research Action** is a researcher-selected scholarly transition or
  authority boundary exposed by the Research Inspector's **Actions** mode and
  executed through the shared Application API. The stable default Actions are
  Discuss, Analyze, Synthesize, Write, Critique, and Check Fidelity. Internal
  execution mechanisms may retain implementation names such as Develop or
  Revise, but those names are not public operations.
- An Action's **Origin** is the immutable current Analysis, Topic, or Work from
  which work begins. Its **Target** is the note or passage the Action is meant
  to affect. **Focal Materials** guide attention without defining the complete
  read boundary, and no readable or focal note becomes writable merely because
  an agent can inspect it.
- A **Discussion** is one resumable researcher-agent exchange containing
  passage-anchored Comments, optional whole-note turns, optional focal notes,
  attributed replies, and any authorized child Action. Closing its Action
  surface preserves it; **Finish Discussion** creates one Research Record and
  makes no claim of acceptance, truth, or settlement.
- A **Method Skill** is an ordinary, directly editable, versioned Skill package
  that supplies the intellectual method for one or more Actions. It remains
  distinct from the protected Scholium mechanism and from ordinary research
  notes. An **Action Profile** is researcher-owned declarative configuration
  for placement, inputs, applicability, and requested capability; neither
  Skill prose nor a Profile grants authority by itself.
- **Settle** is the researcher's fingerprint-bound, replaceable current
  judgment that one saved revision is sufficiently stable for current
  research. It is neither a verdict nor a qualification. Each distinct
  settled revision pins one deduplicated machine-local exact-byte recovery
  version of that Note.
- **Critique** is an attributed agent assessment of one Work. It does not
  replace or silently edit the Work.
- **Fidelity** audits the exact revision's philosophical content and, when an
  applicable Researcher Skill is bound, citations. It remains distinct from
  Settle and Critique.
- **Connect** is the Inspector surface for source-located neutral, support,
  opposition, or incompatibility relations. **Attention** contains derived, recoverable
  warnings; it makes no philosophical judgment.
- **Properties** is the human-facing projection of frontmatter. A **Research
  Unit** is the minimal YAML declaration of the epistemic scope represented by
  a note; About presents its Scope and material Limitations with other chosen
  properties rather than creating another status model.
- A **Research Action Grant** is one short-lived, task-bound write authority.
  Its plaintext key is carried only in the prepared handoff; Scholium persists
  only a digest and the frozen Action, Skill revision, Origin, scope,
  identities, revisions, and expiry.
- **Research Record** is the portable intellectual record of one finished
  Discussion or validated Action run. A separate nonmodal two-panel utility
  window browses these records; active Discussion remains in Actions, and
  ordinary Markdown annotations remain in the document.
- A **Checkpoint** is a self-contained, fingerprint-bound snapshot of the
  complete Triptych, distinct from editor Undo.

There is no formal Revision artifact, Proposal, Research Task, Research
Session, Failure object, or Alternative relation. “Revision” may still
describe an edit or a Critique section.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS document editor for sustained humanities
research, especially philosophy. The research document—not a dashboard, task,
workflow state, or agent conversation—is primary; exact Markdown underlies
every projection.

Before polish or optional workflows may block release, setup, open, create,
read, edit, autosave, Search, conflicts, recovery, Library, Document tabs, and
contextual inspection must work without data loss, shell reconstruction, or
surprising state changes. Visual metrics are provisional unless required by
readability, accessibility, source integrity, or native-window behavior.

Scholium supports source-grounded reading, writing, authoritative Markdown
annotation, deliberate agent communication, Settle, Search, Connect,
organization, recovery, and provenance. It is not project or reference management,
permanent AI chat, or a full Obsidian replacement. The manual core must work
without Obsidian, Zotero, or agents.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and may instruct an external agent to
mutate files through filesystem or CLI tools. Scholium never revives Proposal.
A standing permission policy decides only when a validated short-lived grant
may be issued without another question; every prepared write phase still uses
one Research Action Grant whose key, frozen scope, and completion command
authorize only that phase. Discussion and Critique remain optional.

Scholium supplies safety, not transferred responsibility:

- exact paths, stable identities, and Application-owned fingerprint checks;
- autosave, atomic writes, external-change detection, and conflicts;
- automatic and manual Triptych checkpoints, comparison, and restoration.

Extensive external work without a suitable checkpoint is not guaranteed
recoverable. Fingerprints detect revisions; they are not permission tokens and
do not need to be copied into the agent prompt.

The Application API validates each Research Action's Target, focal context,
source access, revision, Method Skill, Action Profile, permission, checkpoint,
and completion contract. Frontends select semantic Actions, never protected
package identifiers or assembled technical instructions. The protected
mechanism supplies protocol and safety; one installed Method Skill supplies
the intellectual procedure.

Scholium distinguishes:

- protected, release-managed **System Skills** for mechanism only;
- directly editable, Triptych-installed **Working Method Skills**;
- read-only bundled references used only for explicit compare or restore; and
- researcher-installed **Researcher Skills**, disabled until deliberately
  configured and enabled.

Bundled methods are usable defaults, not best methods, philosophy lessons, or
certification. The researcher may edit, replace, or disable a Working Method.
Scholium never silently falls back to a bundled reference after that choice.

### 2.3 Authorship and provenance

Scholium assumes exactly one researcher for each Triptych. It has no
collaborator, coauthor, or multi-researcher approval model. Agents are
attributed participants, never additional researcher authorities.

Keep independent: Origin and confirmed modified identities; vault role and
location; settlement fingerprint and changed-since-settled state; Critique
authorship; and Discussion turns. Agent origin
does not disappear after Finish, Settle, incorporation, or later editing.

Visible labels stay sparse. Location communicates Analysis, Topic, Work, and
Critique roles; do not compose badges such as **Agent — Analysis**. Put useful
provenance and modification detail in Properties or Research Record and show
warnings only when relevant.

## 3. The Scholium Triptych

### 3.1 Exactly three vaults

| Vault | Research role |
| --- | --- |
| **Analyses** | Reusable analyses of papers and other sources. |
| **Topics** | Reusable concepts, distinctions, positions, debates, objections, and syntheses. |
| **Works** | Researcher-governed plans, arguments, drafts, Critiques, papers, chapters, books, and related writing. |

Analyses and Topics remain reusable across Works in the same philosophical
domain. A substantially different domain uses another complete Triptych.
There is no fourth vault or **All Notes** mode.

Researchers choose all locations. Scholium may recommend a common parent but
never requires or relocates it. Because `.scholium/` sits beside Works, two
Triptychs may not share a Works parent.

### 3.2 Triptych navigation and windows

One configured window belongs to one Triptych and presents three peer Library
scopes: **Analyses | Topics | Works**. Switching scope changes only the browsed
hierarchy and **This Vault** Search; it does not replace the open document.

**File → New Triptych…** opens setup for three new locations; **File → Open
Triptych** opens a registered Triptych separately; **File → New Window** creates
another workspace for the focused Triptych. **Open in New Tab** adds a page
only to the current window's central Document region. One stable document may
appear at most once in that window; opening it again selects its existing page
rather than creating another editor surface. Other windows retain independent
document sessions. Switching tabs changes the active document and its
Apparatus projection, while Library disclosure and selection, Sidebar
visibility, Apparatus visibility, and Apparatus mode remain stable.

**New Triptych…** and missing registration use Bootstrap. Expired access stays
in the configured workspace under one **Restore Access** sheet. The workspace
retains one frame and three-item split across loading/no-note/note states;
notes never resize it. No-note Document is text-, action-, and VoiceOver-free,
while Library remains available through the Sidebar route.

Works folders are researcher-controlled organization, not registered projects.
Scholium supplies no project selector, assignment, completeness check, or
Triptych switcher inside Document.

### 3.3 `.scholium` and machine-local state

The portable directory beside Works contains only:

- manifest and stable identity mappings;
- Triptych Guide and Triptych-local settings or folder preferences;
- per-vault Properties profiles;
- Working Method Skills, Action Profiles, explicit bindings, and portable
  intellectual Research Records under `.scholium/research-records/v1/`;
- user packages at `.scholium/skills/<skill-id>/SKILL.md`.

It may be synchronized through ordinary cloud storage or Git; Scholium never
uploads it automatically.

Application Support owns:

- security-scoped bookmarks and absolute paths, including a separate bookmark
  for the folder containing Works that authorizes sibling `.scholium/` without
  creating a fourth vault, plus the agent application selected for Beta handoff;
- window sessions and vault-qualified Document tabs;
- derived indexes, temporary files, and caches;
- temporary grants, pending permission requests, source bookmarks, transport
  state, derived record indexes, and other machine-local execution data; and
- self-contained Triptych checkpoints.

Production requires the real per-user Application Support root before it may
construct a workspace runtime or any machine-owned store. Failure to resolve,
contain, create, or verify that root never falls back to a temporary directory
and never creates an implicit read-only runtime. QA may substitute only an
explicit isolated root supplied by its launch contract.

### 3.4 Triptych Guide and AI instructions

The agent-facing Guide states vault roles, researcher-owned Works organization,
relation syntax, fidelity/provenance/uncertainty/conflict rules, and safe CLI/
file conventions.

Scholium never creates, overwrites, or silently updates workspace `AGENTS.md`
except an explicitly requested protected one-shot bootstrap. The agent must
resolve Triptych/root, inspect ancestor instructions, validate a minimal
candidate, promote it, and read it back. Any applicable existing file stops the
operation; no overwrite, merge, or shadow is allowed. Only a successful
task-created temporary file may be removed; the result is researcher-owned.

Triptych-local technical instructions are managed only in **Settings →
Research Guidance**. Inventory is discovered from the filesystem and CLI, not
a standing generated index.

### 3.5 Import

Import copies a regular UTF-8 Markdown file directly into the root of the
currently selected Analyses, Topics, or Works vault. The external original
remains unchanged; the imported Note preserves its exact bytes, including BOM,
newline style, malformed or unknown YAML, and final newline. A collision uses
`Name 2.md`, then the next available ordinal, without replacing either file.
The imported file is immediately an ordinary Note of the selected Scope; root-
level Notes require no classification workflow.

## 4. Works folders and organization

Works is an ordinary researcher-defined Markdown hierarchy. Scholium creates
no project membership, required metadata, selector, schema, completeness
warning, or internal template. `Critiques/` alone has special behavior.

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
- role-aware Properties, default Research Actions, and researcher-enabled
  custom Actions;
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
  remove source line breaks and never acquire independent line numbers.

All three modes consume the selected Appearance's one shared line-width value.
It changes only layout in Source: Victor Mono and the exact-source typography
contract remain unchanged. The CSS `ch` unit resolves against each mode's
current font and is a character-width unit, not an exact characters-per-line
promise.

Edit activation remains construct-scoped. A plain pointer click on projected
inline syntax or projected block content places one collapsed CodeMirror caret
at its mapped source position; it never constructs a text range as a side
effect of revealing syntax. Pointer-drag selection updates the authoritative
selection continuously but holds the visual Markdown projection stable until
pointer release; a discrete triple-click paragraph selection may reveal its
selected constructs immediately. A direct click on a rendered link reveals
that link's source, while Control-click and Command-click activate the target
without moving the caret.

Rendered callouts hide generated role names visually but retain them for
accessibility. A supplied title inherits the role heading style; an untitled
callout adds no heading. Ordinary Body prose uses the selected Appearance's
alignment; the canonical default is justified without hyphenation. Callout,
table, code, mathematics, footnote, and ordinary-quotation composition remains
owned by each protected object rule rather than inheriting Body alignment
indiscriminately.

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

### 5.3 Create, duplicate, rename, and identity

**New Note** is an immediate, nonmodal action. The Library-header Add button
creates an empty Markdown note at the current vault root. **File → New Note**
and its keyboard shortcut perform the same focused-window action. A folder
row's **New Note** context action creates inside that exact vault-relative
folder; the folder row also exposes an accessibility action, so secondary click
is not the only route to the contextual operation.

An ordinary folder context menu is compact and ordered by semantic group:

1. **New Note**, **New Folder**, **Rename Folder…**, and **Move Folder…**;
2. **Expand All** or **Collapse All** when the folder has descendants;
3. **Copy Relative Path** and **Reveal in Finder**;
4. destructive **Move Folder and Notes to Trash…** at the bottom.

Expansion mutates only window-local disclosure state. Copy and Reveal expose
the exact existing vault-relative folder without changing research source.
Ordinary note rows likewise expose **Copy Relative Path** beside their existing
open, lifecycle, and Finder actions; Open in New Tab, Copy, and Reveal also
remain available as accessibility actions.

A folder is only a vault-relative filesystem location used for classification.
It has no UUID, Properties, Research Record, checkpoint identity, or independent
lifecycle record. Empty folders remain visible in Library. **New Folder**
immediately and atomically claims `Untitled Folder`, `Untitled Folder 2`, and so
on inside the clicked folder; it opens no sheet. Rename and Move use one scoped
sheet only because the researcher must supply a name or destination.

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

Paths are locations; notes have stable app-owned identities. Duplication creates
a new identity with no inherited Settlement or Research Records. Confirmed
moves/renames preserve records and update resolved incoming links. Ambiguous
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
- **Put Back** restores the exact original vault-relative path and reports a
  conflict rather than inventing another name or destination.
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

## 7. Settlement, annotation, and Discussion

### 7.1 Settle

Settle is available for every active Analysis, Topic, and Work as a quiet
current-note action. It binds to the exact saved fingerprint, accepts an
optional rationale, records date and researcher identity, and never blocks on
an agent response or Fidelity warning. Repeating Settle for the current
fingerprint may update the rationale, date, or researcher judgment and may
backfill a missing machine-local pin; it does not create a second pin for
identical bytes.
If portable-state replacement fails, Scholium may remove a newly created pin
only when the storage boundary proves failure occurred before rename. Any
post-rename or commit-uncertain outcome retains the pin even if a later concurrent
Settle has already replaced the portable current state.
Save failure, dirty conflict, unknown stable identity, or a revision mismatch
blocks Settle. A later saved fingerprint keeps the prior statement, offers
**Settle Again**, and may produce **Changed Since Settled** in Attention. Settle
is neither a Research Record list row nor an activity-history node. Repeating
Settle for the same fingerprint updates the portable judgment without creating
another recovery version. Settled versions are separate from temporary Action
recovery and are retained per stable Note identity according to the
machine-local Triptych policy: latest 10, 30, 50, or no automatic deletion.
Latest is determined by a durable per-Note monotonic Settle order rather than
the adjustable wall clock; the default is 30. Lowering a limit requires a
preview and explicit confirmation
before the enumerated older versions are removed. Once confirmed, those exact
snapshot identities remain in a machine-local pending journal until idempotent
removal finishes; a later Settle version never joins that approved removal set.
Restore does not Settle the restored revision.

### 7.2 Discussion, Comment, and written annotation

Review exposes **Comment** for a nonempty passage selection; Edit and Source do
not. Review selection reveals one compact contextual Comment bar near the
text. Edit selection instead reveals only the common formatting commands valid
for that exact selection. The Format menu and keyboard retain equivalent
formatting routes; the secondary-click menu does not duplicate these common
commands and contains only operations whose meaning depends on the clicked
construct. It contains no Preview command or Preview submenu. Footnote hover,
focus, and navigation belong to Review only; Edit retains only the ordinary
cursor-placement needed to reach the underlying Markdown, and Source exposes
the exact text. Markdown has no bundled underline command.

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
researcher need not restate this routine collection rule; preparation binds
the researcher-selected Method/Profile revision to that same Discussion and
preserves every Comment before any agent handoff. Later handoffs reload the
machine-local instructions for that frozen run rather than constructing an
application-owned substitute prompt. Comments and Discuss remain one Discussion model, not
parallel archives, but adding a Comment never initiates Discuss or an agent
handoff.

Discussion begins without source mutation. It remains resumable through
researcher turns, attributed agent replies, and any separately authorized
child Action. Closing its sheet retains the draft. **Finish Discussion** moves
the complete exchange into one portable Research Record; Finish means only
that the exchange is no longer active and implies no approval, rejection,
truth, failure, or settlement.

Scholium has no app-owned Annotation record, marginal-note store, Annotation
action, or overlay. A researcher annotates a document authoritatively by
editing its Markdown, including an ordinary semantic Callout when a visibly
separate note is useful.

## 8. Research Actions, Method Skills, and direct agent work

### 8.1 Actions and the protected execution contract

The Research Inspector's **Actions** mode exposes only the default Actions
valid for the current note, followed by researcher-enabled custom Actions:

| Target | Default Actions, in order |
| --- | --- |
| Analysis | **Discuss, Analyze, Check Fidelity** |
| Topic | **Discuss, Synthesize, Check Fidelity** |
| Work | **Discuss, Write, Critique, Check Fidelity** |

There is no default mode picker. Analyze Source and Reanalyze are one adaptive
Analyze Action; reading multiple Materials is context assembly, not a
Multi-note mode; Analyze and Synthesize remain separate authority-bound phases.
**Manuscript** ships as an optional ordinary Method Skill whose Action Profile
is disabled and hidden by default. The researcher may enable it as a custom
Work Action.

Internal Develop, Revise, Critique, Fidelity, and Manuscript mechanisms may
remain protected implementation identities. The public Action snapshot records
the scholarly Action, exact Method Skill and Profile revisions, not an internal
name presented as researcher vocabulary.

Every official and custom Action uses one Scholium-rendered modular sheet;
the document's lightweight line-Comment composer is not an Action sheet. An
Action Profile may request only bounded native modules: current Target or
passage; a natural-language instruction; bounded text, single-choice,
multi-choice, or toggle parameters; optional focal note or Material selection;
source access; expected academic outcome; and feedback. It may set a visible
label, role applicability, Triptych placement, order, and **Show in Actions**.
It cannot provide arbitrary Swift, HTML, JavaScript, shell code, native window
layouts, or application statuses.

Opening that sheet captures the exact execution kind, complete Profile
semantic revision, and Profile-document revision that the researcher saw.
Preparation must reject the sheet if any of those values changed, including a
same-kind change to readable roles, candidate write authority, editable
properties, or other capabilities.

Scholium always owns and displays stable identity, revision, source access,
authority, consequential scope, preparation, cancellation, conflict,
comparison, and recovery. A Skill or Profile cannot hide or
replace these modules. Custom Actions appear under **Researcher Skills** and
create no new application-defined event taxonomy.

The optional-agent journey is choose Action, state the request naturally,
inspect focal context and consequences, prepare a durable run, hand it to an
external agent, then inspect the response or confirmed source state. Scholium
contains no embedded agent runtime, does not monitor agent reasoning, and never
claims that opening an agent app means the task was accepted or completed.

Provider-neutral copy and explicit app selection remain available. A Codex
handoff may open a new task at the exact requested root with locator-only
bootstrap data; it must not append to an existing task, auto-submit, select a
model, alter permissions, or put Target or Material content in a launch URL.

Origin, passage, and focal Materials guide attention. Resolved one-hop Connect
relations may suggest Materials with their source location, but are never
evidence, never preselected, and never expand readable or writable scope.
Transitive paths, lexical similarity, Comment text, and inferred philosophical
roles cannot select Materials automatically.

Opening an Action flushes only its current Target editor. Preparation rechecks
the frozen Target, every explicitly selected Material, source access, Method,
Profile, and authority without saving unrelated Notes. Current Actions create
no automatic whole-Triptych checkpoint. Every Scholium-mediated existing-Note
write preserves the exact displaced bytes in per-Note pre-write recovery before
commit; Critique uses the same exact-note recovery and explicit rollback for a
new output. Any relevant save failure, dirty conflict, unknown identity, stale
revision, unsupported Target, invalid Method Skill, or unapproved capability
blocks preparation or commit. Discuss and Check Fidelity are read-only. The
researcher may still create a manual whole-Triptych checkpoint or instruct an
external agent outside Scholium; external edits remain ordinary concurrent
filesystem inputs.

### 8.2 Authorship, feedback, and truthful records

Scholium-owned records keep four authorship classes distinct:

| Class | Proper content |
| --- | --- |
| Researcher-authored | Comments, questions, direct Markdown, explicit authorization, and deliberate later judgments |
| Agent-authored | Analysis, synthesis, Critique, writing, replies, feedback, uncertainty, and proposed diagnoses |
| Scholium-established | Identities, revisions, configured methods, authorized scope, checkpoints, conflicts, confirmed changes, and application failures |
| Deliberately unknown | Unexpressed intention, belief, significance, maturity, truth, reasons for silence, and private lessons |

An Action does not reveal the researcher's intention. Scholium records only
the meaning already expressed by a necessary action and never interprets
beyond it. Opened does not mean read; selected does not mean supporting;
modified does not mean improved; Settled does not mean true; silence does not
mean acceptance; structurally valid does not mean philosophically sound.

After Analyze, Synthesize, Write, Critique, or another substantive Action, the
agent returns bounded feedback when material. It may report the academic
outcome, what it tried to do, the Materials it actually relied upon, important
uncertainty, missing evidence, access limits, unresolved pressure, method
conflicts, recommended next Actions, and a proposed failure diagnosis. It must
not fabricate a finding to fill a field or write an interpretation of the
researcher's mind as a Scholium-established fact.

A failure proposal remains attributed feedback. The researcher may reply,
question it, request another Action, ignore it, or preserve a lesson in
ordinary Markdown. Scholium creates no Failure object, score, status, form, or
mandatory post-run disposition. It likewise creates no Alternative relation;
researchers express competing paths in their notes, while Set Aside means only
that a note is not currently active.

One finished Discussion or validated nonconversational Action creates one
portable Research Record. Cancelled preparation with no scholarly response
need not create one. The record may contain researcher turns, attributed agent
replies and feedback, participating note identities, Action and exact Skill
revisions, starting and ending revisions, agent-reported actually used
Materials, confirmed changes, discrepancies, and deliberately expressed
researcher responses. It excludes assembled prompts, raw keys, bookmarks,
absolute paths, token counts, transport logs, routine save events, derived
index freshness, window state, and stored diff hunks.

Portable Research Records use schema version 3. Decoding rejects another
schema version or unknown fields without projecting, authorizing, rewriting,
or deleting the underlying file.

Every current Action completion contains a complete Material-use report.
`actuallyUsedMaterialNoteIDs: []` is the Agent's explicit report that no frozen
Material was actually used; omission is invalid, and Scholium never infers an
empty report from selection or silence. Membership remains Agent testimony,
while Scholium validates each reported identity, role, qualified reference,
title, and exact starting revision.

Every portable Action record also preserves whether exact-revision Fidelity
was `not_required`, `completed`, or `unverified`; a Discussion records only
`not_applicable`. `completed` means the required checks ran against the exact
recorded revision, including checks that found issues. It does not mean passed,
true, important, philosophically adequate, improved, or accepted.

Intellectual records live under `.scholium/research-records/v1/` as one file
per record in `active/` or `records/`. Pending requests, grants,
credentials, temporary transport state, and rebuildable indexes remain in
Application Support. Markdown remains authoritative research content; a record
never reconstructs writable source.

The independent **Research Record** utility window is Triptych-scoped and uses
one list row per finished Discussion or completed Action, with a coherent
detail rather than one row per turn. Opening from a note applies a removable
**This Note** filter. Search and filters cover note, date, Skill, Action, and
participant; Pin is explicit. Record titles derive quietly from Action,
context, and date and are not editable.

The detail uses attributed editorial prose, fine rules, restrained context,
and collapsed **Record Details**, not chat bubbles. Line Comments retain only
their revision-bound inclusive line range; no stored passage copy is required
for a Comment or agent handoff. Multi-note context appears
once. Active Discussion
never moves into this window. The toolbar, Research menu, and keyboard route
open the window without revealing or changing Inspector state.

Records are never summarized or deleted automatically. **Delete Record…**
opens a second confirmation, then permanently removes the one underlying record
and its projections from every participant without editing Markdown,
checkpoints, exact-note recovery, or unrelated records. Scholium provides no Record Trash
or Restore workflow for portable records. A diff is computed
only on request from exact retained revisions or checkpoints. If those bytes
cannot be verified, the interface states **Comparison Unavailable**; diff text
or rendered hunks are never permanent record content.

### 8.3 Research Guidance and Skill architecture

**Settings → Research Guidance** uses stable responsibility categories rather
than one flat package list:

1. **Methods** shows the active Working Method for Discuss, Analyze,
   Synthesize, Write, Critique, and Check Fidelity, plus the optional
   Manuscript method. It supports direct editing, disable, replacement,
   comparison, and explicit restore from the bundled reference.
2. **Researcher Skills** shows installed, disabled, invalid, and
   researcher-created packages and their Action Profiles. It owns staged
   installation, creation, editing, validation, Triptych placement, role
   applicability, **Show in Actions**, and ordering. Before first activation,
   its detail view presents a nonexecuting preview of the modular Action sheet
   at regular and narrow widths, including every app-owned Target, revision,
   permission, conflict, and recovery region that the Profile
   cannot hide.
3. **Permissions** owns the Triptych default and deliberate per-Skill
   overrides. Requested capabilities remain visible here but do not become
   authority.
4. **Sources & Integrations** owns source bindings, Zotero, citation methods,
   agent handoff, and the Scholium CLI.
5. **Recovery & Technical** owns settled-version retention, Skill snapshots,
   restore, validation detail, and **Reveal Skills Folder**.

These categories use a restrained native list/detail hierarchy with persistent
selection, succinct rows, semantic grouping, and one detail destination. They
do not become card grids, nested sidebars, dashboards, or a package marketplace.
Task-specific parameters, focal Materials, and write scope stay in the Action
sheet; Settings contains only longer-lived configuration.

Every assisted workflow separates three owners:

```text
Protected Scholium mechanism
        + directly editable Method Skill
        + researcher-owned Action Profile
```

System Skills own protocol, identity, revision, authorization, checkpoint,
conflict, agent change requests, validated completion, record routing, and
recovery. They contain no claim to be the best philosophical method and cannot
be edited, replaced, or shadowed.

Each Triptych installs directly editable Working Method Skills for Discuss,
Analyze, Synthesize, Write, Critique, and Content Fidelity. A bundled read-only
reference remains available only for explicit comparison or restoration. It
is not an active fallback and release updates never overwrite the researcher's
current method. A workflow with a disabled, missing, incompatible, or invalid
active Skill is unavailable with one executable repair route.

Researcher Skills are ordinary bounded packages at
`.scholium/skills/<skill-id>/SKILL.md`. They may contain UTF-8 `SKILL.md` plus
one-level `references/`, `templates/`, and `evals/` regular files. The first
installation contract accepts local directories only and rejects archives,
network installation, executables, scripts, symlinks, path escape, nested
ownership, collisions, malformed metadata, and unsupported resources.

Installation is staged and inspectable. Before an imported package becomes
active, Scholium shows its origin, bounded contents, purpose, applicable roles,
requested capabilities, and proposed Action placement. It installs atomically
and disabled. Enabling remains unavailable until its Profile is structurally
valid and the same detail surface has shown the generated Action-interface
preview; preview never executes the Skill or grants authority. The researcher
then chooses Triptychs, roles, Action Profile, and permission policy. Installing
the same Skill into several Triptychs creates independent snapshots; later
edits do not synchronize silently.

Every save of an active Skill creates an identifiable revision, and each run
records the exact revision and loaded resources. Editing an ordinary research
note never activates it as instruction. A methodology note may inspire a Skill,
but Notes remain research objects and Skills remain methods applied to them.

Action Profiles declare readable roles, focal-input modules, candidate writable
roles and operations, property boundaries, source requirements, feedback, and
review expectations. A declaration can narrow what Scholium may grant but can
never enlarge application hard limits. Enlarging a previously approved Profile
or Skill envelope invalidates its machine-local approval until the researcher
confirms the new digest.

Bundled philosophical Method Skills must preserve evidential layers; separate
source-explicit claims, reconstruction, charitable repair, and agent criticism;
distinguish concepts, definitions, premises, conclusions, objections, replies,
concessions, and background; preserve material uncertainty and competing
possibilities; and avoid forced findings. Analyze reconstructs before critical
pressure. Synthesize updates a conceptual home only when material genuinely
adds, corrects, qualifies, or reopens it. Critique distinguishes exposition,
argument, objection, reply, and researcher commitment. These are method-quality
requirements for Scholium's defaults, not certification that any method is
philosophically best or that an agent followed it.

Structural validation establishes only bounded identity, compatibility,
resources, and declared capability. It never certifies truth, source support,
philosophical quality, or researcher endorsement. Sharing, inheritance,
automated evolution, executable plugins, nested Practices, and a marketplace
remain outside this contract.

### 8.4 Permission, preparation, completion, and Fidelity

Read capability, focal context, and write authority remain separate. Read
capability defines what an agent may inspect through a mediated handoff; focal
context identifies the note, passage, Comment, or Materials that deserve
attention; write authority is the exact validated note set for one phase.
A researcher may allow Triptych-wide reading within an approved Skill envelope
without selecting every note as focal context. That does not grant write
authority or prove that every readable note was consulted.

Bootstrap adopts **Ask Me Every Time** without requiring an abstract setup
choice and states that the researcher can change the policy later for each
Triptych or Skill in Research Guidance. Permissions offers:

1. **Ask Me Every Time**;
2. **Ask Me Only for Works**; and
3. **Triptych-wide**.

A deliberate per-Skill override replaces the Triptych default only for runs of
that exact approved Skill/Profile digest. When no stored override exists because
none was configured or the researcher deliberately removed it, the Triptych
default applies. A stored override whose digest no longer matches does not fall
through to a potentially broader Triptych default: **Ask Me Every Time**
applies until the researcher reviews the change and explicitly renews or removes
the override. These are machine-local policies that decide whether Scholium
may issue one bounded grant without another sheet; they are not reusable bearer
tokens:

- **Ask Me Every Time** requires a decision for every agent-requested
  additional note change or write-capable child phase.
- **Ask Me Only for Works** may grant a qualifying Analysis or Topic request
  without a sheet when it remains inside the exact approved envelope, but any
  request to change a Work or begin a Work-writing child phase requires a
  decision.
- **Triptych-wide** may grant a qualifying request inside the current Triptych
  without a sheet only when every requested note, role, operation, identity,
  revision, Skill/Profile digest, and source requirement remains inside the
  approved envelope.

Clicking a current Action already authorizes the clearly displayed initial
Target and does not trigger a redundant second prompt. Standing policy governs
agent-requested additional notes, expanded write scope, or a new child phase.
Silence, an expired decision, and an unmatched policy grant nothing. No policy
overrides the hard limits below.

Effective authority is the intersection of application hard limits,
machine-local policy, Skill declaration, approved Action Profile envelope, the
concrete request, and current validated identities and revisions. Destructive
lifecycle operations, out-of-Triptych writes, record edits, unsupported create,
delete, rename, or conflict overwrite never become silently authorized.

One application-level coordinator owns Action availability, preparation,
completion, cancellation, and Fidelity. Preparation resolves Origin and exact revision,
validates source access and focal Materials, resolves the exact Method Skill
and Profile, creates recovery evidence, freezes the write set, rechecks every
revision, and rolls back partial preparation. Discuss and Settle use separate
typed authorities and no write packet.

After preparation succeeds, each write-capable phase receives a
cryptographically random short-lived completion key bound to the Triptych, run,
Action, Skill/Profile revisions, frozen note identities, roles, operations,
and expiry. Only its digest persists. Completion, cancellation, revocation, or
expiry invalidates it. An identical repeated completion is idempotent; a
different payload fails closed.

The agent reports candidate modified identities. Scholium normalizes paths,
rejects traversal, symlink escape, role mismatch, identity substitution,
out-of-scope files, unsupported lifecycle state, and unauthorized creation,
deletion, or rename. The Application derives confirmed modified, unmodified,
and unreported sets from frozen and current fingerprints, performs readback,
and records only validated source changes. A discrepancy is a narrow
Scholium-established fact, never evidence of intellectual improvement or
failure.

An agent that identifies additional necessary Targets may submit one typed
change request for the current parent run. The request contains stable
Triptych/run/Skill/Profile identities, proposed note identities and expected
revisions, requested Action or operation, and an agent-authored reason. The
protected local bridge carries the request into the running app; the external
agent neither draws nor automates the interface.

When policy requires a decision, Scholium presents one native sheet in the
exact Triptych window with **Allow These Notes Once**, subset selection,
**Continue Without Changes**, and **Cancel the Run**. There is no redundant
Deny action. Before resolving, Scholium flushes and revalidates policy, Skill,
Profile, roles, lifecycle, identities, and revisions. Silence is never
permission. If Scholium is closed or live state cannot be validated, the tool
returns unavailable rather than inventing authority.

A frozen parent snapshot or grant is never widened. Allowance creates an
independent child phase with its own snapshot, exact-note recovery, grant,
completion, Fidelity, and lineage. Analyze may therefore request a separately bounded
Synthesize phase; Critique may lead to Write; optional Manuscript coordinates
only explicitly permitted children. The external conversation may continue,
but Scholium preserves each scholarly and authority boundary.

The Core Skill and Triptych guidance explain this cooperative request protocol
and instruct compatible agents not to transmit Works content to an additional
external service, upload destination, or web query without explicit researcher
instruction. Scholium does not host, stream, monitor, or police an external
agent. A direct external Markdown edit is an ordinary concurrent filesystem
event, not a permission-system failure.

Manual and automatic Check Fidelity share exact-revision evidence validation.
A multi-target check retains a distinct result for every note revision and
never collapses mixed outcomes into one verdict. Missing evidence leaves the
phase Awaiting or Unverified; later source changes make the result Stale.
Discuss and Critique do not inherit a write Fidelity result, and Fidelity never
certifies truth, researcher acceptance, or that an agent followed a method.

### 8.5 External edits and conflicts

A clean open note refreshes quietly after an external change. If the local
buffer is dirty, Scholium retains it and presents conflict instead of
overwriting either version.

Before replacing an existing research file, Scholium must durably retain the
expected and candidate bytes and use a volume-supported commit mechanism that
can preserve and verify the displaced file. If that boundary is unavailable or
the observed displaced bytes differ, the mutation fails closed, retains every
available version for recovery, and never reports **Saved**.

## 9. Analyses workflow

1. Create or import one source-facing Analysis and bind one exact readable
   source: a specific Zotero attachment resolved through explicit source
   access, or a researcher-selected local regular file. A Zotero item identity
   may supplement this with bibliographic metadata but is not itself source
   access.
2. Use **Analyze** when agent assistance is useful. The same Action populates
   an initial Analysis or reopens the current source and Analysis revisions to
   extend, correct, clarify, reorganize, or leave warranted content unchanged.
3. Analyze reconstructs the source before critical pressure. It distinguishes
   source-explicit claims, reconstruction, charitable repair, and agent
   criticism; it may clarify rival definitions, formulate an objection,
   consider the strongest reply, and report residual pressure without forcing
   a weakness.
4. If the source cannot be reopened, Analyze reports a bounded access failure
   and cannot simulate source analysis from the Analysis note alone.
5. Add direct Markdown or passage Comments through Discussion, use Check
   Fidelity for the exact revision, and let the researcher decide whether any
   Topic or Work should change.

Analyze's required source access is satisfied only by a specific readable
source: an exact Zotero attachment identity resolved through the explicit
source-access route, or a researcher-selected local regular file with a
security-scoped bookmark and fingerprint. A Zotero item identity alone provides
only the non-evidential bibliographic context in §15.2 and never satisfies this
requirement. Missing item metadata remains a nonblocking integration warning;
a missing, changed, unreadable, nonregular, symlinked, or unauthorized required
source blocks Analyze with one repair route. Bookmarks, absolute paths, and
source bytes remain machine-local. Portable configuration and records retain
only stable source identity, fingerprint, route kind, and a display label.

For a long source, maintain one source-level Analysis by default. Each session
declares a bounded unit and applies required orientation, analysis, and synthesis
passes. Expand Research Unit only to material actually represented and record
unread, excluded, unreliable, or incompletely analyzed material as
Limitations. Chapter sections need not become separate Analyses. Create a
separate Analysis only by researcher request or when a segment needs an
independently citable identity. `complete` means complete for the declared
unit; **Entire source** requires source-wide analysis.

## 10. Topics workflow

1. Create or update a Topic from Analyses, accessible sources, and other
   reliable information actually used, preserving disagreement, limitations,
   and uncertainty.
2. Use **Discuss** to clarify concepts, objections, replies, and unresolved
   alternatives without source mutation.
3. Use **Synthesize** to integrate warranted material into the current Topic.
   Reading multiple Materials is ordinary context assembly; there is no
   Multi-note mode. The current Topic is the initial write Target.
4. Additional Topic Targets require applicable standing authority or a
   validated agent change request and become independent child Synthesize
   phases.
5. Use Check Fidelity for the exact resulting revision and let the researcher
   decide whether other notes need attention.

Topic development remains within Discussion rather than a separate Develop
Action. When the researcher asks to incorporate a result, or the agent requests
and receives authority, a child Synthesize phase retains the Discussion context
while keeping its own snapshot, grant, exact-note recovery, completion, and
Fidelity.

Scholium never auto-merges an Analysis into Topics. It may report relevant
material, but selected context, neutral links, and transitive Connect paths
establish neither use nor support. Read-only critical exchange belongs to
Discuss; formal Critique remains Work-only.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers may scaffold, write, revise, and organize Works directly. Agents
may do so through **Write** when instructed, but Critique remains visibly
separate and optional. Critique assesses without modifying the target Work;
any resulting source change requires a separately authorized Write child.
Manuscript is an optional hidden Method Skill that coordinates only isolated,
independently authorized phases and grants no submission authority.

### 11.2 Critique target and storage

- A Critique targets one Work; broader reflection uses Discussion with optional
  focal notes.
- Each Work has at most one current Critique document. Later rounds update it;
  prior rounds and deliberately expressed researcher responses remain in
  Research Record without restore semantics or a formal approval disposition.
- Critiques are recognized only in the designated `Critiques/` area.
- Bodies are read-only in Scholium, but files remain externally editable and
  may be renamed or moved within Critiques, Set Aside, restored, trashed, or
  revealed.

### 11.3 Critique Action

Critique uses the current whole Work or selected passage context, includes
applicable Discussion anchors, and accepts an optional focus or disciplinary
lens. A current selection defaults
to Passage. Whole evaluates important claims, premises, arguments, sources,
objections, and alternatives against selected Analyses and Topics; this is an
attributed assessment, not an automatic diagnostic. Passage stays bounded
unless the researcher broadens it.

The Action uses the Triptych's active Critique Method Skill without one-run
technical-instruction editing. **Edit Critique Method…** opens **Settings →
Research Guidance → Methods → Critique**, where the directly editable method,
validation, comparison, and bundled restore belong.

### 11.4 Critique form

Default sections are Overall Assessment; Strengths; Major Concerns; Source
Support; Objections and Alternatives; Revision Priorities; Specific Findings;
and Materials Consulted and Limitations. Findings may be **Traced**,
**Untraced**, **Disputed**, or **Beyond Sources**—agent judgments, never
Scholium statuses or Work qualification.

Each specific finding records Work identity and fingerprint, heading when
available, original line, and a short quotation. Selecting it opens the target
passage; a fingerprint mismatch marks an earlier version. Work overlays remain
deferred until Comment anchoring is reliable.

## 12. Connect and Connection syntax

| Markdown in A | Meaning |
| --- | --- |
| `[[B]]` | neutral, undirected A—B |
| `+[[B]]` | A supports B |
| `-[[B]]` | A opposes B |
| `?[[B]]` | undirected incompatibility A—B |

`+` and `-` describe the containing Note's stance toward the target: support
is favorable argumentative direction, while opposition is an authored
negative stance without a claim of strict contradiction. `?` instead records
one mutual incompatibility: both Notes cannot be retained together in the
researcher's current account, without asserting which should be rejected or
that either is false. None certifies that the relation succeeds, counts as
evidence, or is accepted beyond its explicit authoring. The inverse phrases
**Supports This Note** and **Opposes This Note** are derived only when the
current Note is the object; incompatibility has no direction or inverse label.

These are the only Vector-Link forms. Aliases, headings, and fragments remain
valid. Scholium has no reverse-support or directed-question relation. Preserve
research-file bytes and never rewrite or reinterpret a marker through
heuristics. Never infer support, opposition, or incompatibility from keywords,
proximity, folders, or multi-hop paths. Incoming and Outgoing views show
direction and exact source without permanent badge clutter.

## 13. Search and Attention

One Search field has exactly three scopes:

- **This Note**: occurrences in the open note;
- **This Vault**: the selected Analyses, Topics, or Works vault;
- **Triptych**: all three vaults.

There is no All Workspace, Selected Roles, separate in-note Find, advanced
Search workspace, Quick Open, Recents, or Back/Forward history. Exact title,
alias, filename, and path matches rank above body matches, so Search also owns
known-note navigation. Library, Document tabs, and windows support ordinary or
parallel navigation.

Search is a centered, compact Spotlight-style command surface. Scope is visible
before typing; empty Search shows no results sheet. Text expands a bounded
native result list vertically, not into a workspace-scale panel. It follows
appearance and accessibility settings without copying Spotlight categories or
Finder actions. Opening Search does not dim, tint, or blur the retained
workspace or native toolbar. A transparent outside-click target may cover the
workspace content; the opaque Search surface, focus, boundary, and restrained
elevation establish its foreground hierarchy.

The transient keyboard or pointer result target is not document selection. It
uses one full-width warm opaque row with a narrow accent leading rule, exposes
the native selected accessibility trait, and retains native scrolling, focus,
and keyboard mechanics. Search never layers a partial dark system-selection
slab behind only part of a result row.

Each window remembers its ordinary scope. `Command-F` requires an open note and
temporarily selects **This Note**. Dismissal restores the prior scope unless the
researcher explicitly changed it, cancels work, rejects stale results, and
clears query/results while retaining scope and saved searches.

Beta Search uses one deterministic local SQLite FTS5 corpus for
the active Triptych. **This Vault** is a predicate over that corpus and
**Triptych** uses it without a vault predicate, so BM25 statistics remain
comparable across Analyses, Topics, and Works. **This Note** instead searches
the current editor's exact in-memory revision and returns one row per
non-overlapping occurrence after the complete query is satisfied; invoking
Search never saves or indexes that buffer. Vault and Triptych results remain
one row per active note. Set Aside and Trash are excluded from the persisted
corpus but remain searchable while they are the open **This Note**.

The finite expert syntax is space-as-AND, escaped exact phrases, trailing
prefix `*`, clause exclusion, lexical fields `title`, `alias`, `heading`,
`body`, `author`, `year`, `tag`, `footnote`, and `path`, and structured fields
`callout` and `has:broken-link`. Structured filter-only queries are valid. A
query containing only excluded free text is invalid. `status` produces an
explicit unsupported-field diagnostic because it is not a Scholium property.
Unknown fields or canonical values, `vault`, `role`, or `metadata` fields,
malformed escapes, CJK prefix `*`, and unsupported OR, grouping, NEAR,
regular-expression, fuzzy, range, or nested syntax produce an inline query
diagnostic and never silently broaden retrieval. Scope is selected only by the
visible interface or CLI option.

Search indexes only visible semantic text and derived identity/filter fields,
never raw Markdown source or link destinations. Title, alias, heading, author,
year, tag, path, canonical callout, footnote, and residual body text are
separate projections; the same heading, callout, or footnote content is not
also weighted as body. Links contribute displayed text and images contribute
alt text. Source mappings preserve exact UTF-16 ranges through Unicode
normalization. Production CJK retrieval uses the same deterministic
character-and-overlapping-bigram projection at index and query time, followed
by contiguous-substring verification; Apple language tokenization is not a
persisted Search contract.

Complete normalized title, alias, filename stem, and relative-path identity
precede one-corpus BM25, then normalized title, fixed Analyses/Topics/Works
order, and normalized path break ties. Exact identity candidates come directly
from ordinary tables and cannot be lost to a lexical candidate cutoff. Public
results explain matched field and rank reason without exposing raw BM25. The
interface caps at 100 rows and reports only `N Results` or `N+ Results`; Search
does not perform an expensive exact total count.

Each response binds a versioned query contract, Triptych generation, sorted
source-manifest hash, source fingerprint or editor revision, and freshness
token. A stale result must refresh rather than navigate. Building, refreshing,
stale, failed, and query-invalid are distinct states; cancellation is not a
failure. A failed routine refresh continues serving the last complete
generation, while a first or incompatible build never serves results from a
different ranking contract. One generation publishes atomically or not at
all and its disposable index stores no writable research authority.

An exact Topic match may show its direct resolved Connections in a separately
loaded **Related** section only when its graph manifest matches the lexical
manifest. Related failure never removes lexical results; relations neither
alter ranking nor imply evidence and never expand transitively here. Vector
search, embeddings, AI query interpretation/ranking, and chat-style Search are
excluded. **Vector-Link** means only researcher-authored relation markers.

Attention may report possible-orphan conditions, Changed Since Settled, Broken
Connections, malformed metadata, unresolved identity, or **Material Changed
Since Use**. The latter requires one completed Synthesize record whose
agent-reported actually used Analysis set and exact recorded revision were
validated; selecting a Material is insufficient. If that Analysis later
changes, Attention may offer **Inspect**, **Resynthesize**, and **Leave
Unchanged**. Dismissal binds the material identity and revision pair, so a later
change may appear again.

Attention never says the Topic is wrong, outdated, or Superseded; uses age
alone; or issues an automatic philosophical verdict. Warnings are dismissible;
Settings controls duration, default seven days. The researcher retains
judgment.

## 14. Checkpoints, versions, and recovery

Autosaves create no visible versions. Current Actions create no automatic
whole-Triptych checkpoint. The researcher may choose **Create Checkpoint…** at
any time when a self-contained Triptych milestone is genuinely useful.

Every checkpoint is self-contained; includes all vaults and portable control
state needed to interpret them; lives outside the vaults; and never depends on
another checkpoint, even if filesystem cloning is used internally. Manual
checkpoints remain until the researcher deletes them.

File offers **Create Checkpoint…**, **Restore from Checkpoint…**, and **Reveal
Checkpoints in Finder**. Restore compares created, changed, moved, and deleted
files and supports selected-note or whole-Triptych restore. A full rollback
moves post-checkpoint files to Trash instead of permanently deleting them.
Restore writes new current source through the conflict-aware repository path;
Undo remains editor-session only.

There is no checkpoint-management screen or proprietary backup format. Finder
manages folders. Document, HTML, PDF, and DOCX export is deferred, not
permanently prohibited.

Invisible pre-write recovery state supports exact save/conflict recovery for
the Notes actually written; it is not an application-authored account of the
research. Settle may pin an exact entry as a researcher-selected settled
version without turning it into a truth claim. Temporary write recovery and
settled-version retention remain separate references over verified immutable
bytes. Invalid recovery metadata must not cause unrelated recoverable bytes to
be deleted or silently attributed to a note. Durable settled-pin
manifests, not the derived SQLite row, own pin identity and ordering; a missing
or field-mismatched row is rebuilt only from a fully validated manifest. Pin
order allocation is coordinated across local processes. If a validated
manifest cannot be projected unambiguously, its exact bytes remain protected
and automatic cleanup stops until the recovery authority is repaired.

## 15. Zotero integration

### 15.1 Local read-only API

The optional built-in integration reads Zotero through its localhost API; it
uses neither an online Web API credential nor a researcher-deployed server.
Its absence blocks no core workflow.

**Settings → Integrations → Zotero** shows connection status, **Open Zotero**,
one **Check Connection** action, **Clear Connection History**, last successful
time, and a concise local/read-only privacy statement.
When disabled, direct the researcher to **Allow other applications on this
computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Protected Analysis task context

`zotero_item_key` is an Analysis-only protected-machine field. It is absent
from About and ordinary Properties. Scholium has no **Create Analysis from
Zotero**, matching, comparison, confirmation, or metadata-overwrite flow. Only
a protected machine or authorized agent mutation may write the key through the
current-fingerprint boundary.

When the current Analysis has a valid normalized key, Overview exposes one quiet
**Open in Zotero** action that opens that exact item in Zotero Desktop. The
action displays neither the key nor fetched Zotero metadata, performs no
matching or confirmation, and is absent for Topics, Works, and Analyses without
a valid key.

When Analyze or another eligible Analysis Action begins preparation with a
non-empty key,
Application performs one exact local item read and automatically attaches the
catalogued `scholium-zotero-integration` System Skill. The immutable Action
snapshot is labelled **Zotero bibliographic metadata** and may carry item key,
item type, title, complete creator roles, date/year, language, container,
volume, issue, pages, edition, series, publisher, place, DOI, ISBN, ISSN,
citation key, URL, abstract, tags, Collections, and modification time.

The same run reuses that snapshot when resumed; every new run reads Zotero
again. No metadata cache crosses tasks. Unavailable Zotero, a missing item, or
an invalid response adds one nonblocking warning and never prevents the agent
from continuing with available evidence or leaving unnecessary fields absent.
No key and non-Analysis targets perform no read and emit no Zotero warning.

Task metadata is never written into Markdown or displayed in Inspector.
Abstract, tags, and Collections remain bibliographic metadata, never paper
content or philosophical evidence. Attachments, Zotero Notes, annotations,
PDFs, and full text never enter automatic context. Built-in integration never
changes Zotero data, files, or live SQLite.

### 15.3 Recommended Bibliography

One Triptych-wide **Recommended Bibliography** utility is fixed at the
Sidebar bottom outside Library's Scope-, Location-, selection-, filter-, and
source-list ownership. It remains in the same position when Analyses, Topics,
Works, Library, Set Aside, or Trash changes, and only a Triptych change changes
its research boundary. Its compact band uses the heading, fixed sibling
position, structural boundary, and **Triptych Recommended Bibliography**
accessibility group to express that ownership; it adds no explanatory subcopy.
The complete band is one button: its heading row shows the nonzero count and a
quiet forward chevron, while the second row shows **No recommendations** or one
static `Author, Year, Title` preview. It contains no compact horizontal list,
individual candidate action, or diagonal-open glyph. Activating any part of the
band opens the complete researcher-facing surface for handling agent-
recommended literature. It is not Library content, a vault projection, a
Research Action, Inspector launcher, note appendix, Zotero write path, or
evidence store.

Optional goals are Background Reading, Core Positions, Historical
Predecessors, Objections, Replies, Companion Literature, Alternative
Approaches, Missing Citations, Recent Developments, and Classic Works, with an
optional purpose. No selected goal requests neutral source-centred screening.
Source Analyzer is the complete default method; Advanced may bind one compatible
Triptych-local replacement. Broken explicit bindings show Repair and never
silently fall back.

Preparation locks Triptych identity and selected-note fingerprints, snapshots
exact methods/resources, and treats zero candidates as success. The agent
distinguishes reference-list occurrence, in-text citation, substantive
discussion, praise, criticism, centrality, verified metadata, and independent
inspection. Unread candidates receive no Debate Importance or relevance score.

Store the atomic portable projection at
`.scholium/recommended-bibliography.json`. Match by verified scoped Zotero key,
DOI, guarded ISBN, citation key, then exact normalized title + complete author
identity + year. Never auto-merge chapters/books, editions/translations,
conflicting or incomplete authors, or ambiguous titles. A matched Analysis
proves no coverage beyond its Research Unit and evidence.

Rows show title, authors/year, goals, one short reason, and verification/match
state. Actions are **Open Analysis** when a matched Analysis exists and
**Dismiss**. The section provides **Recommend…**, **Copy Instructions**,
**Cancel**, and **Update Recommendations**; preserves prior results on refresh
failure; and distinguishes empty, successful-zero, preparing, awaiting-agent,
stale, malformed, duplicate, ambiguous, Zotero-unavailable, and general error
states through text/symbol plus accessible focus and narrow adaptation.

Recommended Bibliography preparation and completion remain separate from
Research Actions. CLI provides `bibliography prepare`, `show`, `complete`,
and `cancel`; Scholium owns normalization and duplicate discrimination.

### 15.4 Optional external-agent Zotero MCP

Beta also supplies a protected `scholium-zotero-integration` System Skill and a
supported local MCP service or installation route. The skill is an instruction
contract; MCP is transport, not an embedded runtime.

It may report readiness, search, inspect exact metadata and bounded attachment
pointers, identify an import target, and import BibTeX/RIS. A real import needs
an explicit current-task request for the exact record and destination,
successful dry run, tool confirmation, and read-back. Prior reading, search,
analysis, or import grants no standing write permission.

Never read/write Zotero's live SQLite directly, select ambiguous records or
destinations silently, or treat metadata, tags, abstracts, or attachment
identity as evidence. Source analysis remains separately requested; citation
formatting requires an explicit Triptych-local binding. If MCP is unavailable,
report the boundary without global configuration scans or database bypass.

## 16. Onboarding

Before onboarding or workspace restoration, one app-owned bootstrap state is
either **Starting**, **Ready**, or **Storage Unavailable**. Only Ready contains
the validated Application Support location and may construct workspace state
or services. Storage Unavailable replaces the app root with a
nonmodal recoverable failure page; **Retry** is the default action, **Details**
reveals selectable diagnostic text, and **Quit** remains available. New Window,
New Triptych, and all workspace commands stay disabled. Retry performs a fresh
validation and enters the ordinary workspace or onboarding route only after it
succeeds; no temporary or implicit read-only workspace exists in the meantime.

First launch, **New Triptych…**, and missing registration use one narrow
Bootstrap window. It asks one decision at a time—Analyses, Topics, Works, then
bounded authorization beside Works—through standard Open panels. It constructs
no workspace split, toolbar, inert regions, tabs, feature tour, project model,
or explanatory manual.

Bootstrap silently adopts **Ask Me Every Time** for agent-requested additional
note changes and write-capable child phases and states: “Agent changes will ask
for permission every time. You can change this later for each Triptych or Skill
in Research Guidance Settings.” It does not ask the researcher to understand a
permission matrix before opening the workspace.

Failure retains setup input. Success opens one configured workspace and closes
Bootstrap only after that exact workspace route has attached its native window,
split, and toolbar; they never compete. Recoverable Workspace routes restore
directly. The presented Bootstrap default is used only when no
recoverable Workspace exists. Bootstrap starts at **720 × 720**; this is an
initial size, not a minimum. Expired folder access instead uses the workspace's
bounded **Restore Access** sheet and preserves its active document. Settings
**Manage Triptychs…** lists registrations, edits their three locations, creates
another, and opens one in a separate window.

## 17. Permanent boundaries and deferred capabilities

Never add:

- permanent LLM chat, project/task management, plugin marketplace, fourth
  vault, or All Notes mode;
- an embedded agent runtime, agent-reasoning monitor, unrestricted executable
  Skill system, or Proposal approval layer;
- automatic philosophical support, settlement, sufficiency, truth, prose
  authorization, or untraced-premise verdicts;
- Zotero replacement, embedded PDF reader, proprietary backup export, or
  arbitrary Obsidian-theme compatibility; or
- bundled general instructions purporting to teach researchers philosophy.

The researcher-governed Skills contract requires protected System Skills;
directly editable Working Method Skills
for Discuss, Analyze, Synthesize, Write, Critique, and Content Fidelity;
optional hidden Manuscript; declarative Action Profiles; bounded installation;
standing permissions; agent change requests; portable Research Records; and
protected Zotero and agent-tool transports.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; and Work finding overlays.

**Run with Codex** is outside the 1.0 boundary. Background/noninteractive
execution, auto-submission, streamed thread/tool state, general agent-host
approval or interruption control, and App Server or SDK orchestration require
a future product decision. The current typed note-change request does not
broaden into those capabilities, and **Open in Codex** implies none of them.

File-backed Method Skills and Action Profiles are Settings-owned Research
Guidance, not a marketplace, runtime, specialized request taxonomy, or
philosophical authority. Finder remains authoritative for Markdown,
attachments, and checkpoint folders; Zotero for bibliography/PDFs; external
agents for optional open-ended work.

Scholium defines no separate durable research-handoff packet or ontology.
Analyses, Topics, Works, and researcher-authored Markdown remain the durable
research context; a researcher may create an ordinary Markdown handoff note if
useful. An Action may assemble a bounded transient external-agent handoff from
authorized inputs, but the assembly is neither an additional research object
nor portable Research Record content.

## 18. Canonical interface contract

Sections 1–17 own scholarly and product meaning. This section defines its
native presentation and state ownership without restating each workflow.

### 18.1 Interface principles

- Keep Document the largest, most stable region; navigation, Properties,
  research context, diagnostics, and agent assistance remain subordinate.
- Prefer native macOS windows, split views, inspectors, toolbars, menus, sheets,
  alerts, file panels, controls, selection, and focus. Custom presentation must
  preserve equivalent menu, keyboard, accessibility, cancel, and recovery.
- Give every mutable fact one owner. Route commands to the focused window or
  document; identities, repositories, indexes, watchers, and registries are
  shared workspace services, not view state.
- Derive Review, Edit, Source, Properties, Search, and research views
  reversibly from authoritative Markdown; projections never reconstruct
  writable source.
- Distinguish source, researcher prose, agent content, Discussion turns,
  Action output, Settle, Critique, Connect, and diagnostics by text and
  structure, not color alone.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancel,
  compare, retry, conflict, and recovery routes. Hover, drag, color, motion,
  secondary click, and gestures are never the only route to a core task.
- Gate all workspace composition behind the single Application Support
  bootstrap owner. A storage failure is an app-root state, not a workspace
  sheet, alert loop, hidden temporary runtime, or view-local fallback.

### 18.2 Workspace shell and Document tabs

The configured shell exists only after Application Support reaches Ready.
While storage is unavailable, no workspace route, window session, repository,
watcher, index, or restore task may be constructed, and workspace commands are
disabled rather than queued against a hidden runtime.

Each configured window contains exactly one native split view with three
sibling items:

1. **Sidebar:** a Library navigation region containing Scholium and Triptych
   identity; one quiet equal-column **Analyses / Topics / Works** ScopeIndex
   with no Attention statistics; one conditional current-Scope Attention alert;
   one title-style LocationPicker for **Library**, **Set
   Aside**, and **Trash**; one active location-owned source region; and
   Library-local Filter and Add. A fixed Triptych-wide Recommended
   Bibliography utility is its sibling below the Library source region.
   Settings is not a Library destination.
2. **Document:** selected note or the text-free semantic background.
3. **Apparatus:** Research Inspector's read-only Overview, Connect, and Actions
   projections. It never owns buffers, autosave, Undo, or conflicts;
   full chronology belongs to Research Record.

The workspace starts at **1180 × 760**, not a minimum. Scene state owns route
identity and restoration; the native window and split controller own divider,
compression, collapse, fullscreen, and frame geometry. Scholium never
persists, restores, observes, or continuously reasserts divider geometry. The only additional
initial condition is that a newly created window's first explicit Apparatus
reveal may request a provisional **320pt** readable thickness once, after the
native split is attached. That request yields to the remaining Document space
and native bounds; it is not a minimum, maximum, restored divider value, or
later-reveal preference. After that one transition, the native container and
direct user resizing remain authoritative. Scholium declares no scene/window minimum
unless the complete adaptation matrix proves one necessary. The sole specified
content constraint is the expanded Library's **300pt minimum readable
thickness**: the native split must keep it at or above that boundary or
collapse it. This is neither a preferred width, restored divider value, nor parallel
geometry owner. Library remains a semantic Sidebar and Apparatus a semantic
Inspector. All three planes are opaque, and the native tracking separator is
the sole inter-pane boundary; Scholium draws no parallel main divider or
shadow.

New windows show Library and hide Apparatus. Initial or restored peripheral
visibility is installed before the native split's first presentation; the
window never draws an expanded Apparatus and then retracts it during launch.
Restore applies both visibility values once; then native collapsed state is authoritative and the model only
mirrors Library and Apparatus visibility for labels, commands, and the next
session. Menu, toolbar, and content actions send explicit per-window intents to
the native controller; model observation never continuously reasserts split
state. Notes/tabs never reconstruct the shell or change peripheral
visibility/mode. Library Scope and Location are per-window presentation state,
not Note, vault, or Markdown facts. Switching Scope preserves the selected
Location and reloads that Location under the new Scope without replacing the
open Document. A new window's first Inspector reveal selects Overview. Each
window restores its own last Inspector mode; changing notes, Document tabs, or
document presentation mode never changes it.

The native titlebar owns traffic-light, drag, and height geometry. Its one
toolbar belongs to Document and exists inert from the first configured frame;
loading may replace items but not move traffic lights or change band height.
Opaque regions extend beneath it, and controls use the live safe area rather
than a measured toolbar height.

Visible Library and Apparatus own pane-local Hide controls. On collapse, that
route leaves with the pane and one borderless Show control enters the Document
toolbar; expansion reverses the transfer. Native collapsed state governs the
reconciliation, which must leave exactly one route without rebuilding the
shell. Tracking separators remain structural bounds. Add no split-item
accessory row, custom title strip, Inspector replacement, ellipsis, fixed
height, automatic glass-like item, or Liquid Glass.

Attention never enters the Document toolbar. While Sidebar is visible, its
conditional current-Scope alert is the only workspace-chrome signal;
collapsing Sidebar removes that signal without transferring a count, symbol,
reserved gap, or popover anchor. Inspector retains its distinct current-Note
summary. **Window → Attention** is enabled only when the focused Workspace has
a visible Sidebar alert or Inspector summary capable of anchoring the transient
popover; otherwise showing Sidebar restores the contextual route.

If needed, the collapsed Inspector's Show control and View command may send one
explicit intent through the exact window coordinator to the native split.
The Inspector routes share selected-document availability and preserve native
transition and geometry. Collapsed-Inspector Show remains visible but disabled
without a Target; a visible Inspector can always be hidden. Research Record is
Triptych-scoped and remains available in every configured workspace; opening it
with a Target applies the removable **This Note** filter.

With two or more documents, a Document-owned strip appears only in the middle
item. Each tab references one retained editor session. The native tab
controller owns containment; Scholium supplies equal-width selection
and save-before-transition. One stable document has at most one tab in a
window; repeated open or **Open in New Tab** selects that tab in place. Close
flushes and selects a retained neighbor; last close returns no-note. Tabs
create no window group, parallel state, or toolbar owner. Prototype styling
has no authority; selector styling is provisional.

Window close, route handoff, and application termination are bounded. A
content flush, save, or conflict failure keeps the affected window and exact
buffer available with a retry path. Machine-local window-session or layout
persistence is best-effort after content is safe; its failure is diagnosed but
does not veto close or misreport a source-save failure. Late lifecycle work may
not act on a newer route, window, document, or close attempt.

The Library BrandHeader sits below window controls. A static Scholium wordmark
and a separate Triptych identity menu share the 28pt peripheral page edge;
Triptych management never turns the wordmark into a second toolbar. Traffic-
light alignment is visual reference only, never derived geometry. No-note is
text/action-free and VoiceOver-hidden. No Collapse Note, custom `<<`,
Back/Forward, Recents, or Quick Open exists.

Menus follow researcher tasks:

- **File:** Triptych/window create/open; direct **New Note** at the focused
  vault root; Import; Duplicate; Move/Rename; Reveal; Checkpoint create/restore.
- **Edit:** editing and **Edit Properties…**.
- **View:** Search, document mode/text size, Sidebar, Research Inspector.
- **Window:** standard window navigation plus **Attention**. The command is
  enabled only when the focused Workspace has a visible Sidebar or Inspector
  Attention anchor, and opens that anchor's transient popover.
- **Research:** role-valid Actions and **Show Research Record**, never
  Attention or Checkpoints.
- **Settings:** Triptychs, Property profiles, Research Guidance, Attention,
  Zotero, and Appearance.

### 18.3 Library and Search

- The ScopeIndex is Library's only horizontal index. Analyses, Topics, and
  Works occupy three equal columns, with each label centered and the selected
  item marked by a provisional **18pt × 1pt** Accent underline. It has no
  capsule, shared backing plate, enclosing border, or full-width rule. The
  group exposes selection, follows reading direction for Left/Right Arrow, and
  lets Tab continue into Library content without pointer activation creating a
  keyboard-only focus ring. Scope labels expose no Attention count visually or
  accessibly; Attention state belongs to the conditional current-Scope alert or
  the current-Note Inspector summary.
- One native **Filter** menu groups Integrity, Metadata, Properties, Order, and
  Actions with at most one submenu level. Its icon-only entry hides the
  redundant outer menu indicator; native submenu chevrons remain. Current
  Library rows and filters have no Review, Unreviewed, Qualified, or
  Unqualified state.
- Notes outside folders appear at vault root as ordinary Library rows.
- Folder/note rows form one hierarchy at one semantic callout size and a
  provisional **28pt minimum** rhythm that grows rather than clips when text
  requires it. Folder and unselected Note titles use Regular; only the selected
  Note uses Semibold. Use color, indentation, symbols, and this restrained
  selection weight—not size or permanent Folder emphasis. One leading semantic
  slot contains either a folder disclosure or a Note symbol; a folder never
  repeats both disclosure and folder icon. Notes are one line without sublines,
  use middle truncation for the Beta, and expose full titles through pointer
  help and accessibility names. The Beta adds no custom marquee, fade-mask
  reveal, or scroll-linked title motion. At most one redundant
  state mark precedes title; selected, focused, disclosed, drop-target, and
  inactive-selected remain distinct, and selection stays visible off-focus.
- When Library is selected, the LocationHeader Add button directly creates at
  the current vault root.
  Every ordinary folder row offers direct **New Note** and **New Folder**, then
  **Rename Folder…**, **Move Folder…**, conditional subtree expansion/collapse,
  Copy Relative Path, Reveal in Finder, and destructive **Move Folder and Notes
  to Trash…**. Equivalent accessibility actions provide non-secondary-click
  routes. Neither creation action opens a sheet. Library enumerates empty real
  directories. Protected machine-managed folders and ambiguous
  projections retain only safe nonmutating navigation.
- The Library Location shows no total. Attention treats zero as the steady
  state, **1–3** unresolved items as its primary design condition, and larger
  queues as exceptional accumulation rather than a separate mode or hard cap.
  When the selected Scope's last trustworthy count is zero, Sidebar contains
  no Attention row, reserved gap, visible zero, or accessibility target. When
  the count is nonzero, one full-width **ATTENTION** alert appears after
  ScopeIndex and before LocationHeader on the **28pt** peripheral page edge.
  Its warning symbol, exact count, and persistent raised Navigation surface
  make the condition prominent without relying on color alone. It has no
  leading selection rule or other decorative Accent boundary.
  It neither auto-opens, steals focus, pulses, nor repeats attention-seeking
  motion. The complete alert opens a native transient Attention popover from
  itself and never becomes selected Library content. Inspector may open the
  same Workspace-owned queue from its current-Note summary. Attention is not a Location:
  opening it leaves the selected Location, source content, Document, and
  Sidebar selection unchanged.
- Refresh preserves the last trustworthy per-Scope counts and the corresponding
  current-Scope alert while Sidebar is visible. A first load with no trustworthy result never
  claims zero. If it fails, the alert position shows a distinct non-counting
  **Attention Unavailable** state with Retry rather than hiding a potentially
  urgent condition. Resolving or dismissing the final item removes the alert;
  if that disappearing control owns keyboard focus, focus moves to
  LocationPicker. No reassurance row replaces it.
- Attention is one native transient popover owned by the exact
  Workspace window, never an application-wide Scene, sheet, inline destination,
  custom panel, or always-on-top surface. Its preferred bounded content size is
  **420 × 480pt**. Sidebar alert and Inspector summary each anchor the same
  Workspace-owned queue to their complete trigger.
  Native transient behavior dismisses it after outside activation or Escape;
  opening a Note or Resynthesize also dismisses it. It has no custom or manual
  close control. Dismissing and reopening within the same Workspace may retain
  its session filter and selection. Activating a different Workspace window
  resets query, kind filter, selected task, and current-Note subset; the
  machine-local dismissal ledger is unaffected. The conditional Sidebar alert
  uses the selected Scope; Inspector entry adds the current Note. Changing Sidebar
  Scope clears that Note subset and switches the queue to the newly selected
  Scope.
- The Attention popover groups **Identity & Metadata** (Change Attribution
  Needed, Malformed Metadata, Unresolved Identity), **Structure & Connections**
  (Possible Orphan, Broken Connection, Ambiguous Connection), and **Revision &
  Reliance** (Changed Since Settled, Material Changed Since Use). Each row shows
  the issue, resolved Note title, locator, and only real available actions.
  Ordinary rows provide Inspect and timed Dismiss. Material Changed Since Use
  retains Inspect, Resynthesize, and Leave Unchanged. Inspect opens the Note in
  the exact owning Workspace without global window search or notification and
  dismisses the popover; its session selection remains available if the same
  Workspace reopens Attention before the task changes.
- Loading retains the popover structure; refreshing, stale, or failed refresh
  retains the last trustworthy list when one exists and exposes status plus
  Retry; failure without a prior result shows a complete error; an empty queue
  shows a quiet completion state. The heading and search/filter controls remain
  top-aligned in ready, loading, empty, stale, and complete-error states; only
  the list or state region below them consumes the remaining height. When
  resolution, refresh, or dismissal removes
  the selected item, focus moves next, previous, then the popover filter/search
  control. Count updates use the same Scope and dismissal ledger as the popover.
- The stable LocationHeader contains one title-style LocationPicker and only
  the actions applicable to the selected Location. Its current title always
  identifies **Library**, **Set Aside**, or **Trash**. Library shows Filter and
  Add; Set Aside and Trash omit those controls instead of retaining disabled
  icon arrays. The header keeps the same position and height while the source
  region changes.
- The LocationPicker is one native menu of three mutually exclusive items.
  Its title presentation is quiet and borderless: it has no enclosing fill,
  bezel, capsule, or custom disclosure glyph, and relies on the menu's one
  native indicator.
  Its selected item uses a checkmark; Set Aside and Trash may show a last-
  complete count as neutral location metadata. Missing, refreshing, or failed
  counts never disable selection or change the selected Location. Opening the
  menu enters its native keyboard order; Arrow keys, Home, End, and Return
  navigate and choose, while Escape closes the menu and restores focus to the
  LocationPicker. Leaving Set Aside or Trash requires choosing Library or
  another Location; there is no parallel Back control, footer toggle, or
  lifecycle tab row.
- Ordinary ScopeIndex and LocationPicker navigation stages the target Source
  List from the latest accepted Workspace snapshot while the last committed
  Scope/Location pair remains intact, then commits the target pair and list
  atomically. It never replaces a trustworthy Source List with a full-page
  Loading state merely because an in-memory projection crosses an asynchronous
  boundary. Loading remains available only when no trustworthy committed
  projection exists or an explicit recovery/refresh owns that state. A staged
  target failure retains the prior pair and content and reports the failure;
  it never presents that target's error under the prior Location title.
- **Set Aside** and **Trash** are same-plane Library Locations, never overlays,
  cards, sheets, or separate Sidebar modes. Selecting one replaces only the
  source-region content; BrandHeader, ScopeIndex, conditional Attention state,
  LocationHeader, and Recommended Bibliography retain their ownership.
  Switching Scope retains the Location and loads its content for the new Scope.
  An empty Location remains selected and shows its own short empty state rather
  than silently returning to Library. At most one Location content subtree
  accepts input or appears in the accessibility tree; an implementation may
  retain inactive presentation solely to preserve disclosure or scroll context
  only while it remains layout-neutral, inert, and accessibility-hidden.
- Library, Set Aside, and Trash empty, loading, and error states are
  page-level Location content: they align to the shared **28pt** peripheral
  edge and begin one **16pt** section step below LocationHeader. They never
  borrow the tighter **12pt** OutlineRow surface inset. Populated Note and
  Folder rows retain that row inset and their existing hierarchy rhythm. An
  initial Library load with no trustworthy projection uses one system
  indeterminate progress indicator and the explicit **Loading Library…** name;
  it does not use a shimmer, skeleton, or moving highlight. Staged replacement
  never places that loading treatment over retained trustworthy content.
- Lifecycle rows reuse the same provisional 28pt minimum OutlineRow rhythm and
  Note semantic slot. A single-line truncated title opens the note in place;
  a trailing **Put Back** control keeps a preferred **28pt** target and remains
  keyboard and VoiceOver reachable without hover. Ordinary lifecycle rows draw
  no separator. After Put Back, Move to Trash, or permanent deletion removes a
  row, focus moves next, previous, then LocationPicker; cancellation or failure
  restores the originating row.
- Compact Recommended Bibliography is an intrinsic-height fixed Sidebar
  utility below and outside the Library source scroll. It is never a Source
  List section, Location, footer navigation control, vault projection, or
  selected Library row. It shares the complete Sidebar's Paper-derived
  `navigationSurface`, uses one
  structural top boundary, and no card, shadow, or fixed numeric height. Its
  complete band is one quiet full-width button with the same raised hover/press
  grammar as other summary rows, not a card or bezel. Its heading row contains
  the nonzero count and a quiet forward chevron; the second row uses the 10pt
  metadata role for **No recommendations** or one static, single-line
  `Author, Year, Title` preview. It has no horizontal candidate scroller or
  compact per-candidate action; the complete list and operations belong to the
  full surface. Use `&` for two authors and first author + `et al.` for three or
  more.
- Debate Importance ordering first requires one exact Debate Scope.
- Shared Search follows Section 13: compact centered surface, always-visible
  scopes, no empty sheet, bounded results that identify match context and
  destination, and deterministic lexical Beta.

### 18.4 Document modes, context, and Properties

Review, Edit, and Source are modes, not tabs, and follow Section 5.1. Ordinary
scrolling space clears initial editor content from chrome. Review owns a
transient Comment bar and its in-place field; Edit owns a separate formatting
bar; Source owns neither. Each disappears when the selection clears, focus
leaves its task, or the document mode changes. The Comment field also
disappears when the researcher cancels or a save is acknowledged.

The two selection surfaces share one restrained component style: an opaque
semantic surface background, the resolved Scholium accent boundary, semantic
text, and the same focus treatment. They consume only resolved roles derived
from Variables and do not introduce independent colors, blur, glass, or
shadow recipes.

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

Subject to the transfer rule in §18.2, Document toolbar order is conditional
Show Sidebar; Heading
Outline and compact identity; mode and Search; Research Record; conditional
Show Inspector. Scholium controls are borderless ink. No second identity row,
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

### 18.5 Contextual research and Actions

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
custom 20pt relationship glyph in a 24pt leading track with a 4pt gap to the
shared title axis; individual Note rows repeat neither symbol, relationship
label, nor count. Support uses mirrored open/fork marks, opposition uses
mirrored terminal/blocking marks, incompatibility uses one undirected pair of
strokes repelling at the center, and neutral uses one quiet undirected
connection. These marks share one restrained semantic text color and never
encode truth, force, or value by hue. Titles wrap. Do not open a second panel
merely to show a title. Preserve source anchors. An empty group retains its
heading and `0` without **None**. Connect shows the same freshness state before
its groups. Stale or failed state keeps the last complete graph readable and
offers a full-row Retry action.

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

### 18.6 Canonical state and action meanings

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

Destructive actions use exactly **Set Aside**, **Move to Trash**, **Put Back**,
**Delete Permanently**, and **Cancel** when applicable.

### 18.7 Simplified Chinese terminology and translation boundary

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
| Move to Trash… | 移至纸篓… |
| Put Back… | 放回… |

The literal `Trash/` directory, paths, stable identifiers, enum/raw values,
and researcher-authored titles remain verbatim and are never translated.

## 19. Scholarly Editorialism and design variables

**Scholarly Editorialism** combines humanist type, editorial hierarchy, warm
opaque surfaces, fine rules, marginal organization, deliberate whitespace, and
restrained color in a contemporary macOS environment—neither antique-book
imitation nor decorative minimalism.

Until sustained Usable Core acceptance, this is semantic direction, not a
pixel gate. Except accessibility, readability, source safety, and native
boundaries, Sections 18–20 metrics remain provisional and cannot override
native behavior, add state owners, or delay the core.

Canonical design system in brief:

- Document remains primary; Sidebar, Document, and Apparatus are distinct,
  opaque structural planes derived from one Paper resolver. The complete
  Sidebar shares one Navigation surface; Apparatus remains a document-adjacent
  margin whose tone is much closer to Document than Navigation.
- System sans organizes interface structure, Alegreya carries readable
  research content, and Victor Mono identifies exact source and revisions.
- Typography, the purpose-named 4pt grid, whitespace, alignment, and semantic
  color establish hierarchy before rules, containers, or elevation.
- Native macOS controls own geometry, focus, selection, menus, sheets, and
  transient presentation. Scholium adds no parallel window or control skin.
- Inspector uses one ModeIndex, section/fact/reading grammar, relationship
  clusters, Action rows, and local state views; ordinary rows and sections are
  borderless by default. Library's canonical target uses one ScopeIndex,
  LocationPicker, and Source List under §18.3.
- Interface copy follows §19.6, and every component carries the applicable
  keyboard, accessibility, localization, appearance, and recovery states from
  §20.

Exploratory documents retain only unresolved proposals. Once a visual recipe
enters this specification and becomes reachable, its implementation evidence
belongs in `IMPLEMENTATION_STATUS.md`, not in a parallel design guide.

### 19.1 No custom glass

Scholium-owned surfaces are opaque. No custom glass, blur, vibrancy,
translucent/material cards, image-behind-glass, large radii, text gradients, or
decorative shadow defines the brand; depth uses tone, spacing, alignment, type,
rules, and restrained elevation.

System chrome, menus, presentations, controls, focus, selection, semantic
Sidebar/Inspector, and tracking separators stay native. Document tabs are
ordinary Document controls, not simulated window tabs. Incidental system
material is not a token.

Research Guidance, Actions, permission sheets, and Research Record use
continuous native planes, textual list/detail structure, editorial hierarchy,
fine rules, alignment, and deliberate whitespace. They do not use per-Skill
cards, colorful category tiles, score badges, agent avatars, chat bubbles,
nested rounded containers, or decorative workflow diagrams. Selection and
consequence remain clear through native state, typography, symbols, and text.

Library Locations and pane-local titlebar controls retain one opaque
navigation plane. Location content neither dims retained content nor floats
above it, and adds no material, reflection, grabber, rounded panel, accessory
row, separately measured bar, shadow, or sheet motion. The LocationPicker's
transient menu remains system-owned rather than becoming a Scholium popover.
Pane-local hosts consume the native safe area once; the titlebar owns vertical
alignment.

The fixed Recommended Bibliography band is a sibling Sidebar utility, not a
Library Location or Source List footer. It shares the complete Sidebar's
Paper-derived Navigation surface; one structural top boundary, fixed position,
heading, and accessible Triptych-scoped group express its ownership without
explanatory subcopy, a card, blur, material, decorative elevation, or an
independent palette. Its named top and bottom insets place the content slightly
above visual centre and preserve a calm bottom edge.

### 19.2 Typography and color

- System sans is interface structure: navigation names, chrome, menus,
  controls, Settings, alerts, section headings, field labels, action names,
  dates, and compact scanning cues. The fixed **Scholium** Alegreya wordmark
  remains the identity exception.
- Library Folder and unselected Note titles use the same 12pt Regular system
  role; only the selected Note uses Semibold. The compact Document-toolbar
  identity uses the 13pt system body role with secondary ink. Recommended
  Bibliography's empty state uses the purpose-named 10pt metadata role with
  secondary ink; a populated compact preview uses the editorial citation role.
- **Alegreya** is for Review/Edit prose and may identify content-derived
  titles, linked research objects, researcher judgments, field values,
  explanations, Scope, Limitations, and other research content when density,
  scaling, and mixed-script fallback remain legible.
- Apparatus text never exceeds the adjacent Document Body at the default
  Appearance. Its interface labels and headings use the quieter semantic text
  roles; its 12pt content values and explanations may use Alegreya, but small
  text still meets §20 contrast and mixed-script legibility requirements.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, paths, stable identifiers, and diffs.
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
  rows. Only the complete top-level list participates in surrounding document
  block spacing. Edit keeps every Markdown paragraph-separator blank line as a
  real, keyboard-addressable exact source line. Its measured line box supplies
  the corresponding Review paragraph gap; Edit does not collapse it or add the
  same gap again to the preceding paragraph. Consecutive authored blank lines
  remain distinct source lines.
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
  Increase Contrast semantic output. The complete Sidebar, including Recommended
  Bibliography, uses one recessive and neutral `navigationSurface`. Inspector's
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

### 19.3 Variable boundary

Keep eight families: Color, Typography, Surfaces, Elevation, Boundaries,
feature Metrics, Motion, and provisional Document Rhythm. Promote only stable
cross-component decisions or critical thresholds. The adaptive grid uses a
bounded **4pt** foundation with a **2pt** optical exception; APIs expose
purpose-named roles, never numbered positions. Invent no numbered opacity,
radius, shadow, border, gradient, or paper scales.

- Interface type roles: identity, section title, row title, metadata, and
  narrowly approved editorial hierarchy. Library exposes purpose-named Folder,
  Note, selected-Note, Attention-alert, bibliography-empty, and
  bibliography-preview roles; the toolbar exposes the compact-identity role.
  These roles may resolve to a shared point
  size but leaf views do not recreate their weights or sizes. Document roles:
  Body,
  `heading(level:)`, Exact Source, Code, Diff, Revision Identity.
- Document Rhythm exposes one machine-local Line width input with the default,
  range, unit, and shared-mode ownership in §18.4. It creates no second
  built-in measure path.
- The Color family exposes only the two approved Accent and Paper inputs.
  Semantic roles are resolver outputs, not additional Variables; components
  consume those roles without owning a palette value.
- Surfaces are opaque semantic planes; dense evidence is quietest and most
  legible.
- The Sidebar Attention alert is one state-derived presentation component, not
  an owner of diagnostics or counts. Zero produces no component. Nonzero combines
  the existing raised Navigation surface, warning symbol, label, and exact
  count; unavailable substitutes complete diagnostic text and Retry. No
  Attention count, aggregate, or anchor is projected into the Document toolbar.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones. Apparatus sections, ordinary rows, and Action rows default to no
  boundary; a consumer must explicitly request a boundary for a named semantic
  distinction.
- Native controls own interaction states. Custom targets prefer **28pt** and
  never fall below **20pt**; this does not redefine native sizes.
- Standard actions use direct SF Symbols. Domain symbols may centralize
  Scholium meaning, but text remains primary.
- Grid roles are optical alignment **2pt**, label/accessory **4pt**, inline
  control **8pt**, nested content **12pt**, section separation **16pt**, and
  region content **20pt**. The two peripheral planes share a separate **28pt**
  page-edge inset; their internal rhythms remain purpose-owned. Fixed
  component anchors remain purpose-owned:
  preferred/minimum custom targets **28/20pt**, Document tab strip **40pt**,
  Action target **44pt**, and region header **48pt**. A general compact
  **24pt** row role does not size Library rows, and Library has no fixed
  lifecycle-footer anchor. Recommended Bibliography's fixed position uses its
  intrinsic content height rather than a footer-height Variable.
- The Library's **300pt minimum readable thickness** is a component-specific
  containment threshold outside the grid, not a spacing role, preferred width,
  or scene minimum.
- Peripheral metrics own the shared **28pt** outer page edge for Library and
  Inspector. Library metrics independently own the
  Library's **12pt** row-surface inset, **28pt** minimum row rhythm, **16pt**
  hierarchy indentation step, **12–14pt** semantic leading slot, **8pt**
  leading-to-title gap, and **18pt × 1pt** ScopeIndex selection underline.
  Ordinary row content begins at the 12pt inset while a selected or pressed
  navigation feedback surface may span the Source List width; the surface does
  not change the content axis. Content headings and principal controls align to
  the shared 28pt page edge. BrandHeader and LocationHeader retain
  intrinsic content-driven height rather than copying a toolbar or
  footer height. These values remain provisional until they pass the 300pt,
  localization, scaling, contrast, and human visual-acceptance matrix.
- Apparatus metrics map the outer inset to the shared peripheral edge and
  independently own the Inspector's **18pt** selected-mode underline,
  **78pt** minimum fact
  label column, **14pt** fact-column gap, **204pt** horizontal FactGrid
  threshold, and **44pt** Action-row rhythm. These names may reuse a general
  value only when the purpose is genuinely the same; Inspector-specific rhythm
  is not expressed by borrowing a peripheral or Library metric.
- The one-time **320pt** first-reveal request is a native-container initial
  condition outside the grid. It is not a design Variable, persisted setting,
  minimum, maximum, or continuously enforced preference.
- Set Aside and Trash reuse the Library metrics and common OutlineRow
  and LocationHeader components. They create no parallel lifecycle spacing
  namespace, destination header, or footer role.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, decorative motion, or repeating
  Attention pulse. Conditional Attention presence remains understandable with
  motion entirely absent.
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

Initial sizes are Workspace **1180 × 760**, Bootstrap **720 × 720**, Research
Record **760 × 680**, and fixed Settings content **700 × 560**. Regions scroll
independently; Document takes remaining space without a fixed size. Native
geometry stays outside the grid. WebKit uses `rem`, `ch`, CSS px, and viewport
units without point conversion. The selected **48–96ch** Line width is centered
inside the available Document width while `max(...)` retains the **20/32/40 CSS
px** minimum border separations. Wide rendered tables, code, and mathematics
may scroll inside that measure; rendered prose reflows without page-level
horizontal reading scroll. Source mode instead soft-wraps every exact logical
line within its measure without changing source line breaks or line numbers.
The 72ch default and typographic rhythm have passed ordinary, narrow,
mixed-script, and 100%/200% visual acceptance. Screenshots and prototype
coordinates remain evidence only and never define native/CSS unit conversion.

### 19.5 Application icon

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

## 20. Accessibility and adaptation

- Support System, Light, and Dark without hard-coded inversion.
- Meet at least **4.5:1** contrast for ordinary small text and **3:1** for large
  or bold text; audit every important custom target below 28 × 28pt.
- Preserve hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive windows, 200% document text, and accent changes.
- Give every important state two suitable channels; never rely only on color,
  motion, sound, location, or arrow direction.
- Actions exposes every official and researcher-enabled operation as a linear
  accessible list without requiring hover. Research Record exposes its list,
  filters, dialogue order, participants, anchors, and Record Details with
  complete keyboard navigation inside its fixed readable utility-window size.
- Inspector acceptance covers Overview, Connect, and Actions at **320pt** and
  **278pt**, plus long English, mixed English/Chinese, right-to-left layout,
  empty facts, long values, unavailable Actions, and 200% readability. The
  ModeIndex remains one logical horizontal group; a FactGrid stays horizontal
  or stacks as one whole; Action error and recovery text remains complete.
- Overview exposes the complete Needs Attention summary as one button with the
  current-Note count and scope, while the About heading exposes the
  **Edit Properties** action without absorbing selectable values into the
  control. A current Analysis with a valid Zotero item key exposes one
  keyboard- and VoiceOver-reachable **Open in Zotero** button inside About;
  neither the key nor metadata enters the accessibility tree. Each Connect
  Note row is one primary button whose accessible name
  states its relationship; its cluster glyph is decorative and hidden from
  accessibility. A distinct source anchor remains a named accessibility action
  after the visual trailing glyph is removed.
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, Action sheets, conflict comparison, and
  Research Record close.
- Direct note creation has pointer, **File → New Note**, keyboard-shortcut, and
  accessibility routes. A successful action moves selection to the created
  note; a failure leaves the current selection and source unchanged and reports
  the reason without opening a naming dialog.
- Library exposes the static Scholium wordmark and Triptych identity menu as
  distinct elements. ScopeIndex is one logical horizontal group with current
  selection and reading-direction-aware arrow navigation, and exposes no
  Attention values. The conditional Sidebar alert exposes
  **Open Attention** with its selected Scope and exact count; zero contributes
  no element or gap. If its last item disappears while it owns keyboard focus,
  focus moves to LocationPicker. Collapsing Sidebar adds no Attention element,
  count, value, or reserved gap to the Document toolbar; the contextual route
  returns when Sidebar is shown, while an applicable Inspector summary remains
  independently reachable.
  LocationPicker exposes its localized current Location, expanded state, and
  selected native menu item; optional Location counts are values, not badges or
  selection state. Inactive Location content is accessibility-hidden. Put Back
  remains in keyboard and VoiceOver order without hover, and row removal
  follows the next/previous/LocationPicker focus sequence defined in §18.3.
  Settings remains available through standard application routes, not as a
  Library destination.
- Attention exposes its popover heading, filter, three group headings,
  selected task, issue, resolved Note title, locator, state, and available
  actions in one linear keyboard and VoiceOver order. Loading retains that
  structure; refreshing, stale, and recoverable failure keep the last complete
  rows operable while status and Retry remain named. When the selected task
  disappears, focus follows the next/previous/filter sequence in §18.3.
- Recommended Bibliography is exposed after the Library source region as one
  **Triptych Recommended Bibliography** group. Its accessible scope does not
  rely on fixed position or surface color, and its full workflow remains
  keyboard and VoiceOver reachable across Scope and Location changes. The
  compact band contains one **Open Recommended Bibliography** button whose value
  is **No recommendations** or the recommendation count; no candidate inside
  the compact preview becomes a separate accessibility target.
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
- A running Action exposes its Action name and **Running** state together while
  retaining a distinct, explicitly named Cancel control in the same linear
  Actions order. Its progress animation is not the sole state channel.
- Document-owned Autosave Failed and Conflict toasts announce their state,
  retained-buffer consequence, and available recovery action. Persistent
  failure remains reachable after its announcement; the transient Checkpoint
  Restored confirmation is announced once without moving document focus.
- Keep accessibility labels and hints semantically complete but nonduplicative
  under §19.6. The visible two-line authoring budget never removes information
  needed to distinguish source, state, authority, consequence, or recovery.
- The separate Review Comment bar and Edit formatting bar are keyboard
  reachable and expose every visible command by name. Review's Comment field announces the inclusive line
  range, Return-to-save, Shift-Return-to-insert-line, and Escape-to-cancel
  behavior without moving or erasing the underlying document selection.
- The Appearance Line width slider has a localized label and help text, exposes
  its current value in character-width units, and supports standard keyboard
  adjustment and VoiceOver without requiring pointer dragging.
- Test long labels, mixed English/Chinese, right-to-left chrome, minimum width,
  every lifecycle/error state, and editor/native-container focus transitions.
- At the Library boundary, verify both permitted narrow outcomes: expanded at
  **300pt or wider**, or natively collapsed. The open-but-unreadable compressed
  state is forbidden. All three Triptych scopes, the current Location, and
  applicable Library actions remain reachable at the threshold; localized and
  right-to-left variants are covered by the adaptation matrix. Library rows
  grow vertically rather than clipping enlarged interface text.
- Keep the configured minimum inline separation from both structural dividers.
  At 200% document text, prose must reflow without page-level horizontal
  reading scroll; only wide tables, code, and mathematics may scroll inside
  their own containers.
- Synthetic events cannot certify real VoiceOver, Voice Control, Dictation,
  Full Keyboard Access, or CJK IME; retain manual gates where required.
- A lifecycle timeout preserves the affected editor buffer, restores a useful
  focus target, and exposes retry without treating local presentation-state
  persistence as research-content failure.
- The Storage Unavailable root page exposes an immediate, keyboard-default
  Retry; selectable Details; and Quit with current VoiceOver names, values,
  focus order, and failure text. It remains legible under Increase Contrast and
  does not rely on animation, transparency, or color to communicate failure or
  recovery.

Beta and 1.0 require complete keyboard and VoiceOver coverage for the declared
core and no unresolved critical/high-severity accessibility defects. A medium-
severity ceiling remains a release-owner judgment.

## 21. Release requirements and acceptance

### 21.1 Evidence hierarchy

Evidence order is live source/construction; executable tests; isolated QA on
disposable fixtures; dated status; this target; then history/memory as context.
Target prose, previews, and compilation prove no workflow, accessibility,
package, signing, or performance result.

### 21.2 Primary acceptance journeys

**Usable Core** covers:

- Bootstrap success/failure, registration/restoration, and independent windows;
- create/open/read/edit/save/Search and explicit cross-vault navigation;
- Edit/Source fidelity, formatting, Review passage Comment, and Markdown
  Callout authoring,
  and mode changes;
- About/Properties, optional Research Unit, Settle, and simplified Actions;
- native split resize/visibility, Document tabs without shell reconstruction,
  focus, keyboard, light/dark, scaling, minimum width, and core VoiceOver; and
- external edits, conflicts, stable rename, Set Aside, Trash, checkpoints,
  restore/interruption, and cross-window dirty-peer behavior.

Later Beta/1.0 additionally cover applicable Research Actions, Working and
Researcher Skills, staged installation, permissions and change requests,
portable Research Records, hierarchical Materials, Research Guidance/Recovery,
Connections, Attention, Zotero unavailable/read-only behavior, CLI parity,
deletion/restore, adaptations, and 1380/1080/900/minimum-width workspaces.

Beta handoff evidence includes copy-before-chooser ordering, explicit app
selection and machine-local persistence, choose/forget/cancel/failure paths,
keyboard/VoiceOver, and no auto-paste/submission. 1.0 Codex evidence includes a
new task, exact root, locator-only composer, explicit submission, unavailable
fallback, Unicode/space paths, keyboard/VoiceOver, and unchanged-run recovery.

For material evidence, use disposable fixtures and retain command, source
revision, Xcode/SDK, build, fixture identity, result, and artifact location.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every in-scope requirement has evidence or waiver. |
| **G2 Workflow independence** | Manual core works without Obsidian, Zotero, agents, or manual filesystem work. |
| **G3 Source integrity** | Exact-source tests cover malformed YAML, unknown fields, BOM/newlines, comments, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflict, checkpoints/restore, Trash/purge, external rename, and derived failures pass fixture journeys. |
| **G5 Scholarly transparency** | Authoritative Markdown, Discussion turns, Action outputs, Settle, Critique, Fidelity, provenance, authority, agent feedback, and uncertainty remain visibly distinct. |
| **G6 Accessibility/i18n** | Section 20's declared threshold is met. |
| **G7 Performance** | The packaged-app protocol in §21.4 passes on the frozen fixture and approved reference machine. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | External binaries use a clean exact tag, corresponding GPL source/licenses, no private state, accurate signing/architecture, checksum, and clean-account smoke test. |
| **G10 Agent skill architecture** | Protected mechanism, editable Working Methods, Researcher Skills, declarative Action Profiles, staged installation, permissions, change requests, records, bootstrap, and Zotero/agent bridges pass declared journeys. |

Usable Core/0.1 require G1–G4, G6, and G8; G9 applies to any distributed
artifact. G6/G7 baselines and gaps must not be misrepresented as Beta passes.
Beta requires every applicable gate including G10. 1.0 additionally requires
the full **Open in Codex** journey; **Run with Codex** is not a gate. Current
evidence belongs only in `IMPLEMENTATION_STATUS.md`.

### 21.4 Packaged performance gate

Performance evidence has three noninterchangeable classes:

1. regression microbenchmarks detect internal slowdowns;
2. scenario measurements exercise an incomplete fixture, fewer than 30
   retained samples, or a nonrelease artifact; and
3. product-gate measurements exercise the exact packaged Release app, frozen
   RDF-1, complete visible boundaries, and the full retained sample set.

Only the third class can satisfy G7. Debug builds, unit tests, internal timers,
human stopwatches, and partial memory series are never substitutes.

The candidate Beta thresholds remain subject to explicit release-owner
approval. Once approved, use nearest-rank p95 over exactly 30 valid samples
after five excluded warm-ups:

| Interaction | Candidate p95 limit |
| --- | ---: |
| Warm library launch to a usable note list | `< 1,000 ms` |
| Indexed Search query to complete visible results | `< 100 ms` |
| Warm Review-note activation to interactive rendering | `< 300 ms` |
| Application-cold 5,000-word Review-note activation to interactive rendering | `< 1,000 ms` |

Editor candidate limits remain separately unapproved: `< 100 ms` for key to
first painted edit, visible Edit/Source transition, and cached preview;
`< 300 ms` for warm Edit activation; `< 1,000 ms` for application-cold
5,000-word Edit activation; and `< 5 ms` for one visible-range projection.
Continuous scrolling must add no uninterrupted Editor task longer than one
display refresh interval, and neither native nor Web UI work may add an
uninterrupted task over 100 ms.

`Tools/Scripts/generate-rdf1.py` owns the deterministic no-RNG RDF-1 fixture.
Its verified manifest fixes exactly 800 synthetic Markdown notes, complete
path/size/SHA-256 inventory and tree hash, role and malformed-frontmatter
counts, link/folder coverage, one 5,000-word Work, one 100,000-CJK-character
Work, fixed navigation targets, and fixed English/CJK Search queries with
expected identities. RDF-1 is disposable test data, never a research source.

The gate must use the exact app produced by the release packager from one clean,
reviewed, exactly tagged commit. App provenance, tag, commit, source-clean
state, architecture, and fixture manifest must match. One unchanged machine
record covers macOS, hardware, power mode, display, foreground applications,
window size, accessibility settings, and logging. Each metric uses isolated
Application Support, preferences, bookmarks, and derived state.

The measured boundary is user-visible and accessible: a selectable, unblocked
library; complete visible Search results; or rendered, interactive Review/Edit
content after native publication and editor-renderer readiness. Semantic
projection or an internal callback alone is insufficient. Retain raw durations, p50, p95,
maximum, mean, valid and invalid sample counts with reasons, correctness,
machine record, artifact identity, fixture identity, and raw outputs outside
every research vault. Missing process roles, changed process sets, provenance
mismatch, incomplete samples, or unapproved thresholds fail closed.

The 100,000-CJK fixture must remain editable at beginning, middle, and end with
working undo, mode switching, and byte-exact save. After 50 note/mode switches,
retained editor-renderer counts and total app-plus-renderer memory must converge
rather than grow monotonically. These are correctness and stability conditions,
not percentile results. Current measurements and remaining activation work
belong only in `IMPLEMENTATION_STATUS.md`.

### 21.5 Source-first Beta distribution

The first external release identity is:

- tag and public label `v0.1.0-beta.1`;
- app marketing version `0.1.0`, build `1`, minimum macOS 26;
- exact tagged source under `GPL-3.0-or-later`; and
- an optional architecture-labelled, ad-hoc-signed Scholium app ZIP plus its
  SHA-256 checksum on the same release page.

The app bundle includes its version-matched `scholium` helper. There is no
separate public CLI asset. The release also includes applicable license texts
and notices, identifies verified architectures without overstating universal
support, and contains no real vault, Application Support state, bookmark,
credential, index, absolute private path, or research content.

Ad-hoc signing is not Developer ID signing, notarization, publisher
verification, or Gatekeeper acceptance. Testers may approve the trusted GitHub
download through **System Settings → Privacy & Security → Open Anyway** after
the first launch attempt. Documentation must never advise disabling Gatekeeper,
recursively removing quarantine, or installing an untrusted root certificate.

Before tagging or upload, freeze a reviewed clean commit; audit the tree and
history for private material; run complete repository verification with
disposable fixtures; package with the clean-source requirement; inspect app and
helper metadata, resources, entitlements, architecture, signatures, icon, ZIP,
checksum, and licenses; pass G7; and exercise the exact expanded ZIP in a clean
macOS account through first launch, Triptych setup, read/edit/save, Search,
conflict/recovery, Inspector/Action, restoration, and unavailable integrations.
No real research vault may be opened during release verification.

Developer ID signing, notarization, and stapling are optional future channel
improvements. If adopted, rebuild from the exact release commit and repeat the
complete external smoke test; never re-sign an already tested artifact or
share a certificate private key outside its responsible organization.

### 21.6 Change control

Every approved target change updates the affected canonical rule and removes
the text it replaces in the same patch. Git owns prior versions; this document
does not preserve supersession chains or compatibility narratives for an
unreleased product. Architecture records structural consequences, and status
records implementation, migration, verification, acceptance, and release
evidence. Temporary code or visuals never become authority accidentally.

## 22. Unresolved target decisions

Sections 1–21 are the complete current contract. Git history owns replaced
rules and decision chronology; decision IDs that remain in dated status or
test names are historical locators, not independent product authority.
Implementation and acceptance gaps belong in `IMPLEMENTATION_STATUS.md`.

Only questions that can still change the target remain here:

- promote or revise provisional interface metrics only after the complete
  adaptation and human visual-acceptance matrix; and
- approve the packaged G7 p95 thresholds before they become release limits.

Resolving an item updates its owning canonical section and removes the item
from this list in the same patch.

## Appendix A. Default property profiles

Existing/custom YAML remains authoritative and losslessly preserved. Canonical
vocabulary defines recognized meaning; About defines the default read-only
projection; creation requirements are empty for every role. Profiles never
inject absent YAML, erase unknown source, or turn visibility into editability.
App-owned time and provenance remain outside frontmatter. Research Unit follows
the role-aware constraints in §5.2.

### Analyses

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `title` | Researcher | No | Source identity; resolver fallback is H1, then filename. |
| `research_unit` | Researcher | Completion, then every Limitation | Optional `completion` and/or `limitations`. |
| `authors` | Researcher | Yes | Author list. |
| `year` | Researcher | Yes | Publication year. |
| `type` | Researcher | Yes | Publication form. |
| `access` | Researcher | Combined Source Basis | Extent of consulted material. |
| `text_reliability` | Researcher | Combined Source Basis | Reliability of consulted text. |
| `locators` | Researcher | Combined Source Basis | Citation stability/checkability. |
| `tags` | Researcher | No | Retrieval terms. |
| `debate_importance` | Researcher | No | Optional whole number 0–10. |
| `debate_importance_scope` | Researcher | No | Must appear with Debate Importance. |
| `zotero_item_key` | Protected machine | No | Exact task-context identity; not ordinarily editable. |

Debate Importance follows 5.2 and never means project relevance, quality,
truth, prestige, or citation count. Relevance keys remain custom source.

### Topics

Topic YAML is optional.

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `research_unit` | Researcher | Scope, then every Limitation | Optional `scope` and/or `limitations`. |
| `aliases` | Researcher | Yes | Search and link alternatives. |
| `tags` | Researcher | No | Retrieval terms. |

Topic identity is first H1, then filename. YAML `title` is not recognized.

### Works

| YAML | Ownership | Default About | Rule |
| --- | --- | --- | --- |
| `research_unit` | Researcher | Research Scope, then every Limitation | Optional `scope` and/or `limitations`. |
| `kind` | Researcher | Yes | Paper, chapter, book, talk, review, teaching material, etc. |
| `authors` | Researcher | Yes | Co-authors when relevant. |
| `venue` | Researcher | Yes | Intended or actual journal, publisher, course, or event. |
| `tags` | Researcher | No | Retrieval terms. |

Work identity is first H1, then filename. YAML `title`, `status`, and `deadline`
are not recognized. Only canonical keys receive typed semantics; all other
source remains custom and targeted edits never normalize it.

## Appendix B. Bundled Critique Method requirements

The bundled Critique Skill must inspect the bounded Work context and applicable
Analyses and Topics; distinguish what those notes report, support, dispute, or
leave uncertain from the agent's own reconstruction or evaluation; and treat
neither neutral links nor transitive paths as evidence.

For the whole Work it addresses material strengths, weaknesses, source
coverage, omissions, objections, alternatives, and priorities. For a selected
passage it identifies the exact target, issue, significance, research basis,
and recommendation. It records the Materials actually consulted, access limits,
and uncertainty. Any Traced, Untraced, Disputed, or Beyond Sources label remains
an attributed agent judgment, never a Scholium status.

Critique never modifies the target Work. A recommended source change requires
a separately authorized Write child phase. The Triptych-installed editable
Working Method owns the active prose; its bundled reference remains read-only
and serves only explicit comparison or restoration. This specification states
requirements without duplicating either Skill's complete prose.

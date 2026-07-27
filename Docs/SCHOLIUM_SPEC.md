# Scholium Specification

**Status:** Canonical product, interface, and release specification
**Applies to:** Scholium for macOS and its agent-facing CLI
**Canonicalized:** 2026-07-17
**Last target change:** 2026-07-27 (D-112)

This is Scholium's sole target authority for product, interface, action
language, Scholarly Editorialism, accessibility, release, and stable decisions.
`IMPLEMENTATION_ARCHITECTURE.md` describes structure; `IMPLEMENTATION_STATUS.md`,
README, live construction, and tests establish reachability and evidence.
Current divergence is migration work, not an alternative rule.

In this specification:

- **Target** is required behavior, whether implemented or not.
- **Reachable** means exposed by the current build, not accepted for release.
- **Verified** means directly exercised by the stated evidence.
- **Deferred** is intentionally outside the stated release boundary.
- **Unresolved** means a decision or acceptance judgment remains open.

Apple HIG and the selected SDK own platform/API behavior; this specification
owns the Triptych, scholarly semantics, evidence, and research governance.

The direct-agent-edit model supersedes Proposal and unapplied-Revision
workflows. Unsupported pre-release app state fails closed or is ignored. This
clean cutover never deletes or normalizes researcher Markdown, custom YAML, or
unrecognized Triptych files.

## 1. Canonical terminology

- A **Scholium Triptych** (**Triptych**) is one configured workspace containing
  exactly three vaults: **Analyses**, **Topics**, and **Works**. Their ordinary
  documents are an **Analysis**, **Topic**, and **Work**.
- **Unclassified** temporarily stages imported Markdown before the researcher
  assigns it to a vault.
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
- **Connect** is the Inspector surface for source-located neutral, support, or
  incompatibility relations. **Attention** contains derived, recoverable
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
- user packages at `.scholium/skills/<skill-id>/SKILL.md`; and
- imports at `.scholium/unclassified/`.

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

### 3.5 Import and Unclassified

Import copies Markdown into `.scholium/unclassified/` without changing the
original. The copy is readable and editable but receives no role-specific
role-aware About, Settle, or Critique behavior until classified into Analyses,
Topics, or Works. Irrelevant Markdown should not be imported.

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
  commenting. Its internal and persisted mode identifier remains `read`.
- **Edit** edits the exact body through a visual projection, shares
  Review's semantic render components, typography, callout presentation,
  document measure, and theme variables, reveals syntax only around the active
  construct, and shows neither YAML nor line numbers. Its internal and
  persisted mode identifier remains `livePreview`. Inactive content should
  match Review; caret, selection, marked-text composition, and the active
  construct are the permitted editing differences.
- **Source** edits complete Markdown and YAML, shows line numbers, and retains
  the same document session, viewport, measure, and semantic colors while using
  exact-source typography.

All three modes consume the selected Appearance's one shared line-width value.
It changes only layout in Source: Victor Mono and the exact-source typography
contract remain unchanged. The CSS `ch` unit resolves against each mode's
current font and is a character-width unit, not an exact characters-per-line
promise.

Rendered callouts hide generated role names visually but retain them for
accessibility. A supplied title inherits the role heading style; an untitled
callout adds no heading. Prose uses natural start alignment, never full
justification.

An inactive Edit callout atomically projects one half-open source
range. Selection reveals source only on actual overlap, not boundary contact.
Down Arrow from above enters at the range start; Up Arrow from below or a
pointer press on its rendered title/body enters at its logical end. CodeMirror then
resumes native editing. Only the disclosure mark changes fold state by pointer;
the focused summary retains keyboard disclosure.

Review and Edit support Obsidian-compatible inline `$…$` and display
`$$…$$` mathematics outside YAML, code, raw HTML, comments, and escaped
delimiters. The immutable editing dialect owns exact delimiter behavior.
Malformed or unsupported mathematics stays visible as exact source with a
diagnostic; rendering never rewrites it.

Review and Edit treat Obsidian-compatible `![[Target]]` embeds, including
aliases and heading or block fragments, as source-located neutral links.
Inactive embeds share protected presentation, navigation, and diagnostics; the
active construct reveals its exact syntax. This stage neither reads nor
transcludes target content or creates philosophical relationship edges. Any
later transclusion requires a separate recursion, cycle, authorization,
external-change, and large-file contract.

Internal links and Vector Links provide bounded previews without becoming
evidence or another source authority. Review additionally previews footnote
references on ordinary hover; a footnote preview contains only the referenced
definition. Footnote focus, activation, navigation, and return controls belong
to Review only, with keyboard and accessibility-equivalent routes. Edit keeps
the rendered marker passive: selecting it performs only CodeMirror's ordinary
cursor placement at the underlying Markdown. Source exposes the exact text.

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
Properties; existing timestamp keys remain exact custom source.

An Analysis may pair whole-number `debate_importance` (0–10) with
`debate_importance_scope`. Both are required together and comparable only
within the same named debate, domain, tradition, period, or reception context.
It is not project relevance, source quality, truth, prestige, or citation
impact. After choosing one exact scope, Library may sort rated Analyses high to
low with unrated notes afterward. No global cross-debate ranking exists;
Scholium neither generates nor presents Project Relevance. Existing
`relevance` and `relevance_rating` keys remain preserved custom data.

About omits absent fields without explanatory empty copy. Its role-specific
order is defined in Appendix A. `status` has no Scholium semantics, query,
index, filter, ordering, or UI. Work `deadline`, Topic/Work YAML `title`,
required markers, and **Open Properties by Default** likewise do not exist.
Unknown source YAML remains byte-preserved but acquires no retired semantics.

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
still has no lifecycle identity. Managed Critiques and ambiguous legacy folder
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
post-rename or unclassified outcome retains the pin even if a later concurrent
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
separate note is useful. Scholium never converts retired Annotation records
into Markdown automatically.

### 7.3 Clean cutover

Pre-production Human Review, Qualification, ResearcherComment, app-owned
Annotation, pre-Function Dialogue, separate Comment/Discuss archives, Research
Activity history, legacy Function bindings, and legacy grants are unsupported
by the new model. Repository code, shipped legacy Workflow Skills, construction
paths, decoders, migrations, projections, Search fields, tests, and UI that
exist only for those authorities are deleted when their replacement becomes
reachable; they are not retained as compatibility architecture.

The cutover never deletes or rewrites researcher Markdown, unknown YAML,
unrecognized Triptych files, or pre-existing machine-local data merely because
the new application no longer reads it. Unsupported legacy data remains
byte-unchanged, but a pre-production application provides no parser, migration,
projection, recovery path, authorization route, or dedicated reveal entry for
it. It never appears in the current interface or becomes a new Research Record.

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

Provider-neutral copy and explicit app selection remain available. A later
Codex handoff may open a new task at the exact requested root with locator-only
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
and collapsed **Record Details**, not chat bubbles. New line Comments retain
only their revision-bound inclusive line range; legacy exact-passage data is
never required for a new Comment or agent handoff. Multi-note context appears
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

One Application coordinator owns Action availability, preparation, completion,
cancellation, and Fidelity. Preparation resolves Origin and exact revision,
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
| `-[[B]]` | B supports A |
| `?[[B]]` | symmetric incompatibility A—B |

These forms replace legacy typed-link syntax; aliases, headings, and fragments
remain valid. Preserve legacy bytes and diagnose them without automatic
conversion. Never infer support from keywords, proximity, folders, or
multi-hop paths. Incoming and Outgoing views show direction and exact source
without permanent badge clutter.

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

Beta Search contract v4 uses one deterministic local SQLite FTS5 corpus for
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
Unknown fields or canonical values, removed `vault`, `role`, or `metadata`
fields, malformed escapes, CJK prefix `*`, and unsupported OR, grouping, NEAR,
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
generation, while a first or incompatible v3 build never falls back to the
different v1 ranking contract. One generation publishes atomically or not at
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
checkpoints remain until the researcher deletes them. Retained legacy automatic
checkpoints may remain recoverable but do not authorize or describe a current
Action.

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
bytes. Corrupt legacy recovery metadata must not cause unrelated recoverable
bytes to be deleted or silently attributed to a note. Durable settled-pin
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
**Test Connection**, **Refresh Library Information**, **Clear Connection
History**, last successful time, and a concise local/read-only privacy statement.
When disabled, direct the researcher to **Allow other applications on this
computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Protected Analysis task context

`zotero_item_key` is an Analysis-only protected-machine field. It is absent
from About and ordinary Properties. Scholium has no **Create Analysis from
Zotero**, matching, comparison, confirmation, or metadata-overwrite flow. Only
a protected machine or authorized agent mutation may write the key through the
current-fingerprint boundary.

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

One Triptych-wide **Recommended Bibliography** section is fixed at Library's
bottom across vault scopes and labelled **Reading leads, not evidence**. It is
not a Research Action, Inspector launcher, note appendix, Zotero write path, or
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
state. Actions are **Open Analysis**, verified-key **Open in Zotero**, and
**Dismiss**. The section provides **Recommend…**, **Copy Instructions**,
**Cancel**, and **Update Recommendations**; preserves prior results on refresh
failure; and distinguishes empty, successful-zero, preparing, awaiting-agent,
stale, malformed, duplicate, ambiguous, Zotero-unavailable, and general error
states through text/symbol plus accessible focus and narrow adaptation.

The delivery-neutral `RecommendedBibliographyUseCases` is separate from
Research Actions. CLI provides `bibliography prepare`, `show`, `complete`,
and `cancel`; Core/Application owns normalization and duplicate discrimination.

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
the validated Application Support location and may construct `WorkspaceStore`
or `WorkspaceRuntime`. Storage Unavailable replaces the app root with a
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
split, and toolbar; they never compete. SwiftUI restores recoverable Workspace
routes directly. The presented Bootstrap default is used only when no
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

Required for the researcher-governed Skills cutover but not current
reachability: protected System Skills; directly editable Working Method Skills
for Discuss, Analyze, Synthesize, Write, Critique, and Content Fidelity;
optional hidden Manuscript; declarative Action Profiles; bounded installation;
standing permissions; agent change requests; portable Research Records; and
protected Zotero and agent-tool transports.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; and Work finding overlays.

**Run with Codex** is not a 1.0 feature. Background/noninteractive execution,
auto-submission, streamed thread/tool state, general agent-host approval or
interruption control, and App Server or SDK orchestration require a fresh 2.0
decision. D-106's narrow typed note-change request does not broaden into those
capabilities. 1.0 **Open in Codex** must imply none of them.

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

Each configured window contains exactly one native `NSSplitViewController`
with three sibling items:

1. **Library:** Triptych identity; Analyses/Topics/Works scope; Attention;
   Filter; one folder/note hierarchy; Recommended Bibliography; compact Set
   Aside, Trash, and Settings routes.
2. **Document:** selected note or the text-free semantic background.
3. **Apparatus:** Research Inspector's read-only Overview, Connect, and Actions
   projections. It never owns buffers, autosave, Undo, or conflicts;
   full chronology belongs to Research Record.

The workspace starts at **1180 × 760**, not a minimum. SwiftUI Scene data owns
route identity and restoration; AppKit owns window, divider, compression,
collapse, fullscreen, and frame geometry. Scholium neither corrects opening
frames nor persists divider geometry. It declares no scene/window minimum
unless the complete adaptation matrix proves one necessary. The sole specified
content constraint is the expanded Library's **300pt minimum readable
thickness**: AppKit must keep it at or above that boundary or collapse it.
This is neither a preferred width, restored divider value, nor parallel
geometry owner. Library remains a semantic Sidebar, Apparatus an unmodified
Inspector, and all three planes opaque with one-pixel rules.

New windows show Library and hide Apparatus. Restore applies both visibility
values once; then native collapsed state is authoritative and the model only
mirrors Library and Apparatus visibility for labels, commands, and the next
session. Menu, toolbar, and content actions send explicit per-window intents to
the native controller; model observation never continuously reasserts split
state. Notes/tabs never reconstruct the shell or change peripheral
visibility/mode. A new window's first Inspector reveal selects Overview. Each
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

If needed, the collapsed Inspector's Show control and View command may send one
explicit intent through the exact window coordinator to the native split.
The Inspector routes share selected-document availability and preserve native
transition and geometry. Collapsed-Inspector Show remains visible but disabled
without a Target; a visible Inspector can always be hidden. Research Record is
Triptych-scoped and remains available in every configured workspace; opening it
with a Target applies the removable **This Note** filter.

With two or more documents, a Document-owned strip appears only in the middle
item. Each tab references one retained editor session. `.unspecified`
`NSTabViewController` owns containment; Scholium supplies equal-width selection
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

The Library identity row sits below window controls; its Scholium disclosure
and content share the 20pt region-content alignment. Traffic-light alignment
is visual reference only, never derived geometry. No-note is text/action-free
and VoiceOver-hidden. No Collapse Note, custom `<<`, Back/Forward, Recents, or
Quick Open exists.

Menus follow researcher tasks:

- **File:** Triptych/window create/open; direct **New Note** at the focused
  vault root; Import; Duplicate; Move/Rename; Reveal; Checkpoint create/restore.
- **Edit:** editing and **Edit Properties…**.
- **View:** Search, document mode/text size, Sidebar, Research Inspector.
- **Research:** role-valid Actions and **Show Research Record**, never
  Attention or Checkpoints.
- **Settings:** Triptychs, Property profiles, Research Guidance, Attention,
  Zotero, and Appearance.

### 18.3 Library and Search

- One native **Filter** menu groups Integrity, Metadata, Properties, Order, and
  Actions with at most one submenu level. Current Library rows and filters have
  no Review, Unreviewed, Qualified, or Unqualified state.
- Unclassified is reachable for classification but not a permanent Library
  row. Notes outside folders appear at vault root.
- Folder/note rows form one hierarchy at one semantic callout size and compact
  24pt height. Use weight, color, indentation, and symbols—not size. Notes are
  one line without sublines and expose full titles accessibly. At most one
  redundant state mark precedes title; selection remains visible off-focus.
- The Library-header Add button directly creates at the current vault root.
  Every ordinary folder row offers direct **New Note** and **New Folder**, then
  **Rename Folder…**, **Move Folder…**, conditional subtree expansion/collapse,
  Copy Relative Path, Reveal in Finder, and destructive **Move Folder and Notes
  to Trash…**. Equivalent accessibility actions provide non-secondary-click
  routes. Neither creation action opens a sheet. Library enumerates empty real
  directories. Protected machine-managed folders and ambiguous legacy
  projections retain only safe nonmutating navigation.
- LIBRARY shows no total. Triptych-wide ATTENTION follows scope before Library,
  with the same 10pt edge, warning symbol, and count. It expands/focuses an
  inline full-width queue, never a modal/Research destination; Inspector may
  summarize only the current note.
- **Set Aside** and **Trash** are same-plane Library destinations, never
  overlays, cards, sheets, or separate Sidebar modes. They replace only the
  Library heading and hierarchy region; Triptych identity, scope, Attention,
  Recommended Bibliography, and the 52pt footer remain stable. On successful
  load the heading shows borderless Back, localized title, and localized count;
  Filter and New Note are unavailable. Back, Escape, or the active footer item
  returns to Library; the other destination switches directly. Attention and a
  lifecycle destination dismiss each other. The hidden hierarchy stays mounted
  to preserve context but accepts no input and leaves the accessibility tree.
- Lifecycle rows keep the 24pt rhythm. A single-line truncated title opens the
  note in place; a fixed 20pt trailing **Put Back** control remains keyboard and
  VoiceOver reachable even when visually quiet. Hover is optional. After Put
  Back, Move to Trash, or permanent deletion removes a row, focus moves next,
  previous, then Back; cancellation or failure restores the originating row.
- Compact Recommended Bibliography stays above the footer even when None,
  horizontally scrolls `Author, Year, Title` leads with thin rules, and links
  to the full surface. Use `&` for two authors and first author + `et al.` for
  three or more.
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
Shared ownership and units are approved; the 72ch default still requires the
adaptation matrix and researcher side-by-side acceptance. Edit and
Source reconfigure one retained CodeMirror state; window, split, theme,
line-width, or text-size changes never replace it or create an Editor window.

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
Show Sidebar; Heading Outline and compact identity; mode and Search; Research
Record; conditional Show Inspector. Scholium controls are borderless ink. No
second identity row, Document Properties button, or More control exists.
Complete Properties is in Research; direct controls retain menu/keyboard
routes. Document Text Size is per-window and source-neutral.

Properties performs targeted frontmatter edits and distinguishes absent,
empty, invalid, derived, and not-applicable. Exact YAML stays available in
Source. About follows the role-specific catalog in Appendix A; absence is
quiet, and `zotero_item_key` and Analysis title are never selectable there.

### 18.5 Contextual research and Actions

Apparatus contains Research Inspector only; active Discussion, Research Record,
and checkpoint recovery keep distinct ownership. Active Discussion opens as an
Action sheet. Research Record is an independent, nonrestored `UtilityWindow`,
reads the focused Triptych directly, and keeps a fixed **760 × 680** content
size chosen for readable temporary inspection. It uses one native list/detail
layout, has no Workspace Sidebar control or alternate wide/narrow presentation,
does not adapt into another primary interface, and never appears inside
Inspector. Its leading record list remains compact and top-aligned in ready,
empty, and filtered-empty states; controls and rows use compact native macOS
density while every custom target retains the minimum accessible hit region.
There is
exactly one native trailing Inspector per
Workspace, with **Overview, Connect, Actions** in that order. These are
mutually exclusive modes inside the Inspector, not split columns, Document
tabs, panels, or windows. Their text labels use a restrained ink underline,
not a filled/capsule segment; labels remain horizontally reachable rather than
truncating. The selected mode is exposed accessibly, Left/Right Arrow changes
mode, Tab enters its content, and every mode owns at most one vertical scroll.

A new window begins in Overview and stores its last mode per window. Restoring
a window restores that mode; switching notes, Document tabs, or
Review/Edit/Source never changes it. Hiding the Inspector transfers only its Show
route under §18.2; no Inspector content moves into Document. Research menu and
keyboard commands may open an Action without revealing the Inspector or
changing its mode.

Overview presents only compact current-note projections, in this order:

1. **Needs Attention:** current-note count, distinct actionable kinds, and a
   full-row Show All route to Library's complete queue. At zero it retains the
   heading and `0` but no reassurance sentence or decorative verdict.
2. **About:** only non-empty role-specific fields in Appendix A. Scope and each
   Limitation use reading blocks. **Edit Properties** is a native full-row
   action; About has no Customize route. There is no Research Status, Key
   Properties, Provenance, Derived State, or Zotero section.

Freshness appears only as a compact actionable line when Refresh is pending,
stale, failed, or unavailable. It preserves last-known-good projections and
offers Retry where applicable; it never claims reading, truth, or evidence.

Connect begins with three expanded, independently collapsible groups:

| Target | Groups |
| --- | --- |
| Analysis | Neighbor Analyses, Related Topics, Related Works |
| Topic | Related Sources, Neighbor Topics, Related Works |
| Work | Related Sources, Related Topics, Neighbor Works |

Within a group, explicit links sort supports, supported by, incompatible, then
neutral. Minimal ↑, ↓, ×, and — marks state predicate and direction; titles
wrap. Do not open a second panel merely to show a title. Preserve source
anchors. An empty group retains its heading and `0` without **None**. Connect
shows the same freshness state before its groups. Stale or failed state keeps
the last complete graph readable and offers a full-row Retry action.

Actions begins directly with the role-valid default Actions in Section 8.1.
There is no horizontal Research Activity HUD, completed chronology, generic
**Open Research Record** row, **Work with Agent** wrapper, or mode picker. The
Discuss Action itself reopens the current Note's resumable active Discussion
and automatically includes its existing line Comments. It has no second
active-Discussion row or parallel destination.

Researcher-enabled custom Actions follow under one **Researcher Skills** group
in the researcher-chosen order. Only Profiles with **Show in Actions** enabled
appear. Availability fails closed while checking; an unavailable Action states
only its first executable repair. Settle remains a quiet direct current-note
action, and Attention remains in Overview/Library rather than becoming
completed history.

Each Action is one native full-row button with a direct symbol, the shortest
accurate title, explanation only under §19.6, and only when useful a trailing
chevron or shortcut. Its modular sheet shows the necessary scholarly inputs
and app-owned authority or recovery facts without exposing assembled prompts,
package internals, or technical mode names. The active Action and its sheet
retain keyboard, menu, pointer, focus, cancellation, and VoiceOver parity.

Functional text is never a generic blue link or a separate **Open** button.
Body and secondary colors, hover surface, focus ring, button semantics, and
the full hit region make interaction recognizable without depending on color,
hover, or pointer use.

All section headings across Overview, Connect, and Actions
use one Apparatus heading token. Its provisional starting point is 10pt system
semibold, 0.7pt tracking, and secondary text color. English localization
supplies uppercase strings; runtime code never forces case, so Chinese and
other languages retain natural writing.

Inspector layout uses named `ScholiumGrid.Apparatus` variables rather than
leaf-view literals. Short facts form one section-level two-column grid with a
shared label column and first-baseline alignment. If the available width or
localized labels cannot fit, the complete grid becomes stacked; individual
rows never switch independently. Scope, Research Scope, Limitations, and other
long researcher prose always use a reading block: label on its own line and
Alegreya content on the next line with a 12pt leading indent. Labels and action
names remain system sans semibold; field values, explanations, and research
prose use Alegreya; exact paths and revisions remain monospaced. Counts use
monospaced digits without changing the surrounding face.

Provisional rhythm is a 28pt minimum scanning/action row, 12pt Alegreya with
approximately 17–18pt reading leading, 4pt label-to-copy gap, 8pt between
reading blocks, and 16pt between sections. The native comparison catalog and
human review may revise typography, grid, indent, and spacing while preserving
semantics, interaction, researcher control, and accessibility.

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
Editing** or **Reload from Disk**. Checkpoint restore, editor Undo, and Research
Record are never interchangeable; editor `Command-Z` never means checkpoint
restoration.

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
| Back to Library | 返回研究文档 |

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

### 19.1 No custom glass

Scholium-owned surfaces are opaque. No custom glass, blur, vibrancy,
translucent/material cards, image-behind-glass, large radii, text gradients, or
decorative shadow defines the brand; depth uses tone, spacing, alignment, type,
rules, and restrained elevation.

System chrome, menus, presentations, controls, focus, selection, semantic
Sidebar/Inspector, and tracking separators stay native. Document tabs are
ordinary Document controls, not simulated window tabs. Incidental system
material is not a token. This supersedes prior glass/material rules.

Research Guidance, Actions, permission sheets, and Research Record use
continuous native planes, textual list/detail structure, editorial hierarchy,
fine rules, alignment, and deliberate whitespace. They do not use per-Skill
cards, colorful category tiles, score badges, agent avatars, chat bubbles,
nested rounded containers, or decorative workflow diagrams. Selection and
consequence remain clear through native state, typography, symbols, and text.

Library lifecycle destinations and pane-local titlebar controls retain their
existing opaque plane. They neither dim retained content nor float above it,
and add no material, reflection, grabber, rounded panel, accessory row,
separately measured bar, shadow, or sheet motion. Pane-local hosts consume the
native safe area once; the titlebar owns vertical alignment.

### 19.2 Typography and color

- System sans is interface structure: navigation names, chrome, menus,
  controls, Settings, alerts, section headings, field labels, action names,
  dates, and compact scanning cues. The fixed **Scholium** Alegreya wordmark
  remains the identity exception.
- **Alegreya** is for Review/Edit prose and may identify content-derived
  titles, linked research objects, researcher judgments, field values,
  explanations, Scope, Limitations, and other research content when density,
  scaling, and mixed-script fallback remain legible.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, paths, stable identifiers, and diffs.
- The default Appearance uses a **72ch** Line width plus **Alegreya 12pt**,
  **2.0** line spacing, **1em** paragraph spacing, **0.02em** tracking,
  justified text, and no hyphenation. Line width is configurable from
  **48–96ch** in **1ch** steps and is shared by Review, Edit, and Source.
  Its H1/H2/H3–H6 scales are provisionally **200/150/115%**, with centered H1
  and medium shared heading weight. These document typography values are
  user-configurable. Callouts inherit Body typography and expose independent
  role spacing/composition parameters without acquiring a separate palette.
- Provide intentional CJK serif fallback and test mixed Chinese/Latin lines.
- Color exposes exactly two approved sRGB inputs: **Accent** `#A94C22` and
  **Paper** `#F8F0E2`. One resolver derives every Light, Dark, and Increase
  Contrast semantic output; Library and Apparatus share the peripheral surface.
  No output, Navigation surface, or functional/status hue is independently
  configurable.
- Native and WebKit consume the same derived `ScholiumColorRole` outputs.
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
  narrowly approved editorial hierarchy. Document roles: Body,
  `heading(level:)`, Exact Source, Code, Diff, Revision Identity.
- Document Rhythm exposes one machine-local Line width input with the default,
  range, unit, and shared-mode ownership in §18.4. It creates no second
  built-in measure path.
- The Color family exposes only the two approved Accent and Paper inputs.
  Semantic roles are resolver outputs, not additional Variables; components
  consume those roles without owning a palette value.
- Surfaces are opaque semantic planes; dense evidence is quietest and most
  legible.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones.
- Native controls own interaction states. Custom targets prefer **28pt** and
  never fall below **20pt**; this does not redefine native sizes.
- Standard actions use direct SF Symbols. Domain symbols may centralize
  Scholium meaning, but text remains primary.
- Grid roles are optical alignment **2pt**, label/accessory **4pt**, inline
  control **8pt**, nested content **12pt**, section separation **16pt**, and
  region content **20pt**. Fixed component anchors remain purpose-owned:
  compact hierarchy row **24pt**, preferred/minimum custom targets **28/20pt**,
  Document tab strip **40pt**, Action target **44pt**, region header **48pt**,
  and Library footer **52pt**.
- The Library's **300pt minimum readable thickness** is a component-specific
  containment threshold outside the grid, not a spacing role, preferred width,
  or scene minimum.
- Set Aside and Trash reuse the region-content, inline-control,
  label/accessory, hierarchy-row, action-target, and footer roles above; they
  create no parallel spacing namespace.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, or decorative motion.
- Document rhythm remains renderer-aware and provisional until Review/Edit
  pass side-by-side review at ordinary, narrow, mixed-script, and 200%
  text conditions.

### 19.4 Provisional layout defaults

Layout defaults support testing, not independent gates. AppKit owns chrome and
split geometry; Scholium owns semantic order and necessary content insets.
Scenes have no Scholium numeric minimum unless the complete adaptation matrix
proves one. Independently, the Library content threshold in §18.2 adds no
preferred/maximum width or persisted divider position.

Initial sizes are Workspace **1180 × 760**, Bootstrap **720 × 720**, Research
Record **760 × 680**, and fixed Settings content **700 × 560**. Regions scroll
independently; Document takes remaining space without a fixed size. AppKit
geometry stays outside the grid. WebKit uses `rem`, `ch`, CSS px, and viewport
units without point conversion. The selected **48–96ch** Line width is centered
inside the available Document width while `max(...)` retains the **20/32/40 CSS
px** minimum border separations. Wide tables, code, and mathematics may scroll
inside that measure; prose reflows without page-level horizontal reading
scroll. The 72ch default and typographic rhythm still require ordinary, narrow,
mixed-script, and 200% visual acceptance. Fractional browser-proof translations
are superseded; screenshots and prototype coordinates remain evidence only.

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
a new recorded decision.

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
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, Action sheets, conflict comparison, and
  Research Record close.
- Direct note creation has pointer, **File → New Note**, keyboard-shortcut, and
  accessibility routes. A successful action moves selection to the created
  note; a failure leaves the current selection and source unchanged and reports
  the reason without opening a naming dialog.
- Lifecycle destination headings expose the localized name and successful
  count as one heading; active footer entries expose selection. The retained
  Library hierarchy is accessibility-hidden while a destination is active.
  Put Back remains in keyboard and VoiceOver order without hover, and row
  removal follows the next/previous/Back focus sequence defined in §18.3.
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
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
  every lifecycle/error state, and WebKit/AppKit focus transitions.
- At the Library boundary, verify both permitted narrow outcomes: expanded at
  **300pt or wider**, or natively collapsed. The open-but-unreadable compressed
  state is forbidden; the three Triptych scopes and longest fixed Library
  heading remain single-line at the threshold in English, with localized and
  right-to-left variants covered by the adaptation matrix.
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
content after native publication and WebKit readiness. Semantic projection or
an internal callback alone is insufficient. Retain raw durations, p50, p95,
maximum, mean, valid and invalid sample counts with reasons, correctness,
machine record, artifact identity, fixture identity, and raw outputs outside
every research vault. Missing process roles, changed process sets, provenance
mismatch, incomplete samples, or unapproved thresholds fail closed.

The 100,000-CJK fixture must remain editable at beginning, middle, and end with
working undo, mode switching, and byte-exact save. After 50 note/mode switches,
retained editor/WebView counts and total app-plus-WebKit memory must converge
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

Every target change records task, affected sections/scope, trust/source impact,
vault/app compatibility, required evidence, and new non-goals/questions.
Temporary code or visuals never become authority accidentally.

## 22. Decision index and unresolved work

Sections 1–21 are the complete contract. Stable or implemented decisions are
not restated here: implementation does not retire their target rules. This
index preserves IDs and canonical locations; deleted or superseded IDs remain
only in Git history.

| Decision | Canonical section | Decision | Canonical section |
| --- | --- | --- | --- |
| **D-003** | 5.1, 18.1 | **D-084** | 7, 8.1, 18.5 |
| **D-031** | 13 | **D-037** | 7, 8.1–8.2 |
| **D-038** | 8.4 | **D-039** | 5.2, 7.1 |
| **D-040** | 8.3 | **D-042** | 5.1, 18.4, 19.2–19.3 |
| **D-043** | 7.2 | **D-049** | 8.3, 15.3 |
| **D-050** | 8.4 | **D-052** | 18.2, 19.4 |
| **D-055** | 18.3, 18.5 | **D-059** | 8.1, 17 |
| **D-060** | 18.2, 19.1 | **D-074** | 3.2, 18.2 |
| **D-076** | 3.2, 16 | **D-078** | Introduction, 3–4 |
| **D-079** | 8.2, 18.5 | **D-081** | 18.7 |
| **D-083** | Introduction, 8.2–8.4 | **D-085** | 5.1 |
| **D-086** | 5.1 | **D-087** | 18.2–18.5, 19.3–19.4, 20 |
| **D-088** | 18.3, 19.1, 19.3–19.4, 20 | **D-089** | 18.7 |
| **D-090** | 18.2, 19.3–19.4, 20 | **D-091** | 18.2, 18.4–18.5, 19.1, 20 |
| **D-092** | 19.2–19.3, 20 | **D-093** | 18.2, 18.4, 19.2–19.4, 20 |
| **D-094** | 3.2, 18.2 | **D-095** | 18.2, 20 |
| **D-096** | 8.5, 14 | **D-097** | 19.5 |
| **D-098** | 13, 18.3, 20 | **D-100** | 5.1, 18.4, 19.2–19.4, 20 |
| **D-101** | 1–2, 5–11, 13–14, 18–22 | **D-102** | 5.2, 8.1, 13, 15.2, 18.4–18.7, 19.2–19.3, Appendix A |
| **D-103** | 5.3, 18.2–18.3, 20 | **D-104** | 3.3, 16, 18.1–18.2, 20 |
| **D-105** | 7, 8.1–8.2, 9–11, 13, 18.1, 18.5, 18.7, 22 | **D-106** | 1–3, 5–11, 13, 16–22 |
| **D-107** | 7.1, 8.1, 14, 22 | **D-108** | 7.2, 8.1–8.2, 18.4–18.5, 20, 22 |
| **D-109** | 18.5, 20, 22 | **D-110** | 8.2, 17, 22 |
| **D-111** | 7.3, 17, 22 | **D-112** | 18.5, 19.6, 20, 22 |

Clean-cutover inventory:

- **D-078:** do not rename or retain the removed project-specific role, schema
  profiles, evidential layer, CLI spellings, fixtures, decoders, or GUI
  contracts. Do not migrate or delete researcher-vault files; unsupported
  custom YAML stays exact source without acquiring a hidden app schema.
- **D-083:** retain no KBManager app-support import; v0 registry/window
  migration; noncanonical persisted vault-role spelling; retired Settings
  destination migration; retired Search scope or positional CLI Search form;
  duplicated status-property alias; single-prompt migration; deprecated
  Dialogue/Critique facade; package-entry `skills assemble` command; alternate
  Function CLI spelling; missing-field Research Skill binding decoder; or
  Dialogue response-contract fallback.
- **D-091:** retain no shared peripheral toolbar, split-item accessory row,
  custom title strip/height/background, load-time geometry change, duplicate
  Show/Hide route, or glass-wrapped transfer control. Inspector visibility must
  still use the exact native split.
- **D-092:** retain no static appearance palette, Navigation input, duplicate
  status role, renderer-owned color, or public functional/status hue. Accent
  and Paper remain the only inputs to the shared native/WebKit resolver.
- **D-093:** replace Document Styles with machine-local named Appearance
  configurations and retain no generated CSS preview. Keep protected semantic
  component structure, shared mathematics/code/table roles, and additive
  sanitized CSS compatibility. D-100 supersedes only D-093's former absence of
  a maximum document measure.
- **D-094:** one stable document appears at most once in one window's Document
  tabs; repeated open selects the retained page while other windows stay
  independent.
- **D-095:** content safety may veto a bounded close or termination attempt;
  machine-local presentation persistence may not, and late work is attempt-
  scoped.
- **D-096:** existing-file mutation requires durable expected/candidate bytes
  plus a verifiable displaced-file-preserving commit boundary; otherwise fail
  closed without a **Saved** claim.
- **D-097:** retain one approved application-icon lineage across debug, QA, and
  release bundles; retain no prior icon, Appearance-derived variant, mirrored
  copy, interface-glyph reuse, or packaging-specific replacement.
- **D-098:** retain exactly one Triptych lexical corpus, the three public
  scopes, finite contract-v4 syntax, exact-identity precedence, symmetric CJK
  verification, versioned freshness, a separate direct Related section, and
  the non-dimming opaque command surface and full-row editorial result-target
  treatment; retain no per-vault federation, hidden scope/filter bypass,
  raw-source corpus, vector/AI ranking, exposed implementation score, visible
  workspace scrim, custom blur, or partial system-selection slab.
- **D-100:** Appearance exposes one machine-local Line width, default **72ch**,
  range **48–96ch**, and step **1ch**, shared by Review, Edit, and Source.
  Retain no built-in preset, full-width switch, percentage mode, or per-mode
  override. Center the measure with the mode-specific minimum insets, keep
  Source exact-source typography, and update retained CodeMirror presentation
  without replacing its edit state.
- **D-101:** retained only for the three-mode Inspector, authoritative Markdown
  annotation, revision-bound Settle, short-lived write authority, and
  Application-owned containment, fingerprint, conflict, and recovery. D-106
  supersedes its chronology, public Action, and separate Comment model.
- **D-102:** separate canonical property vocabulary, default About profiles,
  and creation requirements; require no creation properties or
  required-looking markers.
  Remove all `status` semantics and Search support, Work `deadline`, Topic/Work
  YAML `title`, default Properties disclosure, About Customize, and visual
  Zotero presentation. Use role-aware Research Units: Analysis Completion plus
  Limitations, Topic/Work Scope plus Limitations, with Work labelled Research
  Scope. Resolve titles through the shared role-aware fallback. Treat
  `zotero_item_key` as an Analysis-only protected-machine field and attach one
  exact, labelled, nonblocking Zotero bibliographic snapshot plus the formal
  integration Skill to each eligible Research Action; never cache it across
  tasks, show it in Inspector, copy it into Markdown, or treat metadata as
  source evidence. Use one Inspector heading token, fact grids, long-text
  reading blocks, quiet meaningful empty states, and native full-row actions.
  No compatibility layer is retained for this pre-production cutover; unknown
  YAML remains exact source without recognized semantics. D-106 supersedes its
  former Action presentation.
- **D-103:** make New Note a direct focused-window action rather than a
  lifecycle sheet. Library Add and File/keyboard create an empty, selected note
  at the current vault root; a folder context action and accessibility
  equivalent create in that exact folder. Claim the first available
  `Untitled[ N].md` path atomically, retry only path collisions, never replace
  source, and omit the operation in protected machine-managed folders. Treat a
  folder only as a path classification, enumerate empty folders, and add direct
  `Untitled Folder[ N]` creation plus Rename, Move, and confirmed Move Folder
  and Notes to Trash. A folder operation renames one directory entry after a
  complete descendant-note revision preflight; notes—not folders—retain stable
  IDs, receive one batch path rebinding, and drive exact incoming-link and
  app-owned path migration. Non-Markdown descendants move byte-unchanged.
  Complete the menu with conditional Expand/Collapse All, Copy Relative Path,
  Reveal in Finder, note-row Copy Relative Path, and equivalent accessibility
  actions. Fail closed on managed Critiques, ambiguous projections, symlinks,
  destination/subtree collisions, stale inventory, or incomplete rollback.
- **D-104:** require a validated real per-user Application Support root before
  constructing production workspace state. Retain no temporary-directory
  fallback, implicit read-only runtime, queued workspace command, or modal
  alert loop. Storage failure owns the app root with default Retry, selectable
  Details, and Quit; retry revalidates from scratch. QA may use only an
  explicitly supplied isolated root.
- **D-105:** retain no Human
  Review, Qualification, ResearcherComment, app-owned Annotation, pre-Function
  Dialogue archive, or `review:` Search syntax, projection, database column,
  saved-query compatibility, UI, store, decoder, migration, or recovery path.
  Researcher annotations belong in authoritative Markdown as direct prose or
  semantic Callouts. Never convert retired app-owned records into Markdown or
  alter research files during clean cutover. D-106 supersedes its former
  passage-record authority by organizing Comments inside Discussion.
- **D-106:** adopt researcher-governed Research Actions and ordinary editable
  Method Skills. Expose Discuss/Analyze/Check Fidelity for Analysis,
  Discuss/Synthesize/Check Fidelity for Topic, and Discuss/Write/Critique/Check
  Fidelity for Work, with no default mode picker; keep Manuscript installed
  only as a hidden optional custom Action. Separate protected mechanism, directly
  editable Working Methods, read-only bundled references, Researcher Skills,
  and declarative Action Profiles. Classify Research Guidance by Methods,
  Researcher Skills, Permissions, Sources & Integrations, and Recovery &
  Technical rather than flattening packages. Use explicit active/disabled
  bindings with no silent bundled fallback, staged disabled-first local Skill
  installation, three standing permission policies, and independently bounded
  agent-requested child phases. Unify passage and whole-note Comments inside
  resumable Discussion. Remove Research Activity history and keep active
  Discussion in Actions while portable finished records use one independent
  fixed-size list/detail Research Record window, recoverable Record Trash, and
  disposable on-demand comparison. Record only narrow application facts, attributed agent
  testimony, and deliberate researcher judgment; infer no intention, truth,
  success, failure, or acceptance. Add revision-bound Material Changed Since
  Use without calling a Topic wrong or outdated. Delete superseded repository
  code, shipped legacy Skills, construction, decoders, projections, tests, and
  UI once replacements are reachable, while leaving researcher Markdown,
  unknown YAML, unrecognized Triptych files, and unsupported legacy data
  byte-unchanged and unauthorized. D-106 supersedes D-101 and D-105 wherever
  they require separate Comment/Discuss records, Research Activity, old public
  Actions, immutable bundled Workflow methods, or machine-local intellectual
  Research Records; their remaining source-integrity and clean-cutover rules
  stay in force.
- **D-107:** replace automatic whole-Triptych Action checkpoints with bounded
  exact-Note recovery. Opening an Action saves only its current Target;
  preparation never flushes unrelated Notes. Scholium-mediated writes retain
  displaced exact bytes through the per-Note recovery ledger, while manual
  whole-Triptych checkpoints remain researcher-initiated. Each distinct Settle
  revision pins one machine-local exact-byte version, deduplicated by stable
  Note and fingerprint. Recovery & Technical offers per-Note limits of 10, 30,
  50, or no automatic deletion, defaults to 30, and explicitly previews older
  pins before a lower limit removes them. The confirmed exact pin set is
  journaled until idempotent cleanup finishes, without absorbing later pins.
  Portable Settle state remains one current judgment per Note and remains
  semantically independent of recovery. Retention order is a durable per-Note
  monotonic sequence and does not change when the machine clock moves backward.
- **D-108:** make Comment a lightweight revision-bound line annotation rather
  than an agent handoff. Expose it only from Review through its transient
  selection bar; keep Edit's separate selection bar limited to formatting;
  save Comment in place with Return, insert a line with
  Shift-Return, and cancel with Escape. New Comments retain only Note identity,
  fingerprint, and inclusive line range, never selected text, quotation,
  context, or exact offsets, and never attempt reattachment after the Note
  changes. Discuss deliberately starts agent interaction, automatically
  collects the current Note's Comments, and reopens the one active Discussion
  through its own Action without a duplicate current-state row. Keep Source
  exact and free of Comment presentation, and keep required Action validation
  at preparation without blanking stable launchers or serially resolving the
  same Profile before a sheet can appear. Keep common formatting in Edit's
  selection bar, Format menu, and keyboard rather than duplicating it in the
  secondary-click menu; omit Preview from secondary click and keep footnote
  preview and navigation in Review. Give Review Comment and Edit formatting the same opaque,
  Variables-derived selection-surface style.
- **D-109:** keep Research Record recognizably secondary: one nonrestored,
  fixed **760 × 680** utility window with a readable list/detail layout. Retain
  no Workspace Sidebar control, user-facing wide/narrow choice, stacked
  responsive replacement, or primary-workspace adaptation. Keep the leading
  list compact and top-aligned without shrinking custom controls below the
  accessibility threshold.
- **D-110:** keep portable Research Record deletion as one researcher-initiated
  **Delete Record…** action with a destructive second confirmation. Do not
  expose Record Trash, Restore, or a hidden retained-trash lifecycle. Permanent
  deletion removes only the selected portable record and its derived Note
  projections; it never deletes Markdown, checkpoints, exact-note recovery, or
  unrelated records. D-110 supersedes D-106 only where D-106 requires
  recoverable Record Trash.
- **D-111:** because Scholium has not shipped, clean cutover exposes no legacy
  data entry. Unsupported pre-production machine-local bytes remain untouched,
  invisible, unparsed, unmigrated, unrecoverable through the product, and
  nonauthorizing. Current portable Skills retain **Reveal Skills Folder**;
  there is no **Reveal Legacy Data** command. D-111 supersedes D-106 only where
  its preservation rule previously implied a manual reveal route.
- **D-112:** make interface explanation exceptional rather than routine. Begin
  with the shortest accurate label; omit supporting copy when label and context
  suffice. When necessary, use one terse sentence or fragment authored for at
  most two ordinary-width lines. Do not repeat one meaning across visible copy,
  tooltip, and accessibility hint. A disabled Action shows only its first
  executable repair. Keep permission, provenance, conflict, destructive
  consequence, failure, and recovery detail in the appropriate body or
  presentation rather than hiding or truncating it to satisfy brevity.

Unresolved work must not be described as complete:

- sustained manual VoiceOver, Full Keyboard Access, Voice Control, Dictation,
  contrast, scaling, localization, and installed-IME acceptance;
- final document rhythm and production mono comparison;
- researcher-governed Actions/Skills implementation, unified Discussion, and
  portable Research Record acceptance;
- broader Search ranking/usability evaluation;
- packaged Release performance thresholds and measurements; and
- clean-tagged distribution and external-install evidence.

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

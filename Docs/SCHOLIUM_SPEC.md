# Scholium Specification

**Status:** Canonical product, interface, and release specification
**Applies to:** Scholium for macOS and its agent-facing CLI
**Canonicalized:** 2026-07-17

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
- A **Research Function** is a researcher-selected scholarly operation exposed
  by the Research Inspector's **Actions** mode and executed through the shared
  Application API. **Work with Agent** is its entry point for bounded discussion
  or an explicitly chosen write; Fidelity, Critique, and Manuscript remain
  separate actions where the role permits them.
- A function's **Origin** is the immutable current Analysis, Topic, or Work
  from which the activity begins. Its **Materials** are explicitly selected
  read-only notes. A Write additionally freezes one authorized set of existing
  active note identities under Current Note, Selected Notes, Analyses and
  Topics, or Entire Triptych; a Material never becomes writable merely because
  the agent read it.
- A **Comment** is a deliberate passage-scoped communication exchange with an
  agent: researcher request, agent reply, researcher Finish. Only Finish emits
  the durable **Commented** activity. Written annotations remain authoritative
  Markdown, optionally expressed as semantic Callouts; they are not app-owned
  records.
- **Settle** is the researcher's idempotent, fingerprint-bound judgment that
  one saved revision is sufficiently stable for current research. It is neither
  a verdict nor a qualification.
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
- A **Research Activity Grant** is one short-lived, task-bound write authority.
  Its plaintext key is carried only in the prepared handoff; Scholium persists
  only a digest and the frozen Origin, scope, identities, revisions, and expiry.
- **Research Record** is the note-following detail view for durable research
  activity, Comment exchanges, Critique, and provenance. It is a nonmodal
  secondary window and contains no versions. Ordinary Markdown annotations
  remain in the document and never appear as separate chronology.
- A **Checkpoint** is a self-contained, fingerprint-bound snapshot of the
  complete Triptych, distinct from editor Undo.

There is no formal Revision artifact, Proposal, Research Task, or Research
Session. “Revision” may still describe an edit or a Critique section.

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
mutate files through filesystem or CLI tools. Scholium issues no workspace-wide
or persistent permission and never revives Proposal. Each prepared Write uses
one short-lived Research Activity Grant whose key, frozen scope, and completion
command authorize only that activity. Comment, Discuss, and Critique remain
optional.

Scholium supplies safety, not transferred responsibility:

- exact paths, stable identities, and Application-owned fingerprint checks;
- autosave, atomic writes, external-change detection, and conflicts;
- automatic and manual Triptych checkpoints, comparison, and restoration.

Extensive external work without a suitable checkpoint is not guaranteed
recoverable. Fingerprints detect revisions; they are not permission tokens and
do not need to be copied into the agent prompt.

The Application API validates each Research Function's Target, Materials,
revision, method, checkpoint, and completion contract. Frontends select
semantic functions, never package identifiers or skill source. An intellectual
operation uses exactly one complete primary method: an official Workflow Skill
or an explicitly compatible Researcher Skill. System Skills supply protocol;
Practices only supplement. Direct Source Analysis and raw Zotero retrieval do
not require a Research Function.

Beta distinguishes:

- protected, release-managed **System Skills**;
- read-only, release-managed **Workflow Skills**; and
- editable **Researcher Skills**, including independent copies of permitted
  bundled packages and researcher-owned Philosophical Practices.

Bundled methods assist warranted, source-faithful, reviewable work; they do not
teach philosophy, certify truth, or replace researcher judgment. Researcher
methods remain researcher-owned responsibility.

### 2.3 Authorship and provenance

Keep independent: Origin and confirmed modified identities; vault role and
location; settlement fingerprint and changed-since-settled state; Critique
authorship; and Comment or Discuss turns. Agent origin
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
- prompt templates, workflow assignments, function/citation bindings;
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
- app-owned Research Activity, Settlement, Comment, Discuss,
  Critique, and Research Record data; and
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

- Read, Live Preview, and Source over one exact Markdown buffer;
- autosaved editing without an ordinary Save button;
- create, duplicate, import, rename, move, Reveal in Finder, Set Aside, Trash,
  Put Back, and permanent deletion;
- exact-source preservation, conflict detection, atomic writes, and external
  coordination;
- source-located Connect relations, passage Comments, and authoritative
  Markdown annotation including semantic Callouts;
- role-aware Properties and one-note or multi-note Discuss/Write;
- Search in **This Note**, **This Vault**, or **Triptych**, plus Attention; and
- Research Record and independent checkpoint recovery.

Critique bodies are read-only in Scholium but remain ordinary externally
editable Markdown; Scholium does not set filesystem read-only permissions.

### 5.1 Document modes and YAML

- **Read** renders committed content for reading, selection, navigation, and
  commenting.
- **Live Preview** edits the exact body through a visual projection, shares
  Read's semantic render components, typography, callout presentation,
  document measure, and theme variables, reveals syntax only around the active
  construct, and shows neither YAML nor line numbers. Inactive content should
  match Read; caret, selection, marked-text composition, and the active
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

An inactive Live Preview callout atomically projects one half-open source
range. Selection reveals source only on actual overlap, not boundary contact.
Down Arrow from above enters at the range start; Up Arrow from below or a
pointer press on its rendered title/body enters at its logical end. CodeMirror then
resumes native editing. Only the disclosure mark changes fold state by pointer;
the focused summary retains keyboard disclosure.

Read and Live Preview support Obsidian-compatible inline `$…$` and display
`$$…$$` mathematics outside YAML, code, raw HTML, comments, and escaped
delimiters. The immutable editing dialect owns exact delimiter behavior.
Malformed or unsupported mathematics stays visible as exact source with a
diagnostic; rendering never rewrites it.

Read and Live Preview treat Obsidian-compatible `![[Target]]` embeds, including
aliases and heading or block fragments, as source-located neutral links.
Inactive embeds share protected presentation, navigation, and diagnostics; the
active construct reveals its exact syntax. This stage neither reads nor
transcludes target content or creates philosophical relationship edges. Any
later transclusion requires a separate recursion, cycle, authorization,
external-change, and large-file contract.

Internal links, Vector Links, and footnote references provide bounded previews
without becoming evidence or another source authority. A footnote preview
contains only the referenced definition. Read may preview on ordinary hover;
Live Preview requires Command-hover so pointer editing remains primary. Both
provide keyboard, menu, and accessibility-equivalent routes, and activation
still performs the ordinary link or footnote navigation action.

Read and Live Preview have a direct keyboard toggle. Source is entered through
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
generic workflow state. An authorized agent edit follows the Research Activity
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
Link Graph, and Research Functions.

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
a new identity with no inherited Settlement or Research Activity and records
origin. Confirmed moves/renames preserve records and update resolved incoming
links. Ambiguous external rename keeps the note readable but blocks
identity-dependent mutation, Settle, Research Record, and Comment
attachment until confirmation.

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
- **Delete Permanently** purges the note, Comment and Discuss
  exchanges, Settlements, Research Activity, associated Critique, and
  note-specific app state from live storage and every checkpoint. A checkpoint
  that cannot be scrubbed is invalidated and removed; a shared activity record
  remains only for other notes and records the removed participant.

Note-specific records follow stable identity into Set Aside and Trash while
recovery remains possible. Permanent deletion advertises no checkpoint or
Research Record recovery.

## 7. Settlement and Comments

### 7.1 Settle

Settle is available for every active Analysis, Topic, and Work from the lower
right of Research Activity. It binds to the exact saved fingerprint, accepts an
optional rationale, records date and researcher identity, is idempotent for that
fingerprint, and never blocks on an agent response or Fidelity warning. Save
failure, dirty conflict, unknown stable identity, or a revision mismatch blocks
Settle. The current fingerprint shows a quiet Settled state; a later saved
fingerprint keeps the historical record, offers **Settle Again**, and produces
the transient **Changed Since Settled** HUD and Attention state. Response ready
and Awaiting Fidelity appear as nonblocking reminders in the confirmation; the
researcher retains the judgment.

### 7.2 Comment and written annotation

Read, Live Preview, and Source expose **Comment** for an exact passage
selection. Comment opens a complete agent-communication exchange with reply
recording, Follow Up, and researcher Finish. Finish is the sole operation that
appends **Commented**. Comment has no whole-note fallback, and reattachment
remains available only when quotation and context identify one reliable
location.

Scholium has no app-owned Annotation record, marginal-note store, Annotation
action, or overlay. A researcher annotates a document authoritatively by
editing its Markdown, including an ordinary semantic Callout when a visibly
separate note is useful. Scholium never converts retired Annotation records
into Markdown automatically.

### 7.3 Clean cutover

Pre-production Human Review, Qualification, ResearcherComment, app-owned
Annotation, and pre-Function Dialogue payloads are unsupported and are not
decoded, migrated, projected, searched, or displayed. The cutover does not
delete, rewrite, or synthesize research Markdown. Current Comment, Discuss,
Research Activity, Settlement, Critique, and Function records remain distinct
current authorities.

## 8. Research Functions and direct agent work

### 8.1 Research Functions and function contract

The Research Inspector's **Actions** mode exposes only the functions valid for
the current role-valid note:

| Target | Functions, in order |
| --- | --- |
| Analysis or Topic | **Discuss, Write, Check Fidelity** |
| Work | **Discuss, Write, Critique, Check Fidelity, Manuscript** |

**Work with Agent** is a static grouping title, never a launcher, menu, or
intermediate choice screen. Its **Discuss** and **Write** rows are directly
reachable. Discuss is read-only. Write opens the internal Develop method for an
Analysis or Topic and the internal Revise method for a Work; those method names
remain implementation identities rather than additional launchers.

**Check Fidelity** prepares the complete Fidelity Research Function with its
selected scope, exact revisions, Materials, method skills, and agent handoff.
Selecting the row never synthesizes a result or Research Activity event; only
validated agent completion against the exact revision may do so.

These stable operations are not a taxonomy of philosophy. There is no Manage
Comments doorway, Review or Annotation state, or embedded settlement sheet.

The optional-agent journey is choose function, inspect context, prepare durable
run, hand off, explicitly paste/submit when needed, then inspect source and
run state.
Hide technical identities unless repair or recovery needs them.

Beta uses provider-neutral copy-first handoff. **Copy and Choose Agent App…**
copies complete instructions, explicitly selects and remembers one macOS app on
this Mac, then opens it. Later actions are **Copy and Open [App]…**, **Copy
Only**, **Choose Another Agent App…**, and **Forget Agent App**. The app-wide
preference stays outside Triptychs. Scholium never infers an app, pastes,
submits, starts a turn, or sends research/account/model/permission/configuration
data in the launch request.

**Choose Another Agent App…** changes the preference without launching the
replacement; **Forget Agent App** removes only that preference.

Chooser cancel or launch failure preserves copied instructions and durable run
with copy, choose-again, retry, and cancel. macOS launch acceptance is not agent
acceptance or completion.

1.0 adds **Open in Codex** without replacing provider-neutral or copy-only
routes. After durable preparation, it opens a new local Codex task at the exact
requested working root. A locator-only prefilled composer carries Triptych/run
locators and the supported CLI bootstrap command, never Target or Material
content in the launch URL. Scholium does not append to an existing task,
auto-submit, select a model, alter Codex configuration or permissions, install
Codex, or report agent execution. Unavailable Codex or an invalid root leaves
the run recoverable with copy, retry, explanation, and cancel routes.

Each function uses one typed panel with immutable current-note Origin.
Agent-facing panels select read-only Materials through Search, optional
Suggested Only, an individually removable Selected Materials tray, and the real
vault hierarchy. Search covers title/alias/filename/path and retains ancestors;
nothing is preselected or bulk-selected. Distinguish loading, true empty, and
blocking failure with Retry Materials. Preparation freezes selection.

Suggestions use only resolved one-hop Connect relations, in order: from the selected
passage, from the Target, then directly to the Target. Each states its reason
and source location when available. Transitive paths, lexical or AI similarity,
Comment text, and inferred evidential roles are forbidden. Suggestions navigate;
they are not evidence.

A current source selection may default Critique or Fidelity to **Passage**;
otherwise those actions use **Whole**. Passage **Comment** is not a function
panel: the researcher submits a request, the agent replies, and the researcher
chooses Follow Up or Finish. Finish alone creates Commented. **Discuss** is the
read-only Work with Agent method for whole-note or multi-note reflection. A
finished Discuss with no confirmed write creates Discussed; once the researcher
chooses Write, completion creates Developed or Revised instead and never also
creates Discussed.

The direct **Write** row asks the researcher to authorize exactly one scope:

- **Current Note**;
- **Selected Notes**, initially empty and explicitly chosen by the researcher;
- **Analyses and Topics**; or
- **Entire Triptych**.

Resolved linked notes may be recommended inside Selected Notes but are never
selected automatically. The authorized set includes only existing active
Analysis, Topic, and Work identities; it excludes Materials, Critiques,
Comment/Discuss records, lifecycle/control files, generated state,
Set Aside, Trash, Unclassified, creation, deletion, and rename. The Origin is
recorded separately and receives an activity node only if its source actually
changes. Preparation freezes the scope and identity set for that run.

Transport may include the instruction; selected paths and passages; Triptych or
Work context; Research Units; links; destination/edit rules; exact read set;
and, only for Write, the activity key, frozen scope summary, and one supported
completion command. It does not expose per-note fingerprints or ask the agent
to calculate evidence. Origin and Materials are focal context, not general
authorization. Prompts, model settings, token counts, and paragraph-level AI
provenance are not permanent records. Each run has one overall instruction.

Conditional methods persist one read-only preflight with primary method,
checkpoint, and Discuss/Critique record. The agent finalizes explicit
resources; empty means primary-only. The same run receives only selected pinned
resources and cannot mutate or complete beforehand. Generic retrieval is not
function-resource evidence.

Work with Agent shows consequential scholarly context, not active template
source or assembled technical instructions. **Copy Only** uses the active
Settings template; **Open in Codex** transfers the same durable request identity
without making transport text part of the scholarly record.

After source changes, default to a concise academic change summary, material
unresolved questions, and needed review; file-operation detail is secondary.

Beta Discuss stores one immutable request `responseContract`: required
Academic Outcome plus optional Critical Reflection, Remaining Questions,
Philosophical Significance, Debate Context, and Research Directions. Modules
affect presentation only; they cannot expand scope, replace methods, or require
fabrication. Consider every selection without forced findings, weights, or
coverage ledgers. Fidelity, uncertainty, failure disclosure, and researcher
control always apply.

Develop, Revise, Manuscript, and every Work with Agent Write flush all open
authorized documents and create one whole-Triptych **Before Agent Work**
checkpoint before instructions return. Any save failure, dirty external
conflict, unknown identity, or unsupported target blocks handoff. Critique uses
its named checkpoint. Comment, Discuss, and Fidelity are read-only and create
none. The researcher may always instruct an agent outside Scholium.

### 8.2 Research Record and replies

There is no global conversation archive. Each participating note shows the same
shared Discuss or Write record with its Origin, authorized and confirmed sets,
researcher turns, attributed agent replies, and completion evidence. Comment
exchanges remain passage-specific. These are scholarly records, not versions,
prompt logs, or automatic approval queues.

The supported CLI validates request, activity-key, and Comment identities and
appends immutable attributed replies under Application Support. Replies may
address the instruction, one selected note, or one Comment. An agent never
edits the record database directly, finishes a Comment, or declares a source
modification authoritative. A non-CLI reply is recorded
only if the researcher returns it manually.

Beta CLI exposes the immutable `responseContract`; missing snapshots are
unsupported pre-release state and fail closed rather than adopting current
defaults.

Research Record follows the focused window's active Document tab. Its toolbar
and **Research → Show Research Record** routes open the same nonmodal secondary
utility window without opening, closing, replacing, or revealing Research
Inspector. It contains scholarly chronology and provenance only; checkpoints
remain File-owned recovery artifacts. Researchers may use Discuss without an
agent as a concise record of their own questions and decisions.

### 8.3 Research Guidance, prompt templates, and skills

**Settings → Research Guidance** alone edits prompt templates. Each workflow
has one active Triptych-local template. Create, duplicate, rename, delete, and
assign are supported; editing a default creates a researcher copy, while Reset
restores the bundled baseline without overwriting custom templates.

One local selector presents **Prompt Templates, Skills, Advanced**:

- **Prompt Templates** includes subordinate per-Triptych **Discuss Defaults**.
- **Skills** owns discovery, creation, duplication, editing, routing metadata,
  structural validation/repair, eligible evolution, Recovery, and **Reveal
  Skills Folder** for System, Workflow, and Researcher Skills.
- **Advanced** owns only cross-package Scholium CLI, citation method,
  Recommended Bibliography method, and Research Methods with Supplements and
  Practices.

Page-local list/detail dividers are not navigation sidebars. Bundled defaults
need no setup. Lists lead with name, purpose, function, origin, validity, and
active status. Bundled Workflow Skills offer Duplicate, not disabled editing;
Triptych packages allow edit, duplicate, Repair, and eligible Evolve. Package
faults route to Skills; binding faults to Advanced.

The five official Workflow Skills are **Development**, **Critique**,
**Revision**, **Content Fidelity**, and **Manuscript**. Discuss and Comment use
System transport/record infrastructure and Settle has no Workflow Skill. Source
Analyzer, APA 7 citation verification, and Prose Control are optional complete
or specialist copy-on-adoption Researcher Skills, not new ownership classes or
universal authorities. Source Analyzer has no Research Function and grants no
note-write permission.

Official packages may contain pinned one-level references/templates.
Duplication copies the bounded package under a new ID; releases update only the
official copy. System Skills cannot be edited, replaced, or shadowed.
Researcher packages are discovered only at
`.scholium/skills/<skill-id>/SKILL.md`, never notes, arbitrary/global paths, or
nested ownership. Malformed/colliding packages stay visible but unavailable;
structural validation certifies neither truth nor method quality.

Workflow Skills are complete without Practices. A Practice loads only its entry
and requested resource, records IDs/revisions, and supplements the primary;
retired `replace` bindings fail. It cannot alter inputs, permissions,
checkpoints, or writes. Consider each, report only material influence, expose
method conflict, and use no weights/coverage ledgers.

Development covers exploration, concept/argument development, synthesis, and
Analysis/Topic expression. Critique assesses without editing. Revision owns
substantive Work changes and feedback disposition. Content Fidelity is
read-only. Reviewer is an optional Critique calibration Practice. Manuscript
coordinates independently resolved phases, permits Practices only in
compatible child phases, duplicates no method, and grants no submission
authority.

Citation checks are available only when Application validates a Triptych-local
binding to the required capability and style. No filename or global directory
implies capability. Prose Control activates only by explicit researcher request
within Revision for meaning-preserving prose improvement; any change to thesis,
claim strength, concepts, inference, dialectical relations, source roles,
scope, modality, qualification, or status requires separately scoped
substantive writing. Revision owns write durability; Prose Control owns its
editable style profile and preservation ledger.

Application owns discovery, origin/update policy, bindings, dependencies, task
facts, permissions, and exact retrieval. Packages declare stable
`supported_functions`; `supported_modes` is internal. Records name exact
revisions/loaded resources. Core Protocol always loads; agent communication
transport only for Comment or Discuss; Triptych/Zotero/citation/Researcher
resources only when required. A
clipboard fallback cannot claim unretrieved packages.

**Settings → Research Guidance → Advanced → Research Methods** lets each
function keep the official primary, select one compatible researcher-owned
replacement, and add compatible supplements and exact Practices. Application
validates and atomically persists bindings. Actions receives
semantic availability only.

Workflow panels expose scholarly inputs, not prompt names, bodies,
placeholders, previews, skill pickers, or assembled transport. **Edit …
Template…** opens the exact Prompt Templates destination. Invalid active
templates preserve workflow input, explain the fault, and block generation
until repaired. Templates and skills create neither request taxonomies,
marketplaces, embedded runtimes, hidden authorization, nor scholarly records.

Only Triptych Researcher Skills may opt into evolution. Research Guidance
exports a revision-bound request, imports complete proposed-package JSON, shows
per-file comparison, validation, and separately attributed evaluation, then
offers Apply/Restore. Application requires expected revision and confirmation;
Core snapshots and atomically replaces or rolls back the whole package.

Global Recovery is independent of selection/validity; safe snapshots survive
missing/malformed packages and other corrupt snapshots. Restore confirms full
replacement, rechecks state, removes absent files, and first snapshots displaced
packages; missing-package restore is a guarded reinstall. Descriptor-relative,
no-follow reads prevent path/symlink redirection.

### 8.4 Function preparation, completion, and Fidelity

One Application coordinator owns app/CLI availability, preparation, completion,
and cancellation. Preparation resolves Origin identity and exact revision,
validates read-only Materials, resolves exact resources, creates recovery and
evidence, freezes any write set, rechecks revisions, and rolls back partial
preparation. Comment, Discuss, and Settle use separate typed authorities and no
write execution packet.

CLI uses only `function available`, `prepare`, `show`, `select-resources`,
`complete`, `prepare-fidelity`, and `cancel`. `show` recovers immutable state;
`prepare-fidelity` constructs/reuses the exact child. JSON `nextActions` are
typed argument vectors with optional stdin templates, never shell strings.
Work with Agent preserves Origin, Materials, selected passage, and researcher
instruction when the researcher changes from Discuss to Write, but the new
write scope remains an explicit choice.

For a Write, Scholium creates an activity ID and a cryptographically random
activity key after the checkpoint succeeds. The key binds only the current
Triptych, activity, method, frozen note identities, permitted roles, and an
expiry no later than 24 hours and the current run. Only its digest persists.
Completion, cancellation, revocation, or expiry invalidates it. Repeating the
same completion payload is idempotent; a different payload after completion
fails closed.

The agent completes the activity by presenting the key and candidate modified
paths or stable identities. Scholium normalizes each path, rejects traversal,
symlink escape, out-of-scope files, role mismatch, identity substitution,
create/delete/rename, and unsupported lifecycle state, then compares the
current fingerprint of every authorized note with its frozen start revision.
The Application, not the agent, derives the confirmed modified and unmodified
sets, performs revision checks and readback, and records only successful source
changes. A reported unchanged note is unmodified. An authorized note changed
but omitted from the report becomes a Research Record discrepancy and Attention
item, not agent-attributed activity. Any scope or identity violation revokes the
grant and routes to checkpoint recovery.

One multi-target completion creates one shared activity record and one durable
event on every confirmed modified note. The Origin receives an event only when
confirmed modified. Each HUD tooltip or focus detail gives the date, Origin
title, confirmed modified count, and unmodified count without monitoring or
summarizing paragraph content. Cancellation after external changes records the
cancelled run and preserves recovery; it never silently rolls source back.
Clean notes in other windows refresh from the confirmed commit, while dirty
peers keep their buffers and enter ordinary conflict handling.

`version`, `doctor`, and hierarchical `help` need no Triptych. Parsing rejects
unknown/duplicate/valueless options before Application state; JSON errors use a
stable envelope. Packaged apps contain a version-matched helper; Settings
installs exact bytes locally, verifies execution, reports PATH separately, and
never edits shell profiles.

Beta application launch uses complete prepared instructions; 1.0 Codex launch
uses preparation identity and CLI bootstrap. Neither adds a second API.
Prepared, cancelled, completed, Awaiting Fidelity, verified, unverified, and
stale states remain coordinator-owned; launch status is ephemeral delivery
only.

Manual and Automatic Fidelity share evidence validation. Manual targets the
current revision or the confirmed set of one shared write activity.
Develop/Revise finalization creates or reuses a child with the same inputs, and
Manuscript reuses its final Revise child. One multi-target Fidelity run records
one shared run plus an exact result for each note revision; it never collapses
mixed per-note outcomes into a single verdict. Critique, Comment, and Discuss
create no write Fidelity.

With no embedded agent runtime, automatic children remain Awaiting Fidelity
until outcomes arrive. Only a matching completed child advances the parent;
direct write-run outcomes fail. Deterministic keys reuse identical function,
scope, evidence, checks, and revision. Missing evidence leaves Awaiting/
Unverified; later changes make it Stale. Provenance and record types stay
distinct.

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

1. Create or import an Analysis and write or revise it against the available
   source.
2. Read it, follow relevant Connect relations, and add Markdown Callouts,
   direct prose edits, or passage-specific Comments when useful.
3. Use Work with Agent or Fidelity when useful. Discuss is read-only; Write
   uses Development and may update the explicitly authorized current or
   multi-note set.
4. Direct Source Analysis may inspect an available source without creating a
   Research Function, stored PDF, or Zotero control.
5. The researcher decides what to incorporate and whether related Topics or
   Works need updates.

For a long source, maintain one source-level Analysis by default. Each session
declares a bounded unit and applies required orientation, analysis, and synthesis
passes. Expand Research Unit only to material actually represented and record
unread, excluded, unreliable, or incompletely analyzed material as
Limitations. Chapter sections need not become separate Analyses. Create a
separate Analysis only by researcher request or when a segment needs an
independently citable identity. `complete` means complete for the declared
unit; **Entire source** requires source-wide analysis.

## 10. Topics workflow

1. Create or update a Topic from Analyses actually used, preserving
   disagreement, limitations, and uncertainty.
2. Read it and follow Connect relations to sources and Works.
3. Add Markdown Callouts, direct prose edits, or passage Comments, or use Work
   with Agent or Fidelity; Discuss is nonmutating and Write uses Development.
4. Decide whether other materially affected notes need updates.

Scholium never auto-merges an Analysis into Topics. It may report relevant
material, but neutral or transitive Connect relations establish neither
integration nor support. Topics have no persistent Critique; an assessment
request normally uses Discuss or an explicitly authorized Write.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers may scaffold, write, revise, and organize Works directly. Agents
may do so when instructed, but Critique remains visibly separate. Critique is
optional. Critique assesses, Revision writes, and Manuscript coordinates
isolated phases while retaining one immutable Origin and any explicit bounded
write set.

### 11.2 Critique target and storage

- A Critique targets one Work; broader reflection uses multi-note Discuss.
- Each Work has at most one current Critique document. Later rounds update it;
  prior rounds and researcher dispositions remain in Research Record without
  restore semantics.
- Critiques are recognized only in the designated `Critiques/` area.
- Bodies are read-only in Scholium, but files remain externally editable and
  may be renamed or moved within Critiques, Set Aside, restored, trashed, or
  revealed.

### 11.3 Critique function

Critique uses **Whole | Passage**, includes applicable passage Comments, and
accepts an optional focus or disciplinary lens. A current selection defaults
to Passage. Whole evaluates important claims, premises, arguments, sources,
objections, and alternatives against selected Analyses and Topics; this is an
attributed assessment, not an automatic diagnostic. Passage stays bounded
unless the researcher broadens it.

The panel uses the Triptych's active Critique template without one-run editing
or technical-instruction preview. **Edit Critique Template…** opens **Settings
→ Research Guidance → Prompt Templates → Critique**, where placeholders,
validation, preview, management, and reset belong.

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
Connections, malformed metadata, or unresolved identity. It never infers
**Superseded** or a philosophical verdict, uses age alone, or
issues automatic untraced-premise verdicts. Warnings are dismissible; Settings
controls duration, default seven days. The researcher retains judgment.

## 14. Checkpoints, versions, and recovery

Autosaves create no visible versions. Before every Work with Agent Write,
Manuscript mutation, or Critique, Scholium creates a named, fingerprint-bound
whole-Triptych checkpoint. Comment, Discuss, Settle, and Fidelity create none.
The researcher may choose **Create Checkpoint…** at any time.

Every checkpoint is self-contained; includes all vaults and portable control
state needed to interpret them; lives outside the vaults; and never depends on
another checkpoint, even if filesystem cloning is used internally. The latest
ten automatic checkpoints are retained; manual checkpoints remain until the
researcher deletes them.

File offers **Create Checkpoint…**, **Restore from Checkpoint…**, and **Reveal
Checkpoints in Finder**. Restore compares created, changed, moved, and deleted
files and supports selected-note or whole-Triptych restore. A full rollback
moves post-checkpoint files to Trash instead of permanently deleting them.
Restore writes new current source through the conflict-aware repository path;
Undo remains editor-session only.

There is no checkpoint-management screen or proprietary backup format. Finder
manages folders. Document, HTML, PDF, and DOCX export is deferred, not
permanently prohibited.

Invisible pre-write recovery state may support exact save/conflict recovery,
but it is not Document history, a user-visible version browser, or an
alternative to checkpoints. Corrupt legacy recovery metadata must not cause
unrelated recoverable bytes to be deleted or silently attributed to a note.

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

When any Analysis Research Function begins preparation with a non-empty key,
Application performs one exact local item read and automatically attaches the
catalogued `scholium-zotero-integration` System Skill. The immutable function
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
not a Research Function, Inspector launcher, note appendix, Zotero write path, or
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
Research Functions. CLI provides `bibliography prepare`, `show`, `complete`,
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
- app-enforced agent authorization or Proposal approval;
- automatic philosophical support, settlement, sufficiency, truth, prose
  authorization, or untraced-premise verdicts;
- Zotero replacement, embedded PDF reader, proprietary backup export, or
  arbitrary Obsidian-theme compatibility; or
- bundled general instructions purporting to teach researchers philosophy.

Deferred until the dependable core is accepted, but required for later Beta:
protected System Skills, five official Workflow Skills, bounded selective
assembly and Manuscript phases; request-scoped Discuss `responseContract`;
and protected Zotero MCP transport.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
additional contributed or discipline-specific workflows; richer Discuss
reflection and Comment-preservation modes; and Work finding overlays.

**Run with Codex** is not a 1.0 feature. Background/noninteractive execution,
auto-submission, streamed thread/tool state, approval handling, interruption,
and App Server or SDK orchestration require a fresh 2.0 decision. 1.0 **Open in
Codex** must imply none of them.

Prompt templates and file-backed skills are Settings-owned Research Guidance,
not a marketplace, runtime, specialized request taxonomy, or philosophical
authority. Finder remains authoritative for Markdown, attachments, and
checkpoint folders; Zotero for bibliography/PDFs; external agents for optional
open-ended work.

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
- Derive Read, Live Preview, Source, Properties, Search, and research views
  reversibly from authoritative Markdown; projections never reconstruct
  writable source.
- Distinguish source, researcher prose, agent content, Comment,
  Discuss, Write, Settle, Critique, Connect, and diagnostics by text and
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
Both share selected-document availability and preserve native transition and
geometry. Research Record and collapsed-Inspector Show remain visible but
disabled without a Target; a visible Inspector can always be hidden.

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
- **Research:** role-valid functions and **Show Research Record**, never
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

Read, Live Preview, and Source are modes, not tabs, and follow Section 5.1.
Ordinary scrolling space clears initial editor content from chrome; there is no
floating context surface.

All modes use one adaptive editorial-grid configuration for insets, responsive
threshold, trailing space, text scale, and semantic typography. The selected
Appearance supplies exactly one **Line width** value: default **72ch**, range
**48–96ch**, step **1ch**. Scholium provides no built-in preset, full-width
switch, percentage mode, or per-mode override. Remaining inline space is split
symmetrically with `max(mode minimum inset, (available width - line width) / 2)`.
The regular minimum inset is **32 CSS px** in Read/Live and **40 CSS px** in
Source; all three reduce to **20 CSS px** below **44rem**. The **32 CSS px** top
inset and existing trailing scrolling space remain separate. CSS lengths never
convert to macOS points. `ch` resolves against Read/Live Body type or Source's
exact-source type and therefore does not promise an exact character count.
Shared ownership and units are approved; the 72ch default still requires the
adaptation matrix and researcher side-by-side acceptance. Live Preview and
Source reconfigure one retained CodeMirror state; window, split, theme,
line-width, or text-size changes never replace it or create an Editor window.

Appearance is machine-local configuration and never Markdown or vault state.
It stores multiple named configurations, keeps exactly one selected, and
supports save, rename, duplicate, and deletion while retaining at least one.
Structured controls configure the shared Line width plus Body, headings, and
each semantic Callout. Line width applies to Read, Live Preview, and Source;
Body, heading, and Callout presentation applies only to Read and Live Preview.
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

Apparatus contains Research Inspector only; Research Record and checkpoint
recovery stay separate. Research Record is a nonrestored `UtilityWindow`, reads
the focused Workspace directly, and starts at **760 × 680** without treating
that size as a minimum. There is exactly one native trailing Inspector per
Workspace, with **Overview, Connect, Actions** in that order. These are
mutually exclusive modes inside the Inspector, not split columns, Document
tabs, panels, or windows. Their text labels use a restrained ink underline,
not a filled/capsule segment; labels remain horizontally reachable rather than
truncating. The selected mode is exposed accessibly, Left/Right Arrow changes
mode, Tab enters its content, and every mode owns at most one vertical scroll.

A new window begins in Overview and stores its last mode per window. Restoring
a window restores that mode; switching notes, Document tabs, or Read/Live
Preview/Source never changes it. Hiding the Inspector transfers only its Show
route under §18.2; no Inspector content moves into Document. Research menu and
keyboard commands may open a function without revealing the Inspector or
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

Actions begins with **Research Activity**, a compact horizontal HUD of all
actual durable events for the current note, followed by transient response or
currency states. Its icon-only nodes never predict a workflow. Pointer hover
and keyboard focus disclose date, source note title, and confirmed modified or
unmodified note count. It supports ordinary scrolling and explicit Previous or
Next controls. Selecting any node opens its Research Record detail.

Only these durable events may appear:

| Event | Sufficient evidence |
| --- | --- |
| **Created** | Scholium proves stable identity assignment on entry to the Triptych. |
| **Commented** | The researcher finishes one passage Comment exchange. |
| **Discussed** | The researcher finishes one Discuss with no confirmed write. |
| **Developed** | A confirmed Analysis or Topic fingerprint changes in a scoped Write. |
| **Fidelity Checked** | Fidelity completes successfully for that exact revision. |
| **Settled** | The researcher settles the exact saved fingerprint. |
| **Critiqued** | Critique completes and commits its attributed record. |
| **Revised** | A confirmed Work fingerprint changes in a scoped Write. |
| **Critique Addressed** | The researcher completes a fully disposed Critique round. |

Critique Addressed requires every actionable finding to be marked Accept,
Reject, or Rebut; every Accept must have its corresponding change or an explicit
researcher rationale for no text change; and the researcher must invoke
**Complete Round**. A single disposition, merely opening Critique, or an
ordinary Revised event is insufficient. Independent Comments remain independent
nodes and are never merged. Existing notes receive Created only when reliable
creation evidence exists.

Only **Response ready**, **Awaiting Fidelity**, and **Changed Since Settled**
may appear as transient actionable nodes. They do not enter completed history.
Response ready opens its Comment exchange directly; there is no separate Open
Comment button. Opening, reading, ordinary editing, saving, Search, selecting
Materials, preparing or copying a handoff, checkpoints, failure,
cancellation, and recovery create no HUD event. The latest end is visible by
default with a partial adjacent node when space permits. Trackpad, mouse-wheel,
Previous/Next, arrow-key, focus, and VoiceOver routes remain equivalent. Reduce
Motion changes scroll position without spring or node-growth animation.

Research Activity retains its heading and count when empty and shows no empty
card. Settle remains a direct action rather than an Open Comment control.
Actions then presents the static **Work with Agent** heading with direct
**Discuss** and **Write** rows, followed by role-valid **Critique**, **Check
Fidelity**, and **Manuscript** rows. Availability fails closed while checking;
an unavailable action states only its first executable repair. **Open Research
Record**, Show All, Retry, and Edit Properties use the same row treatment.

Functional text is never a generic blue link or a separate **Open** button.
Every action is one native full-row button with a direct symbol, title,
optional explanation, and only when useful a trailing chevron or shortcut.
Body and secondary colors, hover surface, focus ring, button semantics, and
the full hit region make interaction recognizable without depending on color,
hover, or pointer use.

All section headings across Overview, Connect, Actions, and Research Activity
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

Document has no bottom Research Strip or hidden-Inspector duplicate. Function
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
| Work with Agent / Discuss / Write | 与 Agent 协作 / 讨论 / 写入 |
| Develop / Revise / Manuscript | 发展 / 修订 / 稿件 |
| Settle / Settled | 暂定 / 已暂定 |
| Fidelity / Critique | 核查 / 评析 |
| Attention / Connect | 关注 / 连接 |
| Completion / Research Scope / Limitation | 完成度 / 研究范围 / 局限 |
| Checkpoint / Snapshot | 恢复点 / 快照 |
| Comment / Response | 评论 / 回应 |
| Research Activity / Research Record | 研究活动 / 研究记录 |
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
- **Alegreya** is for Read/Live Preview prose and may identify content-derived
  titles, linked research objects, researcher judgments, field values,
  explanations, Scope, Limitations, and other research content when density,
  scaling, and mixed-script fallback remain legible.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, paths, stable identifiers, and diffs.
- The default Appearance uses a **72ch** Line width plus **Alegreya 12pt**,
  **2.0** line spacing, **1em** paragraph spacing, **0.02em** tracking,
  justified text, and no hyphenation. Line width is configurable from
  **48–96ch** in **1ch** steps and is shared by Read, Live Preview, and Source.
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
  Document tab strip **40pt**, Function target **44pt**, region header **48pt**,
  and Library footer **52pt**.
- The Library's **300pt minimum readable thickness** is a component-specific
  containment threshold outside the grid, not a spacing role, preferred width,
  or scene minimum.
- Set Aside and Trash reuse the region-content, inline-control,
  label/accessory, hierarchy-row, action-target, and footer roles above; they
  create no parallel spacing namespace.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, or decorative motion.
- Document rhythm remains renderer-aware and provisional until Read/Live
  Preview pass side-by-side review at ordinary, narrow, mixed-script, and 200%
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

## 20. Accessibility and adaptation

- Support System, Light, and Dark without hard-coded inversion.
- Meet at least **4.5:1** contrast for ordinary small text and **3:1** for large
  or bold text; audit every important custom target below 28 × 28pt.
- Preserve hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive windows, 200% document text, and accent changes.
- Give every important state two suitable channels; never rely only on color,
  motion, sound, location, or arrow direction.
- Research Activity exposes the same recorded events as a linear accessible
  list, labels its actionable state without hover, and supports Previous/Next
  plus ordinary keyboard scrolling; horizontal swipe or drag is supplementary.
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, function panels, conflict comparison, and
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
- Live Preview/Source fidelity, formatting, passage Comment and Markdown
  Callout authoring,
  and mode changes;
- About/Properties, optional Research Unit, Settle, and Research Activity;
- native split resize/visibility, Document tabs without shell reconstruction,
  focus, keyboard, light/dark, scaling, minimum width, and core VoiceOver; and
- external edits, conflicts, stable rename, Set Aside, Trash, checkpoints,
  restore/interruption, and cross-window dirty-peer behavior.

Later Beta/1.0 additionally cover applicable Research Functions, hierarchical
Materials, Research Guidance/Recovery, Connections, Attention, Zotero
unavailable/read-only behavior, CLI parity, deletion/restore, adaptations, and
1380/1080/900/minimum-width workspaces.

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
| **G5 Scholarly transparency** | Authoritative Markdown, Comment, Discuss, Write, Settle, Critique, Fidelity, provenance, and uncertainty remain visibly distinct. |
| **G6 Accessibility/i18n** | Section 20's declared threshold is met. |
| **G7 Performance** | The packaged-app `PERFORMANCE_BENCHMARK.md` protocol passes on frozen fixture/machine. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | External binaries use a clean exact tag, corresponding GPL source/licenses, no private state, accurate signing/architecture, checksum, and clean-account smoke test. |
| **G10 Agent skill architecture** | Ownership, assembly, bindings, evolution, response contracts, bootstrap, and Zotero MCP pass declared journeys. |

Usable Core/0.1 require G1–G4, G6, and G8; G9 applies to any distributed
artifact. G6/G7 baselines and gaps must not be misrepresented as Beta passes.
Beta requires every applicable gate including G10. 1.0 additionally requires
the full **Open in Codex** journey; **Run with Codex** is not a gate. Current
evidence belongs only in `IMPLEMENTATION_STATUS.md`.

### 21.4 Change control

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
| **D-105** | 7, 8.1–8.2, 9–11, 13, 18.1, 18.5, 18.7, 22 | | |

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
  range **48–96ch**, and step **1ch**, shared by Read, Live Preview, and Source.
  Retain no built-in preset, full-width switch, percentage mode, or per-mode
  override. Center the measure with the mode-specific minimum insets, keep
  Source exact-source typography, and update retained CodeMirror presentation
  without replacing its edit state.
- **D-101:** Inspector exposes Overview, Connect, and Actions only. Overview is
  Attention, About, Zotero Source, and compact actionable freshness. Actions
  starts with real recorded Research Activity and then role-valid launchers.
  The HUD contains only Created, Commented, Discussed, Developed, Fidelity
  Checked, Settled, Critiqued, Revised, and Critique Addressed events; it may
  also project Response ready, Awaiting Fidelity, and Changed Since Settled as
  transient states. Work with Agent distinguishes read-only Discuss from an
  explicitly scoped multi-target Write. Comment is the sole app-owned passage
  action, written annotations remain authoritative Markdown, Settle is
  revision-bound and idempotent, and short-lived activity keys reduce agent
  burden without replacing Application-owned
  containment, fingerprint, conflict, and recovery checks. Pre-production Human
  Review, Qualification, ResearcherComment, app-owned Annotation, and
  pre-Function Dialogue payloads are unsupported after the clean cutover.
- **D-102:** supersede D-101 wherever it specified the former Properties,
  Zotero-in-Inspector, Work-with-Agent launcher, or action-row presentation.
  Separate canonical property vocabulary, default About profiles, and creation
  requirements; require no creation properties or required-looking markers.
  Remove all `status` semantics and Search support, Work `deadline`, Topic/Work
  YAML `title`, default Properties disclosure, About Customize, and visual
  Zotero presentation. Use role-aware Research Units: Analysis Completion plus
  Limitations, Topic/Work Scope plus Limitations, with Work labelled Research
  Scope. Resolve titles through the shared role-aware fallback. Treat
  `zotero_item_key` as an Analysis-only protected-machine field and attach one
  exact, labelled, nonblocking Zotero bibliographic snapshot plus the formal
  integration Skill to each eligible Research Function; never cache it across
  tasks, show it in Inspector, copy it into Markdown, or treat metadata as
  source evidence. Use one Inspector heading token, fact grids, long-text
  reading blocks, quiet meaningful empty states, native full-row actions,
  direct Discuss/Write rows under a static Work with Agent heading, and full
  Research Function preparation for Check Fidelity. No compatibility layer is
  retained for this pre-production cutover; unknown YAML remains exact source
  without recognized semantics.
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
- **D-105:** use one clean current research-record model. Retain no Human
  Review, Qualification, ResearcherComment, app-owned Annotation, pre-Function
  Dialogue archive, or `review:` Search syntax, projection, database column,
  saved-query compatibility, UI, store, decoder, migration, or recovery path.
  Comment remains the sole app-owned passage record and Critique automatically
  includes finished current-revision Comments applicable to its Whole or
  Passage scope. Researcher annotations belong in authoritative Markdown as
  direct prose or semantic Callouts. Never convert retired app-owned records
  into Markdown or alter research files during this clean cutover. D-105
  supersedes D-037, D-043, D-084, and D-101 wherever they require the removed
  records or Annotation surface; their remaining current-workflow rules stay
  in force.

Unresolved work must not be described as complete:

- sustained manual VoiceOver, Full Keyboard Access, Voice Control, Dictation,
  contrast, scaling, localization, and installed-IME acceptance;
- final document rhythm and production mono comparison;
- compact multi-note Discuss and richer reflection/compression;
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

## Appendix B. Default Critique prompt for Works

```text
Critique the Work identified in the Scholium request using the standards and
questions of a careful specialist in the relevant field. Apply those standards
without presenting yourself as a human specialist.

Critique scope: {{critique_scope}}
Critique lens: {{critique_lens}}
Selected passages or requested focus: {{selected_ranges}}
Additional instructions: {{additional_instructions}}

Inspect the relevant Analyses and Topics in the Triptych. Distinguish what those
notes report, support, dispute, or leave uncertain from your own reconstruction
or evaluation. Do not treat neutral links or transitive paths as evidence.

For a Whole Critique, explain the target's main strengths, major weaknesses,
source coverage, important omissions, objections or alternatives, and priorities
for change. Assess whether important claims, premises, and arguments are
adequately traceable to the available Analyses and Topics.

For a Passage Critique, identify the target line or passage, the issue, why it
matters, the relevant research basis, and a concrete recommendation.

Use the default sections Overall Assessment, Strengths, Major Concerns, Source
Support, Objections and Alternatives, Revision Priorities, Specific Findings,
and Materials Consulted and Limitations. You may label source-related findings
Traced, Untraced, Disputed, or Beyond Sources. These are your attributed
judgments, not Scholium statuses.

Always identify the materials actually consulted and any limitations. Write the
result to the designated Critique document. Never modify the target Work;
requested source changes require the separate Revise function.
```

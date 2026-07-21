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
  by the Research Inspector's **Functions** mode and executed through the
  shared Application API: Dialogue, Develop, Fidelity, Critique, Revise, or
  Manuscript.
- A function's **Target** is its one immutable Analysis, Topic, or Work. Its
  **Materials** are explicitly selected read-only notes; they are never
  implicit write targets.
- **Dialogue** records researcher Comments, agent Responses, and follow-ups. It
  may create transient external-agent instructions, but it is not chat, task,
  or permission infrastructure.
- **Human Review** is the researcher's fingerprint-bound review of an Analysis
  or Topic. It alone records **Qualification** as Qualified or Unqualified and
  is presented within Dialogue without becoming an agent-facing function.
- **Critique** is an attributed agent assessment of one Work. It does not
  replace or silently edit the Work.
- **Fidelity** audits the exact revision's philosophical content and, when an
  applicable Researcher Skill is bound, citations. It remains distinct from
  Human Review and Critique.
- **Connections** are source-located neutral, support, or incompatibility
  relations. **Attention** contains derived, recoverable warnings; it makes no
  philosophical judgment.
- **Properties** is the human-facing projection of frontmatter. A **Research
  Unit** is the minimal YAML declaration of the epistemic scope represented by
  a note; **Research Status** presents that unit and its material limitations.
- **Research Record** is the note-following chronology of Human Review,
  anchored Comments, Dialogue, Critique rounds and dispositions, and detailed
  provenance. It is a nonmodal secondary window and contains no versions.
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

Scholium supports source-grounded reading, writing, commenting, review, Search,
Connections, organization, recovery, and provenance. It is not project or
reference management, permanent AI chat, or a full Obsidian replacement. The
manual core must work without Obsidian, Zotero, or agents.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and may instruct an external agent to
mutate files through filesystem or CLI tools. Scholium issues no persistent
permission, Proposal, scope, or required token: only the current instruction
authorizes the task. Dialogue and Critique remain optional.

Scholium supplies safety, not transferred responsibility:

- exact paths, stable identities, and advisory fingerprints;
- autosave, atomic writes, external-change detection, and conflicts;
- automatic and manual Triptych checkpoints, comparison, and restoration.

Extensive external work without a suitable checkpoint is not guaranteed
recoverable. Fingerprints detect revisions; they are not permission tokens.

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

Keep independent: origin or last modifier; vault role and location; Human
Review and qualification; fingerprint and changed-since-review state; Critique
authorship; and Comments or Dialogue replies. Agent origin does not disappear
after review, qualification, incorporation, or later editing.

Visible labels stay sparse. Location communicates Analysis, Topic, Work, and
Critique roles; do not compose badges such as **Agent · Analysis**. Put useful
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
- app-owned Human Review, Comments, Dialogue, and Research Record data; and
- self-contained Triptych checkpoints.

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
Properties, Human Review, qualification, or Critique behavior until classified
into Analyses, Topics, or Works. Irrelevant Markdown should not be imported.

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
- source-located Connections and anchored researcher Comments;
- role-aware Properties and one-note or multi-note Dialogue;
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

Each vault has one profile for visible fields, order, disclosure, and editable
allowlist; no folder/note layouts exist. Identity, fingerprints, provenance,
and app facts are protected in Properties but visible in exact Source YAML.

The optional Research Unit has one shape:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

When present, `scope` is non-empty and `limitations` contains only material
claim boundaries—never role, identity, links, confidence, coverage percentage,
reading passes, timestamps, or derived facts.

New Analysis offers **Declare Now** or **Not Yet**. Not Yet writes no mapping
or sentinel. The note remains editable and available for Comments, Dialogue,
Develop, and a Human Review draft, but **Complete Review** requires declared
Research Status. Existing Analyses receive no migration. Topics and Works use
the same optional mapping only when it adds a durable boundary not already
clear from title, body, or links. An authorized agent edit follows ordinary
fingerprint, conflict, and source-preservation rules.

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

Properties presents `research_unit` as **Research Status**: Scope first,
non-empty Limitations second, and **Not Yet** when absent. A role-specific
top-level `status` is separate production progress, never time or truth. See
Appendix A.

### 5.3 Duplicate, rename, and identity

Paths are locations; notes have stable app-owned identities. Duplication creates
a new identity, resets Review/qualification, and records origin. Confirmed
moves/renames preserve records and update resolved incoming links. Ambiguous
external rename keeps the note readable but blocks identity-dependent mutation,
Review, Research Record, and Comment attachment until confirmation.

## 6. Note location, Set Aside, and Trash

There is no generic lifecycle status or advance control; location determines
active, Set Aside, or Trash state.

- **Set Aside** is direct and reversible. It records no reason or failure
  status. Set-aside notes remain readable but are excluded from ordinary
  Search, synthesis, Critique, and agent context unless explicitly included.
- **Move to Trash** excludes the note from ordinary Search, Connections, agent
  context, and workflows without immediately erasing it.
- **Put Back** restores the exact original vault-relative path and reports a
  conflict rather than inventing another name or destination.
- **Cancel** changes nothing.
- **Delete Permanently** purges the note, Comments, Dialogue, Human Review,
  associated Critique, and note-specific app state from live storage and every
  checkpoint. A checkpoint that cannot be scrubbed is invalidated and removed;
  an inseparable shared Dialogue is deleted in full.

Note-specific records follow stable identity into Set Aside and Trash while
recovery remains possible. Permanent deletion advertises no checkpoint or
Research Record recovery.

## 7. Human Review, comments, and researcher dispositions

### 7.1 Scope and completion

Human Review applies to Analyses and Topics; Works use Critique. Completion
requires a declared Analysis Research Status, a Qualified or Unqualified
verdict, and a non-empty Review Note of at most 500 characters.

Dialogue presents anchored Comments, agent Responses and follow-ups, and an
independent researcher-authored Human Review section. Human Review works
without an agent or prior exchange and never prepares instructions or chooses
Materials. The Review Note is a note-level judgment, not a Comment. The UI
shows a counter, never truncates automatically, and exposes only the applicable
**Review**, **Continue Review**, **Qualified**, or **Unqualified** state.

**Complete Review** stays unavailable until its conditions are met. If
Research Status is missing, offer **Declare Research Status…** while preserving
draft review, Comments, editing, Dialogue, and Develop. **Save as Draft** does
not mark the fingerprint reviewed; **Cancel** discards unsaved presentation
changes. Qualification changes only through Human Review.

### 7.2 App-owned comments

Every Comment is researcher-owned, outside Markdown, and anchored to stable
note identity, reviewed fingerprint, UTF-8/UTF-16 range, original line,
quotation, and context. Read and editor selections create the same record.
Reattach automatically only when quotation and context identify one reliable
location; otherwise mark **Needs Reattachment**. The researcher may reattach
or resolve; an agent may reply but cannot resolve.

There is no whole-note Comment model, composer, decoder, or fallback. Without
a source selection, Dialogue offers no Comment textbox and directs the
researcher to **Add Comment** from a passage. That action opens Dialogue for an
Analysis/Topic and Critique for a Work, carrying the anchor and focusing the
inline composer. Comment, Human Review, Response, Critique, and disposition
records remain distinct despite shared presentation.

### 7.3 Unqualified Analyses

An Unqualified Analysis remains readable, editable, searchable, linkable, and
available to Topics, Works, Critique, and later agent work. Explicit scholarly
reliance may produce a source-anchored, nonblocking Attention warning. A
neutral Connection alone is not reliance; a citation, explicit support, or
recognized source-bearing use may be. The warning clears when qualification or
usage changes.

## 8. Research Functions and direct agent work

### 8.1 Research Functions and function contract

The Research Inspector's **Functions** mode exposes only the functions valid
for the current role-valid note:

| Target | Functions, in order |
| --- | --- |
| Analysis or Topic | **Dialogue · Develop · Fidelity** |
| Work | **Critique · Revise · Dialogue · Fidelity · Manuscript** |

These stable operations are not a taxonomy of philosophy. There is no Manage
Comments doorway or nested Comment, Human Review, or Critique sheet.

The optional-agent journey is choose function, inspect context, prepare durable
run, hand off, explicitly paste/submit when needed, then inspect source/status.
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

Each function uses one typed panel with immutable current-note Target.
Agent-facing panels select read-only Materials through Search, optional
Suggested Only, an individually removable Selected Materials tray, and the real
vault hierarchy. Search covers title/alias/filename/path and retains ancestors;
nothing is preselected or bulk-selected. Distinguish loading, true empty, and
blocking failure with Retry Materials. Preparation freezes selection.

Suggestions use only resolved one-hop Connections, in order: from the selected
passage, from the Target, then directly to the Target. Each states its reason
and source location when available. Transitive paths, lexical or AI similarity,
Comment text, and inferred evidential roles are forbidden. Suggestions navigate;
they are not evidence.

A current source selection defaults the scope to **Passage**; otherwise
**Whole**. Dialogue includes Human Review and Analysis/Topic Comments. Critique
includes Work Comments, findings, suggestions, and attributed **Accept**,
**Reject**, or **Rebut** dispositions; a disposition never edits the Work.
Fidelity offers **Content** and **Citations**. `Command-R` opens Human Review in
Dialogue for an Analysis/Topic and Critique for a Work. One presentation channel
keeps role-valid panels mutually exclusive.

Dialogue is read-only by default and may append an attributed Response. If an
agent determines that the Target must change, it promotes the same fixed
request through the API to Develop or Revise before mutation. Frontends do not
classify prose or expose workflow/package mechanics.

Transport may include the instruction; selected paths, fingerprints, passages,
lines, Comments; Triptych/Work context; Research Units; links; destination/edit
rules; exact read set; and, only for write runs, permission for the single
fingerprint-bound Target/range. Target/Materials are focal context, not general
authorization. Prompts, model settings, token counts, and paragraph-level AI
provenance are not permanent records. Each run has one overall instruction.

Conditional methods persist one read-only preflight with primary method,
checkpoint, and Dialogue/Critique record. The agent finalizes explicit
resources; empty means primary-only. The same run receives only selected pinned
resources and cannot mutate/complete beforehand. Generic retrieval is not
function-resource evidence.

Dialogue shows consequential scholarly context, not active template source or
assembled technical instructions. **Copy Only** uses the active Settings
template; **Open in Codex** transfers the same durable request identity without
making transport text part of the scholarly record.

After source changes, default to a concise academic change summary, material
unresolved questions, and needed review; file-operation detail is secondary.

Beta Dialogue stores one immutable request `responseContract`: required
Academic Outcome plus optional Critical Reflection, Remaining Questions,
Philosophical Significance, Debate Context, and Research Directions. Modules
affect presentation only; they cannot expand scope, replace methods, or require
fabrication. Consider every selection without forced findings, weights, or
coverage ledgers. Fidelity, uncertainty, failure disclosure, and researcher
control always apply.

Develop, Revise, Manuscript, and Dialogue promoted to a write function flush
autosave and create **Before Agent Work** before instructions return. Critique
uses its named checkpoint. Human Review and Fidelity are read-only and create
none. The researcher may always instruct an agent outside Scholium.

### 8.2 Research Record and replies

There is no global Dialogue archive. Each selected note shows the same
chronological Dialogue entry for a multi-note exchange: Comments/follow-ups,
selected-note list, and agent replies. Entries are scholarly records, not
versions, prompt logs, or response-approval queues; the note expresses the
researcher's eventual decision.

`scholium dialogue` validates request and Comment identities and appends
immutable, attributed replies under Application Support. Replies may address
the instruction, one selected note, or one Comment. An agent never edits the
record database directly or resolves a researcher Comment. A non-CLI reply is
recorded only if the researcher returns it manually.

Beta CLI exposes the immutable `responseContract`; missing snapshots are
unsupported pre-release state and fail closed rather than adopting current
defaults.

Research Record follows the focused window's active Document tab. Its toolbar
and **Research → Show Research Record** routes open the same nonmodal secondary
utility window without opening, closing, replacing, or revealing Research
Inspector. It contains scholarly chronology and provenance only; checkpoints
remain File-owned recovery artifacts. Researchers may use Dialogue without an
agent as a concise record of their own Comments and decisions.

### 8.3 Research Guidance, prompt templates, and skills

**Settings → Research Guidance** alone edits prompt templates. Each workflow
has one active Triptych-local template. Create, duplicate, rename, delete, and
assign are supported; editing a default creates a researcher copy, while Reset
restores the bundled baseline without overwriting custom templates.

One local selector presents **Prompt Templates · Skills · Advanced**:

- **Prompt Templates** includes subordinate per-Triptych **Dialogue Defaults**.
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
**Revision**, **Content Fidelity**, and **Manuscript**. Dialogue is System
transport/record infrastructure; Human Review has no Workflow Skill. Source
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
revisions/loaded resources. Core Protocol always loads; Dialogue only for
Dialogue; Triptych/Zotero/citation/Researcher resources only when required. A
clipboard fallback cannot claim unretrieved packages.

**Settings → Research Guidance → Advanced → Research Methods** lets each
function keep the official primary, select one compatible researcher-owned
replacement, and add compatible supplements and exact Practices. Application
validates and atomically persists bindings. The Functions mode receives
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
and cancellation. Preparation resolves Target identity/fingerprint, validates
Materials without Target duplication, resolves exact resources, creates
checkpoint/evidence, rechecks revisions, and rolls back partial work. Human
Review uses separate authority and no execution packet.

CLI uses only `function available`, `prepare`, `show`, `select-resources`,
`complete`, `prepare-fidelity`, and `cancel`. `show` recovers immutable state;
`prepare-fidelity` constructs/reuses the exact child. JSON `nextActions` are
typed argument vectors with optional stdin templates, never shell strings.
Dialogue `promote` preserves Target, Materials, scope, and Comments.

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
current revision; Develop/Revise finalization creates or reuses a child with
the same inputs, and Manuscript reuses its final Revise child. Critique and
Dialogue create no Target Fidelity.

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
2. Read it, follow relevant Connections, and add anchored Comments.
3. Use Dialogue, Develop, or Fidelity when useful; Dialogue contains Human
   Review, while Develop absorbs exploratory, conceptual, argumentative,
   synthetic, or expressive work.
4. Direct Source Analysis may inspect an available source without creating a
   Research Function, stored PDF, or Zotero control.
5. The researcher decides what to incorporate and whether related Topics or
   Works need updates.

Qualification judges one exact fingerprint without changing authorship.

For a long source, maintain one source-level Analysis by default. Each session
declares a bounded unit and applies required Orientation, Analytical, and Review
passes. Expand Research Unit only to material actually represented and record
unread, excluded, unreliable, or incompletely reviewed material as
Limitations. Chapter sections need not become separate Analyses. Create a
separate Analysis only by researcher request or when a segment needs an
independently citable identity. `complete` means complete for the declared
unit; **Entire source** requires source-wide analysis and review.

## 10. Topics workflow

1. Create or update a Topic from Analyses actually used, preserving
   disagreement, limitations, and uncertainty.
2. Read it and follow Connections to sources and Works.
3. Add Comments or use Dialogue, Develop, or Fidelity; Dialogue is
   nonmutating unless promoted to Develop.
4. Decide whether other materially affected notes need updates.

Scholium never auto-merges a qualified Analysis into Topics. It may report
relevant reviewed material, but neutral or transitive Connections establish
neither integration nor support. Topics have no persistent Critique; an
assessment request normally improves the Topic through Dialogue/Develop.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers may scaffold, write, revise, and organize Works directly. Agents
may do so when instructed, but Critique remains visibly separate. Works have no
Human Review qualification; Critique is optional. Critique assesses, Revise
writes, and Manuscript coordinates isolated phases while the current Work is
the sole Target.

### 11.2 Critique target and storage

- A Critique targets one Work; broader assessment uses multi-note Dialogue.
- Each Work has at most one current Critique document. Later rounds update it;
  prior rounds and researcher dispositions remain in Research Record without
  restore semantics.
- Critiques are recognized only in the designated `Critiques/` area.
- Bodies are read-only in Scholium, but files remain externally editable and
  may be renamed or moved within Critiques, Set Aside, restored, trashed, or
  revealed.

### 11.3 Critique function

Critique uses **Whole | Passage**, includes applicable Work Comments, and
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

## 12. Connections

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
Finder actions.

Each window remembers its ordinary scope. `Command-F` requires an open note and
temporarily selects **This Note**. Dismissal restores the prior scope unless the
researcher explicitly changed it, cancels work, rejects stale results, and
clears query/results while retaining scope and saved searches.

Beta uses deterministic local SQLite FTS5. An exact Topic match may show its
direct resolved Connections in a separate **Related** section; they neither
alter ranking nor imply evidence. Vector search, embeddings, AI query
interpretation/ranking, and chat-style Search are excluded. **Vector-Link**
means only researcher-authored relation markers.

Attention may report possible-orphan conditions, Changed Since Review, Broken
Connections, explicit reliance on an Unqualified Analysis, malformed metadata,
or unresolved identity. It never infers **Superseded**, uses age alone, or issues
automatic untraced-premise verdicts. Warnings are dismissible; Settings
controls duration, default seven days. The researcher retains judgment.

## 14. Checkpoints, versions, and recovery

Autosaves create no visible versions. Before preparing Develop, Revise,
Manuscript, promoted Dialogue, or Critique, Scholium creates a named,
fingerprint-bound whole-Triptych checkpoint. Human Review and Fidelity create
none. The researcher may choose **Create Checkpoint…** at any time.

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
**Test Connection**, **Refresh Library Information**, **Forget Cached Zotero
Data**, last successful time, and a concise local/read-only privacy statement.
When disabled, direct the researcher to **Allow other applications on this
computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Matching and presentation

Match by `zotero_item_key`, then DOI/ISBN, citation key, exact title + author +
year, then researcher choice. Never choose ambiguity silently. A confirmed key
may be written through the permitted Property path.

An Analysis inspector shows only its identified item as **Zotero Source**. A
Topic or Work shows **Zotero Sources from Linked Analyses**: deduplicated items
from outgoing links to Analyses carrying keys—never incoming
backlinks, bibliography text, transitive Connections, Zotero children,
Unclassified, or the wider library.

Show title, authors, year, container, volume/issue/pages when available,
primary identifier, and citation key; expanded detail may add abstract,
publisher, edition, URL, collections, and modification date. **Open in Zotero**
is the only source action. Scholium does not enumerate, download, reveal, or
open attachments. Unavailable Zotero names the condition and may show
timestamped cached metadata. Built-in integration never changes Zotero data,
files, or live SQLite.

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
assembly and Manuscript phases; request-scoped Dialogue `responseContract`;
and protected Zotero MCP transport.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
additional contributed or discipline-specific workflows; richer Dialogue
comment-preservation and reflection modes; and Work finding overlays.

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
- Distinguish source, researcher prose, agent content, Human Review, Critique,
  Connections, and diagnostics by text and structure, not color alone.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancel,
  compare, retry, conflict, and recovery routes. Hover, drag, color, motion,
  secondary click, and gestures are never the only route to a core task.

### 18.2 Workspace shell and Document tabs

Each configured window contains exactly one native `NSSplitViewController`
with three sibling items:

1. **Library:** Triptych identity; Analyses/Topics/Works scope; Attention;
   Filter; one folder/note hierarchy; Recommended Bibliography; compact Set
   Aside, Trash, and Settings routes.
2. **Document:** selected note or the text-free semantic background.
3. **Apparatus:** Research Inspector's read-only Overview, Connections, and
   Functions projections. It never owns buffers, autosave, Undo, or conflicts;
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

- **File:** Triptych/window/note create/open; Import; Duplicate; Move/Rename;
  Reveal; Checkpoint create/restore.
- **Edit:** editing and **Edit Properties…**.
- **View:** Search, document mode/text size, Sidebar, Research Inspector.
- **Research:** role-valid functions and **Show Research Record**, never
  Attention or Checkpoints.
- **Settings:** Triptychs, Property profiles, Research Guidance, Attention,
  Zotero, and Appearance.

### 18.3 Library and Search

- One native **Filter** menu groups Review, Integrity, Metadata, Properties,
  Order, and Actions with at most one submenu level. Unreviewed/Unqualified may
  appear in row status and Filter, not permanent task toggles.
- Unclassified is reachable for classification but not a permanent Library
  row. Notes outside folders appear at vault root.
- Folder/note rows form one hierarchy at one semantic callout size and compact
  24pt height. Use weight, color, indentation, and symbols—not size. Notes are
  one line without sublines and expose full titles accessibly. At most one
  redundant state mark precedes title; selection remains visible off-focus.
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
threshold, trailing space, text scale, and semantic typography. Document prose
has **no maximum measure**: it occupies the available Document width while
retaining a minimum separation from the Library's right divider and the
Inspector's left divider. The provisional minimum inline insets are **32 CSS
px** in Read/Live and **40 CSS px** in Source, reducing to **20 CSS px** below
**44rem**, with a **32 CSS px** top inset. CSS lengths never convert to macOS
points. Shared ownership and units are approved; these values still require the
adaptation matrix and side-by-side Editor review. Live Preview and Source
reconfigure one retained CodeMirror state; window, split, theme, or text-size
changes never replace it or create an Editor window.

Appearance is machine-local configuration and never Markdown or vault state.
It stores multiple named configurations, keeps exactly one selected, and
supports save, rename, duplicate, and deletion while retaining at least one.
Structured controls independently configure Body, headings, and each semantic
Callout for Read and Live Preview. The default configuration uses the values in
§19.2; Callout controls map presentation parameters without changing protected
role structure, generated accessible role names, or source-controlled fold
state. Mathematics remains centered and italic, with automatic numbering on the
physical right scoped per document; code and tables retain their shared
app-owned styles.
Advanced sanitized CSS snippets remain an additive compatibility path inside
Appearance, but Appearance displays no generated CSS preview. Source typography
and the application interface are not changed by a document configuration.

Subject to the transfer rule in §18.2, Document toolbar order is conditional
Show Sidebar; Heading Outline and compact identity; mode and Search; Research
Record; conditional Show Inspector. Scholium controls are borderless ink. No
second identity row, Document Properties button, or More control exists.
Complete Properties is in Research; direct controls retain menu/keyboard
routes. Document Text Size is per-window and source-neutral.

Properties performs targeted frontmatter edits and distinguishes absent,
empty, invalid, derived, and not-applicable. Exact YAML stays available in
Source. Research Status shows Scope, then non-empty Limitations, and **Not Yet**
for absence.

### 18.5 Contextual research and Research Functions

Apparatus contains Research Inspector only; Research Record and checkpoint
recovery stay separate. Research Record is a nonrestored `UtilityWindow`, reads
the focused Workspace directly, and starts at **760 × 680** without treating
that size as a minimum. There is exactly one native trailing Inspector per
Workspace, with **Overview · Connections · Functions** in that order. These are
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

1. **Research Status:** Scope followed by every non-empty Limitation; **Not
   Yet** means absence, while invalid source reports its exact validation
   problem. Editing opens the existing Properties surface.
2. **Scholarly Status:** Human Review state for an Analysis/Topic or Critique
   currency and round count for a Work, followed by Comment totals, unresolved
   count, and anchors needing reattachment. Review/Critique actions keep their
   existing destinations.
3. **Attention:** the visible current-note count and distinct issue kinds after
   dismissal. The complete queue, messages, filters, and dismissal controls
   remain in Library.
4. **Key Properties:** at most five role-priority facts, excluding Research
   Status Scope, plus the route to complete Properties.
5. **Provenance:** compact note and latest Review/Critique times; detailed
   chronology stays in Research Record.
6. **Diagnostics and Freshness:** important machine checks plus an explicit
   current, refreshing, stale, failed, or unavailable derived-state label.
   Stale or failed state preserves the last-known-good projection and offers
   Retry; it never claims reading, truth, or philosophical evidence.
7. **Zotero Source:** existing read-only matching, confirmation, and Open in
   Zotero behavior, without attachment browsing.

Connections begins with three expanded, independently collapsible groups:

| Target | Groups |
| --- | --- |
| Analysis | Neighbor Analyses · Related Topics · Related Works |
| Topic | Related Sources · Neighbor Topics · Related Works |
| Work | Related Sources · Related Topics · Neighbor Works |

Within a group, explicit links sort supports, supported by, incompatible, then
neutral. Redundant symbols state predicate/direction; titles wrap. Do not open
a second panel merely to show a title. Preserve source anchors. Connections
shows the same freshness state before its groups. Stale or failed state keeps
the last complete graph readable and offers Retry.

Functions presents the role-valid functions in the Section 8.1 order. Human
Review is not a Function launcher. Availability fails closed while checking;
an unavailable function is disabled and states its first actionable repair
reason. Each launcher is a wrapping, full-width native button with a 44pt
target. It opens the existing typed Research Function sheet rather than
embedding the workflow in the narrow Inspector. Closing a sheet restores focus
to its initiating Functions button only when it was launched there.

**Current Activity** shows only the newest current-note run still requiring
action: prepared, awaiting Fidelity, unverified, or stale. If more remain, it
shows their count and an **Open Research Record** route. Complete and cancelled
runs, full instructions, Fidelity outcomes, and complete history remain in
Research Record.

Inspector uses wrapping system interface text. Sections start 16pt below the
tab rule and separate by 16pt; headings use one lighter sans label. Modes share
a 20pt edge; content adds 12pt, symbols use a 16pt track plus 8pt gap, and
trailing actions return to the outer edge unless semantics require otherwise.

Scholarly Status is one restrained third-plane bordered surface, not a badge.
Metadata/actions are sans; verdict is 18pt editorial serif with redundant
symbol/date. Revision currency appears only after review. Review Note uses
editorial serif beside a rule and truncates after two lines. Open Review or
Open Critique remains available; color is insufficient.

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
| Develop / Manuscript | 发展 / 稿件 |
| Review / Human Review | 审阅 / 研究者评审 |
| Qualification | 评审结论 |
| Fidelity / Critique | 核查 / 评析 |
| Attention / Connections | 关注 / 关联 |
| Checkpoint / Snapshot | 恢复点 / 快照 |
| Comment / Response | 注释 / 回应 |
| Research Status / Research Record | 内容状态 / 研究记录 |
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

- System sans is interface language: navigation names, chrome, menus, controls,
  Settings, alerts, paths, status, dates, and dense metadata. The fixed
  **Scholium** Alegreya wordmark is the only identity exception.
- **Alegreya** is for Read/Live Preview prose and may identify content-derived
  titles, linked research objects, researcher judgments, or major headings when
  density, scaling, and mixed-script fallback remain legible.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, and diffs.
- The default Appearance uses **Alegreya 12pt**, **2.0** line spacing, **1em**
  paragraph spacing, **0.02em** tracking, justified text, and no hyphenation.
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
geometry stays outside the grid. WebKit uses `rem`, CSS px, and viewport units
without point conversion. Document content has no maximum width; the
**20/32/40 CSS px** minimum border separations and typographic rhythm values
remain provisional pending ordinary, narrow, mixed-script, and 200% testing.
Fractional browser-proof translations are superseded; screenshots and
prototype coordinates remain evidence only.

## 20. Accessibility and adaptation

- Support System, Light, and Dark without hard-coded inversion.
- Meet at least **4.5:1** contrast for ordinary small text and **3:1** for large
  or bold text; audit every important custom target below 28 × 28pt.
- Preserve hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive windows, 200% document text, and accent changes.
- Give every important state two suitable channels; never rely only on color,
  motion, sound, location, or arrow direction.
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, function panels, conflict comparison, and
  Research Record close.
- Lifecycle destination headings expose the localized name and successful
  count as one heading; active footer entries expose selection. The retained
  Library hierarchy is accessibility-hidden while a destination is active.
  Put Back remains in keyboard and VoiceOver order without hover, and row
  removal follows the next/previous/Back focus sequence defined in §18.3.
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
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
- Live Preview/Source fidelity, formatting, anchored Comments, and mode changes;
- Properties, Research Status/Not Yet, Human Review, and qualification;
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
| **G5 Scholarly transparency** | Dialogue, Human Review, Critique, Fidelity, provenance, and uncertainty remain visibly distinct. |
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
| **D-096** | 8.5, 14 |  |  |

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
  configurations; retain no generated CSS preview or maximum document measure.
  Keep protected semantic component structure, shared mathematics/code/table
  roles, additive sanitized CSS compatibility, and minimum divider separation.
- **D-094:** one stable document appears at most once in one window's Document
  tabs; repeated open selects the retained page while other windows stay
  independent.
- **D-095:** content safety may veto a bounded close or termination attempt;
  machine-local presentation persistence may not, and late work is attempt-
  scoped.
- **D-096:** existing-file mutation requires durable expected/candidate bytes
  plus a verifiable displaced-file-preserving commit boundary; otherwise fail
  closed without a **Saved** claim.

Unresolved work must not be described as complete:

- sustained manual VoiceOver, Full Keyboard Access, Voice Control, Dictation,
  contrast, scaling, localization, and installed-IME acceptance;
- final document rhythm and production mono comparison;
- compact multi-note Dialogue and richer reflection/compression;
- broader Search ranking/usability evaluation;
- packaged Release performance thresholds and measurements; and
- clean-tagged distribution and external-install evidence.

## Appendix A. Default property profiles

Existing/custom YAML remains authoritative and losslessly preserved. Profiles
define recommended human-facing fields; they do not migrate notes, erase
unknown data, or inject absent YAML. App-owned creation/modification time stays
out of frontmatter. Research Unit uses the exact shape and constraints in 5.2.

For a long source, expand one source-level Analysis's Scope only to represented
material and put unread/excluded material in Limitations. Separate segment
Analyses require explicit researcher choice or independent scholarly identity.

### Analyses

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Required source title. |
| About | Authors | `authors` | Required author list. |
| About | Year | `year` | Required publication year. |
| About | Type | `type` | Optional publication form. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional at creation; required for Complete Review. Not Yet writes nothing. |
| Source | Access | `access` | Extent of consulted material. |
| Source | Text Reliability | `text_reliability` | Reliability of consulted text. |
| Source | Locators | `locators` | Citation stability/checkability. |
| Progress | Status | `status` | `draft`, `complete`, or `reviewed`, relative to Research Unit. |
| Assessment | Debate Importance | `debate_importance` | Optional whole number 0–10. |
| Assessment | Debate Scope | `debate_importance_scope` | Required with Debate Importance. |

Debate Importance follows 5.2 and never means project relevance, quality,
truth, prestige, or citation count. Relevance keys remain custom source.

### Topics

Topic YAML is optional.

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Optional when filename/H1 identifies the Topic. |
| About | Aliases | `aliases` | Search and link alternatives. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional conceptual/debate boundary. |
| Progress | Status | `status` | `seed`, `developing`, or `maintained`; never settlement. |

### Works

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Required Work title. |
| About | Authors | `authors` | Optional co-authors. |
| About | Kind | `kind` | Paper, chapter, book, talk, review, teaching material, etc. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional project-question/argument boundary. |
| Progress | Status | `status` | `planning`, `drafting`, `revising`, `review`, `ready`, `submitted`, `published`, or `archived`. |
| Use | Venue | `venue` | Intended/actual journal, publisher, course, or event. |
| Use | Deadline | `deadline` | Relevant delivery/submission date. |

Works status is production state, never argumentative quality, evidential
sufficiency, acceptance probability, or project governance. Only canonical
keys receive typed semantics; other non-machine fields remain custom.
Targeted edits never normalize unrelated source.

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

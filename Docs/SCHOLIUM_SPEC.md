# Scholium Specification

**Status:** Canonical product, interface, and release specification
**Applies to:** Scholium for macOS and its agent-facing CLI
**Canonicalized:** 2026-07-17

This is Scholium's sole target authority. It defines product semantics,
interface behavior, action language, Scholarly Editorialism, accessibility,
release requirements, and stable decisions. `IMPLEMENTATION_ARCHITECTURE.md`
describes structure; `IMPLEMENTATION_STATUS.md`, README, live construction,
and tests establish current reachability and evidence. A difference in current
code is migration work, not an alternative product rule.

In this specification:

- **Target** is required behavior, whether implemented or not.
- **Reachable** means exposed by the current build, not accepted for release.
- **Verified** means directly exercised by the stated evidence.
- **Deferred** is intentionally outside the stated release boundary.
- **Unresolved** means a decision or acceptance judgment remains open.

Apple's Human Interface Guidelines and the selected SDK own platform guidance
and API behavior; this specification owns Scholium's Triptych, scholarly
semantics, evidence distinctions, and research governance.

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
  by the document-local **Research Strip** and executed through the shared
  Application API: Dialogue, Develop, Fidelity, Critique, Revise, or Manuscript.
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

Scholium is a local-first macOS document editor with research intelligence for
sustained humanities research, especially philosophy. The research document,
not a dashboard, workflow state, task, or agent conversation, is its primary
object. Exact Markdown remains the intellectual artifact beneath every
projection.

The immediate priority is a dependable, comprehensible core: setup, open,
create, read, edit, autosave, Search, conflict handling, recovery, Library
navigation, Document tabs, and contextual inspection must work without data
loss, shell reconstruction, or surprising state changes before visual polish
or optional advanced workflows can block release. Exact visual metrics remain
provisional unless required for readability, accessibility, source integrity,
or correct native-window behavior.

Scholium supports reading, writing, commenting, reviewing, searching,
connecting, organizing, recovering, and tracing source-grounded work. It is
not a project manager, reference manager, permanent AI chat, or full Obsidian
replacement. Obsidian, Zotero, and agents are optional; the manual academic
core must work entirely in Scholium.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych. She may instruct an external agent to
create, edit, rename, move, organize, or delete files through filesystem or CLI
tools, but Scholium issues no persistent permission, Proposal, authorization
scope, or app-required token. The current instruction defines the task; no
permission survives it. Dialogue and Critique remain optional.

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

Bundled methods assist agents in producing warranted, source-faithful,
reviewable work. They neither teach the researcher how to conduct philosophy,
certify truth, nor replace her judgment. Researcher-owned methods remain her
responsibility.

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

Researchers choose all three locations; Scholium recommends, but never
requires, a common parent and never relocates them automatically. Because one
portable `.scholium/` directory sits beside Works, two Triptychs may not have
Works roots with the same parent.

### 3.2 Triptych navigation and windows

One configured window belongs to one Triptych and presents three peer Library
scopes: **Analyses | Topics | Works**. Switching scope changes only the browsed
hierarchy and **This Vault** Search; it does not replace the open document.

**File → New Triptych…** opens setup for three new locations; **File → Open
Triptych** opens a registered Triptych separately; **File → New Window** creates
another workspace for the focused Triptych. **Open in New Tab** adds a page
only to the current window's central Document region. Switching tabs changes
the active document and its Apparatus projection, while Library disclosure and
selection, Sidebar visibility, Apparatus visibility, and Apparatus mode remain
stable.

**New Triptych…** and a missing registration use a separate Bootstrap window.
A configured Triptych with expired folder authorization stays in its workspace
and opens one bounded **Restore Access** sheet; it never re-enters setup. A
configured workspace retains one frame and one three-item split across loading,
no-note, and selected-note states. Opening or closing notes never resizes the
window. The no-note Document is a quiet, text-free, action-free semantic
background; Library remains reachable through the standard Sidebar route.

Works folders are researcher-controlled organization, not registered projects.
Scholium supplies no project selector, assignment, completeness check, or
Triptych switcher inside Document.

### 3.3 `.scholium` and machine-local state

The portable directory beside Works contains only small Triptych state:

- manifest and stable identity mappings;
- Triptych Guide and Triptych-local settings or folder preferences;
- per-vault Properties profiles;
- prompt templates, workflow assignments, function/citation bindings;
- user packages at `.scholium/skills/<skill-id>/SKILL.md`; and
- imports at `.scholium/unclassified/`.

It may be synchronized through ordinary cloud storage or Git; Scholium never
uploads it automatically.

Application Support owns machine-specific or replaceable state:

- security-scoped bookmarks and absolute paths, including a separate bookmark
  for the folder containing Works that authorizes sibling `.scholium/` without
  creating a fourth vault, plus the agent application selected for Beta handoff;
- window sessions and vault-qualified Document tabs;
- derived indexes, temporary files, and caches;
- app-owned Human Review, Comments, Dialogue, and Research Record data; and
- self-contained Triptych checkpoints.

### 3.4 Triptych Guide and AI instructions

The concise agent-facing Guide states vault roles, researcher-chosen Works
organization, relation syntax, fidelity/provenance/uncertainty/conflict rules,
and CLI discovery and safe-file conventions.

Scholium never creates, overwrites, or silently updates a workspace
`AGENTS.md`. On explicit request it may provide a protected one-shot bootstrap.
The agent must resolve the Triptych and requested working root, inspect the
applicable ancestor instruction chain, construct and validate a minimal
candidate, promote it, and read it back. If an applicable `AGENTS.md` exists,
the operation stops; no overwrite, merge, or shadow file is allowed. Only a
successful task-created temporary copy may be removed. The resulting file is
researcher-owned.

Triptych-local technical instructions are managed only in **Settings →
Research Guidance**. Inventory is discovered from the filesystem and CLI, not
a standing generated index.

### 3.5 Import and Unclassified

Import copies Markdown into `.scholium/unclassified/` without changing the
original. The copy is readable and editable but receives no role-specific
Properties, Human Review, qualification, or Critique behavior until classified
into Analyses, Topics, or Works. Irrelevant Markdown should not be imported.

## 4. Works folders and organization

Works is an ordinary Markdown hierarchy. Folders may represent projects or
research structures, but Scholium creates no membership, metadata requirement,
selector, schema, completeness warning, or mandatory internal template. For
example, a researcher may use Concepts, Questions, Arguments, Objections,
Replies, Critiques, and Drafts, then rename or replace them freely.
`Critiques/` is the only folder with special Scholium behavior.

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
  Read's prose grammar where possible, reveals syntax only around the active
  construct, and shows neither YAML nor line numbers.
- **Source** edits complete Markdown and YAML and may show line numbers.

Read and Live Preview have a direct keyboard toggle. Source is entered through
the mode menu. It may alter protected or machine-facing YAML; the researcher
accepts responsibility, while Scholium still performs targeted, byte-preserving
validation and never reserializes the whole frontmatter.

Modes add no floating Metadata or Properties surface over the text. Initial
top clearance belongs to the scrolling document.

### 5.2 Properties

Each vault has one configurable profile: visible fields, order, disclosure,
and a human-editable allowlist. There are no folder- or note-specific layouts.
Identity, fingerprints, provenance, and app-maintained facts are protected in
Properties but remain visible as exact YAML in Source.

The optional Research Unit has one shape:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

`scope` is required and non-empty when the mapping exists. `limitations`
contains only material claim boundaries. Do not duplicate role, identity,
links, confidence, coverage percentages, reading passes, timestamps, or other
derived facts.

New Analysis offers **Declare Now** or **Not Yet**. Not Yet writes no mapping
or sentinel. The note remains editable and available for Comments, Dialogue,
Develop, and a Human Review draft, but **Complete Review** requires declared
Research Status. Existing Analyses receive no migration. Topics and Works use
the same optional mapping only when it adds a durable boundary not already
clear from title, body, or links. An authorized agent edit follows ordinary
fingerprint, conflict, and source-preservation rules.

Creation and modification times are app-owned Research Record facts, not
properties. Existing timestamp keys remain exact custom source.

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

Paths are locations; every note has a stable app-owned identity. A duplicate
gets a new identity, resets Human Review and qualification, and records its
source. Confirmed moves and renames preserve associated app-owned records and
update resolved incoming links. If an external rename cannot be rebound
confidently, the note remains readable but identity-dependent mutations, Human
Review, Research Record lookup, and Comment attachment are blocked until the
researcher confirms identity.

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

### 8.1 Research Strip and function contract

The bottom editor Research Strip appears only for an open role-valid note:

| Target | Functions, in order |
| --- | --- |
| Analysis or Topic | **Dialogue · Develop · Fidelity** |
| Work | **Critique · Revise · Dialogue · Fidelity · Manuscript** |

These are stable product operations, not a taxonomy of every philosophical
activity. There is no **Manage Comments** doorway or nested Comment, Human
Review, or Critique sheet.

The optional-agent journey is: choose a function; inspect context; prepare the
durable run; hand it to an external agent; explicitly paste/submit when needed;
return to inspect source and status. Fingerprints, checkpoints, methods,
packages, and evidence keys stay hidden unless repair or recovery needs them.

Beta provides a provider-neutral, copy-first application handoff. The first
action is **Copy and Choose Agent App…**: copy the complete prepared
instructions, ask the researcher to select one macOS app, remember that app on
this Mac, and open it. Later runs offer **Copy and Open [App]…**, plus **Copy
Only**, **Choose Another Agent App…**, and **Forget Agent App**. The app-wide
preference stays outside Triptychs. Scholium never infers the frontmost app,
pastes, submits, starts a turn, or sends Target, Material, credentials, account,
model, permission, or configuration data through the launch request.

**Choose Another Agent App…** changes the preference without launching the
replacement; **Forget Agent App** removes only that preference.

Cancelling the first chooser or failing to locate/open the app leaves the
copied instructions and durable run intact, with copy, choose-again, retry, and
cancel routes. Launch acceptance means only that macOS accepted the request,
not that an agent accepted or completed work.

1.0 adds **Open in Codex** without replacing provider-neutral or copy-only
routes. After durable preparation, it opens a new local Codex task at the exact
requested working root. A locator-only prefilled composer carries Triptych/run
locators and the supported CLI bootstrap command, never Target or Material
content in the launch URL. Scholium does not append to an existing task,
auto-submit, select a model, alter Codex configuration or permissions, install
Codex, or report agent execution. Unavailable Codex or an invalid root leaves
the run recoverable with copy, retry, explanation, and cancel routes.

Each function opens one shared, typed panel. Its current note is the immutable
Target. Agent-facing panels choose read-only Materials through a search field,
optional **Suggested Only**, a **Selected Materials (n)** tray with individual
removal, and the real vault folder hierarchy. Search covers title, alias,
filename, and path while retaining ancestors. Nothing is preselected and there
is no bulk select. Loading, true empty, and failure are distinct; failure blocks
preparation and offers **Retry Materials**. Preparation freezes the selection.

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

Prepared transport may include the researcher's instruction; selected paths,
fingerprints, passages, lines, and Comments; Triptych context and ordinary Work
metadata; Research Units; links; destination and edit rules; the exact read
set; and, only for a write-capable run, permission to modify the single
fingerprint-bound Target within the authorized range. Target and Materials are
focal context, not a general authorization boundary. Prompts, model settings,
token counts, and paragraph-level AI provenance are not permanent records.
Each run accepts one overall researcher instruction.

Conditional methods first create one persisted read-only preflight containing
the complete primary method, checkpoint, and Dialogue/Critique record. The
external agent inspects fixed inputs and finalizes an explicit conditional
resource selection; empty means the primary method suffices. The same run then
receives only selected release-pinned resources. Before finalization it has no
mutation instructions and cannot complete. Generic retrieval is not function
resource evidence.

Dialogue shows consequential scholarly context, not active template source or
assembled technical instructions. **Copy Only** uses the active Settings
template; **Open in Codex** transfers the same durable request identity without
making transport text part of the scholarly record.

After changing source, an agent's default researcher-facing response is a
concise academic change summary. It identifies unresolved questions or needed
review when material; routine file-operation detail is secondary.

Beta Dialogue stores one immutable request-scoped `responseContract`. Required
**Academic Outcome** may be joined by Critical Reflection, Remaining Questions,
Philosophical Significance, Debate Context, and Research Directions. Modules
affect presentation only: they cannot expand retrieval or write scope, replace
methods, or require fabricated content. Each selected module is considered;
none is silently skipped, though no distinct warranted finding may result.
There are no weights or coverage ledgers. Fidelity, uncertainty, failure
disclosure, and researcher control always apply.

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

**Settings → Research Guidance** is the only prompt-template editor. Each
workflow has one active Triptych-local template. Researchers may create,
duplicate, rename, delete, and assign templates; editing a default creates a
researcher-owned copy, and **Reset to Scholium Default** restores the bundled
baseline without overwriting another custom template.

One local selector presents **Prompt Templates · Skills · Advanced**:

- **Prompt Templates** includes subordinate per-Triptych **Dialogue Defaults**.
- **Skills** owns discovery, creation, duplication, editing, routing metadata,
  structural validation/repair, eligible evolution, Recovery, and **Reveal
  Skills Folder** for System, Workflow, and Researcher Skills.
- **Advanced** owns only cross-package Scholium CLI, citation method,
  Recommended Bibliography method, and Research Methods with Supplements and
  Practices.

Page-local list/detail dividers do not become Settings navigation sidebars or
add a Show/Hide Sidebar control. Bundled defaults work without configuration.
Lists expose human name, purpose, function, **Built-in** or **Triptych** origin,
validity, and active status before maintenance detail. Bundled Workflow Skills
offer **Duplicate**, not a disabled editor. Triptych-owned packages may be
edited, duplicated, repaired through **Repair…**, and, when eligible, changed
through **Evolve…**. Invalid package status routes to Skills; invalid
cross-package bindings route to Advanced.

The five official Workflow Skills are **Development**, **Critique**,
**Revision**, **Content Fidelity**, and **Manuscript**. Dialogue is System
transport/record infrastructure; Human Review has no Workflow Skill. Source
Analyzer, APA 7 citation verification, and Prose Control are optional complete
or specialist copy-on-adoption Researcher Skills, not new ownership classes or
universal authorities. Source Analyzer has no Research Function and grants no
note-write permission.

Official packages may contain release-pinned one-level references and
templates. Duplication copies the complete bounded package under a new ID;
later releases update only the official copy. System Skills cannot be edited,
duplicated as replacements, or shadowed. Researcher packages are discovered
only from `.scholium/skills/<skill-id>/SKILL.md`, never research notes,
arbitrary locations, `~/.codex/skills`, another agent's global configuration,
or nested ownership folders.
Malformed packages and protected-ID collisions remain visible but unavailable.
Structural validation never certifies philosophical truth or method quality.

Every Workflow Skill is complete without Practices. A selected Practice loads
only its entry and exact requested resource, records IDs/revisions, and
supplements rather than replaces the primary method. Retired `replace`
bindings fail decoding. Practices cannot alter Target, Materials, permissions,
checkpoints, or write boundaries. The agent considers each selected Practice,
reports only material influence, and leaves methodological conflict visible;
there are no weights or coverage ledgers.

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

Application owns discovery, origin/update policy, bindings, dependency closure,
task facts, permissions, and exact resource retrieval. Packages declare stable
`supported_functions`; `supported_modes` is internal routing metadata. Records
name exact revisions and only resources actually loaded. Core Protocol loads
for every function; Dialogue infrastructure only for Dialogue; live Triptych,
Zotero, citation, and Researcher resources only when explicitly required. A
clipboard-only fallback must not claim packages it could not retrieve.

**Settings → Research Guidance → Advanced → Research Methods** lets each
function keep the official primary, select one compatible researcher-owned
replacement, and add compatible supplements and exact Practices. Application
validates and atomically persists bindings. The Research Strip receives
semantic availability only.

Workflow panels expose scholarly inputs, not prompt names, bodies,
placeholders, previews, skill pickers, or assembled transport. **Edit …
Template…** opens the exact Prompt Templates destination. Invalid active
templates preserve workflow input, explain the fault, and block generation
until repaired. Templates and skills create neither request taxonomies,
marketplaces, embedded runtimes, hidden authorization, nor scholarly records.

Only Triptych-owned Researcher Skills may opt into evolution. Research Guidance
exports an explicit revision-bound proposal request, imports a complete
`ResearchSkillProposedPackage` JSON, shows per-file comparison, validation, and
separately attributed evaluation, then offers **Apply** and **Restore**.
Application requires the expected revision and confirmation token; Core
snapshots and atomically replaces or rolls back the complete package.

Global **Recovery** is independent of current selection and validity. Safe
snapshots remain visible when a package is missing/malformed or another
snapshot is corrupt. Restore confirms full replacement, rechecks current
state, removes files absent from the snapshot, and first snapshots any
displaced package. Restoring a missing package is a guarded reinstall.
Discovery and restore use descriptor-relative, no-follow reads so path or
symlink substitution cannot redirect recovery.

### 8.4 Function preparation, completion, and Fidelity

The Application coordinator owns availability, preparation, completion, and
cancellation for app and CLI. Agent-facing preparation resolves Target identity
and fingerprint; validates every Material and rejects Target duplication;
resolves exact resources; creates checkpoint and evidence record; rechecks all
revisions; and rolls back any partial preparation. Human Review routes to its
separate authority and creates no execution packet.

The CLI uses `function available`, `prepare`, `show`, `select-resources`,
`complete`, `prepare-fidelity`, and `cancel`; no pre-1.0 aliases remain. `show`
recovers immutable packet and durable state. `prepare-fidelity` constructs or
reuses the exact final-revision child. JSON responses contain typed
`nextActions` argument vectors with optional stdin templates, never shell
command strings. Dialogue exposes a typed `promote` action preserving Target,
Materials, scope, and Comments.

`scholium version`, `doctor`, and hierarchical `help` work without a Triptych.
The parser rejects unknown, duplicate, or valueless options before opening
Application state; `--format json` errors use a stable envelope. Packaged apps contain a
version-matched helper. **Settings → Research Guidance → Advanced → Scholium
CLI** installs or updates exact bytes in the user-local command directory,
verifies executable permission, reports PATH discovery separately, and never
edits shell profiles.

Beta application launch uses complete prepared instructions; 1.0 Codex launch
uses preparation identity and CLI bootstrap. Neither adds a second API.
Prepared, cancelled, completed, Awaiting Fidelity, verified, unverified, and
stale states remain coordinator-owned; launch status is ephemeral delivery
only.

**Manual Fidelity** and **Automatic Fidelity** share one evidence-validation
contract. Manual Fidelity targets the current exact revision. After Develop or
Revise records a final fingerprint, automatic orchestration creates or reuses
a child with the same Materials, scope, Comments, and checks. Manuscript reuses
the child of its final selected Revise phase. Critique and Dialogue create no
Target Fidelity.

Because Scholium embeds no agent runtime, an automatic child remains
**Awaiting Fidelity** until an agent submits actual outcomes. Only a completed,
matching child advances the parent; outcomes submitted directly on the write
run are rejected. A deterministic evidence key reuses identical function,
scope, evidence set, checks, and final revision. Missing/unavailable evidence
leaves **Awaiting Fidelity** or **Unverified**; later Target or evidence changes
make it **Stale**. Invocation provenance and all record types stay distinct.

### 8.5 External edits and conflicts

A clean open note refreshes quietly after an external change. If the local
buffer is dirty, Scholium retains it and presents conflict instead of
overwriting either version.

## 9. Analyses workflow

1. Create or import an Analysis and write or revise it against the available
   source.
2. Read it, follow relevant Connections, and add anchored Comments.
3. Use Dialogue, Develop, or Fidelity when useful; Dialogue contains Human
   Review, while Develop absorbs exploratory, conceptual, argumentative,
   synthetic, or expressive work.
4. Direct Source Analysis may inspect an available source without a Strip
   function, stored PDF, or Zotero control.
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
not a Research Function, Strip control, note appendix, Zotero write path, or
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
Bootstrap; they never compete. Later launch may briefly resolve registration in
Bootstrap without exposing workspace chrome. Expired folder access instead
uses the workspace's bounded **Restore Access** sheet and preserves its active
document. Settings **Manage Triptychs…** lists registrations, edits their three
locations, creates another, and opens one in a separate window.

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
3. **Apparatus:** Research Inspector's read-only Connections and Research
   projections. It never owns buffers, autosave, Undo, or conflicts; full
   chronology belongs to Research Record.

Preferred workspace size is **1180 × 760**; AppKit owns minimum content size,
split compression, collapse, animation, dividers, and live widths. Library is a
semantic Sidebar and Apparatus an unmodified semantic Inspector. Scholium does
not set Inspector minimum/maximum, preferred fraction, holding priority,
resize-collapse behavior, full-height layout, safe area, separator, or
animation, and persists no pane width or divider position. The three opaque
planes use one-pixel rules, not cards, blur, large radii, or shadow.

A new window starts with Library visible and Apparatus hidden. Restoration
applies each visibility once; afterward live collapsed state is authoritative
and the window model only mirrors it for commands and the next session. Notes
and tabs never reconstruct the shell or change peripheral visibility/mode.
Showing Research Inspector initially selects **Connections**.

The native toolbar owns titlebar geometry and traffic lights. Its configured
background is transparent while opaque region colors extend underneath;
interactive content respects the live safe area. It contains Scholium's
borderless **Show/Hide Sidebar**; then Heading Outline and compact note identity;
current mode and Search; trailing **Research Record**; and AppKit's standard
`.toggleInspector`. The automatic glass-like Sidebar item remains removed.
Scholium adds no custom title strip, Inspector replacement, ellipsis, fixed
toolbar height, or Liquid Glass treatment.

Because the representable-hosted split may not be in the responder chain, the
standard Inspector item and View command may bridge one window-owned visibility
intent to the registered split controller's
`toggleInspector(_:)`. The bridge preserves the standard item, transition,
animation, and geometry. It disables responder auto-validation only as needed
and uses the same selected-document condition as the View route. Research
Record and Inspector controls remain visible but disabled without a Target.

When two or more documents are open, a Document-owned tab strip appears only
inside the middle split item. Each tab owns one document reference and retained
editor session. `NSTabViewController` with `.unspecified` style is content-
container authority; Scholium supplies the equal-width selector and existing
save-before-transition guard. Closing flushes the editor and selects a retained
neighbor; closing the last tab returns to the no-note background. Tab actions
never create an `NSWindowTabGroup`, new `WindowGroup`, parallel tab-state model,
or toolbar owner. Prototype toolbar/title capsule/New Tab/segmented styling is
not product authority; exact selector styling remains provisional.

The Library identity row sits beneath standard window controls. Its
**Scholium** disclosure and Library content share an 18pt peripheral alignment;
alignment to traffic lights at the default window is only a Section 19 visual
reference, never geometry derived from system controls. No-note content is
text/action free and VoiceOver-hidden. There is no Collapse Note, custom `<<`,
Back/Forward, Recents, or Quick Open.

Menus follow researcher tasks:

- **File:** Triptych/window/note create/open; Import; Duplicate; Move/Rename;
  Reveal; Checkpoint create/restore.
- **Edit:** editing and **Edit Properties…**.
- **View:** Search, document mode/text size, Sidebar, Research Inspector.
- **Research:** role-valid functions and **Show Research Record**, never
  Attention or Checkpoints.
- **Settings:** Triptychs, Property profiles, Research Guidance, Attention,
  Zotero, and Document Styles.

### 18.3 Library and Search

- One native **Filter** menu groups Review, Integrity, Metadata, Properties,
  Order, and Actions with at most one submenu level. Unreviewed/Unqualified may
  appear in row status and Filter, not permanent task toggles.
- Unclassified is reachable for classification but not a permanent Library
  row. Notes outside folders appear at vault root.
- Folder and note rows form one hierarchy at one semantic callout size and
  compact 21pt height. Hierarchy uses weight, color, indentation, and symbols,
  not size. Notes use one line, no preview/author/date/path subline, and expose
  the full title accessibly. At most one restrained state mark precedes title
  with non-color redundancy. Selection persists visibly when focus moves.
- **LIBRARY** shows no total count. Triptych-wide **ATTENTION** follows the
  scope selector before the Library heading, using the same 10pt outer edge,
  warning symbol, and count. It focuses/expands an inline full-width queue,
  never a modal or Research destination. Inspector may summarize only the
  current note.
- Compact Recommended Bibliography remains above the footer even when **None**,
  horizontally scrolls `Author, Year, Title` leads with thin rules, and offers
  an explicit entry to the full surface. Format two authors with `&`; three or
  more as first author + `et al.`.
- Debate Importance ordering first requires one exact Debate Scope.
- Shared Search follows Section 13: compact centered surface, always-visible
  scopes, no empty sheet, bounded results that identify match context and
  destination, and deterministic lexical Beta.

### 18.4 Document modes, context, and Properties

Read, Live Preview, and Source are modes, not tabs, and follow Section 5.1.
Ordinary scrolling space clears initial editor content from chrome; there is no
floating context surface.

The toolbar sequence is Heading Outline, compact note identity, mode, Search,
Research Record, and standard Inspector control. Scholium controls use a
borderless ink treatment. There is no second identity row, document-level
Properties button, or More control. Complete Properties is in Research; every
direct control keeps its menu/keyboard route. **View → Document Text Size** is
per-window and never changes source.

Properties performs targeted frontmatter edits and distinguishes absent,
empty, invalid, derived, and not-applicable. Exact YAML stays available in
Source. Research Status shows Scope, then non-empty Limitations, and **Not Yet**
for absence.

### 18.5 Contextual research and Research Strip

Apparatus contains Research Inspector only; Research Record and checkpoint
recovery stay separate. The inspector scrolls independently and has
**Connections** and **Research** text tabs with a restrained ink underline,
not a filled/capsule segment.

Connections begins with three expanded, independently collapsible groups:

| Target | Groups |
| --- | --- |
| Analysis | Neighbor Analyses · Related Topics · Related Works |
| Topic | Related Sources · Neighbor Topics · Related Works |
| Work | Related Sources · Related Topics · Neighbor Works |

Within a group, explicit links sort supports, supported by, incompatible, then
neutral. Redundant symbols state predicate/direction; titles wrap. Do not open
a second panel merely to show a title. Preserve source anchors.

Research orders **Review Status**, **Properties**, **Provenance**,
**Diagnostics**, and **Zotero Source**. Properties shows at most five
role-priority facts and one route to the full editor; tags stay in that editor.
Diagnostics shows three or four important machine checks and never claims
reading, truth, or support. Provenance detail remains in Research Record.
Zotero retains **Open in Zotero**.

Inspector typography remains ordinary system interface text and wraps rather
than shrinks. Sections begin 15pt below the tab rule with 15pt between them;
headings use one lighter system-sans label role. Both modes share an 18pt outer
edge; section content is inset another 12pt, symbols use a fixed 16pt track and
8pt gap, and trailing actions return to the outer edge unless disclosure or
another semantic relation requires otherwise.

Review Status uses one restrained third-plane bordered surface, not a badge.
Heading/date/revision/action are system sans; verdict is 18pt editorial serif
with redundant symbol and relative date. Revision currency appears only after
a review. A researcher Review Note uses editorial serif beside a semantic rule
and truncates after two lines. Color alone is insufficient; **Open Dialogue**
or **Open Critique** remains available.

The embedded bottom Research Strip uses one thin top rule and no visible title,
card, capsule, or resting button border. Native/semantic interaction states and
menu, keyboard, and accessibility parity remain. It follows the functions and
panels in Sections 7–8. Durable handoff is keyboard/VoiceOver reachable; the
panel stays intact after launch and restores sensible focus when Scholium
reactivates. Report handoff, never agent-execution, status.

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

## 19. Scholarly Editorialism and design variables

**Scholarly Editorialism** is a contemporary macOS research environment using
humanist typography, editorial hierarchy, warm opaque surfaces, fine rules,
marginal organization, deliberate whitespace, and restrained chromatic
emphasis. It suggests the patience and accumulated judgment of humanities
research without imitating an antique book or decorative minimalism.

Until sustained Usable Core acceptance, this is semantic direction, not a
pixel-perfect gate. Except for accessibility thresholds, readability minima,
source safety, and native-platform boundaries, exact dimensions, spacing,
type, and decoration in Sections 18–20 are provisional. They cannot override
native behavior, create another state owner, or delay dependable core work.

### 19.1 No custom glass

Scholium-owned Library, Document, Inspector, Properties, Search, Research
Strip, diff, diagnostics, conflicts, and evidence surfaces are opaque. No
custom glass, blur, vibrancy, translucent/material cards, image-behind-glass,
large radii, gradients behind text, or decorative shadow defines the brand.
Depth comes from tone, spacing, alignment, type, rules, and restrained
elevation.

System window chrome, menus, sheets, popovers, controls, focus, and selection
retain macOS appearance. Semantic Sidebar/Inspector and toolbar tracking
separators remain native. Document tabs use ordinary controls inside Document,
not a simulated system window-tab bar. Incidental system material is not a
Scholium token. This supersedes older glass, atmospheric-navigation, material,
and vibrancy requirements.

### 19.2 Typography and color

- System sans is interface language: navigation names, chrome, menus, controls,
  Settings, alerts, paths, status, dates, and dense metadata. The fixed
  **Scholium** Alegreya wordmark is the only identity exception.
- **Alegreya** is for Read/Live Preview prose and may identify content-derived
  titles, linked research objects, researcher judgments, or major headings when
  density, scaling, and mixed-script fallback remain legible.
- **Victor Mono** is for Source, code, exact excerpts, anchored review content,
  revision identities, and diffs.
- Document Body is **12pt**; approved H1 is **22.5pt**; H2/H3/H4–H6 are
  provisionally **130/115/100%** of Body. Callouts inherit Body unless an
  approved role requires otherwise.
- Provide intentional CJK serif fallback and test mixed Chinese/Latin lines.
- Native and WebKit surfaces use semantic `ScholiumColorRole`; feature views
  name no raw hex or palette value.
- Light appearance uses Ivory Leaf, Parchment, Vellum, Carbon/Sepia/Muted Ink,
  Binding Rule, and Vermilion Copper. Dark uses Walnut, Cordovan, Leather,
  Parchment text, and Luminous Copper—not mechanical inversion.
- Status, authorship, and Connection colors remain distinct with text/symbol
  redundancy. Color never encodes philosophical value, truth, support, or
  authority.

### 19.3 Variable boundary

Keep eight semantic families: Color, Typography, Surfaces, Elevation,
Boundaries, feature-scoped Metrics, Motion, and provisional Document Rhythm.
Promote only stable cross-component decisions or contract-critical thresholds;
do not invent numbered spacing, opacity, radius, shadow, border, gradient, or
paper scales.

- Interface type roles: identity, section title, row title, metadata, and
  narrowly approved editorial hierarchy. Document roles: Body,
  `heading(level:)`, Exact Source, Code, Diff, Revision Identity.
- Surfaces are opaque semantic planes; dense evidence is quietest and most
  legible.
- Purpose-named boundaries are structural divider, subtle boundary, and
  floating boundary; Increase Contrast strengthens roles rather than adding
  new ones.
- Native controls own interaction states. Custom targets prefer **28pt** and
  never fall below **20pt**; this does not redefine native sizes.
- Standard actions use direct SF Symbols. Domain symbols may centralize
  Scholium meaning, but text remains primary.
- Motion is purpose-named, interruptible, and removed under Reduce Motion. No
  duration scale, parallax, animated grain, or decorative motion.
- Document rhythm remains renderer-aware and provisional until Read/Live
  Preview pass side-by-side review at ordinary, narrow, mixed-script, and 200%
  text conditions.

### 19.4 Provisional layout defaults

Layout defaults support usability testing, not independent release gates.
AppKit owns toolbar height, traffic lights, split behavior, compression,
overflow, and live pane widths. Scholium owns semantic order and only the
feature-scoped insets/minima needed for readable content.

Preferred workspace remains **1180 × 760**. Regions keep coherent leading
edges and independent scrolling; Document takes remaining space without fixed
height. Reading measure, rows, spacing, icon tracks, and decorative rules stay
provisional and must be tested at ordinary, narrow, mixed-script, and 200% text.
Prototype coordinates, screenshots, and CSS-to-SwiftUI conversions acquire no
authority without an approved usability or accessibility reason.

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
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
- Test long labels, mixed English/Chinese, right-to-left chrome, minimum width,
  every lifecycle/error state, and WebKit/AppKit focus transitions.
- Synthetic events cannot certify real VoiceOver, Voice Control, Dictation,
  Full Keyboard Access, or CJK IME; retain manual gates where required.

Beta and 1.0 require complete keyboard and VoiceOver coverage for the declared
core and no unresolved critical/high-severity accessibility defects. A medium-
severity ceiling remains a release-owner judgment.

## 21. Release requirements and acceptance

### 21.1 Evidence hierarchy

Use, in order: current source/live construction; executable tests; isolated QA
on disposable nonprivate fixtures; dated `IMPLEMENTATION_STATUS.md` evidence;
this target specification; then historical screenshots, test names, and memory
as context only. Target prose, previews, and compilation do not prove workflows,
accessibility, packaged release, signing, or performance.

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

Use disposable fixtures and retain command, source revision, Xcode/SDK, build,
fixture identity, result, and artifact location for material evidence.

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

Every target change identifies researcher task, affected sections, product/
interface/implementation scope, trust/source-fidelity impact, compatibility
effect on vault and app data, required evidence, and any new non-goal or open
question. Temporary code and visual experiments never become authority by
accident.

## 22. Active cross-cutting decisions and unresolved work

Sections 1–21 are the complete contract. The table keeps stable identifiers
for implementation and cutover work while pointing to each rule's canonical
definition; deleted/superseded IDs remain only in Git history.

| Decision | Active rule | Canonical section |
| --- | --- | --- |
| **D-003** | One exact Markdown source underlies all document modes. | 5.1, 18.1 |
| **D-026** | One role-valid bottom Strip; Human Review lives within Dialogue, not as an agent function. | 7, 8.1 |
| **D-031** | Beta Search is deterministic lexical retrieval; graph relations stay separate. | 13 |
| **D-037** | Dialogue, Human Review, Comments, Responses, Critique, and dispositions share presentations without sharing identity/provenance. | 7, 8.1–8.2 |
| **D-038** | Manual/automatic Fidelity share revision evidence and preserve invocation provenance. | 8.4 |
| **D-039** | New Analysis offers Declare Now/Not Yet; only Complete Review requires status. | 5.2, 7.1 |
| **D-040** | Research Guidance uses Prompt Templates · Skills · Advanced with the ownership defined there. | 8.3 |
| **D-042** | Live Preview shares Read grammar without YAML/line numbers; initial clearance scrolls. | 5.1, 18.4 |
| **D-043** | Every Comment is source-anchored; no unanchored compatibility path exists. | 7.2 |
| **D-049** | Complete primary methods are flexible; Practices only supplement; bibliography leads remain outside notes/Zotero. | 8.3, 15.3 |
| **D-050** | One version-matched CLI provides strict discovery, typed next actions, resumable functions, Fidelity continuation, and explicit local installation. | 8.4 |
| **D-052** | One native Sidebar–Document–Inspector split; AppKit owns geometry, Scholium only visibility. | 18.2 |
| **D-055** | Triptych Attention is an inline Library queue after scope, with non-color identity; Inspector shows only note summary. | 18.3 |
| **D-059** | Beta is copy-first provider-neutral handoff; 1.0 adds Open in Codex; neither auto-submits or reports execution; Run with Codex needs a 2.0 decision. | 8.1, 17 |
| **D-060** | One native toolbar and standard Inspector item; no replacement chrome or custom glass. | 18.2, 19.1 |
| **D-074** | Open in New Tab creates a retained Document content tab; New Window alone creates a workspace shell. | 3.2, 18.2 |
| **D-076** | Bootstrap owns new/missing setup; expired authorization uses a workspace Restore Access sheet. | 3.2, 16 |
| **D-078** | Pre-1.0 uses a clean Analyses/Topics/Works cutover; Works use project-neutral `draftProject`/`draft-project`; researcher source is preserved. | Introduction, 3–4 |
| **D-079** | Research Record is a note-following utility window, separate from Inspector and checkpoints. | 8.2, 18.5 |
| **D-081** | Simplified Chinese follows the contextual vocabulary boundary; identifiers, exact content, and package-authored text remain unchanged. | 18.7 |
| **D-083** | Pre-1.0 app/agent state uses the clean-cutover inventory below. Unsupported state fails closed or is ignored; researcher source is untouched. | Introduction, 8.2–8.4 |

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
result to the designated Critique document. Do not modify the target Work unless
the researcher's instruction asks you to do so.
```

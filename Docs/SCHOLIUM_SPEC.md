# Scholium Specification

**Status:** Canonical product, interface, and release specification

**Applies to:** Scholium for macOS and its agent-facing CLI

**Canonicalized:** 2026-07-17

**Purpose:** Define Scholium's target product, Triptych model, research
workflows, interface and visual language, accessibility contract, release
requirements, and stable decisions in one maintained authority.

This specification is the sole target authority for Scholium. It owns product
semantics, interface behavior, exact action language, Scholarly Editorialism,
accessibility, release requirements, and stable decisions. Subordinate
implementation documents may explain how the current code realizes this
contract but cannot redefine it. `IMPLEMENTATION_STATUS.md`, README, live
construction, and executable tests establish current reachability and evidence.
Current code that differs is migration work, not an alternative product rule.

Use these terms consistently:

- **Target** means required behavior whether or not it is implemented.
- **Reachable** means the current build exposes the behavior; it is not release
  acceptance by itself.
- **Verified** means the stated evidence directly exercised the behavior.
- **Deferred** means intentionally outside the present release boundary.
- **Unresolved** means a decision or acceptance judgment remains open.

Apple Human Interface Guidelines and the selected SDK own Apple platform
guidance and API behavior. They do not define Scholium's Triptych, scholarly
semantics, evidence distinctions, or research governance.

This guide's direct-agent-edit decision supersedes older product language requiring every agent change to remain a Proposal or unapplied Revision. Legacy app-owned records created by those retired workflows remain ordinary files for the researcher to archive manually; Scholium does not delete or silently rewrite them.

## 1. Canonical terminology

- **Scholium Triptych** is the full name of one configured research workspace; **Triptych** is its short name.
- Every Triptych contains exactly three vaults: **Analyses**, **Topics**, and **Works**. Their ordinary documents are an **Analysis**, **Topic**, and **Work**.
- **Unclassified** is temporary staging for imported Triptych-relevant Markdown that has not yet been assigned to one of the three vaults.
- **Dialogue** is a concise scholarly record of researcher Comments, agent Responses, and follow-up exchanges. It may generate transient copyable instructions for an external agent, but it is not a chat client, task manager, or permission system.
- **Critique** is an attributed agent assessment of one Work. It does not replace its target.
- **Research Function** is one researcher-selected scholarly operation exposed by the document-local Research Strip and executed through the shared Application API. The visible functions are Dialogue, Develop, Review, Fidelity, Critique, Revise, and Manuscript.
- **Target** is the one immutable Analysis, Topic, or Work whose state a Research Function concerns. A function run never has more than one writable Target.
- **Materials** are additional read-only notes selected inside an agent-facing
  function panel. They never become implicit write targets. Human Review does
  not create an agent instruction packet and therefore has no Materials draft.
- **Fidelity** is an exact-revision audit of philosophical content and, when an applicable Researcher Skill is bound, citations. It remains evidentially distinct from Human Review and Critique.
- **Research Strip** is the single bottom editor control surface that exposes only functions valid for the selected note's role.
- **Human Review** is the researcher's fingerprint-bound review of an Analysis or Topic.
- **Qualification** is the researcher's Qualified or Unqualified verdict, recorded only through Human Review.
- **Attention** contains derived warnings and recoverable research issues. Attention does not make philosophical judgments.
- **Connections** are source-located neutral, support, or incompatibility relations.
- **Properties** is the human-facing frontmatter presentation.
- **Research Unit** is the minimal YAML declaration of the epistemic scope to which a note's claims apply. It is not a new note type or project object.
- **Research Status** is the human-facing presentation of a Research Unit and its material limitations.
- **Note History** contains the note's Human Review, Dialogue, Critique association where applicable, and available checkpoint versions. These record types remain visibly distinct.
- **Checkpoint** is a self-contained, fingerprint-bound snapshot of the complete Triptych. It is distinct from editor Undo. Permanent deletion must purge the deleted note and its associated records from checkpoint copies or invalidate copies that cannot be scrubbed safely.

There is no formal **Revision** artifact, Proposal workflow, Research Task, or Research Session in the target product. When used, an agent edits researcher-authorized files directly. The ordinary word “revision” may still describe an edit or a Critique section such as Revision Priorities.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS document editor with research intelligence for sustained humanities research, especially philosophy. Its primary object is the research document—not a dashboard, task, workflow state, or agent conversation.

Scholium is a research-grade writing environment where philosophers can think naturally while the system preserves the exact intellectual artifact underneath.

Scholium helps a researcher read, write, comment, review, search, connect, organize, recover, and trace source-grounded work. It is not a general project manager, reference manager, permanent AI chat interface, or a general-purpose Obsidian replacement in feature breadth. This does not make Obsidian a dependency: a researcher must be able to complete Scholium's core academic workflow in Scholium itself. Obsidian is optional interoperability for researchers who already use it, not a prerequisite for setup, source analysis, Topic synthesis, Works drafting, Review, comments, Dialogue, Critique, Connections, Search, Attention, checkpoints, or recovery.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and is expected to manage the academic
workflow herself when she chooses. She may optionally instruct an external
agent to create, edit, rename, move, organize, or delete notes directly through
filesystem or CLI tools. Scholium does not maintain a separate authorization
scope, require an app-issued permission token, require a proposal, or make an
agent necessary for setup, source analysis, Topic synthesis, Works writing,
Human Review, comments, search, Connections, checkpoints, or recovery.

The current researcher instruction defines the permitted task and scope for
optional agent work. The agent is responsible for following it. No permission
persists beyond that task. Dialogue and Critique are optional extensions, not
conditions for a note to be reviewed, written, or settled.

Scholium supplies safety tools without taking responsibility away from the researcher:

- exact target paths and stable identities;
- fingerprints for revision checks, not authorization;
- autosave and external-change detection;
- conflicts when a dirty local buffer and external edit diverge;
- automatic and manual Triptych checkpoints;
- comparison and restoration.

If a researcher authorizes extensive agent work without an appropriate checkpoint, Scholium does not promise recovery.

Research skills may use these primitives through the typed Research Function
API, but Scholium does not certify their philosophical conclusions. The
researcher chooses a visible function; Application validates the Target,
Materials, revision, applicable workflow, checkpoint, and completion contract.
The frontend and CLI never inspect skill source or select package identifiers.
Use exactly one complete primary method when an intellectual operation requires
one. A prepared Research Function resolves exactly one official Workflow or an
explicitly compatible complete Researcher Skill; System Skills never count as
philosophical methods, and Practices only supplement the primary method. Direct
Source Analysis may use Source Analyzer without a Research Function. Raw Zotero
status, search, and retrieval need no philosophical method unless interpretation
or verification is requested.
For Beta, Scholium distinguishes protected **System Skills**, official
release-managed **Workflow Skills**, and editable **Researcher Skills**.
System Skills are not researcher-editable. A Workflow Skill remains read-only
in the release bundle, but the researcher may duplicate it into an independent
Researcher Skill that later releases never overwrite. The bundled Practice
template follows the same copy-on-adoption rule. Researcher Skills and
researcher-owned Philosophical Practices remain editable, and the researcher
is responsible for their content and methodological consequences. Bundled
workflow methods are philosophy-facing aids for agents: they pursue warranted
scholarly conclusions, preserve fidelity to sources and researcher commitments,
and help construct a precise, reviewable knowledge base. Technical operations
remain subordinate to that academic purpose. The methods do not purport to
teach the researcher how to conduct philosophy, certify truth, or replace her
judgment.

### 2.3 Authorship and provenance

Agent origin does not disappear merely because material is reviewed, qualified, incorporated, or edited later. Keep these concepts independent:

- origin or last modifier;
- vault role and location;
- Human Review and qualification;
- current fingerprint and changed-since-review state;
- Critique authorship;
- app-owned comments and Dialogue replies.

Keep visible UI labels sparse. Location communicates Analysis, Topic, Work, and Critique roles. Do not add composed badges such as **Agent · Analysis** or **Agent · Revision**. Show provenance and modification information in Properties or History when useful; show temporary warnings only when relevant.

## 3. The Scholium Triptych

### 3.1 Exactly three vaults

| Vault | Research role |
|---|---|
| **Analyses** | Reusable source analyses for papers and other research materials. |
| **Topics** | Reusable topic-centred knowledge: concepts, terminology, distinctions, positions, debates, objections, and synthesis. |
| **Works** | Researcher-governed writing, planning notes, arguments, Critiques, drafts, papers, chapters, books, and related material. |

Analyses and Topics remain reusable across every folder and body of writing in Works when they concern the same philosophical domain. A substantially different domain uses another complete Triptych. Scholium provides no fourth vault and no alternative **All Notes** mode.

Researchers choose the three vault locations. Scholium recommends—but does not require—placing them under one parent. It never relocates a vault automatically.

Because each Triptych has one portable `.scholium/` directory beside Works, the Works roots of two different Triptychs must not share the same parent directory. Scholium rejects that configuration instead of allowing two Triptychs to overwrite one portable control directory.

### 3.2 Triptych navigation and windows

Scholium presents **Analyses | Topics | Works** as three peer tabs inside one
stable document-first workspace. Different Triptychs may be open
simultaneously in separate windows or grouped by macOS as native window tabs.
Each native tab is a complete Scholium window session: it owns one selected
document, document mode, inspector and History presentation, scroll location,
Search state, and pending presentation while shared vault services remain
coherent. Scholium provides no second in-window document-tab system.

One window or native tab belongs to one complete Triptych. **File → New
Triptych…** opens setup for three new locations, **File → Open Triptych**
opens a registered Triptych in its own window, and **File → New Window**
opens another independent window for the focused Triptych. Ordinary note
selection replaces the selected document in that session. Switching the
Library among **Analyses**, **Topics**, and **Works** changes only the browsed
hierarchy and the meaning of **This Vault** Search; it does not close,
collapse, or replace the document already open in the session. **Open in New Tab**
creates another complete window session and asks macOS to group it with the
source window; windows from different Triptychs may share the same native tab
group. Standard macOS Window-menu tab commands and `Command-W` remain the tab
and close model. Scholium does not add custom tab cycling, tab closing,
Merge/Move commands, a Triptych switcher inside the document area, or a Works
project selector.

After setup, the workspace keeps one stable frame and one configured
`NavigationSplitView` hierarchy. Its detail contains either the selected
document or Scholium's fixed featured artwork. Opening, replacing, or closing a
note never changes the window frame or position. The native macOS Show/Hide
Sidebar control and View-menu command change only Library visibility; they do
not clear or replace the selected document. Scholium provides no separate
Collapse Note command. The no-note detail contains only a decorative,
text-free Scholium composition; it has no Home title, instruction, button,
document controls, or Research Strip. The actionable Library remains available
through the standard sidebar route.

Works folders are ordinary researcher-controlled folders. A researcher may use one folder for each paper, chapter, book, or other project, but Scholium does not register, select, assign, validate, or otherwise manage projects. No project selector appears below the Triptych navigation.

### 3.3 `.scholium` and machine-local state

A single hidden `.scholium/` control directory sits beside Works. It contains small, portable Triptych information:

- Triptych manifest and stable identity mappings;
- Triptych Guide or related instruction state;
- Triptych-local folder and organization preferences that do not assign project membership;
- Triptych-local settings;
- per-vault Properties configurations;
- editable prompt templates and their Triptych-local workflow assignments;
- explicit primary, supplemental, and exact-Practice function bindings plus
  citation-method bindings;
- Triptych-local user skill packages under
  `.scholium/skills/<skill-id>/SKILL.md`;
- imported Unclassified Markdown under `.scholium/unclassified/`.

The researcher may synchronize `.scholium` through ordinary cloud storage or Git. Scholium never uploads it automatically.

Machine-specific and replaceable state remains in Application Support:

- security-scoped bookmarks and absolute paths, including the separate bookmark
  for the folder containing Works that authorizes the sibling `.scholium/`
  directory without creating a fourth vault;
- window sessions and their single vault-qualified selected document; legacy
  tab and navigation fields remain decode-only during migration;
- search, link, graph, and render indexes;
- temporary files and caches;
- app-owned Human Review, comments, and Dialogue replies;
- self-contained Triptych checkpoints.

### 3.4 Triptych Guide and AI instructions

Scholium provides one concise agent-facing guide explaining:

- the three selected vaults and their roles;
- the Works folder organization and any ordinary `kind` metadata the researcher chose to record;
- canonical relation syntax;
- source-fidelity, provenance, uncertainty, and conflict rules;
- CLI discovery and safe file-operation conventions.

Scholium never creates, overwrites, or silently updates a researcher-workspace
`AGENTS.md`. On an explicit setup request, it may provide a protected one-shot
bootstrap instruction to an external agent. The agent must resolve the exact
Triptych, verify the requested agent working root, inspect the applicable
ancestor chain for existing instructions, construct a minimal candidate,
validate it, promote it, and read it back. If an applicable `AGENTS.md` already
exists, the agent stops instead of overwriting, merging, or creating a shadow
file. After successful validation, it may delete only a temporary bootstrap
copy created for that task; the bundled bootstrap source remains protected and
a failed bootstrap is retained for diagnosis. The resulting `AGENTS.md` is
researcher-owned and may later be changed only by the researcher or through a
new explicit instruction.

Triptych-local technical instructions are managed only in **Settings →
Research Guidance**. Dynamic inventory comes from the filesystem and CLI
rather than a standing generated index.

### 3.5 Import and Unclassified

Scholium imports one or more Markdown files by copying them into `.scholium/unclassified/`; the originals remain unchanged. An imported note remains readable and editable but does not participate in role-specific Review, qualification, Critique, or Properties behavior until the researcher classifies it as Analysis, Topic, or Work. Classification moves the imported copy into the selected vault.

Irrelevant Markdown should not be imported into the Triptych.

## 4. Works folders and organization

Scholium treats the Works vault as an ordinary researcher-organized Markdown hierarchy. A folder may represent a paper, article, chapter, book, or any other grouping, but that meaning belongs to the researcher and is not an app-managed project record. Scholium does not maintain project membership, require project metadata, offer a project selector, or warn about project completeness.

The researcher may create an organization such as:

```text
<Project>/
├── Concepts/
├── Terminology/
├── Cases/
├── Questions/
├── Views and Camps/
├── For/
├── Against/
├── Arguments/
├── Objections/
├── Replies/
├── Critiques/
└── Drafts/
```

This is an example, not a structure Scholium creates or manages. The folders are not formal note kinds or evidential classifications. The researcher may rename, remove, add, and reorganize them at will. Scholium imposes no folder-specific schema, mandatory template, one-note-per-concept rule, or required internal section structure. `Critiques/` is the only folder with special Scholium behavior.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work notes support:

- Read, Live Preview, and Source over one exact Markdown buffer;
- autosaved editing without an ordinary Save button;
- create, duplicate, import, rename, move, reveal in Finder, Set Aside, Trash, Put Back, and permanent deletion;
- folder organization through the app or external tools;
- exact-source preservation, conflict detection, and atomic app writes;
- incoming and outgoing Connections with source locations and ambiguity;
- source-anchored researcher comments;
- one-note or multi-note Dialogue records with optional transient copyable
  instructions for an external agent;
- role-aware Properties;
- one Search field with **This Note**, **This Vault**, and **Triptych** modes,
  known-note ranking, filters, and Attention;
- one stable configured workspace whose no-note detail is the decorative
  featured artwork; selecting, replacing, or closing a note never resizes or
  repositions the window, and the standard sidebar control changes only Library
  visibility;
- Note History and available checkpoint comparison.

Critique bodies are read-only inside Scholium but remain ordinary Markdown files that external editors may modify. Scholium does not enforce filesystem-level read-only permissions.

### 5.1 Document modes and YAML

- **Read** renders the committed note for reading, selection, navigation, and commenting.
- **Live Preview** edits the exact Markdown body through a visual projection.
  Wherever an editable projection permits, it uses the same prose typography
  and rendered-construct styling as Read and reveals Markdown syntax only
  around the active construct. It does not display YAML frontmatter or a
  line-number gutter.
- **Source** exposes and edits the complete Markdown and YAML and may display line numbers.

When either editable mode first opens a note, its first line begins below the
floating Metadata and Properties surface. That clearance belongs to the
scrolling document rather than a permanent safe area: once the researcher
scrolls it away, later text may travel beneath the floating surface.

Only Read and Live Preview receive a direct keyboard toggle. Source is entered through the document-mode pull-down menu so accidental entry is less likely. Source mode may edit protected or machine-facing YAML directly; the researcher assumes responsibility for those exact-source edits. Scholium still validates and preserves bytes without whole-frontmatter reserialization.

### 5.2 Properties

Scholium provides fixed starting defaults for Analyses, Topics, and Works. The researcher may configure each vault independently:

- visible fields;
- display order;
- disclosure state;
- human-editable allowlist.

The configuration applies vault-wide. There are no folder-level or note-level Properties layouts. Identity, fingerprints, provenance, and automatically maintained fields remain protected in the structured Properties interface, although Source mode can expose and edit the exact YAML.

The default profiles use one minimal nested Research Unit when an epistemic
scope declaration is needed:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

`scope` is required whenever `research_unit` is present. `limitations` is an
optional list containing only boundaries that materially restrict what the
note may claim. The mapping does not duplicate note role, source identity,
links, backlinks, relation counts, coverage percentages, confidence, reading
passes, or timestamps. Scholium derives what it can from role, identity,
Connections, and app-owned state.

Creating a new Analysis asks the researcher to choose **Declare Now** or **Not
Yet**. Declare Now records a Research Unit with non-empty Scope and optional
Limitations. Not Yet writes no `research_unit` mapping and no sentinel value.
Such an Analysis remains editable and available for Comments, Dialogue,
Develop, and a Review draft, but **Complete Review** is unavailable until the
Research Status is declared. Existing Analyses without a Research Unit remain
valid and receive no migration or automatic YAML rewrite. Topics and Works may
use the same mapping when a durable conceptual, debate, project-question, or
argumentative boundary adds information not already clear from the title,
body, and links. Scholium does not inject YAML merely to create an absent
Research Unit.

An external agent may add the declaration through an ordinary researcher-
authorized exact-source edit. The normal fingerprint, conflict, and byte-
preservation rules apply; Research Status creates no special authorization
path.

Creation and modification time are app-owned History data, not properties that
researchers or agents must fill. Agents never create, infer, or maintain
frontmatter timestamps. Existing timestamp keys remain exact preserved source
for compatibility, but they are not part of the target default profiles.

An Analysis may optionally record `debate_importance` as a whole number from
0–10 together with `debate_importance_scope`. This helps researchers
prioritize a large Analyses vault while keeping the judgment explicitly local
to a named debate, domain, tradition, period, or reception context. It has no
pass grade and is not project relevance, source quality, truth, prestige, or
citation impact. Scholium requires both fields together and permits omission
when comparative evidence is inadequate. Scholium does not generate, validate,
or present Project Relevance as an active property or rating. Existing
`relevance` and `relevance_rating` YAML remains byte-preserved as inactive
legacy or custom data; the researcher decides project relevance.

Debate Importance is comparable only within one explicit Debate Scope. The
Library lets the researcher filter to one `debate_importance_scope` and then
sort matching Analyses by numeric Debate Importance from high to low; unrated
Analyses remain visible after rated Analyses. Scholium does not offer a global
cross-debate importance ranking. A bounded Research Synthesis, rather than a
Reviewer verdict, may recalibrate a large corpus against one common debate map.

The interface presents `research_unit` as **Research Status** inside the
existing Properties region. It shows Scope first and Limitations only when
non-empty, and shows the honest value **Not Yet** when the mapping is absent.
A role-specific top-level `status` may appear beside it but remains a separate
property: it records Analysis progress, Topic development, or Work production
rather than time or philosophical truth. The exact profile contract is in
Appendix A.

### 5.3 Duplicate, rename, and identity

Every note has a stable app-owned identity. Paths are locations, not identity.

- A duplicate receives a new identity.
- Human Review and qualification reset on the duplicate.
- The duplicate records its source note.
- Confirmed moves and renames preserve comments, History, Critique association, and other app-owned records.
- Scholium automatically updates resolved incoming links after an app-performed rename or move.
- When an external rename or sync conflict cannot be rebound confidently, Scholium keeps the note readable but blocks identity-dependent mutations, Review, History restore, and comment attachment until the researcher confirms the identity.

## 6. Note location, Set Aside, and Trash

Scholium has no generic note lifecycle property or status-advance control. A note's location determines whether it is in the active Triptych, Set Aside, or Trash.

- **Set Aside** is a direct, reversible action. Scholium asks for no reason and stores no failure or superseded status. Set-aside notes remain readable and recoverable but are excluded from ordinary search, synthesis, Critique, and agent context unless explicitly included.
- **Move to Trash** moves the note into the relevant Trash area without immediately erasing it. Trashed notes are excluded from ordinary search, Connections, agent context, and research workflows.
- **Put Back** returns a Set Aside or Trash note to its exact original vault-relative path. Scholium derives that path from the location prefix, does not ask for another destination, and reports a conflict rather than renaming or relocating the note.
- **Cancel** leaves the note unchanged.
- Permanent deletion is explicit. It purges the note's associated comments,
  Dialogue records, associated Critique document or association, Human Review
  records, and other note-specific app state. It also purges the note and
  those records from every checkpoint copy. A checkpoint that cannot be
  scrubbed safely is invalidated and removed rather than retained as a
  recoverable copy. If a shared multi-note Dialogue cannot be partitioned
  safely, the shared record is deleted in full.

Reviews, comments, Dialogue entries, Critique links, and other note-specific
records follow the stable identity into Set Aside or Trash. They remain while
the note remains recoverable. Permanent deletion removes them and all
recoverable checkpoint copies according to the rule above.

## 7. Human Review and comments

### 7.1 Scope and completion

Human Review applies to Analyses and Topics. Works use Critique instead of qualification.

A completed Human Review requires:

- a declared Research Status for an Analysis;
- a Qualified or Unqualified verdict;
- a non-empty Review Note of at most 500 characters.

Review and Comments share one panel with no second-level Comments sheet. The
panel shows existing Comments before the Human Review controls. An inline
Comment composer appears only when the panel receives a current source anchor;
without one, the panel offers no whole-note Comment textbox and directs the
researcher to select a passage and use **Add Comment**. The Review Note remains
the separate note-level Human Review judgment field. The sheet shows a
character counter and never truncates the note
automatically. **Complete Review** remains unavailable until all applicable
conditions are satisfied. When an Analysis has no Research Status, the panel
explains the gate and offers **Declare Research Status…**; **Save as Draft**,
Comments, editing, Dialogue, and Develop remain available. **Save as Draft**
preserves an incomplete review without marking the fingerprint reviewed.
**Cancel** discards unsaved changes to the sheet.

The Review control displays only the applicable state: **Review**, **Continue Review**, **Qualified**, or **Unqualified**. Qualification can be changed only through Review.

### 7.2 App-owned comments

Researcher comments remain app-owned and outside the Markdown source. A selection comment binds to:

- stable note identity;
- exact reviewed fingerprint;
- UTF-8 and UTF-16 source range and original line;
- selected quotation;
- surrounding context.

Read and editor selections create the same record. Scholium renders a restrained annotation without inserting hidden Markdown. After edits, it reattaches only when quotation and context identify one reliable location; otherwise it marks the comment **Needs Reattachment**.

Every Comment requires a source anchor. Scholium has no whole-note Comment
record, creation path, display state, or compatibility decoder. Note-level
judgment belongs to Human Review for an Analysis or Topic and to Critique for a
Work rather than being duplicated as a Comment. The researcher may reattach an
unresolved Comment. The agent may reply but cannot resolve a researcher
Comment.

Editor **Add Comment** opens the role-valid combined panel, focuses its inline
composer, and carries the current source anchor. Analysis and Topic Comments
share Review presentation; Work Comments share Critique presentation. Comment
records, Human Review, and Critique provenance remain distinct in storage and
History despite this shared presentation.

### 7.3 Unqualified Analyses

An Unqualified Analysis remains available for reading, editing, linking, search, Topic integration, Work Critique, and further agent work. Scholium does not move it automatically or forbid its use.

Scholium detects explicit scholarly reliance on an Unqualified Analysis and presents a source-anchored Attention warning. A neutral `[[Analysis]]` Connection alone is not reliance. A citation, explicit support relation, or recognized source-bearing use may trigger the warning. The warning identifies the use and never blocks editing or agent work. It clears when qualification or usage changes.

## 8. Research Functions and direct agent work

### 8.1 Research Strip and function contract

When an Analysis, Topic, or Work is open, one Research Strip floats at the
bottom of the editor. It is absent when no note is selected. It exposes only
one-word, role-valid scholarly functions in this fixed order:

| Target role | Functions |
| --- | --- |
| Analysis or Topic | **Dialogue · Develop · Review · Fidelity** |
| Work | **Critique · Revise · Dialogue · Fidelity · Manuscript** |

For agent-facing functions, the visible optional-agent journey is deliberately
direct:

1. Choose a function.
2. Inspect or adjust scholarly context.
3. Copy the instructions.
4. Send them through the researcher's chosen agent surface.
5. Return to Scholium and inspect the resulting source change and status.

Fingerprints, checkpoints, method resolution, package identities, and evidence
keys remain behind that journey unless repair or recovery requires them.

Choosing a function opens one shared function panel with function-specific
sections. Review is the researcher's Human Review and combined Comments
surface; it does not prepare instructions or select Materials. In every
agent-facing panel, the current note becomes the immutable Target. Additional
notes are chosen only inside the panel as read-only Materials. The Materials browser
shows a search field, an optional **Suggested Only** filter, a compact
**Selected Materials (n)** tray with individual Remove actions, and the real
**Analyses**, **Topics**, and **Works** folder hierarchy. Search covers title,
alias, filename, and path while retaining matching ancestors. Every candidate
starts unselected; there is no bulk selection. Preparation freezes Materials
so the visible packet cannot diverge from copied instructions. Loading, true
empty, and failure remain distinct; failure blocks preparation and offers
**Retry Materials**.

Material suggestions are explainable navigation hints, never evidence. They
use only explicit, resolved, one-hop Connections in this precedence: linked
from the selected passage, linked from the Target, then links directly to the
Target. The interface labels the reason, such as **Suggested — Linked from
Target**, and shows the direct source location when available. Scholium does
not use transitive paths, lexical similarity, AI ranking, Comment text, or an
inferred evidential role to suggest Materials.

A current selection defaults applicable agent-facing work to **Passage**;
otherwise the scope is **Whole**. Review contains Analysis or Topic Comments
and Human Review controls in the same panel, Critique contains Work Comments in
the same panel, and Fidelity offers
**Content** and **Citations** checks. There is no **Manage Comments** doorway or
second-level Comments, Review, or Critique sheet. The frontend never shows
workflow modes, skill package identifiers, or prompt mechanics.
`Command-R` opens Review for an Analysis or Topic and Critique for a Work;
role-valid routing and one sheet channel make them mutually exclusive.

Dialogue remains a concise scholarly interaction record with optional
transient instruction generation. It does not communicate with an agent
process, maintain a global chat, classify philosophical prose, or constrain
what a researcher may ask an agent to do. It is read-only by default. If an
external agent determines that the request requires changing the current note,
it must promote the run through the function API to **Develop** for an Analysis
or Topic or **Revise** for a Work before mutation. The frontend does not make
that classification.

The researcher provides one overall Comment or instruction. The Target and
selected Materials are focal context, not an authorization boundary. Scholium
may generate transient copyable instructions containing, as applicable:

- researcher instruction;
- selected note names, vault-relative paths, and advisory fingerprints;
- selected passages, source lines, and included researcher comments;
- Triptych context, selected note paths, and relevant ordinary Work metadata such as `kind` when present;
- applicable declared Research Units and the app-owned Dialogue target or selection;
- relevant linked-note information;
- requested destination and applicable editing rules;
- the exact read set and, only for a write-capable preparation, permission to
  modify the single fingerprint-bound Target within the authorized range.

The visible functions are stable product operations, not a taxonomy of every
philosophical activity. Development absorbs exploration, concept development,
argument development, synthesis, and Analysis or Topic expression; the exact
method remains an agent judgment within the bounded workflow. Source Analysis
is not a Strip function: a researcher may ask an agent directly to inspect an
available paper or source. The generated instructions are transport material,
not the permanent scholarly record. Scholium does not require the researcher
to preserve technical prompts, hidden instructions, model parameters, token
counts, or paragraph-level AI provenance.

When a function has conditional method references, one-click preparation first
produces a read-only preflight containing the complete primary method. The
external agent inspects the fixed Target and Materials, then finalizes an
explicit conditional-resource selection through the function API; an empty selection means
the primary method is sufficient. The preflight has already persisted the run,
required checkpoint, and appropriate Dialogue or Critique record. Selecting
resources finalizes that same run, checkpoint, and record rather than preparing a
replacement. Until then the run has no mutation instructions and cannot be
completed. Scholium returns the immutable execution packet with only the
selected references and their exact package revisions attached. The Strip
never exposes these internal choices or classifies philosophical prose, and
generic skill retrieval cannot be reported as function-run resource evidence.

Dialogue shows the selected notes, included Comments, researcher instruction,
and consequential context that the researcher needs to verify. It does not
show, preview, select, or permit one-run editing of the active prompt template
or the assembled technical instructions. **Copy Instructions for Agent** uses
the active Dialogue template configured in Settings.

When an agent changes notes, its default researcher-facing response is a
concise academic change summary. It should identify an unresolved question or
required researcher review when relevant; routine file-operation details are
secondary. The note remains the researcher's eventual decision.

For Beta, the Dialogue panel also lets the researcher select one or more
scholarly response modules while keeping one required **Academic Outcome**.
The effective selection is stored with the request as an immutable
`responseContract`; later preference changes do not alter an earlier request.
The initial optional modules are Critical Reflection, Remaining Questions,
Philosophical Significance, Debate Context, and Research Directions. A module
controls presentation only: it cannot authorize wider retrieval, select a
different workflow, expand a write set, or require fabricated content merely
to fill a heading. The agent considers every selected module and allocates
methodological effort flexibly according to the actual question and evidence.
A module may yield no distinct warranted finding, but it may not be silently
skipped. Scholium stores no numerical weights, coverage labels, or allocation
ledger. Academic Outcome remains required. Fidelity,
uncertainty, failure disclosure, and researcher control remain mandatory
regardless of the selection.

Develop, Revise, Manuscript, and a Dialogue promoted to a writing function
complete pending autosaves and create **Before Agent Work** before instructions
are returned. Critique preserves its existing checkpoint behavior. Review and
Fidelity are read-only and create no checkpoint. The researcher remains free
to instruct an agent outside Scholium.

### 8.2 Note History and replies

Scholium provides no separate global Dialogue History. Every selected note
receives the Dialogue entry in its own Note History. For a multi-note Dialogue,
each selected note shows the same:

- researcher Comments and follow-up exchanges;
- selected-note list;
- applicable checkpoint;
- agent replies.

Dialogue entries are chronological scholarly records, not document versions,
technical prompt logs, or per-response approval queues. They cannot be
restored as document versions. The note itself expresses the researcher's
eventual decision.

A local agent may reply through the `scholium dialogue` CLI. The CLI validates request and comment identities and writes immutable, attributed reply records under Application Support; the agent never edits the review database directly. Replies may address the instruction overall, one selected note, or one researcher comment. Only the researcher resolves comments.

Dialogue is note-nonmutating by default: it may read the fixed Target and
selected Materials and append an attributed Response to Dialogue or Note
History. A request to change the note must promote through the function API to
Develop or Revise before mutation; the frontend does not classify prose.

For a Beta request, the CLI also exposes the immutable request-scoped
`responseContract` to the responding agent. Older entries without a snapshot
use a clearly identified compatibility fallback and must not be described as
preserving an exact request-time selection.

An agent without local CLI access can still use the copied prompt. Its reply must be returned manually if the researcher wants it recorded in Note History.

The researcher may use Dialogue without an external agent as a concise record
of her own Comments and decisions. Comment-preservation choices beyond the
request-scoped response contract remain future design work.

### 8.3 Research Guidance, prompt templates, and skills

**Settings → Research Guidance** is the only Scholium surface that displays or
edits prompt templates. Each supported workflow has one active Triptych-local
template. Researchers may create, duplicate, rename, delete, and assign
templates there. Editing a Scholium default creates a researcher-owned
customization; **Reset to Scholium Default** restores the bundled baseline
without silently overwriting another researcher-created template.

Research Guidance also contains a distinct **Skills** collection. For Beta it
shows three ownership classes:

- protected, release-managed **Scholium System Skills** for universal platform
  protocol and supported application or MCP adapters;
- read-only, release-managed **Scholium Workflow Skills** consisting of exactly
  **Development**, **Critique**, **Revision**, **Content Fidelity**, and
  **Manuscript**; and
- editable **Researcher Skills**, including independent copies of official
  workflows, researcher-owned Philosophical Practices, and optional editable
  complete or specialist methods such as Source Analyzer, APA 7 citation
  verification, and Prose Control.

**Prompt Templates** and **Skills** are the two principal Research Guidance
collections. Per-Triptych **Dialogue Defaults** are a subordinate ordinary
section under Prompt Templates for new Dialogue requests, not a third peer
collection and not a Skill or prompt-template item.

Bundled Skills are immediately usable with Scholium's valid defaults; using a
research function does not require the researcher to configure package
composition. The default Skills presentation shows only the human-facing name,
plain-language purpose, relevant function, **Built-in** or **Triptych**
ownership, structural validity, and active status. A bundled Workflow Skill
offers **Duplicate** but no disabled source editor. A Triptych-owned
Researcher Skill offers ordinary edit and duplicate actions.

One **Advanced** disclosure contains Research Methods, Supplements, Practices,
citation bindings, routing metadata, revision comparison, evolution, and
Recovery. **Evolve…** remains available only for an eligible Triptych-owned
Researcher Skill. If required configuration is missing or malformed, the
ordinary summary presents **Repair…**, which opens the exact Advanced recovery
destination. Progressive disclosure changes presentation only: validation,
snapshots, atomic replacement, provenance, and recovery boundaries remain
unchanged.

Official packages may include release-pinned one-level references and
templates in addition to `SKILL.md`. Duplicating a permitted official package
copies the complete bounded package under a new local ID, not only its
`SKILL.md`; its package revision and resources thereafter belong to the
researcher and do not receive release updates. Source Analysis is not a
Workflow package or Strip function. Scholium ships Source Analyzer as a
complete copy-on-adoption Researcher Skill for an external agent directly
asked to inspect an accessible source. It has no Research Function, does not
require Scholium to store the source or control Zotero, and grants no note-
write permission. A researcher
may duplicate a Workflow Skill
into a new independent Researcher Skill, but later releases update only the
official copy. System Skills cannot be edited, duplicated as replacements, or
shadowed by a Triptych-local package.

Every official Workflow Skill is complete without Philosophical Practices and
declares compatible Practices only as routing hints. If the current task or an
active Researcher Skill explicitly selects a Practice, the agent loads only
the Practices package entry and exact selected resource, records stable IDs and
revisions, and applies each as a supplement. A Practice never replaces the
complete primary method. New bindings permit supplementation only; legacy
`replace` bindings decode but show a typed repair issue and are never silently
rewritten. Practice selection cannot change Target, Materials, permissions,
checkpoint rules, or write boundaries. The agent considers every selected
Practice and allocates effort flexibly according to the work and evidence,
reports only material influence, and may return no warranted finding. Scholium
stores no weights, coverage labels, or allocation ledger. Methodological
conflicts remain visible for the researcher. Development
conditionally covers exploration, concept and argument
development, synthesis, and Analysis or Topic expression. Critique assesses a
Work without editing it. Revision owns substantive Work changes and received-
feedback disposition. Content Fidelity performs read-only Content and optional
Citations checks. Reviewer remains a researcher-editable Critique-only
calibration Practice; Critique is complete without it. Manuscript coordinates
independently resolved function phases, accepts Practices only within compatible
prepared child phases, duplicates none of their methods, and grants no
submission authority.
Dialogue remains System transport and record infrastructure; Human Review has
no Workflow Skill.

The APA 7 citation-verification starter is not a fourth ownership class or a
universal Scholium citation authority. It is a copy-on-adoption Researcher
Skill that may be edited, replaced, or ignored when another style, language,
edition practice, discipline, or venue governs. Citations is a Content Fidelity
check. It is available only when the backend validates an active Triptych-local
binding to a skill declaring the required citation-verification or citation-
formatting capability and the applicable style. Settings guides installation
and binding; the Strip never infers capability from a filename or scans a
global plugin directory.

The Prose Control starter is likewise a copy-on-adoption Researcher Skill, not
an official Workflow method or universal Scholium prose style. It is selected
within Revision only when the researcher requests meaning-preserving
improvement of existing prose. Revision owns the write permission and
durability boundary; the selected Prose Control package owns the editable
style profile and preservation ledger. It never activates automatically. A
change to thesis, claim strength, concepts,
inference, dialectical relations, source roles, scope, modality,
qualification, or status requires a separately scoped substantive Writing
operation.

Triptych-local packages remain direct packages discovered only from
`.scholium/skills/<skill-id>/SKILL.md`; no nested ownership folders are
required at runtime. Scholium does not search research notes, arbitrary
filesystem locations, `~/.codex/skills`, or another agent's global
configuration. **Reveal Skills Folder** opens the supported Triptych-local
location. Researchers may inspect and edit user-owned package source, rename
or delete a Researcher Skill, and duplicate an official Workflow Skill. A
malformed package or protected-ID collision remains visible with a structural
error but is unavailable for assembly. Validation concerns package structure
only; Scholium does not judge philosophical truth or methodological quality.

Scholium owns bounded package discovery, structural validation, package origin
and update policy, explicit Triptych bindings, dependency closure, current task
facts, permissions, and exact resource retrieval. Each package declares stable
`supported_functions`; `supported_modes` remains legacy compatibility and an
internal method hint. Application resolves the function to an exact package
revision and records only conditional resources actually loaded, classified as
methods, templates, or checklists. An
external agent may choose the philosophical submethod appropriate to the real
work, but it does not choose a hidden package ID. A clipboard-only agent may
receive a self-contained bounded fallback prompt, but it must not claim to
have applied packages it could not retrieve.

Catalog compatibility and automatic activation remain separate. Core Protocol
loads for every function. Dialogue infrastructure loads for Dialogue. Live
Triptych, Zotero, citation, and Researcher Skill resources load only when the
prepared request and explicit bindings require them.

**Research Guidance → Skills → Research Methods** is the researcher-facing
activation surface for compatible Triptych-local Researcher Skills. For each
applicable one-word function, the researcher may keep the built-in Workflow
Skill, replace it with one compatible researcher-owned primary method, add
compatible supplemental methods, and select exact researcher-owned Practices.
Application validates function, package role, Practice identity, and current
binding revision before atomically persisting the selection. The Strip receives
only semantic function availability: it never receives or displays package
identifiers, binding metadata, or a one-run resource picker.

Dialogue, Critique, and any future approved research workflow expose scholarly
inputs and scope, not prompt mechanics. They do not display template names,
bodies, placeholders, previews, pickers, or editors. A restrained text action
opens **Research Guidance** directly at the applicable template. If the active
template is structurally invalid, Scholium preserves the current workflow
inputs, explains that the template needs attention, opens the same Settings
destination, and does not generate or copy instructions until the problem is
resolved.

Prompt templates configure existing workflows; skills provide reusable agent
guidance. Managing either one does not create specialized Dialogue request
types, a workflow-local skill picker, an agent runtime, hidden authorization,
or a plugin marketplace. Technical template text, skill source, and assembled
transport instructions do not become part of the scholarly Dialogue record.

Only a Triptych-local Researcher Skill may opt into self-evolution. Research
Guidance copies an explicit external proposal request containing the complete
current bounded package, its revision, and the researcher’s maintenance purpose.
It imports the returned complete `ResearchSkillProposedPackage` JSON, exposes a
per-file current/proposed comparison, then shows validation and separately
attributed revision-bound evaluation status, **Apply**, and **Restore**.
Application requires the expected package revision and a confirmation token;
Core snapshots and atomically replaces the complete bounded package or rolls
back. Bundled System and Workflow Skills are immutable. Evolution never routes
automatically from research work and has no Research Strip function.

Research Guidance keeps one global **Recovery** inventory independent of the
currently selected or currently valid skill. Valid snapshots remain available
when the current package is missing or malformed and when another snapshot is
corrupt; corrupt entries are reported without hiding safe ones. Restore
requires confirmation that the complete package will be replaced, rechecks the
current present-or-missing state, and removes files absent from the selected
snapshot. When a current package is displaced, Scholium first saves it as a new
undo snapshot; restoring a missing package performs a guarded reinstall because
there is no displaced package to snapshot. Snapshot discovery and restore use
descriptor-relative, no-follow reads so a path or symlink substitution cannot
redirect recovery.

### 8.4 Function preparation, completion, and Fidelity

The Application function coordinator owns agent-facing availability,
preparation, completion, and cancellation for both the app and CLI. Review
routes directly to the separate Human Review and Comments authorities and does
not produce an execution packet. Agent-facing preparation resolves a
stable Target identity and fingerprint, validates every Material independently,
rejects Target duplication, resolves the exact workflow resources, creates the
required checkpoint and evidential record, then rechecks all revisions before
returning instructions. A partial preparation is rolled back.

The CLI uses discoverable agent language: `function available`, `prepare`,
`show`, `select-resources`, `complete`, `prepare-fidelity`, and `cancel`.
`availability` and `select-methods` remain undocumented Beta compatibility
aliases only. `show` recovers the immutable packet and current durable state;
`prepare-fidelity` constructs or reuses the exact final-revision child from its
parent rather than making an agent reconstruct a request. JSON preparations
and completions include typed `nextActions` as argument vectors with optional
stdin templates. They are never shell-interpolated command strings.
Dialogue preparations also expose a typed `promote` action that preserves the
fixed Target, Materials, scope, and selected Comments while preparing Develop
or Revise. Dialogue itself remains note-nonmutating.

`scholium version`, `doctor`, and hierarchical `help` work without a configured
Triptych. The parser rejects unknown, duplicate, and valueless options before
Application state is opened. A command using `--format json` reports a stable
JSON error envelope. Packaged app builds contain the matching CLI helper;
**Research Guidance → Skills → Advanced → Scholium CLI** installs or updates it
in the researcher's user-local command directory, verifies exact bytes and
executable permission, reports PATH discovery separately, and never edits a
shell profile automatically.

Fidelity has two invocation kinds with one evidence-validation contract.
**Manual Fidelity** is the direct Strip function against the current exact
revision. **Automatic Fidelity** is orchestration after Develop or Revise
modifies the Target: after the substantive parent records its exact final
fingerprint, Scholium creates or reuses the final-fingerprint Fidelity child
with the same Materials, scope kind, selected Comments, and checks. The
researcher does not operate that linkage. Manuscript reuses the automatic
Fidelity evidence attached to its final selected Revise child. Critique and
Dialogue do not trigger Target Fidelity because they do not edit the Target.

Automatic orchestration does not mean that Scholium runs or fabricates an
audit. Because Scholium has no embedded agent runtime, the child remains
**Awaiting Fidelity** until an agent submits actual outcomes. Only a completed,
matching child may advance the parent to its verified terminal state; direct
Fidelity outcomes on the write run are rejected. The deterministic evidence
key reuses rather than duplicates identical evidence for one function, scope,
evidence set, checks, and final revision. A missing or unavailable child leaves
the parent **Awaiting Fidelity** or **Unverified**. Later Target or evidence
changes make the result **Stale**. Manual and automatic paths record their
invocation kind for provenance while Human Review, Comments, Dialogue,
Critique, and Fidelity outcomes remain separate even when linked.

### 8.5 External edits and conflicts

When an external agent or editor changes a clean open note, Scholium quietly refreshes it from disk. When Scholium has an unsaved local buffer, it preserves that buffer and presents a conflict rather than overwriting either version. Fingerprints are used for conflict detection, Review binding, checkpoint comparison, and restoration integrity; they are not permission tokens.

## 9. Analyses workflow

1. The researcher creates or imports an Analysis and writes or revises it in Scholium, using a paper or other source when available.
2. The researcher reads the Analysis, follows linked Topics and Works, and adds source-anchored Comments where needed.
3. From the editor Strip, the researcher may open Dialogue, Develop, Review,
   or Fidelity. Review is the existing Human Review; Develop covers the
   context-sensitive exploratory, conceptual, argumentative, synthetic, or
   expressive work selected by the external agent's method.
4. A source may be analyzed by asking an available agent directly; Scholium
   does not require a Source Analysis button, store PDFs, or control Zotero
   attachments. Zotero may provide bounded metadata when enabled.
5. The researcher decides whether to incorporate any returned work and may
   update materially affected Topics or Works herself or through an optional
   function run.

An Analysis remains reusable for future Works in the same philosophical domain. Qualification records the researcher's judgment of one exact fingerprint; it does not change authorship.

For a long source, including a monograph, Scholium uses one continuously
maintained source-level Analysis by default. Each research session declares a
bounded analysis unit and applies the required Orientation, Analytical, and
Review passes to that unit. The existing Analysis is then updated in place:
its Research Unit records the cumulative source material actually represented,
and its limitations state unread, excluded, unreliable, or incompletely
reviewed material. The note may organize chapter-specific sections without
turning every chapter into a separate Analysis.

A separate Analysis is created only when the researcher requests one or when a
segment needs an independently citable scholarly identity. `complete` means
complete for the declared Research Unit, not automatically complete for the
physical book. **Entire source** may be claimed only after the complete source
has received the required source-wide analysis and review; incremental chapter
work does not silently become a whole-book conclusion.

## 10. Topics workflow

1. The researcher creates or updates a Topic from relevant Analyses and identifies the Analyses actually used.
2. The Topic preserves disagreements, limitations, and uncertainty rather than flattening sources into consensus.
3. The researcher reads the Topic to gain knowledge and follows Connections to Analyses and Works.
4. The researcher adds comments and may use Dialogue, Develop, Review, or
   Fidelity from the editor Strip. Develop includes synthesis and Topic
   development without exposing a separate submode button.
5. Dialogue hands bounded context to an external agent without mutation unless
   the agent promotes the run to Develop.
6. The researcher decides whether to update the Topic or other materially affected Triptych notes.

Scholium does not automatically merge a newly qualified Analysis into Topics. It may report that relevant reviewed material exists. Neutral or transitive Connections never establish integration or support.

Topics do not receive a separate persistent Critique feature. A Dialogue instruction may ask an agent to assess a Topic's accuracy, coverage, or organization, but the normal result is direct improvement of the Topic.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Works are researcher-governed. The researcher may create a scaffold, write,
revise, and organize a Work herself. An agent may create a scaffold or
directly edit a Work when instructed, but Critique remains visibly separate
from researcher prose. Works do not use Human Review qualification, and a
Critique is optional. The Work Strip exposes **Critique · Revise · Dialogue ·
Fidelity · Manuscript**. Critique assesses without editing; Revise is the
explicit write function; Manuscript coordinates isolated phases while the
current Work remains the only document Target.

### 11.2 Critique target and storage

- A Critique normally targets one Work note.
- Multi-note or folder-spanning assessment uses the general multi-note Dialogue mechanism.
- Each Work has at most one current Critique document.
- Later Critique rounds update that document; earlier states remain available through checkpoint-backed Version History.
- Critiques live in the designated `Critiques/` area of Works. Arbitrary Markdown elsewhere is not classified as Critique from metadata alone.
- Scholium presents the body read-only but permits rename, movement within Critiques, Set Aside, Put Back, Trash, and Reveal in Finder.
- External editors and agents may edit the Critique file directly.

### 11.3 Critique function

**Critique** is one Work function. Its panel combines the former Overall and
Specific choices through **Whole | Passage**, includes applicable Work
Comments, and accepts an optional focus or disciplinary lens. An existing
editor selection defaults the panel to Passage.

Whole asks the agent to assess important claims, premises, and arguments
against relevant Analyses and Topics. This source-trace assessment is part of
Critique, not an automatic Scholium diagnostic. Passage remains bounded to the
selected passage and Comments unless the researcher explicitly broadens scope.

The Critique workflow uses the active Triptych-wide Critique template without
showing or permitting one-run adjustment of that template or the assembled
technical instructions. It states that Critiques use the template configured
for the Triptych and provides **Edit Critique Template…**, which opens
**Settings → Research Guidance → Prompt Templates → Critique**. Settings
provides documented placeholders, structural validation, preview, template
management, and **Reset to Scholium Default**.

### 11.4 Critique form

A Critique uses attributed structured prose with these default sections:

1. Overall Assessment
2. Strengths
3. Major Concerns
4. Source Support
5. Objections and Alternatives
6. Revision Priorities
7. Specific Findings
8. Materials Consulted and Limitations

Specific source-related findings may use **Traced**, **Untraced**, **Disputed**, or **Beyond Sources**. These remain attributed agent judgments, not Scholium diagnostics. Scholium does not calculate trace-coverage scores or apply Qualified/Unqualified verdicts to Works.

Specific findings initially remain in the Critique document. Each records the target Work, target fingerprint, heading or section when available, original line, and a short quotation. Selecting the target opens the relevant Work passage. A fingerprint mismatch marks the finding as referring to an earlier version. Overlaying Critique findings on the Work is deferred until human-comment anchoring is proven reliable.

## 12. Connections

For source text in note A:

| Markdown | Normalized meaning |
|---|---|
| `[[B]]` | neutral, undirected A—B |
| `+[[B]]` | A supports B |
| `-[[B]]` | B supports A |
| `?[[B]]` | symmetric incompatibility A—B |

These four forms completely replace legacy typed-link syntax. Aliases, headings, and fragments remain supported. Legacy bytes remain untouched and receive diagnostics only; Scholium does not offer automatic conversion.

Scholium never infers philosophical support from keywords, proximity, folder membership, or multi-hop paths. Neutral and transitive paths remain connections rather than evidence. Incoming and Outgoing views expose direction and exact source location without filling the interface with permanent relation badges.

## 13. Search and Attention

Scholium uses one Search field with exactly three modes:

- **This Note** searches occurrences within the open note.
- **This Vault** searches the currently selected **Analyses**, **Topics**, or
  **Works** vault.
- **Triptych** searches all three vaults in the active Triptych.

Do not add All Workspace, Selected Roles, or other visible search-scope modes.
Do not present a separate in-note Find field or a separate advanced-search
workspace. The standard Find command activates **This Note** in the shared
Search field.

Search uses a centered Spotlight-style overlay. The **This Note / This Vault /
Triptych** scope control is visible immediately, including before text is
entered. Empty Search shows the field and scope without an empty results
sheet. At rest, Search is a compact command surface rather than a workspace-
scale sheet: it uses ordinary interface-sized text and occupies only the width
needed for the field and three scopes. Entering text expands it vertically to
reveal a bounded native result list while its width remains compact and
responsive. It follows the active
system appearance and accessibility adaptations and does not copy Spotlight's
application categories or Finder-specific actions.

Known-note navigation belongs to Search. Exact title, alias, filename, and
path matches rank above body matches without becoming a separate mode.
Scholium provides no Quick Open, Recent Notes, or Back/Forward navigation
history and persists none of their state. Ordinary navigation uses the
Library or Search; parallel work uses a native macOS tab or window.

Each window remembers the last explicitly selected ordinary scope.
`Command-F` is available only when a note is open and temporarily invokes the
shared Search surface in **This Note**. Dismissing Find restores the previous
ordinary scope. If the researcher explicitly changes scope during temporary
Find, that choice becomes the new ordinary scope and ends the temporary
override. Dismissal cancels pending work, rejects stale results, clears the
transient query and results, and retains only the ordinary scope and saved
searches.
The document-local Research inspector and Attention remain contextual and
derived surfaces rather than Search modes. Search results are retrieval leads,
not evidence.

Beta Search is deterministic, local SQLite FTS5 retrieval. It may resolve an
exact Topic title or alias and show that Topic's direct, already-resolved graph
connections in a separate **Related** section. Related items never change FTS
ranking, never include inferred or transitive relations, and never establish
evidential support. Search retrieves; Connections explain.

Do not add vector search, embeddings, AI-generated query interpretation,
AI-based ranking, or a chat-style question box to Beta Search. These are not
required for scholarly retrieval and must not be implied by labels or empty
states.

The existing **Vector-Link** name refers only to researcher-authored Markdown
relationship markers such as `+[[B]]`; it is unrelated to vector search or
embeddings.

Attention may report:

- no links, no explicit relation, or no integration as possible-orphan conditions;
- Changed Since Review;
- Broken Connections;
- explicit reliance on an Unqualified Analysis;
- malformed metadata or unresolved identity where applicable.

Scholium does not infer **Superseded** status and does not use file age alone as Attention. There are no nondismissible warnings. Dismissal duration is configurable in Settings and defaults to seven days. The researcher retains responsibility for every judgment.

Scholium does not implement an automatic untraced-premise diagnostic. Source-trace judgment belongs to an attributed Work Critique.

## 14. Checkpoints, versions, and recovery

Ordinary autosaves do not create visible versions.

Immediately before Scholium prepares Develop, Revise, Manuscript, promoted
Dialogue, or Critique work for an agent, it creates the function's named,
fingerprint-bound checkpoint of the entire Triptych. The researcher may also
choose **Create Checkpoint…** at any time, especially before substantial
external work. Review and Fidelity are read-only and create no checkpoint.

Each checkpoint:

- is self-contained;
- contains Analyses, Topics, Works, and the portable Triptych configuration needed to interpret them;
- is stored outside the vaults;
- may use filesystem cloning internally, but never depends on another checkpoint;
- remains usable if another checkpoint is moved or deleted in Finder.

Automatic checkpoints retain the latest ten. Manual checkpoints remain until the researcher deletes them.

Scholium provides:

- **Create Checkpoint…**;
- **Restore from Checkpoint…**;
- **Reveal Checkpoints in Finder**.

The restore interface shows files created, changed, moved, or deleted since the selected checkpoint. The researcher may restore selected notes or the entire Triptych. Files created after the checkpoint move to Trash during a full rollback rather than being permanently deleted.

Scholium provides no checkpoint-management screen and no proprietary backup
format. Researchers manage checkpoint folders through Finder. Export to
document, HTML, PDF, or DOCX is deferred beyond the experimental release and
is not a permanent product prohibition.

Editor **Undo** reverses editing operations in the current session. **Restore This Version** creates a new current version through the same conflict-aware repository path; it does not rewrite history silently.

## 15. Zotero integration

### 15.1 Local read-only API

The built-in Zotero integration is optional. When the researcher enables it,
Scholium reads Zotero through Zotero's localhost API. The researcher does not
deploy a server, provide a password, or configure the online Web API for this
built-in path. The absence of Zotero does not block source analysis, Topic
synthesis, Works writing, Review, or recovery.

**Settings → Integrations → Zotero** provides:

- connection status;
- **Open Zotero**;
- **Test Connection**;
- **Refresh Library Information**;
- **Forget Cached Zotero Data**;
- last successful connection time;
- a concise local, read-only privacy explanation.

If access is disabled, Scholium instructs the researcher to enable **Allow other applications on this computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Matching and presentation

Prefer a stable `zotero_item_key`. If absent, match in this order:

1. DOI or ISBN;
2. citation key;
3. exact title plus author and year;
4. researcher selection among ambiguous candidates.

Never silently choose an ambiguous match. Once confirmed, Scholium may write the Zotero item key through the permitted property path.

For an Analysis, the Research inspector's compact **Zotero Source** section shows only the Zotero item identified by that Analysis. For a Topic or Work, **Zotero Sources from Linked Analyses** includes only Analysis notes named by links written in the currently opened Topic or Work and carrying a Zotero item key. Incoming backlinks do not qualify. Scholium does not crawl bibliography citations, transitive Connections, Zotero children, Unclassified notes, or the wider library. If several linked Analyses identify the same Zotero item, the paper appears once.

For each included paper, the section shows:

- title, authors, and year;
- journal, book, or collection;
- volume, issue, and pages when available;
- DOI, ISBN, or another primary identifier;
- citation key;

An expanded section may show abstract, publisher, edition, URL, collections, and Zotero modification date. Technical keys remain out of ordinary UI labels.

The only source action is **Open in Zotero**. Scholium does not enumerate, download, reveal, or open Zotero attachments. PDF reading and attachment management remain in Zotero.

If Zotero is unavailable, Scholium names the exact condition and may show
cached metadata labelled with its retrieval time. Scholium's built-in
integration never modifies Zotero metadata, tags, annotations, files, or the
live SQLite database.

### 15.3 Recommended Bibliography

Only an Analysis exposes a compact **Recommended Bibliography** section in the
Research inspector, immediately after **Zotero Source** and before
**Connections**. Topics and Works do not expose it. The section is not a
Research Function, Strip button, Markdown appendix, Zotero write path, or
source-evidence store. It is labelled **Reading leads, not evidence**.

The researcher may optionally select Background Reading, Core Positions,
Historical Predecessors, Objections, Replies, Companion Literature,
Alternative Approaches, Missing Citations, Recent Developments, or Classic
Works, and may add a purpose. No selected goal requests neutral source-centred
screening. Source Analyzer supplies the complete default method. Advanced
Research Guidance may bind one compatible Triptych-local complete Source
Analyzer; a broken explicit binding shows Repair and never silently falls back.

Preparation locks the Analysis identity and fingerprint, snapshots the exact
method package and loaded resources, and accepts zero candidates as success.
The agent distinguishes reference-list occurrence, in-text citation,
substantive discussion, authorial praise, criticism, or centrality,
independently verified metadata, and independent source inspection. Unread
candidates receive no Debate Importance or project-relevance rating.

Scholium stores the atomic portable projection at
`.scholium/recommended-bibliography.json`, outside note content and Zotero.
Trusted matching uses verified scoped Zotero item key, DOI, guarded ISBN,
citation key, then exact normalized title plus complete author identity and
year. It never automatically merges chapters with books, editions with
translations, conflicting author lists, incomplete multi-author records, or
ambiguous title-only matches. A matched Analysis is not proof that the source
has been analyzed beyond its declared Research Unit and coverage evidence.

The dense inspector rows show title, authors and year, goals, one short reason,
and verification or match state. Available actions are **Open Analysis**,
**Open in Zotero** for a verified key, and **Dismiss**. The section provides
**Recommend…**, **Copy Instructions**, **Cancel**, and **Update
Recommendations**, preserves prior results during refresh or failure, and
covers empty, successful-zero, preparing, awaiting-agent, stale, malformed,
duplicate, ambiguous, Zotero-unavailable, and general-error states with non-colour status,
keyboard focus, meaningful VoiceOver labels, and compact/narrow adaptation.

The delivery-neutral `RecommendedBibliographyUseCases` capability is separate
from Research Functions. The CLI exposes `bibliography prepare`, `show`,
`complete`, and `cancel`; normalization and duplicate discrimination remain
Core/Application authority rather than a public semantic-ranking command.

### 15.4 Optional external-agent Zotero MCP

The built-in Scholium Zotero interface remains the local, read-only integration
defined above. For Beta, Scholium also supplies a protected
`scholium-zotero-integration` System Skill for external agents and pairs it
with a supported local Zotero MCP service or supported installation path. The
skill is an instruction contract; an available MCP service is the transport.
It is not an embedded agent runtime.

The MCP route may report readiness, search records, inspect exact item metadata
and bounded attachment pointers, report the selected import target, and import
BibTeX or RIS. Retrieval is the default. A real import requires an explicit
current-task request for the exact record, an identified destination, a
successful dry run, the MCP tool's explicit confirmation gate, and read-back
verification. An analysis, search, citation, or earlier import never grants
standing Zotero write permission.

The MCP route never reads or writes the live Zotero SQLite database directly,
never silently selects an ambiguous record or destination, and never treats
metadata, tags, abstracts, or attachment identity as evidence for a source's
philosophical claims. Source analysis remains an external, explicitly requested
method rather than a Scholium Workflow package or Strip function, and citation
formatting remains the responsibility of an explicitly bound Triptych-local
Researcher Skill. If the MCP capability is unavailable, the agent reports the
exact boundary and does not bypass it through global configuration scanning or
raw database access.

## 16. Onboarding

On first launch, Scholium opens as a narrow, left-middle five-step setup and
asks for one decision at a time: Analyses, Topics, Works, then the bounded
authorization needed beside Works. The flow uses standard Open panels, has no
scrolling page, and reaches a usable workspace without a feature tour or
explanatory manual. Completing setup performs the only application-driven
expansion to the normal workspace frame; Reduce Motion makes that change
immediate. Configured windows launch or restore at the normal workspace size,
and the setup guide never appears again over the configured Triptych.
Scholium does not ask the researcher to register a project or choose an
app-managed Works structure. Later, **Manage Triptychs…** in Settings lists
complete registered Triptychs, edits the three locations of the selected
Triptych, creates another Triptych, and opens the selected Triptych in a
separate window.

## 17. Permanent boundaries and deferred capabilities

Do not add:

- a permanent LLM chat sidebar;
- app-enforced agent task authorization or proposal approval;
- automatic philosophical support, settlement, sufficiency, truth, or prose-authorization judgments;
- a fourth vault or All Notes mode;
- a generic task manager or plugin marketplace;
- a Zotero replacement or embedded PDF reader;
- automatic untraced-premise verdicts;
- a proprietary backup-export format;
- complete arbitrary Obsidian-theme compatibility;
- bundled general instructions that purport to teach researchers how to
  conduct philosophy. Official Workflow Skills may provide complete methods
  for agents, but the researcher remains responsible for methodological
  choices and philosophical judgment.

Deferred beyond the experimental 0.1 release and required for Beta because
agent-assisted research is a core Scholium capability:

- the protected System Skill layer, five official Workflow Skill packages,
  bounded catalog and package retrieval, function-aware selective assembly,
  and isolated Manuscript phases;
- request-scoped Dialogue `responseContract` snapshots and CLI exposure; and
- the protected Zotero MCP adapter with its supported local transport.

Other capabilities deferred beyond the experimental release, but not
permanently rejected:

- document, project, HTML, PDF, or DOCX export;
- additional discipline-specific or researcher-contributed workflows beyond
  the Beta baseline; and
- richer Dialogue comment-preservation and reflection modes.

Editable prompt templates and file-backed skills are Research Guidance, not a
plugin marketplace. Their Settings-only management does not create a
specialized request taxonomy, an embedded agent runtime, or automatic
philosophical authority.

Use Finder for authoritative Markdown, attachments, and checkpoint folders. Use
Zotero for bibliographic management and PDF reading when the researcher wants
it. Use external agents for Dialogue or other open-ended work only when the
researcher chooses to do so.

## 18. Canonical interface contract

### 18.1 Interface principles

- The research document is the largest and most stable region. Navigation,
  Properties, contextual research, diagnostics, and agent assistance remain
  subordinate to reading and writing.
- Use native macOS windows, split views, inspectors, toolbars, menus, sheets,
  alerts, file panels, controls, selection, focus, and native window tabs when
  they provide the required behavior.
- Keep one owner for each mutable fact and route commands to the focused native
  tab, window, or document. Shared repositories, indexes, identities, watchers,
  and registries remain workspace services rather than window state.
- Every projection is reversible from one authoritative Markdown source. Read,
  Live Preview, Source, Properties, Search, and derived research views must not
  normalize or reconstruct writable source.
- Distinguish source, researcher writing, agent content, Human Review,
  Critique, Connections, and derived diagnostics in text and structure, not
  color alone.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility,
  cancellation, comparison, retry, conflict, and recovery routes. Hover, drag,
  color, motion, secondary click, and gestures are never the sole route to a
  core task.

### 18.2 Workspace shell and native tabs

Configured Scholium uses one stable `NavigationSplitView` workspace. First-run
setup is the sole narrow window state and performs the sole application-driven
expansion to the preferred **1180 × 760** workspace; the minimum content size is
**760 × 520**. Reduce Motion makes setup completion immediate. Opening,
replacing, or closing a note never changes the window frame or position.

The main regions are:

1. **Library:** Triptych identity, Analyses/Topics/Works scope, genuine folder
   hierarchy, Attention, filters, Unclassified, Set Aside, and Trash.
2. **Document:** the selected note or decorative no-note artwork.
3. **Trailing context:** mutually exclusive Research inspector or Note History.
   It yields before the document becomes unusable.

The native **Show/Hide Sidebar** toolbar item and View command change only
Library visibility. Scholium has no Collapse Note function, custom `<<`
control, custom document tabs, Back/Forward, Recent Notes, or Quick Open.
Switching Library among Analyses, Topics, and Works changes only the browsed
hierarchy and **This Vault** Search scope; it never closes or replaces the open
document. Only explicit note selection replaces it.

One native macOS tab is one complete Scholium window session with its own
selected document, document mode, scroll, Search, presentation router,
inspector/History state, and document sessions. **Open in New Tab** creates and
groups another complete session. Standard Window-menu tab commands and
`Command-W` remain authoritative. Scholium adds no custom tab cycling, closing,
Merge, or Move commands.

The no-note detail contains only fixed, text-free, VoiceOver-hidden featured
artwork. It has no Home title, instruction, button, document controls, or
Research Strip. The Library remains the actionable interface.

### 18.3 Library and Search

- Use one compact native **Filter** menu for research state, tags, metadata,
  individual properties, and sort. Keep Unreviewed and Unqualified task toggles
  visible.
- Note rows remain compact and preserve complete titles accessibly. Selection
  remains visible when focus moves to the document or inspector.
- Debate Importance ordering is available only after selecting one exact Debate
  Scope; unrated matching Analyses follow rated ones. Never compare different
  scopes as one scale.
- Shared Search is a compact centered command surface. **This Note**, **This
  Vault**, and **Triptych** are visible before typing. An empty query shows no
  empty results sheet; results expand in a bounded vertical list.
- Exact title, alias, filename, and path matches rank above body matches, so
  Search also owns known-note navigation. Results identify match context and
  destination.
- `Command-F` requires an open note and temporarily invokes **This Note**. On
  dismissal, restore the prior general scope unless the researcher explicitly
  selected another scope. Query changes immediately invalidate stale results;
  dismissal cancels pending work and clears transient query/results.
- Beta Search is deterministic local lexical retrieval. Vectors, embeddings,
  AI interpretation, AI ranking, and chat-style search are excluded.

### 18.4 Document modes, context, and Properties

Read, Live Preview, and Source are modes of one document, not tabs.

- **Read** presents selectable semantic prose and committed content.
- **Live Preview** uses Read's prose grammar wherever editable projection
  permits, reveals syntax only around the active construct, and never displays
  line numbers or YAML frontmatter.
- **Source** exposes the complete Markdown and YAML and may display line
  numbers. Enter it through the mode pull-down rather than the direct
  Read/Live Preview toggle.

Live Preview and Source initially clear the document-context surface so the
first editable line is unobscured. That clearance belongs to scrolling content
and moves away; later prose may travel beneath the context surface.

The context surface contains one mode/outline group followed by one role-aware
Properties disclosure. Both compact controls share a **40pt** height and a
centerline; their complete width and the expanded Properties surface align to
the **920pt** document measure. Secondary facts disappear before crowding.
Reader/editor scaling lives in **View → Document Text Size**, persists per
window, and never changes source.

Properties uses the default profiles in Appendix A and remains a targeted
frontmatter projection. It distinguishes absent, empty, invalid, derived, and
not-applicable values. Exact YAML remains available in Source. Research Unit is
presented as **Research Status**, with Scope first and Limitations only when
non-empty. An absent mapping is **Not Yet**, not malformed or inferred.

### 18.5 Contextual research and Research Strip

The trailing context region presents either Note History or the Research
inspector, never competing panels. The inspector uses Incoming, Outgoing, and
Research modes; it labels direction, predicate, resolution, source anchor,
provenance, and derived status without presenting Connections as evidence.

The bottom editor Research Strip opens one final typed panel directly:

- Analysis/Topic: **Dialogue · Develop · Review · Fidelity**.
- Work: **Critique · Revise · Dialogue · Fidelity · Manuscript**.

Review is human judgment and shares one panel with anchored Analysis/Topic
Comments. Critique shares one panel with anchored Work Comments. A Comment
requires an exact source anchor; Scholium has no whole-note Comment textbox,
decoder, migration, or fallback. **Add Comment** opens the role-valid panel and
focuses its inline anchored composer.

Agent-facing panels fix the Target and expose searchable hierarchical Materials
with explicit selection, a selected tray, direct one-hop suggestion reasons,
failure/retry, and freeze-after-preparation. Nothing is selected automatically;
suggestions are navigation hints, never evidence. Human Review never queries or
displays Materials.

### 18.6 Canonical state and action meanings

| State | Meaning |
| --- | --- |
| **Edited** | The active buffer differs from the last committed source. |
| **Saving** | A revision-checked commit is in progress. |
| **Saved** | The repository committed authoritative source successfully. Derived consumers may still be refreshing. |
| **Save Failed** | Source was not committed; retain the buffer and provide Retry or comparison as appropriate. |
| **Conflict** | The expected revision no longer matches disk; retain the buffer and require comparison before destructive reload. |
| **Refreshing** | Derived consumers are catching up to already committed source. |
| **Derived State Stale** | A derived consumer represents an older committed revision. |
| **Fully Up to Date** | Source and all named derived consumers represent one committed revision. |

Conflict actions are **Compare Changes**, **Reload from Disk**, and **Keep
Editing** when comparison exists. Comparison uses **Return to Editing** and
**Reload from Disk**, with exact editor and disk revision identities visible.
Version history uses **Restore This Version**. Editor `Command-Z` never means
version restoration.

Destructive note actions are **Set Aside**, **Move to Trash**, **Put Back**,
**Delete Permanently**, and **Cancel** as appropriate. Permanent deletion never
advertises checkpoint or History recovery for deleted content.

## 19. Scholarly Editorialism and design variables

Scholium adopts **Scholarly Editorialism**: a contemporary macOS research
environment shaped by humanist typography, editorial hierarchy, warm opaque
surfaces, fine structural rules, marginal organization, deliberate whitespace,
and restrained chromatic emphasis. It conveys the patience, plurality,
tension, and accumulated judgment of humanities research without imitating an
antique book or becoming decorative minimalism.

### 19.1 No custom glass

Scholium-owned Library, document, inspector, Properties, Search, Research Strip,
diff, diagnostic, conflict, and exact-evidence surfaces are opaque. Scholium
does not use Liquid Glass, custom blur, vibrancy, translucent cards,
image-behind-glass treatments, material field cards, or glass as a brand
language. Depth comes from semantic tone, spacing, alignment, typography, fine
boundaries, and restrained elevation rather than translucency, floating cards,
large radii, gradients behind text, or decorative shadows.

System-owned window chrome, menus, sheets, popovers, standard controls, focus,
selection, and native tabs retain their macOS appearance. Any system material
is an incidental platform consequence, not a Scholium token or visual motif.
This rule supersedes every earlier custom-glass, atmospheric-navigation,
regular-material, vibrancy, or Liquid Glass requirement.

### 19.2 Typography and color

- Use the system font for menus, toolbars, buttons, settings, alerts, compact
  controls, paths, status text, and dense metadata.
- Use **Alegreya** for Read prose and Live Preview prose. It may identify
  content-derived document/note titles and major research-object headings when
  density, scaling, and mixed-script fallback remain legible.
- Use **Victor Mono** for Source, code, exact excerpts, line-anchored review
  content, revision identities, and diffs.
- Document Body is **12pt**. H1/H2/H3/H4–H6 are **150/130/115/100%** of Body.
  Callouts inherit Body except an explicitly approved role exception.
- Provide intentional CJK serif fallback and test Chinese/Latin mixed lines.
- Use semantic `ScholiumColorRole` values across native and WebKit surfaces;
  feature views never name raw hex values or palette names.
- Light appearance uses Ivory Leaf document, Parchment navigation, Vellum
  contextual surfaces, Carbon/Sepia/Muted Ink text, Binding Rule boundaries,
  and Vermilion Copper emphasis. Dark appearance is an evening library of
  Walnut document, Cordovan navigation, Leather contextual surfaces,
  Parchment text, and Luminous Copper emphasis—not a mechanical inversion.
- Status, authorship, and Connection colors remain distinct and always have a
  textual or symbolic redundant cue. Color never establishes philosophical
  value, support, truth, or authority.

### 19.3 Variable boundary

Maintain eight small semantic families: Color, Typography, Surfaces,
Elevation, Boundaries, feature-scoped Metrics, Motion, and provisional Document
Rhythm. Promote a value only when it is a stable cross-component decision or a
contract-critical accessibility threshold. Do not create generic numbered
spacing, opacity, radius, shadow, border, gradient, or paper scales.

- Interface typography roles are identity, section title, row title, metadata,
  and narrowly approved editorial hierarchy. Document roles are Body,
  `heading(level:)`, Exact Source, Code, Diff, and Revision Identity.
- Surface roles describe opaque semantic planes. Dense evidence remains the
  quietest, most legible surface.
- Boundaries are purpose-named structural divider, subtle boundary, and
  floating boundary recipes. Increase Contrast strengthens each role rather
  than becoming a separate role.
- Native controls own disabled, selected, focused, pressed, hover, and
  inactive-window presentation. Custom targets prefer **28pt** and never fall
  below **20pt**; these thresholds do not redefine native sizing.
- Standard actions use direct SF Symbols. Domain presentations may centralize
  Scholium-specific meaning, but text remains the primary carrier.
- Motion is purpose-named, interruptible, and removed where Reduce Motion
  requires it. Add no duration scale, parallax, animated grain, or decorative
  motion.
- Document rhythm remains renderer-aware and provisional until Read and Live
  Preview pass side-by-side visual review at ordinary, narrow, mixed-script,
  and 200% text conditions.

## 20. Accessibility and adaptation

- Support System, Light, and Dark appearance without hard-coded inversion.
- Target at least **4.5:1** contrast for ordinary small text and **3:1** for
  large or bold text. Audit every important custom target below 28 × 28 points.
- Preserve the hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive-window appearance, 200% document text, and accent changes.
- Give every important state at least two suitable channels. Color, motion,
  sound, spatial position, or arrow direction alone is insufficient.
- Provide complete keyboard and visible-focus routes for the core workflow.
  Restore focus after sheets, alerts, Search, popovers, function panels,
  conflict comparison, and History close.
- Keep VoiceOver names, roles, values, headings, source anchors, selected state,
  errors, and consequences current. Decorative artwork is accessibility-hidden.
- Do not claim real VoiceOver, Voice Control, Dictation, Full Keyboard Access,
  or CJK IME acceptance from synthetic events alone. Record those as manual
  gates when the operating-system interaction cannot be automated faithfully.
- Test long labels, English/Chinese mixed text, right-to-left chrome, minimum
  window size, empty/loading/unavailable/malformed/stale/conflict/error states,
  and WebKit/AppKit focus transitions.

Beta and 1.0 require complete keyboard and VoiceOver coverage for the declared
core workflow and zero unresolved critical or high-severity accessibility
defects. A medium-severity ceiling remains a release-owner judgment rather than
an assumed pass.

## 21. Release requirements and acceptance

### 21.1 Evidence hierarchy

Use evidence in this order:

1. current source and live construction;
2. executable unit, integration, editor, and UI tests;
3. isolated QA runs on disposable nonprivate fixtures;
4. `IMPLEMENTATION_STATUS.md` and retained evidence;
5. this target specification;
6. historical screenshots, test names, and remembered behavior as context only.

Target documentation is not implementation evidence. A preview or successful
compile does not prove a workflow, accessibility journey, packaged Release
artifact, signing state, or performance gate.

### 21.2 Primary acceptance journeys

The release evidence must cover, as applicable:

- setup, registration, restoration, and several independent Triptych windows;
- create/open/read/edit/save/search and explicit cross-vault navigation;
- Live Preview/Source fidelity, formatting, anchored Comments, and mode changes;
- Properties, Research Status declaration/Not Yet, Human Review, and
  qualification;
- Dialogue, Develop, Critique, Revise, manual/automatic Fidelity, Manuscript,
  hierarchical Materials, and Research Guidance recovery;
- Connections, Attention, Zotero unavailable/read-only behavior, and CLI parity;
- external edits, conflicts, stable-identity rename, Set Aside, Trash,
  permanent deletion, checkpoints, selective/full restore, interrupted
  recovery, and cross-window dirty-peer behavior;
- light/dark, Increase Contrast, Reduce Transparency, Reduce Motion, inactive
  window, 200% document text, mixed-script input, keyboard, focus, and
  accessibility routes; and
- 1380-, 1080-, 900-point and minimum-width workspace behavior.

Use disposable fixtures only. Preserve commands, source revision, Xcode/SDK,
build configuration, fixture identity, result, and retained artifact location
for material evidence.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every requirement in the declared release scope has evidence or an explicit waiver. |
| **G2 Workflow independence** | The manual core workflow works without Obsidian, Zotero, an external agent, or manual filesystem manipulation. |
| **G3 Source integrity** | Exact-source tests cover malformed YAML, unknown fields, BOM/newlines, comments, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflicts, checkpoints, restore, Trash, permanent purge, external rename, and derived-state failures pass disposable-fixture journeys. |
| **G5 Scholarly transparency** | Dialogue, Review, Critique, Fidelity, provenance, and uncertainty remain visibly distinct without hidden philosophical judgments. |
| **G6 Accessibility and internationalization** | The declared accessibility threshold in Section 20 is met. |
| **G7 Performance** | The approved packaged-app protocol in `PERFORMANCE_BENCHMARK.md` passes on the frozen reference fixture and machine. |
| **G8 Documentation consistency** | This specification, architecture, status, README, source, and tests do not silently contradict one another. |
| **G9 Distribution integrity** | Every external binary comes from a clean exact tag, includes corresponding GPL source/licenses, contains no private state, states signing/architecture accurately, publishes a checksum, and passes clean-account smoke testing. |
| **G10 Agent skill architecture** | Protected/researcher-owned boundaries, function-aware assembly, citation bindings, guarded evolution, Dialogue response contracts, bootstrap, and Zotero MCP behavior pass their declared journeys. |

For 0.1 Experimental, G1–G5 and G8 apply; G9 applies whenever an external
artifact is distributed. G6 and G7 require an honest baseline and documented
gaps but must not be represented as passed Beta thresholds. Beta requires all
applicable gates, including G10. Current gate evidence belongs only in
`IMPLEMENTATION_STATUS.md`.

### 21.4 Change control

Every target change identifies the affected researcher task, specification
sections, product/interface/implementation scope, trust and source-fidelity
impact, compatibility effect on existing vault/app-owned data, acceptance
evidence, and any new non-goal or unresolved question. Update this
specification intentionally; never turn temporary implementation or a visual
experiment into target authority.

## 22. Active decisions and unresolved work

The latest explicitly approved decision supersedes older conflicting language.
This specification contains only the active rule; full former wording remains
available in Git history rather than burdening current agents with obsolete
instructions.

| Decision | Active rule |
| --- | --- |
| **D-003** | One exact Markdown source underlies Read, Live Preview, and Source. |
| **D-026** | One bottom Research Strip opens direct role-valid functions. |
| **D-031** | Beta Search is deterministic lexical retrieval; graph relations remain separately labelled. |
| **D-035** | Native and WebKit use one semantic color vocabulary and reviewed light/dark palettes. |
| **D-036** | Stable workspace geometry, one selected document per native-tab session, decorative no-note artwork, and no retired navigation systems. |
| **D-037** | Review/Comments and Critique/Comments share role-valid panels; agent Materials remain explicit hierarchical context. |
| **D-038** | Manual and automatic Fidelity share revision-specific evidence while preserving invocation provenance. |
| **D-039** | New Analysis permits Declare Now or Not Yet; only Complete Review requires declared Research Status. |
| **D-040** | Research Guidance provides usable defaults and puts composition/evolution/recovery under Advanced disclosure. |
| **D-041** | Library vault browsing never replaces the open document. |
| **D-042** | Live Preview shares Read grammar without line numbers; initial editor clearance scrolls away. |
| **D-043** | Every Comment is source-anchored; there is no unanchored compatibility path. |
| **D-044** | Shared Search is a compact command surface with immediately visible scopes. |
| **D-045** | The design-variable system remains small, semantic, and renderer-aware. |
| **D-048** | Scholarly Editorialism and opaque Scholium-owned surfaces supersede every custom-glass requirement. |
| **D-049** | Complete primary methods route flexibly; Practices are supplement-only without numerical allocation, and Analysis-only Recommended Bibliography stores compact reading leads outside notes and Zotero. |
| **D-050** | The app bundles one version-matched Scholium CLI with strict hierarchical discovery, typed next actions, resumable Function state, direct Fidelity continuation, and explicit user-local installation. |

Unresolved work must not be presented as completed behavior:

- sustained manual VoiceOver, Full Keyboard Access, Voice Control, Dictation,
  contrast, scaling, localization, and installed-IME acceptance;
- final visual approval of document rhythm and production mono comparison;
- compact multi-note Dialogue presentation and richer reflection/compression;
- broader Search ranking-usability evaluation;
- packaged Release performance thresholds and measurements; and
- complete clean-tagged distribution and external-install evidence.

## Appendix A. Default property profiles

Existing and custom YAML remains authoritative and losslessly preserved. These
profiles define recommended researcher-facing fields; they do not migrate
notes, erase unknown data, or inject absent YAML during ordinary saves.

Creation and modification time are app-owned History facts. Agents never
create, infer, or maintain timestamp properties. Existing timestamp keys remain
exact preserved source but are not target profile fields.

`research_unit` has exactly this shape when present:

```yaml
research_unit:
  scope: "Introduction and Chapters 1–4"
  limitations:
    - "Chapters 5–8 and the appendix have not been analyzed."
```

`scope` is required and non-empty whenever the mapping exists. `limitations`
is an optional list of material boundaries. Do not add nested type, target,
coverage, percentage, confidence, reading protocol, pass flags, timestamps,
backlinks, or relation counts.

For a long source, maintain one source-level Analysis by default. Expand Scope
only to material actually inspected and represented; record unread or excluded
material in Limitations. Create separate segment Analyses only by explicit
researcher choice or when the segment requires an independently durable
scholarly identity.

### Analyses

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Required source title. |
| About | Authors | `authors` | Required list of source authors. |
| About | Year | `year` | Required publication year. |
| About | Type | `type` | Optional publication form. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional at creation; required before Complete Review. Not Yet writes nothing. |
| Source | Access | `access` | Consulted-material extent. |
| Source | Text Reliability | `text_reliability` | Reliability of the consulted text. |
| Source | Locators | `locators` | Stability/checkability of citations. |
| Progress | Status | `status` | `draft`, `complete`, or `reviewed`, relative to declared Research Unit. |
| Assessment | Debate Importance | `debate_importance` | Optional whole number 0–10. |
| Assessment | Debate Scope | `debate_importance_scope` | Required whenever Debate Importance exists. |

Debate Importance is local to one named debate/domain/tradition/period and is
not project relevance, quality, truth, prestige, or citation count. The two
fields change together. Scholium generates no Project Relevance property or
rating and byte-preserves legacy `relevance` data as inactive custom content.

### Topics

Topic YAML is optional.

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Optional when filename/H1 identifies the Topic. |
| About | Aliases | `aliases` | Search and link alternatives. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional conceptual/debate boundary. |
| Progress | Status | `status` | `seed`, `developing`, or `maintained`; never philosophical settlement. |

### Works

| Group | Property | YAML | Rule |
| --- | --- | --- | --- |
| About | Title | `title` | Required Work title. |
| About | Authors | `authors` | Optional co-authors. |
| About | Kind | `kind` | Form such as paper, chapter, book, talk, review, or teaching material. |
| About | Tags | `tags` | Optional retrieval terms. |
| Research Status | Research Unit | `research_unit` | Optional project-question or argumentative boundary. |
| Progress | Status | `status` | `planning`, `drafting`, `revising`, `review`, `ready`, `submitted`, `published`, or `archived`. |
| Use | Venue | `venue` | Intended or actual journal, publisher, course, or event. |
| Use | Deadline | `deadline` | Relevant delivery or submission date. |

Works status records production state only. It does not encode argumentative
quality, evidential sufficiency, acceptance probability, or project governance.
Works folders remain ordinary researcher organization; Scholium adds no
project property or inferred membership.

Legacy aliases remain readable and untouched during ordinary saves. A targeted
edit writes the canonical key and removes only its corresponding legacy alias;
it never bulk-migrates a note. Other non-machine fields remain custom
Properties, and exact YAML remains available in Source.

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
